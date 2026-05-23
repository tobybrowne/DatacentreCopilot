-- Update trigger functions to include webhook auth secret from Vault.
-- Before applying, create the secret once:
--   select vault.create_secret('YOUR_SECRET_VALUE', 'webhook_secret');

CREATE OR REPLACE FUNCTION public.trigger_bbox_computation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  _secret text;
BEGIN
  IF NEW.glb_path IS NOT NULL AND (OLD IS NULL OR OLD.glb_path IS DISTINCT FROM NEW.glb_path) THEN
    SELECT decrypted_secret INTO _secret FROM vault.decrypted_secrets WHERE name = 'webhook_secret';
    PERFORM net.http_post(
      'https://room-finder.tobybrowne.co.uk/spaces/compute-bbox'::text,
      json_build_object('space_id', NEW.id)::jsonb,
      jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || _secret)
    );
  END IF;
  RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION public.trigger_video_conversion() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  _secret text;
BEGIN
  IF NEW.camera_recording_path IS NOT NULL THEN
    SELECT decrypted_secret INTO _secret FROM vault.decrypted_secrets WHERE name = 'webhook_secret';
    PERFORM net.http_post(
      'https://room-finder.tobybrowne.co.uk/video/convert'::text,
      json_build_object('log_id', NEW.id)::jsonb,
      jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || _secret)
    );
  END IF;
  RETURN NEW;
END;
$$;
