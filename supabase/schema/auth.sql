-- Auth subsystem
-- users wraps auth.users (Supabase Auth). A trigger auto-creates a users row on auth signup.
-- site_users is the many-to-many join between users and sites.
-- sites and site_users are managed by service role only (no user INSERT/DELETE).

CREATE TABLE users (
  id UUID NOT NULL PRIMARY KEY, -- mirrors auth.users.id
  contact_email TEXT NOT NULL,
  glb_position JSONB DEFAULT '{}', -- {x, y, z} last known position in GLB coordinate frame
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE FUNCTION handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.users (id, contact_email) VALUES (NEW.id, NEW.email);
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- RLS: users can only see/modify their own row
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own user record"
ON users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can insert their own user record"
ON users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can delete their own user record"
ON users FOR DELETE USING (auth.uid() = id);


CREATE TABLE sites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- RLS: users can see sites they are members of (via site_users)
ALTER TABLE sites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view sites they belong to"
ON sites FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM site_users
    WHERE site_users.user_id = (SELECT auth.uid())
      AND site_users.site_id = sites.id
  )
);


CREATE TABLE site_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE
);

-- RLS: users can only see their own site_users rows
ALTER TABLE site_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own site user record"
ON site_users FOR SELECT USING (auth.uid() = user_id);
