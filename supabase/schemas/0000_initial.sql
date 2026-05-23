--
-- PostgreSQL database dump
--

\restrict KFCJTAD6atDV3iVk0H29nvHEmjqs662nNv3c0kZTrVgxcIautX2N0bamSk921oG

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: anchor_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.anchor_type_enum AS ENUM (
    'reference',
    'content',
    'temp',
    'note',
    'asset'
);


--
-- Name: asset_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.asset_type_enum AS ENUM (
    'humidifier',
    'ats',
    'ups',
    'pdu',
    'generator',
    'sts',
    'switchgear',
    'ahu',
    'acch',
    'crah',
    'rpp',
    'condensate_pump',
    'duct_heater',
    'heat_trace',
    'msb',
    'transformer',
    'exhaust_fan',
    'vesda',
    'breaker',
    'switchboard',
    'dehumidifier',
    'panelboard',
    'pump',
    'battery_string',
    'fire_system',
    'vfd',
    'fuel_tank',
    'battery_charger',
    'dry_cooler',
    'heat_exchanger',
    'cooling_tower',
    'mts',
    'other'
);


--
-- Name: log_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.log_type AS ENUM (
    'FULL',
    'CAMERA_ONLY',
    'GEOMETRY_ONLY',
    'NONE'
);


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  INSERT INTO public.users (id, contact_email)
  VALUES (NEW.id, NEW.email);
  RETURN NEW;
END;
$$;


--
-- Name: trigger_bbox_computation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_bbox_computation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: trigger_video_conversion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_video_conversion() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: anchors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.anchors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    ml2_id uuid,
    glb_position jsonb,
    space_id uuid NOT NULL,
    anchor_type public.anchor_type_enum DEFAULT 'content'::public.anchor_type_enum NOT NULL,
    glb_rotation jsonb
);


--
-- Name: asset_live_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_live_data (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    asset_id uuid,
    data jsonb NOT NULL,
    alarm boolean DEFAULT false NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: asset_models; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_models (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    site_id uuid NOT NULL,
    name text NOT NULL,
    manufacturer text,
    created_at timestamp without time zone DEFAULT now(),
    manual_id uuid
);


--
-- Name: assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    asset_type public.asset_type_enum,
    anchor_id uuid,
    building_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    asset_model_id uuid
);


--
-- Name: buildings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.buildings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    draft boolean DEFAULT true NOT NULL,
    navmesh_id uuid,
    site_id uuid NOT NULL
);


--
-- Name: experiment_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.experiment_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: latest_asset_live_data; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.latest_asset_live_data AS
 SELECT DISTINCT ON (asset_id) id,
    asset_id,
    data,
    alarm,
    "timestamp",
    created_at,
    updated_at
   FROM public.asset_live_data
  ORDER BY asset_id, "timestamp" DESC;


--
-- Name: log_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.log_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    log_id uuid NOT NULL,
    asset_id uuid NOT NULL
);


--
-- Name: logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    procedure_run_id uuid,
    step_id text,
    geometry_recording_path text,
    camera_recording_path text,
    user_id uuid NOT NULL,
    site_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    camera_recording_path_ogv text
);


--
-- Name: manuals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.manuals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    site_id uuid NOT NULL,
    title text NOT NULL,
    url text,
    path text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: navmeshes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.navmeshes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    navmesh_path text NOT NULL,
    build_settings jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    glb_path text
);


--
-- Name: notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    text text NOT NULL,
    anchor_id uuid,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: procedure_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.procedure_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    procedure_id uuid NOT NULL,
    user_id uuid NOT NULL,
    started_at timestamp without time zone DEFAULT now(),
    completed_at timestamp without time zone
);


--
-- Name: procedures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.procedures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    steps jsonb[] NOT NULL,
    building_id uuid,
    log_type public.log_type DEFAULT 'NONE'::public.log_type
);


