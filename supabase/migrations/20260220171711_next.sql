
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Track the user's real-world position in GLB/mesh coordinate frame,
-- written by the ML2 headset app each second via inverse Kabsch transform.
ALTER TABLE users
  ADD COLUMN glb_position jsonb DEFAULT '{}';


INSERT INTO users (id, contact_email) VALUES ('00000000-0000-0000-0000-000000000000', 'demo@entangl.ai');