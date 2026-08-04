-- POLARIS RLS 재설계
-- 문제: classes / student_results 에 "FOR ALL TO anon USING (true) WITH CHECK (true)" 정책이 걸려있어
--       공개된 anon key만 있으면 누구나 전체 학급/학생 데이터를 조회·수정·삭제 가능했음.
-- 원인: 앱이 Supabase Auth 없이 "6자리 학급 코드"를 사실상의 비밀키로 사용하는 구조인데,
--       RLS의 USING 절은 요청에 담긴 .eq('code', ...) 필터를 알 수 없어 행 단위로 이를 검증할 방법이 없음.
-- 해결: 테이블에 대한 anon 직접 접근(GRANT)을 전부 차단하고, 코드를 인자로 받아
--       서버 측(SECURITY DEFINER)에서 검증하는 RPC 함수로만 접근하도록 변경.
--       + 코드 추측(무차별 대입) 방어를 위해 IP 단위 rate limit 추가.
--
-- 실행: Supabase 대시보드 > SQL Editor 에서 실행
-- 짝꿍 변경: src/app.js, teacher.html 의 supabase.from(...) 호출을 supabase.rpc(...) 로 교체함 (완료).

-- ============================================================
-- 0. 기존 전면 허용 정책 제거
-- ============================================================
DROP POLICY IF EXISTS "anon_all_classes" ON classes;
DROP POLICY IF EXISTS "anon_all_results" ON student_results;

-- ============================================================
-- 1. student_results 에 (class_code, student_name) 유니크 제약 추가
--    -- upsert(..., { onConflict: 'class_code,student_name' }) 가 정상 동작하려면 필요.
--    이미 존재하면 무시.
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'student_results_class_code_student_name_key'
  ) THEN
    ALTER TABLE student_results
      ADD CONSTRAINT student_results_class_code_student_name_key
      UNIQUE (class_code, student_name);
  END IF;
END $$;

-- ============================================================
-- 2. 테이블 직접 접근 차단 (RLS는 켜둔 채로, GRANT 자체를 제거)
--    PostgREST/Supabase는 anon 롤 권한(GRANT)이 없으면 RLS와 무관하게 바로 거부함.
--    이렇게 하면 /rest/v1/classes, /rest/v1/student_results 직접 호출이 전부 막힘.
-- ============================================================
REVOKE ALL ON classes FROM anon, authenticated;
REVOKE ALL ON student_results FROM anon, authenticated;

-- 혹시 모를 우회 대비, 정책도 명시적으로 항상 거부로 재설정
CREATE POLICY "deny_all_classes" ON classes
  FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

CREATE POLICY "deny_all_results" ON student_results
  FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- ============================================================
-- 3. Rate limiting — IP당 시간당 시도 횟수 제한
--    코드가 32문자^6 ≈ 10.7억 조합이라도, 시도 횟수를 제한하지 않으면
--    자동화 스크립트로 유효 코드를 찾아낼 수 있음. IP + 액션 단위로 분(minute) 버킷 카운트.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rpc_rate_limit (
  bucket_key   text NOT NULL,
  window_start timestamptz NOT NULL,
  attempts     int NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket_key, window_start)
);

CREATE INDEX IF NOT EXISTS idx_rpc_rate_limit_window ON public.rpc_rate_limit (window_start);

-- 요청자 식별 (Supabase/PostgREST가 노출하는 request.headers GUC 사용, 실패 시 'unknown')
CREATE OR REPLACE FUNCTION public._rate_limit_key()
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_headers json;
BEGIN
  BEGIN
    v_headers := current_setting('request.headers', true)::json;
  EXCEPTION WHEN OTHERS THEN
    RETURN 'unknown';
  END;
  RETURN coalesce(v_headers ->> 'cf-connecting-ip', v_headers ->> 'x-forwarded-for', 'unknown');
END;
$$;

