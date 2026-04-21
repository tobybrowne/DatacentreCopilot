-- Fix sites RLS policy: 'id' was resolving to site_users.id instead of sites.id
DROP POLICY IF EXISTS "Users can view sites they belong to" ON sites;

CREATE POLICY "Users can view sites they belong to"
ON sites FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM site_users
    WHERE site_users.user_id = (SELECT auth.uid())
      AND site_users.site_id = sites.id
  )
);
