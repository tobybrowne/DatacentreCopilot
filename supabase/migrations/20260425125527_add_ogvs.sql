ALTER TABLE logs
ADD COLUMN camera_recording_path_ogv TEXT;

-- TODO: don't hardcode the endpoint
CREATE OR REPLACE FUNCTION trigger_video_conversion()
RETURNS trigger AS $$
BEGIN
  IF NEW.camera_recording_path IS NOT NULL THEN
    PERFORM net.http_post(
      'https://room-finder.tobybrowne.co.uk/video/convert'::text,
      json_build_object('log_id', NEW.id)::jsonb,
      '{"Content-Type": "application/json"}'::jsonb
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_log_insert_convert_video
  AFTER INSERT ON logs
  FOR EACH ROW
  EXECUTE FUNCTION trigger_video_conversion();