--
-- Name: routes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    start_anchor_id uuid NOT NULL,
    end_anchor_id uuid NOT NULL,
    waypoints jsonb NOT NULL
);


--
-- Name: sites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: spaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.spaces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    blob_path text NOT NULL,
    glb_path text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    site_id uuid,
    building_id uuid,
    building_index integer,
    offset_transformation jsonb,
    bounding_box jsonb,
    loc_bounding_box jsonb
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    contact_email text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    glb_position jsonb DEFAULT '{}'::jsonb,
    site_id uuid
);

ALTER TABLE ONLY public.users REPLICA IDENTITY FULL;


--
-- Name: anchors anchors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anchors
    ADD CONSTRAINT anchors_pkey PRIMARY KEY (id);


--
-- Name: asset_live_data asset_live_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_live_data
    ADD CONSTRAINT asset_live_data_pkey PRIMARY KEY (id);


--
-- Name: asset_models asset_models_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_models
    ADD CONSTRAINT asset_models_pkey PRIMARY KEY (id);


--
-- Name: assets assets_anchor_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_anchor_id_key UNIQUE (anchor_id);


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (id);


--
-- Name: buildings buildings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buildings
    ADD CONSTRAINT buildings_pkey PRIMARY KEY (id);


--
-- Name: experiment_logs experiment_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.experiment_logs
    ADD CONSTRAINT experiment_logs_pkey PRIMARY KEY (id);


--
-- Name: log_assets log_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_assets
    ADD CONSTRAINT log_assets_pkey PRIMARY KEY (id);


--
-- Name: logs logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_pkey PRIMARY KEY (id);


--
-- Name: manuals manuals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manuals
    ADD CONSTRAINT manuals_pkey PRIMARY KEY (id);


--
-- Name: navmeshes navmeshes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.navmeshes
    ADD CONSTRAINT navmeshes_pkey PRIMARY KEY (id);


--
-- Name: notes notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id);


--
-- Name: procedure_runs procedure_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedure_runs
    ADD CONSTRAINT procedure_runs_pkey PRIMARY KEY (id);


--
-- Name: procedures procedures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedures
    ADD CONSTRAINT procedures_pkey PRIMARY KEY (id);


--
-- Name: routes routes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routes
    ADD CONSTRAINT routes_pkey PRIMARY KEY (id);


--
-- Name: sites sites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_pkey PRIMARY KEY (id);


--
-- Name: spaces spaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spaces
    ADD CONSTRAINT spaces_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_asset_live_data_asset_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_asset_live_data_asset_ts ON public.asset_live_data USING btree (asset_id, "timestamp" DESC);


--
-- Name: logs on_log_insert_convert_video; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_log_insert_convert_video AFTER INSERT ON public.logs FOR EACH ROW EXECUTE FUNCTION public.trigger_video_conversion();


--
-- Name: spaces on_space_glb_set_compute_bbox; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_space_glb_set_compute_bbox AFTER INSERT OR UPDATE OF glb_path ON public.spaces FOR EACH ROW EXECUTE FUNCTION public.trigger_bbox_computation();


--
-- Name: anchors anchors_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anchors
    ADD CONSTRAINT anchors_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.spaces(id) ON DELETE CASCADE;


--
-- Name: asset_live_data asset_live_data_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_live_data
    ADD CONSTRAINT asset_live_data_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(id) ON DELETE CASCADE;


--
-- Name: asset_models asset_models_manual_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_models
    ADD CONSTRAINT asset_models_manual_id_fkey FOREIGN KEY (manual_id) REFERENCES public.manuals(id) ON DELETE SET NULL;


--
-- Name: asset_models asset_models_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_models
    ADD CONSTRAINT asset_models_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE;


--
-- Name: assets assets_anchor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES public.anchors(id) ON DELETE SET NULL;


--
-- Name: assets assets_asset_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_asset_model_id_fkey FOREIGN KEY (asset_model_id) REFERENCES public.asset_models(id) ON DELETE SET NULL;


