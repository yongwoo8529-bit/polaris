-- 교사 로그인(이메일/비밀번호) 도입 + 학급 소유권(owner_id) 도입
-- 문제: teacher.html이 고정 비밀번호(pw-gate, 'polaris2026') + "학급코드만 알면 관리 가능"
--       구조라 실질적인 계정 구분이 없었음.
-- 방향: 회원가입 화면은 만들지 않음 — 계정은 관리자(사장님)가 Supabase 대시보드에서
--       직접 발급. 로그인한 계정이 만든 학급만 그 계정에서 조회/삭제 가능하도록 변경.
--
-- ============================================================
-- 사전 준비 (이 SQL 실행 전에 반드시 먼저 하세요)
-- ============================================================
-- Supabase 대시보드 > Authentication > Users > Add user
--   - Email: yongwoo8529@gmail.com (본인 이메일)
--   - Password: 원하는 비밀번호
--   - "Auto Confirm User" 체크 (이메일 인증 절차 없이 바로 로그인 가능하게)
-- 계정 생성 후 아래 SQL 실행.
--
-- 실행: Supabase 대시보드 > SQL Editor

-- 1. classes에 소유자 컬럼 추가
ALTER TABLE public.classes ADD COLUMN IF NOT EXISTS owner_id uuid REFERENCES auth.users(id);

-- 2. 기존 학급 전부 관리자 계정으로 연결
--    (다른 이메일로 계정을 만들었다면 아래 이메일 주소를 그것으로 바꿔서 실행)
UPDATE public.classes
SET owner_id = (SELECT id FROM auth.users WHERE email = 'yongwoo8529@gmail.com')
WHERE owner_id IS NULL;

-- 3. 내 학급 목록 (로그인 필요) — 코드 입력 없이 본인 학급이 자동으로 조회됨
CREATE OR REPLACE FUNCTION public.get_my_classes()
RETURNS TABLE (
  code text, school_name text, teacher_name text, class_name text,
  created_at timestamptz, student_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;

  RETURN QUERY
    SELECT c.code, c.school_name, c.teacher_name, c.class_name, c.created_at,
           (SELECT count(*) FROM student_results r WHERE r.class_code = c.code)
    FROM classes c
    WHERE c.owner_id = auth.uid()
    ORDER BY c.created_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_classes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_classes() TO authenticated;

-- 4. create_class: 로그인 필요 + owner_id 자동 설정 (anon 접근 차단으로 교체)
CREATE OR REPLACE FUNCTION public.create_class(p_school text, p_teacher text, p_class text)
RETURNS TABLE (code text, is_new boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code  text;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_uid   uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;

  PERFORM public._check_rate_limit('create_class', 10);

  IF coalesce(trim(p_school), '') = '' OR coalesce(trim(p_teacher), '') = '' OR coalesce(trim(p_class), '') = '' THEN
    RAISE EXCEPTION 'school, teacher, class name are required';
  END IF;

  SELECT c.code INTO v_code FROM classes c
    WHERE c.owner_id = v_uid AND c.school_name = p_school AND c.teacher_name = p_teacher AND c.class_name = p_class;

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

  INSERT INTO classes (code, school_name, teacher_name, class_name, owner_id)
  VALUES (v_code, p_school, p_teacher, p_class, v_uid);

  RETURN QUERY SELECT v_code, true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_class(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_class(text, text, text) TO authenticated;

-- 5. get_student_results: 로그인 + 본인 소유 학급만 (anon 접근 차단으로 교체)
CREATE OR REPLACE FUNCTION public.get_student_results(p_code text)
RETURNS TABLE (id uuid, student_name text, galaxy_type int, galaxy_name text, scores jsonb, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM classes c WHERE c.code = upper(p_code) AND c.owner_id = auth.uid()) THEN
    RAISE EXCEPTION 'not found or not owned';
  END IF;

  RETURN QUERY
    SELECT r.id, r.student_name, r.galaxy_type, r.galaxy_name, r.scores, r.created_at
    FROM student_results r
    WHERE r.class_code = upper(p_code)
    ORDER BY r.created_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_student_results(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_student_results(text) TO authenticated;

-- 6. delete_result: 로그인 + 본인 소유 학급만 (anon 접근 차단으로 교체)
CREATE OR REPLACE FUNCTION public.delete_result(p_code text, p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM classes c WHERE c.code = upper(p_code) AND c.owner_id = auth.uid()) THEN
    RAISE EXCEPTION 'not found or not owned';
  END IF;

  DELETE FROM student_results WHERE id = p_id AND class_code = upper(p_code);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_result(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_result(text, uuid) TO authenticated;
