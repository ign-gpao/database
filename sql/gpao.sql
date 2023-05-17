--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2 (Debian 14.2-1.pgdg110+1)
-- Dumped by pg_dump version 14.2 (Debian 14.2-1.pgdg110+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: gpao; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE gpao WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'en_US.utf8';


ALTER DATABASE gpao OWNER TO postgres;

\connect gpao

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: priority; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.priority AS ENUM (
    'low',
    'normal',
    'high'
);


ALTER TYPE public.priority OWNER TO postgres;

--
-- Name: session_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.session_status AS ENUM (
    'idle',
    'active',
    'idle_requested',
    'running',
    'closed'
);


ALTER TYPE public.session_status OWNER TO postgres;

--
-- Name: status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.status AS ENUM (
    'waiting',
    'ready',
    'running',
    'done',
    'failed'
);


ALTER TYPE public.status OWNER TO postgres;

--
-- Name: assign_first_job_ready_for_session(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.assign_first_job_ready_for_session(a_session_id integer) RETURNS TABLE(id integer, command character varying)
    LANGUAGE sql
    AS $$    WITH selectedJob AS (
	SELECT J.id FROM jobs J, projects P
	WHERE
		J.id_project = P.id AND
		J.tags <@ (SELECT S.tags FROM sessions S WHERE S.id = a_session_id) AND
		J.status = 'ready'
	ORDER BY P.priority DESC, J.id
	LIMIT 1
	FOR UPDATE SKIP LOCKED)
	UPDATE jobs
	SET status = 'running', start_date=NOW(), id_session = a_session_id
	WHERE
		(SELECT S.status FROM sessions S WHERE S.id = a_session_id) = 'active'
    	AND
		id in (SELECT id FROM selectedJob)
    RETURNING id, command;
$$;


ALTER FUNCTION public.assign_first_job_ready_for_session(a_session_id integer) OWNER TO postgres;

--
-- Name: clean_database(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.clean_database() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  TRUNCATE table projects, sessions CASCADE;
END;
$$;


ALTER FUNCTION public.clean_database() OWNER TO postgres;

--
-- Name: clean_old_session(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.clean_old_session(hostname character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  nb_sessions integer;
BEGIN
  UPDATE sessions SET status = 'closed', end_date=NOW() WHERE sessions.host LIKE hostname AND status <> 'closed';
  GET DIAGNOSTICS nb_sessions = ROW_COUNT;
  RETURN nb_sessions;
END;
$$;


ALTER FUNCTION public.clean_old_session(hostname character varying) OWNER TO postgres;

--
-- Name: clean_unused_session(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.clean_unused_session() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  nb_sessions integer;
BEGIN
  DELETE FROM sessions WHERE id IN (SELECT sessions.id
  FROM sessions
  LEFT JOIN jobs ON sessions.id = jobs.id_session
  WHERE jobs.id_session IS NULL and sessions.status = 'closed');
  GET DIAGNOSTICS nb_sessions = ROW_COUNT;
  RETURN nb_sessions;
END;
$$;


ALTER FUNCTION public.clean_unused_session() OWNER TO postgres;

--
-- Name: reinit_jobs(integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.reinit_jobs(ids integer[]) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  nb_jobs integer;
BEGIN
  UPDATE jobs SET status = 'ready', id_session = NULL, log=NULL, return_code=NULL, start_date=NULL, end_date=NULL
  WHERE id = ANY(ids::integer[]) AND status = 'failed';
  GET DIAGNOSTICS nb_jobs = ROW_COUNT;
  RETURN nb_jobs;
END;
$$;


ALTER FUNCTION public.reinit_jobs(ids integer[]) OWNER TO postgres;

--
-- Name: set_nb_active_session(character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_nb_active_session(hostname character varying, nb_limit integer) RETURNS void
    LANGUAGE plpgsql
    AS $$

BEGIN
   UPDATE sessions SET status = (
    CASE
    WHEN status = 'idle' AND id in (SELECT id FROM sessions WHERE host=hostname AND status <> 'closed' ORDER BY id LIMIT nb_limit) THEN 'active'::session_status
    WHEN status = 'idle_requested' AND id in (SELECT id FROM sessions WHERE host=hostname AND status <> 'closed' ORDER BY id LIMIT nb_limit) THEN 'running'::session_status
    WHEN status = 'active' AND id not in (SELECT id FROM sessions WHERE host=hostname AND status <> 'closed' ORDER BY id LIMIT nb_limit) THEN 'idle'::session_status
    WHEN status = 'running' AND id not in (SELECT id FROM sessions WHERE host=hostname AND status <> 'closed' ORDER BY id LIMIT nb_limit) THEN 'idle_requested'::session_status
    ELSE status END) WHERE status <> 'closed' AND host=hostname;
END;
$$;


ALTER FUNCTION public.set_nb_active_session(hostname character varying, nb_limit integer) OWNER TO postgres;

--
-- Name: set_nb_active_sessions(character varying[], integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_nb_active_sessions(hostnames character varying[], nb_limit integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
hostname varchar;
BEGIN
FOREACH hostname IN ARRAY hostnames
LOOP
    PERFORM set_nb_active_session(hostname, nb_limit);
END LOOP;
END;
$$;


ALTER FUNCTION public.set_nb_active_sessions(hostnames character varying[], nb_limit integer) OWNER TO postgres;

--
-- Name: udate_jobDependency(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public."udate_jobDependency"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
  IF (NEW.status = 'done' AND NEW.status <> OLD.status) THEN
       UPDATE jobDependencies SET active='f' WHERE upstream = NEW.id;
  END IF;
  RETURN NEW;
END;$$;


ALTER FUNCTION public."udate_jobDependency"() OWNER TO postgres;

--
-- Name: update_job_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_job_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
    UPDATE jobs 
    SET status='ready' 
    WHERE 
    status='waiting' 
    AND NOT EXISTS (
        SELECT * FROM jobDependencies WHERE  jobs.id = jobDependencies.upstream and jobDependencies.active = 't');  
        -- Pas besoin de retourner un element puisqu on est sur un EACH STATEMENT
        -- c est a dire la fonction n est pas declenchee pour chaque ligne modifiee
        -- mais une fois pour toute commande modifiant la table
        -- ca peut faire une grosse difference puisqu on modifie la table avec
        -- des commandes du type : UPDATE dependencies SET active='f' WHERE from_id = NEW.id;
    RETURN NULL;
END;$$;


ALTER FUNCTION public.update_job_status() OWNER TO postgres;

--
-- Name: update_job_when_jobdependency_inserted(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_job_when_jobdependency_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE jobs 
    SET status='waiting' 
    WHERE 
    status='ready' 
    AND EXISTS (
        SELECT * FROM public.jobdependencies AS d WHERE  jobs.id = d.downstream and d.active = 't');
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_job_when_jobdependency_inserted() OWNER TO postgres;

--
-- Name: update_job_when_jobdependency_unactivate(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_job_when_jobdependency_unactivate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE jobs 
    SET status='ready' 
    WHERE 
    status='waiting' 
    AND NOT EXISTS (
        SELECT * FROM public.jobdependencies AS d WHERE  jobs.id = d.downstream and d.active = 't')
    AND EXISTS (
        SELECT * FROM public.projects AS p WHERE jobs.id_project = p.id and p.status = 'running');
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_job_when_jobdependency_unactivate() OWNER TO postgres;

--
-- Name: update_job_when_project_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_job_when_project_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.status = 'running' AND NEW.status <> OLD.status) THEN
       UPDATE public.jobs SET status='ready' WHERE 
       status='waiting' 
       AND id_project = NEW.id
       AND NOT EXISTS (
        SELECT * FROM public.jobdependencies AS d WHERE  jobs.id = d.downstream and d.active = 't');
  END IF;
  IF (NEW.status = 'waiting' AND NEW.status <> OLD.status) THEN
       UPDATE public.jobs SET status='waiting' WHERE 
       status='ready' 
       AND id_project = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_job_when_project_change() OWNER TO postgres;

--
-- Name: update_job_when_session_closed(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_job_when_session_closed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.status = 'closed' AND NEW.status <> OLD.status) THEN
       UPDATE public.jobs SET status='ready', id_session = NULL, log=NULL, return_code=NULL, start_date=NULL, end_date=NULL WHERE 
       status='running'
       AND id_session = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_job_when_session_closed() OWNER TO postgres;

--
-- Name: update_jobdependencies_when_job_done(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_jobdependencies_when_job_done() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.status = 'done' AND NEW.status <> OLD.status) THEN
       UPDATE public.jobdependencies SET active='f' WHERE upstream = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_jobdependencies_when_job_done() OWNER TO postgres;

--
-- Name: update_project_when_job_done(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_project_when_job_done() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE projects 
    SET status='done' 
    WHERE 
    status='running' 
    AND NOT EXISTS (
        SELECT * FROM public.jobs AS j WHERE  projects.id = j.id_project and j.status <> 'done');
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_project_when_job_done() OWNER TO postgres;

--
-- Name: update_project_when_projectdency_inserted(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_project_when_projectdency_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE projects 
    SET status='waiting' 
    WHERE 
    status='running' 
    AND EXISTS (
        SELECT * FROM public.projectdependencies AS d WHERE  projects.id = d.to_id and d.active = 't');
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_project_when_projectdency_inserted() OWNER TO postgres;

--
-- Name: update_project_when_projectdepency_unactivate(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_project_when_projectdepency_unactivate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE projects 
    SET status='running' 
    WHERE 
    status='waiting' 
    AND NOT EXISTS (
        SELECT * FROM public.projectdependencies AS d WHERE  projects.id = d.downstream and d.active = 't');
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_project_when_projectdepency_unactivate() OWNER TO postgres;

--
-- Name: update_project_when_projectdependency_inserted(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_project_when_projectdependency_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE projects 
    SET status='waiting' 
    WHERE 
    status='running' 
    AND EXISTS (
        SELECT * FROM public.projectdependencies AS d WHERE  projects.id = d.downstream and d.active = 't');
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_project_when_projectdependency_inserted() OWNER TO postgres;

--
-- Name: update_projectdependencies_when_project_deleted(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_projectdependencies_when_project_deleted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	UPDATE projectdependencies SET active = false WHERE upstream = OLD.id;
	UPDATE projects SET status = 'running' 
	WHERE id IN 
	(SELECT downstream FROM projects INNER JOIN projectdependencies ON projects.id = projectdependencies.upstream 
	WHERE upstream = OLD.id and active = 'f') AND status='waiting';
	DELETE FROM projectdependencies WHERE upstream = OLD.id;
   
   RETURN OLD;
END;$$;


ALTER FUNCTION public.update_projectdependencies_when_project_deleted() OWNER TO postgres;

--
-- Name: update_projectdependencies_when_project_done(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_projectdependencies_when_project_done() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.status = 'done' AND NEW.status <> OLD.status) THEN
       UPDATE public.projectdependencies SET active='f' WHERE upstream = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_projectdependencies_when_project_done() OWNER TO postgres;

--
-- Name: update_session_when_job_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_session_when_job_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (OLD.status = 'running' AND NEW.status <> OLD.status AND NEW.id_session IS NOT null) THEN
--   Dans le cas ou la session est en idle_requested il faut passer en idle
        UPDATE public.sessions SET status= CASE
            WHEN status='running'::public.session_status THEN 'active'::public.session_status
            WHEN status='idle_requested'::public.session_status THEN 'idle'::public.session_status
            END WHERE id = NEW.id_session;
  END IF;
  IF (NEW.status = 'running' AND NEW.status <> OLD.status AND NEW.id_session IS NOT null) THEN
       UPDATE public.sessions SET status='running'::public.session_status WHERE 
       id = NEW.id_session;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_session_when_job_change() OWNER TO postgres;

--
-- Name: update_session_when_project_deleted(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_session_when_project_deleted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
   UPDATE sessions SET status=(
    CASE
    WHEN status = 'idle_requested' AND id IN (SELECT id_session FROM jobs WHERE id_project = OLD.id AND status = 'running') THEN 'idle'::session_status
    WHEN status = 'running' AND id IN (SELECT id_session FROM jobs WHERE id_project = OLD.id AND status = 'running') THEN 'active'::session_status
    ELSE status END);
   RETURN OLD;
END;$$;


ALTER FUNCTION public.update_session_when_project_deleted() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: jobdependencies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.jobdependencies (
    id integer NOT NULL,
    upstream integer NOT NULL,
    downstream integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.jobdependencies OWNER TO postgres;

--
-- Name: jobdependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.jobdependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.jobdependencies_id_seq OWNER TO postgres;

--
-- Name: jobdependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.jobdependencies_id_seq OWNED BY public.jobdependencies.id;


--
-- Name: jobs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.jobs (
    id integer NOT NULL,
    name character varying NOT NULL,
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    command character varying NOT NULL,
    status public.status DEFAULT 'ready'::public.status NOT NULL,
    return_code bigint,
    log character varying,
    id_project integer NOT NULL,
    id_session integer,
    tags character varying[] DEFAULT '{}'::character varying[] NOT NULL
);


ALTER TABLE public.jobs OWNER TO postgres;

--
-- Name: jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.jobs_id_seq OWNER TO postgres;

--
-- Name: jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.jobs_id_seq OWNED BY public.jobs.id;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.projects (
    id integer NOT NULL,
    name character varying NOT NULL,
    status public.status DEFAULT 'running'::public.status NOT NULL,
    priority public.priority DEFAULT 'normal'::public.priority NOT NULL
);


ALTER TABLE public.projects OWNER TO postgres;

--
-- Name: project_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.project_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.project_id_seq OWNER TO postgres;

--
-- Name: project_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.project_id_seq OWNED BY public.projects.id;


--
-- Name: projectdependencies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.projectdependencies (
    id integer NOT NULL,
    upstream integer NOT NULL,
    downstream integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.projectdependencies OWNER TO postgres;

--
-- Name: projectdependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.projectdependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.projectdependencies_id_seq OWNER TO postgres;

--
-- Name: projectdependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.projectdependencies_id_seq OWNED BY public.projectdependencies.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sessions (
    id integer NOT NULL,
    host character varying NOT NULL,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone,
    status public.session_status DEFAULT 'idle'::public.session_status NOT NULL,
    tags character varying[] DEFAULT '{}'::character varying[] NOT NULL
);


ALTER TABLE public.sessions OWNER TO postgres;

--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sessions_id_seq OWNER TO postgres;

--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: view_job; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_job AS
 SELECT jobs.id AS job_id,
    jobs.name AS job_name,
    jobs.start_date AS job_start_date,
    jobs.end_date AS job_end_date,
    jobs.command AS job_command,
    jobs.status AS job_status,
    jobs.tags AS job_tags,
    jobs.return_code AS job_return_code,
    jobs.log AS job_log,
    projects.id AS project_id,
    projects.name AS project_name,
    projects.status AS project_status,
    sessions.id AS session_id,
    sessions.host AS session_host,
    sessions.start_date AS session_start_date,
    sessions.end_date AS session_end_date,
    sessions.status AS session_status,
    to_char(jobs.start_date, 'DD-MM-YYYY'::text) AS date_debut,
    to_char(timezone('UTC'::text, jobs.start_date), 'HH24:MI:SS'::text) AS hms_debut,
    ((((((date_part('day'::text, (jobs.end_date - jobs.start_date)) * (24)::double precision) + date_part('hour'::text, (jobs.end_date - jobs.start_date))) * (60)::double precision) + date_part('minute'::text, (jobs.end_date - jobs.start_date))) * (60)::double precision) + (round((date_part('second'::text, (jobs.end_date - jobs.start_date)))::numeric, 2))::double precision) AS duree,
    to_char(jobs.end_date, 'DD-MM-YYYY'::text) AS date_fin,
    to_char(timezone('UTC'::text, jobs.end_date), 'HH24:MI:SS'::text) AS hms_fin
   FROM ((public.jobs
     JOIN public.projects ON ((projects.id = jobs.id_project)))
     LEFT JOIN public.sessions ON ((sessions.id = jobs.id_session)));


ALTER TABLE public.view_job OWNER TO postgres;

--
-- Name: view_job_dependencies; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_job_dependencies AS
 SELECT jobdependencies.id AS dep_id,
    jobdependencies.upstream AS dep_up,
    jobdependencies.downstream AS dep_down,
    jobdependencies.active AS dep_active,
    jobs.id AS job_id,
    jobs.name AS job_name,
    jobs.start_date AS job_start_date,
    jobs.end_date AS job_end_date,
    jobs.status AS job_status,
    jobs.return_code AS jobs_return_code
   FROM (public.jobdependencies
     JOIN public.jobs ON ((jobs.id = jobdependencies.upstream)));


ALTER TABLE public.view_job_dependencies OWNER TO postgres;

--
-- Name: view_job_status; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_job_status AS
 SELECT COALESCE(sum(
        CASE
            WHEN (jobs.status = 'ready'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS ready,
    COALESCE(sum(
        CASE
            WHEN (jobs.status = 'done'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS done,
    COALESCE(sum(
        CASE
            WHEN (jobs.status = 'waiting'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS waiting,
    COALESCE(sum(
        CASE
            WHEN (jobs.status = 'running'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS running,
    COALESCE(sum(
        CASE
            WHEN (jobs.status = 'failed'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS failed,
    COALESCE(sum(
        CASE
            WHEN ((jobs.status = 'failed'::public.status) OR (jobs.status = 'running'::public.status) OR (jobs.status = 'waiting'::public.status) OR (jobs.status = 'done'::public.status) OR (jobs.status = 'ready'::public.status)) THEN 1
            ELSE 0
        END), (0)::bigint) AS total
   FROM public.jobs;


ALTER TABLE public.view_job_status OWNER TO postgres;

--
-- Name: view_jobs; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_jobs AS
 SELECT jobs.id AS job_id,
    jobs.name AS job_name,
    jobs.start_date AS job_start_date,
    jobs.end_date AS job_end_date,
    jobs.status AS job_status,
    jobs.return_code AS job_return_code,
    jobs.id_project AS job_id_project,
    jobs.id_session AS job_session,
    projects.name AS project_name,
    to_char(jobs.start_date, 'DD-MM-YYYY'::text) AS date,
    to_char(timezone('UTC'::text, jobs.start_date), 'HH24:MI:SS'::text) AS hms,
    (round((((((((date_part('day'::text, (jobs.end_date - jobs.start_date)) * (24)::double precision) + date_part('hour'::text, (jobs.end_date - jobs.start_date))) * (60)::double precision) + date_part('minute'::text, (jobs.end_date - jobs.start_date))) * (60)::double precision) + (round((date_part('second'::text, (jobs.end_date - jobs.start_date)))::numeric, 2))::double precision))::numeric, 2))::double precision AS duree
   FROM (public.jobs
     JOIN public.projects ON ((projects.id = jobs.id_project)));


ALTER TABLE public.view_jobs OWNER TO postgres;

--
-- Name: view_projects; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_projects AS
SELECT
    NULL::integer AS project_id,
    NULL::character varying AS project_name,
    NULL::public.status AS project_status,
    NULL::public.priority AS project_priority,
    NULL::bigint AS count,
    NULL::numeric AS avg_job_duree,
    NULL::double precision AS min_job_duree,
    NULL::double precision AS max_job_duree,
    NULL::numeric AS total_job_duree,
    NULL::text AS project_start_date,
    NULL::text AS project_end_date,
    NULL::numeric AS project_duree,
    NULL::numeric AS parallelization_coeff,
    NULL::bigint AS ready,
    NULL::bigint AS done,
    NULL::bigint AS waiting,
    NULL::bigint AS running,
    NULL::bigint AS failed,
    NULL::bigint AS total;


ALTER TABLE public.view_projects OWNER TO postgres;

--
-- Name: view_project_dependencies; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_project_dependencies AS
 SELECT projectdependencies.id AS dep_id,
    projectdependencies.upstream AS dep_up,
    projectdependencies.downstream AS dep_down,
    projectdependencies.active AS dep_active,
    view_projects.project_id,
    view_projects.project_name,
    view_projects.project_status,
    view_projects.project_priority,
    view_projects.ready,
    view_projects.done,
    view_projects.waiting,
    view_projects.running,
    view_projects.failed,
    view_projects.total
   FROM (public.projectdependencies
     JOIN public.view_projects ON ((view_projects.project_id = projectdependencies.upstream)));


ALTER TABLE public.view_project_dependencies OWNER TO postgres;

--
-- Name: view_project_status; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_project_status AS
 SELECT COALESCE(sum(
        CASE
            WHEN (projects.status = 'ready'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS ready,
    COALESCE(sum(
        CASE
            WHEN (projects.status = 'done'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS done,
    COALESCE(sum(
        CASE
            WHEN (projects.status = 'waiting'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS waiting,
    COALESCE(sum(
        CASE
            WHEN (projects.status = 'running'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS running,
    COALESCE(sum(
        CASE
            WHEN (projects.status = 'failed'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS failed,
    COALESCE(sum(
        CASE
            WHEN ((projects.status = 'failed'::public.status) OR (projects.status = 'running'::public.status) OR (projects.status = 'waiting'::public.status) OR (projects.status = 'done'::public.status) OR (projects.status = 'ready'::public.status)) THEN 1
            ELSE 0
        END), (0)::bigint) AS total
   FROM public.projects;


ALTER TABLE public.view_project_status OWNER TO postgres;

--
-- Name: view_project_status_by_jobs; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_project_status_by_jobs AS
 SELECT jobs.id_project AS project_id,
    projects.name AS project_name,
    projects.priority AS project_priority,
    projects.status AS project_status,
    sum(
        CASE
            WHEN (jobs.status = 'ready'::public.status) THEN 1
            ELSE 0
        END) AS ready,
    sum(
        CASE
            WHEN (jobs.status = 'done'::public.status) THEN 1
            ELSE 0
        END) AS done,
    sum(
        CASE
            WHEN (jobs.status = 'waiting'::public.status) THEN 1
            ELSE 0
        END) AS waiting,
    sum(
        CASE
            WHEN (jobs.status = 'running'::public.status) THEN 1
            ELSE 0
        END) AS running,
    sum(
        CASE
            WHEN (jobs.status = 'failed'::public.status) THEN 1
            ELSE 0
        END) AS failed,
    sum(
        CASE
            WHEN ((jobs.status = 'failed'::public.status) OR (jobs.status = 'running'::public.status) OR (jobs.status = 'waiting'::public.status) OR (jobs.status = 'done'::public.status) OR (jobs.status = 'ready'::public.status)) THEN 1
            ELSE 0
        END) AS total
   FROM (public.jobs
     JOIN public.projects ON ((projects.id = jobs.id_project)))
  GROUP BY jobs.id_project, projects.name, projects.priority, projects.status;


ALTER TABLE public.view_project_status_by_jobs OWNER TO postgres;

--
-- Name: view_sessions; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_sessions AS
 SELECT sessions.id AS sessions_id,
    sessions.host AS sessions_host,
    sessions.start_date AS sessions_start_date,
    sessions.end_date AS sessions_end_date,
    sessions.status AS sessions_status,
    sessions.tags AS sessions_tags,
    to_char(sessions.start_date, 'DD-MM-YYYY'::text) AS date_debut,
    to_char(timezone('UTC'::text, sessions.start_date), 'HH24:MI:SS'::text) AS hms_debut,
    ((((((date_part('day'::text, (sessions.end_date - sessions.start_date)) * (24)::double precision) + date_part('hour'::text, (sessions.end_date - sessions.start_date))) * (60)::double precision) + date_part('minute'::text, (sessions.end_date - sessions.start_date))) * (60)::double precision) + (round((date_part('second'::text, (sessions.end_date - sessions.start_date)))::numeric, 2))::double precision) AS duree,
    to_char(sessions.end_date, 'DD-MM-YYYY'::text) AS date_fin,
    to_char(timezone('UTC'::text, sessions.end_date), 'HH24:MI:SS'::text) AS hms_fin
   FROM public.sessions;


ALTER TABLE public.view_sessions OWNER TO postgres;

--
-- Name: view_sessions_status; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.view_sessions_status AS
 SELECT COALESCE(sum(
        CASE
            WHEN (sessions.status = 'idle'::public.session_status) THEN 1
            ELSE 0
        END), (0)::bigint) AS idle,
    COALESCE(sum(
        CASE
            WHEN (sessions.status = 'idle_requested'::public.session_status) THEN 1
            ELSE 0
        END), (0)::bigint) AS idle_requested,
    COALESCE(sum(
        CASE
            WHEN (sessions.status = 'active'::public.session_status) THEN 1
            ELSE 0
        END), (0)::bigint) AS active,
    COALESCE(sum(
        CASE
            WHEN (sessions.status = 'running'::public.session_status) THEN 1
            ELSE 0
        END), (0)::bigint) AS running,
    COALESCE(sum(
        CASE
            WHEN (sessions.status = 'closed'::public.session_status) THEN 1
            ELSE 0
        END), (0)::bigint) AS closed,
    COALESCE(sum(
        CASE
            WHEN ((sessions.status = 'idle'::public.session_status) OR (sessions.status = 'running'::public.session_status) OR (sessions.status = 'closed'::public.session_status) OR (sessions.status = 'idle_requested'::public.session_status) OR (sessions.status = 'active'::public.session_status)) THEN 1
            ELSE 0
        END), (0)::bigint) AS total
   FROM public.sessions;


ALTER TABLE public.view_sessions_status OWNER TO postgres;

--
-- Name: jobdependencies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobdependencies ALTER COLUMN id SET DEFAULT nextval('public.jobdependencies_id_seq'::regclass);


--
-- Name: jobs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs ALTER COLUMN id SET DEFAULT nextval('public.jobs_id_seq'::regclass);


--
-- Name: projectdependencies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projectdependencies ALTER COLUMN id SET DEFAULT nextval('public.projectdependencies_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.project_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: jobdependencies jobdependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobdependencies
    ADD CONSTRAINT jobdependencies_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: projects project_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT project_pkey PRIMARY KEY (id);


--
-- Name: projectdependencies projectdependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projectdependencies
    ADD CONSTRAINT projectdependencies_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: id_project_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX id_project_idx ON public.jobs USING btree (id_project);


--
-- Name: view_projects _RETURN; Type: RULE; Schema: public; Owner: postgres
--

CREATE OR REPLACE VIEW public.view_projects AS
 WITH date AS (
         SELECT view_jobs_1.job_id_project,
            round((COALESCE(sum(view_jobs_1.duree), (0)::double precision))::numeric, 2) AS total_job_duree,
            min(view_jobs_1.job_start_date) AS min_start_date,
            max(view_jobs_1.job_end_date) AS max_end_date
           FROM public.view_jobs view_jobs_1
          GROUP BY view_jobs_1.job_id_project
        ), duree AS (
         SELECT date_1.job_id_project,
            ((((((date_part('day'::text, (date_1.max_end_date - date_1.min_start_date)) * (24)::double precision) + date_part('hour'::text, (date_1.max_end_date - date_1.min_start_date))) * (60)::double precision) + date_part('minute'::text, (date_1.max_end_date - date_1.min_start_date))) * (60)::double precision) + (round((date_part('second'::text, (date_1.max_end_date - date_1.min_start_date)))::numeric, 2))::double precision) AS project_duree
           FROM date date_1
        )
 SELECT projects.id AS project_id,
    projects.name AS project_name,
    projects.status AS project_status,
    projects.priority AS project_priority,
    count(view_jobs.job_id) AS count,
    COALESCE(round((avg(view_jobs.duree))::numeric, 2), (0)::numeric) AS avg_job_duree,
    COALESCE(min(view_jobs.duree), (0)::double precision) AS min_job_duree,
    COALESCE(max(view_jobs.duree), (0)::double precision) AS max_job_duree,
    date.total_job_duree,
    to_char(date.min_start_date, 'DD-MM-YYYY HH24:MI:SS'::text) AS project_start_date,
    to_char(date.max_end_date, 'DD-MM-YYYY HH24:MI:SS'::text) AS project_end_date,
    COALESCE(round((duree.project_duree)::numeric, 2), (0)::numeric) AS project_duree,
    round((((date.total_job_duree)::double precision / duree.project_duree))::numeric, 2) AS parallelization_coeff,
    COALESCE(sum(
        CASE
            WHEN (view_jobs.job_status = 'ready'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS ready,
    COALESCE(sum(
        CASE
            WHEN (view_jobs.job_status = 'done'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS done,
    COALESCE(sum(
        CASE
            WHEN (view_jobs.job_status = 'waiting'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS waiting,
    COALESCE(sum(
        CASE
            WHEN (view_jobs.job_status = 'running'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS running,
    COALESCE(sum(
        CASE
            WHEN (view_jobs.job_status = 'failed'::public.status) THEN 1
            ELSE 0
        END), (0)::bigint) AS failed,
    COALESCE(sum(
        CASE
            WHEN ((view_jobs.job_status = 'failed'::public.status) OR (view_jobs.job_status = 'running'::public.status) OR (view_jobs.job_status = 'waiting'::public.status) OR (view_jobs.job_status = 'done'::public.status) OR (view_jobs.job_status = 'ready'::public.status)) THEN 1
            ELSE 0
        END), (0)::bigint) AS total
   FROM (((public.projects
     JOIN public.view_jobs ON ((projects.id = view_jobs.job_id_project)))
     JOIN date ON ((projects.id = date.job_id_project)))
     JOIN duree ON ((projects.id = duree.job_id_project)))
  GROUP BY projects.id, date.total_job_duree, date.min_start_date, date.max_end_date, duree.project_duree, (round((((date.total_job_duree)::double precision / duree.project_duree))::numeric, 2));


--
-- Name: jobdependencies update_job_when_jobdependency_inserted; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_job_when_jobdependency_inserted AFTER INSERT ON public.jobdependencies FOR EACH STATEMENT EXECUTE FUNCTION public.update_job_when_jobdependency_inserted();


--
-- Name: jobdependencies update_job_when_jobdependency_unactivate; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_job_when_jobdependency_unactivate AFTER UPDATE OF active ON public.jobdependencies FOR EACH STATEMENT EXECUTE FUNCTION public.update_job_when_jobdependency_unactivate();


--
-- Name: projects update_job_when_project_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_job_when_project_change AFTER UPDATE OF status ON public.projects FOR EACH ROW EXECUTE FUNCTION public.update_job_when_project_change();


--
-- Name: sessions update_job_when_session_closed; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_job_when_session_closed AFTER UPDATE OF status ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_job_when_session_closed();


--
-- Name: jobs update_jobdependencies_when_job_done; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_jobdependencies_when_job_done AFTER UPDATE OF status ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.update_jobdependencies_when_job_done();


--
-- Name: jobs update_project_when_job_done; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_project_when_job_done AFTER UPDATE OF status ON public.jobs FOR EACH STATEMENT EXECUTE FUNCTION public.update_project_when_job_done();


--
-- Name: projectdependencies update_project_when_projectdependency_inserted; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_project_when_projectdependency_inserted AFTER INSERT ON public.projectdependencies FOR EACH STATEMENT EXECUTE FUNCTION public.update_project_when_projectdependency_inserted();


--
-- Name: projectdependencies update_project_when_projectdependency_unactivate; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_project_when_projectdependency_unactivate AFTER UPDATE OF active ON public.projectdependencies FOR EACH STATEMENT EXECUTE FUNCTION public.update_project_when_projectdepency_unactivate();


--
-- Name: projects update_projectdependencies_when_project_deleted; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_projectdependencies_when_project_deleted AFTER DELETE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.update_projectdependencies_when_project_deleted();


--
-- Name: projects update_projectdependencies_when_project_done; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_projectdependencies_when_project_done AFTER UPDATE OF status ON public.projects FOR EACH ROW EXECUTE FUNCTION public.update_projectdependencies_when_project_done();


--
-- Name: jobs update_session_when_job_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_session_when_job_change AFTER UPDATE OF status ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.update_session_when_job_change();


--
-- Name: projects update_session_when_project_deleted; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_session_when_project_deleted BEFORE DELETE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.update_session_when_project_deleted();


--
-- Name: jobdependencies downstream_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobdependencies
    ADD CONSTRAINT downstream_fk FOREIGN KEY (downstream) REFERENCES public.jobs(id) ON DELETE CASCADE NOT VALID;


--
-- Name: projectdependencies downstream_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projectdependencies
    ADD CONSTRAINT downstream_fk FOREIGN KEY (downstream) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: jobs id_project_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT id_project_fk FOREIGN KEY (id_project) REFERENCES public.projects(id) ON DELETE CASCADE NOT VALID;


--
-- Name: jobs id_session_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT id_session_fk FOREIGN KEY (id_session) REFERENCES public.sessions(id) NOT VALID;


--
-- Name: jobdependencies upstream_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobdependencies
    ADD CONSTRAINT upstream_fk FOREIGN KEY (upstream) REFERENCES public.jobs(id) ON DELETE CASCADE NOT VALID;


--
-- Name: projectdependencies upstream_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projectdependencies
    ADD CONSTRAINT upstream_fk FOREIGN KEY (upstream) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

