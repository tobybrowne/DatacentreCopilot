CREATE TYPE log_type AS ENUM (
  'FULL',
  'CAMERA_ONLY',
  'GEOMETRY_ONLY',
  'NONE'
);

ALTER TABLE procedures ADD COLUMN log_type log_type DEFAULT 'NONE';