--
-- Name: assets assets_building_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_building_id_fkey FOREIGN KEY (building_id) REFERENCES public.buildings(id) ON DELETE CASCADE;


--
-- Name: buildings buildings_navmesh_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buildings
    ADD CONSTRAINT buildings_navmesh_id_fkey FOREIGN KEY (navmesh_id) REFERENCES public.navmeshes(id) ON DELETE CASCADE;


--
-- Name: buildings buildings_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buildings
    ADD CONSTRAINT buildings_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE;


--
-- Name: log_assets log_assets_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_assets
    ADD CONSTRAINT log_assets_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(id) ON DELETE CASCADE;


--
-- Name: log_assets log_assets_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_assets
    ADD CONSTRAINT log_assets_log_id_fkey FOREIGN KEY (log_id) REFERENCES public.logs(id) ON DELETE CASCADE;


--
-- Name: logs logs_procedure_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_procedure_run_id_fkey FOREIGN KEY (procedure_run_id) REFERENCES public.procedure_runs(id) ON DELETE CASCADE;


--
-- Name: logs logs_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE;


--
-- Name: logs logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: manuals manuals_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manuals
    ADD CONSTRAINT manuals_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE;


--
-- Name: notes notes_anchor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES public.anchors(id) ON DELETE CASCADE;


--
-- Name: procedure_runs procedure_runs_procedure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedure_runs
    ADD CONSTRAINT procedure_runs_procedure_id_fkey FOREIGN KEY (procedure_id) REFERENCES public.procedures(id) ON DELETE CASCADE;


--
-- Name: procedure_runs procedure_runs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedure_runs
    ADD CONSTRAINT procedure_runs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: procedures procedures_building_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedures
    ADD CONSTRAINT procedures_building_id_fkey FOREIGN KEY (building_id) REFERENCES public.buildings(id) ON DELETE SET NULL;


--
-- Name: routes routes_end_anchor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routes
    ADD CONSTRAINT routes_end_anchor_id_fkey FOREIGN KEY (end_anchor_id) REFERENCES public.anchors(id) ON DELETE CASCADE;


--
-- Name: routes routes_start_anchor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routes
    ADD CONSTRAINT routes_start_anchor_id_fkey FOREIGN KEY (start_anchor_id) REFERENCES public.anchors(id) ON DELETE CASCADE;


--
-- Name: spaces spaces_building_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spaces
    ADD CONSTRAINT spaces_building_id_fkey FOREIGN KEY (building_id) REFERENCES public.buildings(id) ON DELETE SET NULL;


--
-- Name: spaces spaces_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spaces
    ADD CONSTRAINT spaces_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE;


--
-- Name: users users_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE SET NULL;


--
-- Name: asset_live_data Allow users to read live asset data for assets they have access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow users to read live asset data for assets they have access" ON public.asset_live_data FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.assets
  WHERE (assets.id = asset_live_data.asset_id))));


--
-- Name: navmeshes Site members can insert navmeshes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Site members can insert navmeshes" ON public.navmeshes FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE (users.site_id IS NOT NULL))));


--
-- Name: buildings Site members can update buildings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Site members can update buildings" ON public.buildings FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.site_id = buildings.site_id) AND (users.id = ( SELECT auth.uid() AS uid))))));


--
-- Name: navmeshes Site members can update navmeshes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Site members can update navmeshes" ON public.navmeshes FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM (public.buildings
     JOIN public.users ON ((users.site_id = buildings.site_id)))
  WHERE ((buildings.navmesh_id = navmeshes.id) AND (users.id = ( SELECT auth.uid() AS uid))))));


--
-- Name: anchors Users can delete anchors for their spaces; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete anchors for their spaces" ON public.anchors FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.spaces
  WHERE (spaces.id = anchors.space_id))));


--
-- Name: asset_models Users can delete asset models for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete asset models for sites they have access to" ON public.asset_models FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = asset_models.site_id))));


