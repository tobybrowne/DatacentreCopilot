ALTER TABLE spaces ADD COLUMN IF NOT EXISTS bounding_box JSONB;

-- Fires whenever a GLB is first set or replaced, triggering bbox computation
-- on the mono service. Same pattern as on_log_insert_convert_video.
CREATE OR REPLACE FUNCTION trigger_bbox_computation()
RETURNS trigger AS $$
BEGIN
  IF NEW.glb_path IS NOT NULL AND (OLD IS NULL OR OLD.glb_path IS DISTINCT FROM NEW.glb_path) THEN
    PERFORM net.http_post(
      'https://room-finder.tobybrowne.co.uk/spaces/compute-bbox'::text,
      json_build_object('space_id', NEW.id)::jsonb,
      '{"Content-Type": "application/json"}'::jsonb
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_space_glb_set_compute_bbox
  AFTER INSERT OR UPDATE OF glb_path ON spaces
  FOR EACH ROW
  EXECUTE FUNCTION trigger_bbox_computation();
