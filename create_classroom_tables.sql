-- POLARIS 학급 관리 테이블
-- Supabase 대시보드 > SQL Editor 에서 실행

CREATE TABLE IF NOT EXISTS classes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    teacher_name TEXT NOT NULL,
    class_name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS student_results (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    class_code TEXT NOT NULL,
    student_name TEXT NOT NULL,
    galaxy_type INTEGER NOT NULL CHECK (galaxy_type BETWEEN 1 AND 8),
    galaxy_name TEXT NOT NULL,
    scores JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_all_classes" ON classes
    FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_all_results" ON student_results
    FOR ALL TO anon USING (true) WITH CHECK (true);
