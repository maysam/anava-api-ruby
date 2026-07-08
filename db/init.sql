-- Schema for the standalone Ruby/Sinatra API (adapted from
-- supabase/migrations/001_create_recordings_table.sql — Supabase RLS/auth
-- policies removed since this runs against plain Postgres).
CREATE TABLE IF NOT EXISTS recordings (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    model VARCHAR(255) NOT NULL,
    build VARCHAR(255) NOT NULL,
    version VARCHAR(255) NOT NULL,
    date DATE NOT NULL,
    slot_id INTEGER NOT NULL,
    start_timestamp BIGINT NOT NULL,
    end_timestamp BIGINT NOT NULL,
    amplitudes_json TEXT NOT NULL,
    longitude DECIMAL(10, 7),
    latitude DECIMAL(10, 7),
    duration INTEGER,
    percentage INTEGER,
    file_path TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_recordings_user_id ON recordings(user_id);
CREATE INDEX IF NOT EXISTS idx_recordings_date ON recordings(date);
CREATE INDEX IF NOT EXISTS idx_recordings_user_id_date ON recordings(user_id, date);
CREATE INDEX IF NOT EXISTS idx_recordings_start_timestamp ON recordings(start_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_recordings_end_timestamp ON recordings(end_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_recordings_slot_id ON recordings(slot_id);
CREATE INDEX IF NOT EXISTS idx_recordings_model ON recordings(model);

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_recordings_updated_at ON recordings;
CREATE TRIGGER update_recordings_updated_at BEFORE UPDATE
    ON recordings FOR EACH ROW EXECUTE PROCEDURE
    update_updated_at_column();

CREATE OR REPLACE FUNCTION get_user_count()
RETURNS TABLE(user_count bigint)
LANGUAGE sql
AS $$
  SELECT count(distinct user_id) AS user_count
  FROM recordings;
$$;

CREATE OR REPLACE FUNCTION get_user_rank(start_date date, end_date date, target_user text)
RETURNS TABLE(user_id text, avg_percentage numeric, rank integer)
LANGUAGE sql
AS $$
  with ranked_users as (
    select
      user_id,
      avg(percentage) as avg_percentage,
      rank() over (order by avg(percentage) desc) as rank
    from recordings
    where date between start_date and end_date
    group by user_id
  )
  select user_id, avg_percentage, rank::integer
  from ranked_users
  where user_id = target_user
$$;