--
-- Name: assets Users can delete assets for buildings they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete assets for buildings they have access to" ON public.assets FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = assets.building_id))));


--
-- Name: buildings Users can delete buildings for their sites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete buildings for their sites" ON public.buildings FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = buildings.site_id))));


--
-- Name: manuals Users can delete manuals for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete manuals for sites they have access to" ON public.manuals FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = manuals.site_id))));


--
-- Name: notes Users can delete notes for their anchors; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete notes for their anchors" ON public.notes FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.anchors
  WHERE (anchors.id = notes.anchor_id))));


--
-- Name: procedures Users can delete procedures for their buildings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete procedures for their buildings" ON public.procedures FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = procedures.building_id))));


--
-- Name: spaces Users can delete spaces for their sites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete spaces for their sites" ON public.spaces FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = spaces.site_id))));


--
-- Name: users Users can delete their own user record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete their own user record" ON public.users FOR DELETE USING ((auth.uid() = id));


--
-- Name: anchors Users can insert anchors for their spaces; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert anchors for their spaces" ON public.anchors FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.spaces
  WHERE (spaces.id = anchors.space_id))));


--
-- Name: asset_models Users can insert asset models for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert asset models for sites they have access to" ON public.asset_models FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = asset_models.site_id))));


--
-- Name: assets Users can insert assets for buildings they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert assets for buildings they have access to" ON public.assets FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = assets.building_id))));


--
-- Name: buildings Users can insert buildings for their sites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert buildings for their sites" ON public.buildings FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = buildings.site_id))));


--
-- Name: log_assets Users can insert log_assets for assets and logs they have acces; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert log_assets for assets and logs they have acces" ON public.log_assets FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM public.logs
  WHERE (logs.id = log_assets.log_id))) AND (EXISTS ( SELECT 1
   FROM public.assets
  WHERE (assets.id = log_assets.asset_id)))));


--
-- Name: logs Users can insert logs for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert logs for sites they have access to" ON public.logs FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = logs.site_id))));


--
-- Name: manuals Users can insert manuals for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert manuals for sites they have access to" ON public.manuals FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = manuals.site_id))));


--
-- Name: notes Users can insert notes for their anchors; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert notes for their anchors" ON public.notes FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.anchors
  WHERE (anchors.id = notes.anchor_id))));


--
-- Name: procedure_runs Users can insert procedure runs for procedures they have access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert procedure runs for procedures they have access" ON public.procedure_runs FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.procedures
  WHERE (procedures.id = procedure_runs.procedure_id))));


--
-- Name: procedures Users can insert procedures for their buildings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert procedures for their buildings" ON public.procedures FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = procedures.building_id))));


--
-- Name: spaces Users can insert spaces for their sites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert spaces for their sites" ON public.spaces FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = spaces.site_id))));


--
-- Name: users Users can insert their own user record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert their own user record" ON public.users FOR INSERT WITH CHECK ((auth.uid() = id));


--
-- Name: anchors Users can update anchors for their spaces; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update anchors for their spaces" ON public.anchors FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.spaces
  WHERE (spaces.id = anchors.space_id))));


--
-- Name: asset_models Users can update asset models for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update asset models for sites they have access to" ON public.asset_models FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = asset_models.site_id))));


--
-- Name: assets Users can update assets for buildings they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update assets for buildings they have access to" ON public.assets FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = assets.building_id)))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = assets.building_id))));


--
-- Name: buildings Users can update buildings for their sites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update buildings for their sites" ON public.buildings FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = buildings.site_id))));


--
-- Name: manuals Users can update manuals for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update manuals for sites they have access to" ON public.manuals FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = manuals.site_id))));


--
-- Name: notes Users can update notes for their anchors; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update notes for their anchors" ON public.notes FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.anchors
  WHERE (anchors.id = notes.anchor_id))));


