-- 은하 통신선(board.html) 게시판을 localStorage → Supabase로 전환
-- 문제: 기존엔 localStorage만 사용해서 실제로는 기기/브라우저 간 공유가 전혀 안 되는 "가짜 게시판"이었음.
-- fix_rls_policies.sql에서 만든 _check_rate_limit() 재사용 (먼저 그 파일이 실행되어 있어야 함).
--
-- 실행: Supabase 대시보드 > SQL Editor

CREATE TABLE IF NOT EXISTS public.board_messages (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  galaxy_type  int NOT NULL CHECK (galaxy_type BETWEEN 1 AND 7),
  content      text NOT NULL CHECK (char_length(content) BETWEEN 1 AND 500),
  likes        int NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.board_messages ENABLE ROW LEVEL SECURITY;

-- 다른 테이블과 동일한 패턴: 직접 접근은 전부 차단, RPC로만 접근
REVOKE ALL ON public.board_messages FROM anon, authenticated;

CREATE POLICY "deny_all_board_messages" ON public.board_messages
  FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- 목록 조회 (p_type = NULL 이면 전체)
CREATE OR REPLACE FUNCTION public.get_board_messages(p_type int DEFAULT NULL)
RETURNS TABLE (id uuid, galaxy_type int, content text, likes int, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._check_rate_limit('get_board_messages', 60);
  RETURN QUERY
    SELECT m.id, m.galaxy_type, m.content, m.likes, m.created_at
    FROM board_messages m
    WHERE p_type IS NULL OR m.galaxy_type = p_type
    ORDER BY m.created_at DESC
    LIMIT 200;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_board_messages(int) TO anon;

-- 신호(메시지) 등록
CREATE OR REPLACE FUNCTION public.post_board_message(p_type int, p_content text)
RETURNS TABLE (id uuid, galaxy_type int, content text, likes int, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_content text := trim(p_content);
BEGIN
  PERFORM public._check_rate_limit('post_board_message', 5);

  IF p_type IS NULL OR p_type NOT BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'invalid galaxy type';
  END IF;
  IF char_length(v_content) < 1 OR char_length(v_content) > 500 THEN
    RAISE EXCEPTION 'content must be 1-500 characters';
  END IF;

  RETURN QUERY
    INSERT INTO board_messages (galaxy_type, content)
    VALUES (p_type, v_content)
    RETURNING board_messages.id, board_messages.galaxy_type, board_messages.content,
              board_messages.likes, board_messages.created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_board_message(int, text) TO anon;

-- 좋아요 (1씩 증가만 가능; 중복 클릭 방지는 클라이언트 sessionStorage로 처리)
CREATE OR REPLACE FUNCTION public.like_board_message(p_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_likes int;
BEGIN
  PERFORM public._check_rate_limit('like_board_message', 30);

  UPDATE board_messages SET likes = likes + 1
  WHERE id = p_id
  RETURNING likes INTO v_likes;

  IF v_likes IS NULL THEN
    RAISE EXCEPTION 'message not found';
  END IF;

  RETURN v_likes;
END;
$$;

GRANT EXECUTE ON FUNCTION public.like_board_message(uuid) TO anon;