-- 액션별 분당 허용 횟수를 넘으면 예외 발생
CREATE OR REPLACE FUNCTION public._check_rate_limit(p_action text, p_max_per_minute int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key    text := p_action || ':' || public._rate_limit_key();
  v_window timestamptz := date_trunc('minute', now());
  v_count  int;
BEGIN
  INSERT INTO rpc_rate_limit (bucket_key, window_start, attempts)
  VALUES (v_key, v_window, 1)
  ON CONFLICT (bucket_key, window_start)
  DO UPDATE SET attempts = rpc_rate_limit.attempts + 1
  RETURNING attempts INTO v_count;

  IF v_count > p_max_per_minute THEN
    RAISE EXCEPTION 'too many requests, try again later';
  END IF;
END;
$$;

-- 오래된 버킷 정리 (선택 사항). Supabase에서 pg_cron 확장을 켤 수 있다면 매시간 실행 권장:
--   select cron.schedule('cleanup_rate_limit', '0 * * * *',
--     $$ delete from public.rpc_rate_limit where window_start < now() - interval '1 hour' $$);

-- ============================================================
-- 4. RPC 함수 (SECURITY DEFINER) — 코드 검증 + rate limit을 함수 내부에서 수행
-- ============================================================

-- 4-1. 학급 코드로 학급명/교사명 조회 (학생 참여 확인 + 교사 대시보드 헤더)
CREATE OR REPLACE FUNCTION public.get_class_by_code(p_code text)
RETURNS TABLE (class_name text, teacher_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._check_rate_limit('get_class_by_code', 20);
  RETURN QUERY
    SELECT c.class_name, c.teacher_name
    FROM classes c
    WHERE c.code = upper(p_code);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_class_by_code(text) TO anon;

-- 4-2. 학급 생성 (같은 학교+교사+학급명이면 기존 코드 재사용, 아니면 새 코드 발급)
--      is_new 로 신규/기존 여부를 함께 반환 (기존 UI 문구 분기에 필요)
CREATE OR REPLACE FUNCTION public.create_class(p_school text, p_teacher text, p_class text)
RETURNS TABLE (code text, is_new boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code   text;
  v_chars  text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
BEGIN
  PERFORM public._check_rate_limit('create_class', 10);

  IF coalesce(trim(p_school), '') = '' OR coalesce(trim(p_teacher), '') = '' OR coalesce(trim(p_class), '') = '' THEN
    RAISE EXCEPTION 'school, teacher, class name are required';
  END IF;

  SELECT c.code INTO v_code FROM classes c
    WHERE c.school_name = p_school AND c.teacher_name = p_teacher AND c.class_name = p_class;

  IF v_code IS NOT NULL THEN
    RETURN QUERY SELECT v_code, false;
    RETURN;
  END IF;

  LOOP
    v_code := (
      SELECT string_agg(substr(v_chars, (floor(random() * length(v_chars)))::int + 1, 1), '')
      FROM generate_series(1, 6)
    );
    EXIT WHEN NOT EXISTS (SELECT 1 FROM classes c WHERE c.code = v_code);
  END LOOP;

  INSERT INTO classes (code, school_name, teacher_name, class_name)
  VALUES (v_code, p_school, p_teacher, p_class);

  RETURN QUERY SELECT v_code, true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_class(text, text, text) TO anon;

-- 4-3. 교사 대시보드: 해당 학급 코드의 학생 결과 목록 (10초 간격 폴링에 사용)
CREATE OR REPLACE FUNCTION public.get_student_results(p_code text)
RETURNS TABLE (
  id uuid,
  student_name text,
  galaxy_type int,
  galaxy_name text,
  scores jsonb,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._check_rate_limit('get_student_results', 30);
  RETURN QUERY
    SELECT r.id, r.student_name, r.galaxy_type, r.galaxy_name, r.scores, r.created_at
    FROM student_results r
    WHERE r.class_code = upper(p_code)
    ORDER BY r.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_student_results(text) TO anon;

-- 4-4. 학생 결과 제출 (코드가 실제 존재하는 학급인지 함수 내부에서 검증)
CREATE OR REPLACE FUNCTION public.submit_result(
  p_code text, p_name text, p_galaxy_type int, p_galaxy_name text, p_scores jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._check_rate_limit('submit_result', 20);

  IF NOT EXISTS (SELECT 1 FROM classes WHERE code = upper(p_code)) THEN
    RAISE EXCEPTION 'invalid class code';
  END IF;

  INSERT INTO student_results (class_code, student_name, galaxy_type, galaxy_name, scores)
  VALUES (upper(p_code), p_name, p_galaxy_type, p_galaxy_name, p_scores)
  ON CONFLICT (class_code, student_name)
  DO UPDATE SET galaxy_type = excluded.galaxy_type,
                galaxy_name = excluded.galaxy_name,
                scores = excluded.scores,
                created_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_result(text, text, int, text, jsonb) TO anon;

-- 4-5. 학생 결과 삭제 (행 id뿐 아니라 학급 코드도 함께 맞아야 삭제됨 -- id만으로 삭제 불가)
CREATE OR REPLACE FUNCTION public.delete_result(p_code text, p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._check_rate_limit('delete_result', 20);
  DELETE FROM student_results
  WHERE id = p_id AND class_code = upper(p_code);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_result(text, uuid) TO anon;