--
-- Name: procedures Users can update procedures for their buildings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update procedures for their buildings" ON public.procedures FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = procedures.building_id))));


--
-- Name: spaces Users can update spaces for their sites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update spaces for their sites" ON public.spaces FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = spaces.site_id))));


--
-- Name: users Users can update their own user record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own user record" ON public.users FOR UPDATE USING ((auth.uid() = id));


--
-- Name: anchors Users can view anchors for spaces they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view anchors for spaces they have access to" ON public.anchors FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.spaces
  WHERE (spaces.id = anchors.space_id))));


--
-- Name: asset_models Users can view asset models for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view asset models for sites they have access to" ON public.asset_models FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = asset_models.site_id))));


--
-- Name: assets Users can view assets for buildings they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view assets for buildings they have access to" ON public.assets FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = assets.building_id))));


--
-- Name: buildings Users can view buildings for sites they belong to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view buildings for sites they belong to" ON public.buildings FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = buildings.site_id))));


--
-- Name: log_assets Users can view log_assets for assets and logs they have access ; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view log_assets for assets and logs they have access " ON public.log_assets FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.logs
  WHERE (logs.id = log_assets.log_id))) AND (EXISTS ( SELECT 1
   FROM public.assets
  WHERE (assets.id = log_assets.asset_id)))));


--
-- Name: logs Users can view logs for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view logs for sites they have access to" ON public.logs FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = logs.site_id))));


--
-- Name: manuals Users can view manuals for sites they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view manuals for sites they have access to" ON public.manuals FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = manuals.site_id))));


--
-- Name: navmeshes Users can view navmeshes for buildings they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view navmeshes for buildings they have access to" ON public.navmeshes FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.navmesh_id = navmeshes.id))));


--
-- Name: notes Users can view notes for anchors they have access to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view notes for anchors they have access to" ON public.notes FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.anchors
  WHERE (notes.anchor_id = notes.anchor_id))));


--
-- Name: procedure_runs Users can view procedure runs for procedures they have access t; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view procedure runs for procedures they have access t" ON public.procedure_runs FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.procedures
  WHERE (procedures.id = procedure_runs.procedure_id))));


--
-- Name: procedures Users can view procedures for buildings they belong to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view procedures for buildings they belong to" ON public.procedures FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.buildings
  WHERE (buildings.id = procedures.building_id))));


--
-- Name: sites Users can view sites they belong to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view sites they belong to" ON public.sites FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE (users.site_id = sites.id))));


--
-- Name: spaces Users can view spaces for sites they belong to; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view spaces for sites they belong to" ON public.spaces FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.sites
  WHERE (sites.id = spaces.site_id))));


--
-- Name: users Users can view their own user record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their own user record" ON public.users FOR SELECT USING ((auth.uid() = id));


--
-- Name: anchors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.anchors ENABLE ROW LEVEL SECURITY;

--
-- Name: asset_live_data; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.asset_live_data ENABLE ROW LEVEL SECURITY;

--
-- Name: asset_models; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.asset_models ENABLE ROW LEVEL SECURITY;

--
-- Name: assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;

--
-- Name: buildings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.buildings ENABLE ROW LEVEL SECURITY;

--
-- Name: log_assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.log_assets ENABLE ROW LEVEL SECURITY;

--
-- Name: logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.logs ENABLE ROW LEVEL SECURITY;

--
-- Name: manuals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.manuals ENABLE ROW LEVEL SECURITY;

--
-- Name: navmeshes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.navmeshes ENABLE ROW LEVEL SECURITY;

--
-- Name: notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;

--
-- Name: procedure_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.procedure_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: procedures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.procedures ENABLE ROW LEVEL SECURITY;

--
-- Name: notes public access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public access" ON public.notes USING (true);


--
-- Name: sites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;

--
-- Name: spaces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.spaces ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict KFCJTAD6atDV3iVk0H29nvHEmjqs662nNv3c0kZTrVgxcIautX2N0bamSk921oG

