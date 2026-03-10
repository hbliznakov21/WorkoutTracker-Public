-- =============================================================================
-- WorkoutTracker — Supabase Database Setup
-- =============================================================================
-- Run this in your Supabase SQL Editor (https://supabase.com/dashboard)
-- to create all required tables for the WorkoutTracker iOS app.
-- =============================================================================

-- MARK: - Core tables

CREATE TABLE routines (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    day_label   TEXT,
    created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE exercises (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL,
    muscle_group TEXT,
    equipment    TEXT,
    created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE routine_exercises (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id      UUID NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    exercise_id     UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    position        INTEGER NOT NULL,
    target_sets     INTEGER NOT NULL DEFAULT 3,
    target_reps_min INTEGER,
    target_reps_max INTEGER,
    notes           TEXT,
    superset_group  TEXT,
    is_warmup       BOOLEAN DEFAULT FALSE,
    rest_seconds    INTEGER DEFAULT 90,
    created_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE(routine_id, exercise_id)
);

CREATE TABLE workouts (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id     UUID REFERENCES routines(id) ON DELETE SET NULL,
    routine_name   TEXT NOT NULL,
    started_at     TIMESTAMPTZ NOT NULL,
    finished_at    TIMESTAMPTZ,
    calories       INTEGER,
    avg_heart_rate INTEGER,
    healthkit_uuid TEXT,
    created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE workout_sets (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_id    UUID NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    exercise_id   UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    exercise_name TEXT NOT NULL,
    set_number    INTEGER NOT NULL,
    weight_kg     NUMERIC(10, 2) NOT NULL,
    reps          INTEGER NOT NULL,
    logged_at     TIMESTAMPTZ NOT NULL,
    created_at    TIMESTAMPTZ DEFAULT now()
);

-- MARK: - Body & schedule

CREATE TABLE body_weight (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    logged_at TEXT NOT NULL UNIQUE,          -- yyyy-MM-dd
    weight_kg NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE rest_days (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rest_date TEXT NOT NULL UNIQUE,          -- yyyy-MM-dd
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE weekly_schedule (
    id       INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    schedule JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- MARK: - AI analysis cache

CREATE TABLE workout_analyses (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_id    UUID NOT NULL UNIQUE REFERENCES workouts(id) ON DELETE CASCADE,
    routine_name  TEXT NOT NULL,
    analysis_json TEXT NOT NULL,
    created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE session_goals (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_name TEXT NOT NULL,
    goal_date    TEXT NOT NULL,
    goals_json   TEXT NOT NULL,
    created_at   TIMESTAMPTZ DEFAULT now()
);

-- MARK: - Indexes

CREATE INDEX idx_routine_exercises_routine  ON routine_exercises(routine_id);
CREATE INDEX idx_workouts_started_at        ON workouts(started_at);
CREATE INDEX idx_workouts_routine_id        ON workouts(routine_id);
CREATE INDEX idx_workout_sets_workout       ON workout_sets(workout_id);
CREATE INDEX idx_workout_sets_exercise      ON workout_sets(exercise_id);
CREATE INDEX idx_workout_sets_name          ON workout_sets(exercise_name);
CREATE INDEX idx_body_weight_logged_at      ON body_weight(logged_at);
CREATE INDEX idx_rest_days_date             ON rest_days(rest_date);
CREATE INDEX idx_analyses_workout           ON workout_analyses(workout_id);
CREATE INDEX idx_goals_routine              ON session_goals(routine_name);

-- MARK: - Row Level Security (open access with anon key)

ALTER TABLE routines           ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercises          ENABLE ROW LEVEL SECURITY;
ALTER TABLE routine_exercises  ENABLE ROW LEVEL SECURITY;
ALTER TABLE workouts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_sets       ENABLE ROW LEVEL SECURITY;
ALTER TABLE body_weight        ENABLE ROW LEVEL SECURITY;
ALTER TABLE rest_days          ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_schedule    ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_analyses   ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_goals      ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_all" ON routines          FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON exercises         FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON routine_exercises FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON workouts          FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON workout_sets      FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON body_weight       FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON rest_days         FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON weekly_schedule   FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON workout_analyses  FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON session_goals     FOR ALL TO anon USING (true) WITH CHECK (true);

-- =============================================================================
-- MARK: - Seed data (optional starter exercises)
-- =============================================================================
-- Uncomment and run to populate a basic exercise library.

/*
INSERT INTO exercises (name, muscle_group, equipment) VALUES
  -- Chest
  ('Bench Press',             'Chest',     'Barbell'),
  ('Incline Bench Press',     'Chest',     'Barbell'),
  ('Incline DB Press',        'Chest',     'Dumbbell'),
  ('Cable Chest Fly',         'Chest',     'Cable'),
  ('Machine Chest Press',     'Chest',     'Machine'),
  ('Dips',                    'Chest',     'Bodyweight'),
  -- Back
  ('Barbell Row',             'Back',      'Barbell'),
  ('Seated Cable Row',        'Back',      'Cable'),
  ('Lat Pulldown',            'Back',      'Cable'),
  ('T-Bar Row',               'Back',      'Barbell'),
  ('Pull-ups',                'Back',      'Bodyweight'),
  ('Face Pull',               'Back',      'Cable'),
  -- Shoulders
  ('Overhead Press',          'Shoulders', 'Barbell'),
  ('DB Lateral Raise',        'Shoulders', 'Dumbbell'),
  ('Cable Lateral Raise',     'Shoulders', 'Cable'),
  ('Reverse Pec Deck',        'Shoulders', 'Machine'),
  -- Arms
  ('Barbell Curl',            'Biceps',    'Barbell'),
  ('Hammer Curl',             'Biceps',    'Dumbbell'),
  ('Cable Curl',              'Biceps',    'Cable'),
  ('Tricep Pushdown',         'Triceps',   'Cable'),
  ('Overhead Tricep Ext',     'Triceps',   'Cable'),
  ('Skull Crushers',          'Triceps',   'Barbell'),
  -- Legs
  ('Squat',                   'Legs',      'Barbell'),
  ('Hack Squat',              'Legs',      'Machine'),
  ('Leg Press',               'Legs',      'Machine'),
  ('Romanian Deadlift',       'Legs',      'Barbell'),
  ('Leg Curl',                'Legs',      'Machine'),
  ('Leg Extension',           'Legs',      'Machine'),
  ('Calf Raise',              'Calves',    'Machine'),
  ('Hip Thrust',              'Glutes',    'Barbell'),
  -- Core
  ('Ab Wheel Rollout',        'Core',      'Bodyweight'),
  ('Cable Crunch',            'Core',      'Cable'),
  ('Pallof Press',            'Core',      'Cable'),
  ('Hanging Leg Raise',       'Core',      'Bodyweight');
*/

-- Done! Your WorkoutTracker database is ready.
-- Next: copy Config.plist.example to Config.plist and add your Supabase URL + anon key.
