-- CloudEARTHi MOOC (Supabase project Octa_projects). Uses the Octa suite accounts (User_ tables).
-- All Mooc_ tables are closed to the public API; the management app and the student website call the mooc_*
-- functions below with the publishable key and the user's Octa session token.
--
-- Roles
--   super admin  : Octa admin (User_accounts.role = 'admin') or listed in Mooc_super_admins.
--                  Creates projects (course groups) and courses, names course admins, approves teachers.
--   course admin : Mooc_members.role = 'admin' for a course. Gives users teacher or student rights in it,
--                  approves teachers, edits the course, its lectures and its badges.
--   teacher      : Mooc_members.role = 'teacher' for a course. Edits lectures and badges, grades assignments.
--                  Registering as a teacher (Mooc_people.kind = 'teacher') needs approval.
--   student      : registers and enrols at once.

-- ================================================================ tables
create table public."Mooc_super_admins" (
  user_id uuid primary key references public."User_accounts"(id) on delete cascade,
  added_at timestamptz not null default now()
);
comment on table public."Mooc_super_admins" is 'Extra MOOC super admins (Octa admins are super admins anyway).';

create table public."Mooc_people" (
  user_id uuid primary key references public."User_accounts"(id) on delete cascade,
  kind text not null check (kind in ('student', 'teacher')),
  status text not null default 'active' check (status in ('active', 'pending', 'declined')),
  public_profile boolean not null default true,
  headline text check (char_length(headline) <= 200),
  created_at timestamptz not null default now(),
  decided_by uuid references public."User_accounts"(id) on delete set null,
  decided_at timestamptz
);
comment on table public."Mooc_people" is 'Who registered on the MOOC, as student or teacher. Teachers are pending until a course admin or super admin approves them.';

create table public."Mooc_projects" (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  title text not null check (char_length(title) between 2 and 200),
  description text check (char_length(description) <= 4000),
  image_url text check (char_length(image_url) <= 500),
  website text check (char_length(website) <= 300),
  sort_order integer not null default 100,
  created_by uuid references public."User_accounts"(id) on delete set null,
  created_at timestamptz not null default now()
);
comment on table public."Mooc_projects" is 'Course groups: courses listed together under one project (e.g. BOOSTalent, SEEDplus).';

create table public."Mooc_courses" (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,80}$'),
  project_id uuid references public."Mooc_projects"(id) on delete set null,
  title text not null check (char_length(title) between 2 and 200),
  summary text check (char_length(summary) <= 500),
  description text check (char_length(description) <= 10000),
  outcomes jsonb not null default '[]'::jsonb check (jsonb_typeof(outcomes) = 'array'),
  image_url text check (char_length(image_url) <= 500),
  level text check (level in ('beginner', 'intermediate', 'advanced')),
  language text not null default 'English' check (char_length(language) <= 40),
  hours numeric(5,1),
  pass_score integer not null default 70 check (pass_score between 0 and 100),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  sort_order integer not null default 100,
  created_by uuid references public."User_accounts"(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public."Mooc_members" (
  course_id uuid not null references public."Mooc_courses"(id) on delete cascade,
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  role text not null check (role in ('admin', 'teacher', 'student')),
  status text not null default 'active' check (status in ('active', 'removed')),
  added_by uuid references public."User_accounts"(id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (course_id, user_id)
);
create index "Mooc_members_user_idx" on public."Mooc_members" (user_id);
comment on table public."Mooc_members" is 'Course roles: admin, teacher or student (enrolment).';

create table public."Mooc_lectures" (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public."Mooc_courses"(id) on delete cascade,
  position integer not null default 100,
  title text not null check (char_length(title) between 1 and 200),
  summary text check (char_length(summary) <= 4000),
  outcomes jsonb not null default '[]'::jsonb check (jsonb_typeof(outcomes) = 'array'),
  status text not null default 'draft' check (status in ('draft', 'published')),
  created_by uuid references public."User_accounts"(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index "Mooc_lectures_course_idx" on public."Mooc_lectures" (course_id, position);

-- kind: video (YouTube), pdf, text, quiz, assignment, live (online lecture / study group room).
-- config (per kind): video {youtube_id, start, end}; pdf {url, pages}; text {markdown};
--   assignment {instructions, grading: manual|auto, max_points}; live {room, starts_at, minutes, group}; quiz {}.
create table public."Mooc_steps" (
  id uuid primary key default gen_random_uuid(),
  lecture_id uuid not null references public."Mooc_lectures"(id) on delete cascade,
  position integer not null default 100,
  kind text not null check (kind in ('video', 'pdf', 'text', 'quiz', 'assignment', 'live')),
  title text not null check (char_length(title) between 1 and 200),
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config) = 'object' and pg_column_size(config) <= 200000),
  required boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index "Mooc_steps_lecture_idx" on public."Mooc_steps" (lecture_id, position);

-- Interactive questions. On a video: at_seconds; on a PDF: at_page; in a quiz: neither.
-- must_pass: the student cannot go on until it is answered correctly.
create table public."Mooc_questions" (
  id uuid primary key default gen_random_uuid(),
  step_id uuid not null references public."Mooc_steps"(id) on delete cascade,
  position integer not null default 100,
  at_seconds integer check (at_seconds >= 0),
  at_page integer check (at_page >= 1),
  prompt text not null check (char_length(prompt) between 1 and 2000),
  kind text not null default 'single' check (kind in ('single', 'multiple', 'truefalse')),
  options jsonb not null default '[]'::jsonb check (jsonb_typeof(options) = 'array'),
  correct jsonb not null default '[]'::jsonb check (jsonb_typeof(correct) = 'array'),
  explanation text check (char_length(explanation) <= 2000),
  must_pass boolean not null default true,
  created_at timestamptz not null default now()
);
create index "Mooc_questions_step_idx" on public."Mooc_questions" (step_id, position);

-- Everything a student does (an xAPI-style log). Badges and certificates are computed from Mooc_progress.
create table public."Mooc_events" (
  id bigint generated always as identity primary key,
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  course_id uuid references public."Mooc_courses"(id) on delete cascade,
  lecture_id uuid references public."Mooc_lectures"(id) on delete set null,
  step_id uuid references public."Mooc_steps"(id) on delete set null,
  verb text not null check (verb in ('enrolled', 'opened', 'progressed', 'answered', 'completed', 'submitted',
                                     'graded', 'joined_live', 'awarded')),
  score numeric(5,1),
  data jsonb not null default '{}'::jsonb check (pg_column_size(data) <= 8000),
  created_at timestamptz not null default now()
);
create index "Mooc_events_user_idx" on public."Mooc_events" (user_id, created_at);
create index "Mooc_events_course_idx" on public."Mooc_events" (course_id, created_at);

create table public."Mooc_answers" (
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  question_id uuid not null references public."Mooc_questions"(id) on delete cascade,
  first_correct boolean not null,
  correct boolean not null,
  attempts integer not null default 1,
  updated_at timestamptz not null default now(),
  primary key (user_id, question_id)
);

create table public."Mooc_progress" (
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  step_id uuid not null references public."Mooc_steps"(id) on delete cascade,
  completed_at timestamptz,
  score numeric(5,1) check (score between 0 and 100),
  position numeric,                 -- last video second or PDF page reached (to continue where they left off)
  updated_at timestamptz not null default now(),
  primary key (user_id, step_id)
);

create table public."Mooc_submissions" (
  id uuid primary key default gen_random_uuid(),
  step_id uuid not null references public."Mooc_steps"(id) on delete cascade,
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  answer text check (char_length(answer) <= 20000),
  file_url text check (char_length(file_url) <= 500),
  submitted_at timestamptz not null default now(),
  score numeric(5,1) check (score between 0 and 100),
  feedback text check (char_length(feedback) <= 4000),
  graded_by uuid references public."User_accounts"(id) on delete set null,
  graded_at timestamptz
);
create index "Mooc_submissions_step_idx" on public."Mooc_submissions" (step_id, submitted_at);

-- Badges and certificates: the design (an uploaded image) and the rule that awards it.
-- Rule: every required step of the chosen lectures completed (all published lectures if lecture_ids is empty)
-- AND the average score of the scored steps (quizzes, graded assignments) in them >= min_score.
create table public."Mooc_badges" (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public."Mooc_courses"(id) on delete cascade,
  kind text not null default 'badge' check (kind in ('badge', 'certificate')),
  title text not null check (char_length(title) between 2 and 200),
  description text check (char_length(description) <= 2000),
  image_url text check (char_length(image_url) <= 500),
  lecture_ids uuid[] not null default '{}',
  min_score integer not null default 70 check (min_score between 0 and 100),
  active boolean not null default true,
  created_by uuid references public."User_accounts"(id) on delete set null,
  created_at timestamptz not null default now()
);
create index "Mooc_badges_course_idx" on public."Mooc_badges" (course_id);

create table public."Mooc_awards" (
  id uuid primary key default gen_random_uuid(),   -- public verification id: /badge/<id>
  badge_id uuid not null references public."Mooc_badges"(id) on delete cascade,
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  score numeric(5,1),
  issued_at timestamptz not null default now(),
  revoked boolean not null default false,
  unique (badge_id, user_id)
);

-- one-time upload permissions for the 'mooc' storage bucket (uploads go to mooc/<ticket>/<file>)
create table public."Mooc_upload_tickets" (
  ticket_hash text primary key,
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  expires_at timestamptz not null
);

do $$ declare t text; begin
  foreach t in array array['Mooc_super_admins','Mooc_people','Mooc_projects','Mooc_courses','Mooc_members',
                           'Mooc_lectures','Mooc_steps','Mooc_questions','Mooc_events','Mooc_answers','Mooc_progress',
                           'Mooc_submissions','Mooc_badges','Mooc_awards','Mooc_upload_tickets'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ================================================================ helpers (not callable through the API)
-- user of a session token (extends the session like octa_user_session does)
create or replace function public.mooc_uid(p_token text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid;
begin
  update public."User_sessions" s set last_active_at = now(), expires_at = now() + interval '3 hours'
  where s.token_hash = public.octa_user_hash(coalesce(p_token, '')) and s.expires_at > now()
    and exists (select 1 from public."User_accounts" a where a.id = s.user_id and a.status <> 'suspended')
  returning s.user_id into uid;
  return uid;
end $$;

create or replace function public.mooc_is_super(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public."User_accounts" where id = p_user and role = 'admin')
      or exists (select 1 from public."Mooc_super_admins" where user_id = p_user)
$$;

-- the user's role in a course: 'super' | 'admin' | 'teacher' | 'student' | null
create or replace function public.mooc_role(p_user uuid, p_course uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when public.mooc_is_super(p_user) then 'super'
              else (select role from public."Mooc_members" where course_id = p_course and user_id = p_user and status = 'active') end
$$;

create or replace function public.mooc_can_edit(p_user uuid, p_course uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.mooc_role(p_user, p_course) in ('super', 'admin', 'teacher'), false)
$$;

create or replace function public.mooc_can_manage(p_user uuid, p_course uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.mooc_role(p_user, p_course) in ('super', 'admin'), false)
$$;

create or replace function public.mooc_slug(p text) returns text
language sql immutable set search_path = '' as $$
  select left(trim(both '-' from regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', '-', 'g')), 60)
$$;

-- course of a lecture / step / question
create or replace function public.mooc_course_of(p_kind text, p_id uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'lecture' then (select course_id from public."Mooc_lectures" where id = p_id)
    when 'step' then (select l.course_id from public."Mooc_steps" s join public."Mooc_lectures" l on l.id = s.lecture_id where s.id = p_id)
    when 'question' then (select l.course_id from public."Mooc_questions" q join public."Mooc_steps" s on s.id = q.step_id
                          join public."Mooc_lectures" l on l.id = s.lecture_id where q.id = p_id)
    when 'badge' then (select course_id from public."Mooc_badges" where id = p_id)
    when 'submission' then (select l.course_id from public."Mooc_submissions" x join public."Mooc_steps" s on s.id = x.step_id
                            join public."Mooc_lectures" l on l.id = s.lecture_id where x.id = p_id)
  end
$$;

-- find an account by username or email
create or replace function public.mooc_find_user(p text) returns uuid
language sql stable security definer set search_path = '' as $$
  select id from public."User_accounts" where lower(username) = lower(trim(coalesce(p, ''))) or email = lower(trim(coalesce(p, ''))) limit 1
$$;

create or replace function public.mooc_person(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', a.id, 'username', a.username, 'first_name', a.first_name, 'last_name', a.last_name,
                            'email', a.email, 'affiliation', a.affiliation)
  from public."User_accounts" a where a.id = p_id
$$;

-- full course for the editor (questions include the correct answers)
create or replace function public.mooc_course_full(p_course uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(c) || jsonb_build_object(
    'lectures', coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object(
        'steps', coalesce((select jsonb_agg(to_jsonb(s) || jsonb_build_object(
            'questions', coalesce((select jsonb_agg(to_jsonb(q) order by coalesce(q.at_seconds, 0), coalesce(q.at_page, 0), q.position, q.created_at)
                                   from public."Mooc_questions" q where q.step_id = s.id), '[]'::jsonb))
          order by s.position, s.created_at) from public."Mooc_steps" s where s.lecture_id = l.id), '[]'::jsonb))
      order by l.position, l.created_at) from public."Mooc_lectures" l where l.course_id = c.id), '[]'::jsonb),
    'badges', coalesce((select jsonb_agg(to_jsonb(b) || jsonb_build_object(
        'awarded', (select count(*) from public."Mooc_awards" w where w.badge_id = b.id and not w.revoked))
      order by b.kind, b.created_at) from public."Mooc_badges" b where b.course_id = c.id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(public.mooc_person(m.user_id) || jsonb_build_object('role', m.role, 'status', m.status, 'added_at', m.added_at)
      order by m.role, m.added_at) from public."Mooc_members" m where m.course_id = c.id and m.status = 'active'), '[]'::jsonb),
    'project', (select to_jsonb(p) from public."Mooc_projects" p where p.id = c.project_id))
  from public."Mooc_courses" c where c.id = p_course
$$;

-- ================================================================ award engine
-- Checks every active badge/certificate of a course for one student and issues the ones now earned.
create or replace function public.mooc_check_awards(p_user uuid, p_course uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b record; lects uuid[]; missing int; avg_score numeric; issued jsonb := '[]'::jsonb; aid uuid;
begin
  for b in select * from public."Mooc_badges" where course_id = p_course and active
           and not exists (select 1 from public."Mooc_awards" w where w.badge_id = "Mooc_badges".id and w.user_id = p_user) loop
    lects := case when cardinality(b.lecture_ids) > 0 then b.lecture_ids
                  else array(select id from public."Mooc_lectures" where course_id = p_course and status = 'published') end;
    if cardinality(lects) = 0 then continue; end if;
    select count(*) into missing from public."Mooc_steps" s
      where s.lecture_id = any(lects) and s.required
        and not exists (select 1 from public."Mooc_progress" p where p.step_id = s.id and p.user_id = p_user and p.completed_at is not null);
    if missing > 0 then continue; end if;
    select avg(p.score) into avg_score from public."Mooc_progress" p join public."Mooc_steps" s on s.id = p.step_id
      where p.user_id = p_user and s.lecture_id = any(lects) and p.score is not null;
    avg_score := coalesce(avg_score, 100);
    if avg_score < b.min_score then continue; end if;
    insert into public."Mooc_awards"(badge_id, user_id, score) values (b.id, p_user, round(avg_score, 1))
      on conflict do nothing returning id into aid;
    if aid is not null then
      insert into public."Mooc_events"(user_id, course_id, verb, score, data)
      values (p_user, p_course, 'awarded', round(avg_score, 1), jsonb_build_object('badge_id', b.id, 'award_id', aid, 'kind', b.kind));
      issued := issued || jsonb_build_object('award_id', aid, 'badge_id', b.id, 'kind', b.kind, 'title', b.title, 'image_url', b.image_url);
    end if;
  end loop;
  return issued;
end $$;

-- marks a step completed (keeps the best score) and runs the award engine
create or replace function public.mooc_complete_step(p_user uuid, p_step uuid, p_score numeric) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare cid uuid := public.mooc_course_of('step', p_step); lid uuid;
begin
  select lecture_id into lid from public."Mooc_steps" where id = p_step;
  insert into public."Mooc_progress"(user_id, step_id, completed_at, score)
  values (p_user, p_step, now(), p_score)
  on conflict (user_id, step_id) do update set
    completed_at = coalesce(public."Mooc_progress".completed_at, now()),
    score = case when excluded.score is null then public."Mooc_progress".score
                 when public."Mooc_progress".score is null then excluded.score
                 else greatest(public."Mooc_progress".score, excluded.score) end,
    updated_at = now();
  insert into public."Mooc_events"(user_id, course_id, lecture_id, step_id, verb, score)
  values (p_user, cid, lid, p_step, 'completed', p_score);
  return public.mooc_check_awards(p_user, cid);
end $$;

-- ================================================================ API: management app
-- mooc_manage(token, {action: ..., ...}). Every action checks the caller's role.
create or replace function public.mooc_manage(p_token text, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  uid uuid := public.mooc_uid(p_token);
  act text := p->>'action';
  is_super boolean;
  cid uuid; rid uuid; target uuid; r jsonb; n int;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Your session has ended. Please log in again.'); end if;
  is_super := public.mooc_is_super(uid);

  -- ------------------------------------------------------------ reading
  if act = 'me' then
    return jsonb_build_object('ok', true, 'is_super', is_super,
      'person', (select to_jsonb(x) from public."Mooc_people" x where x.user_id = uid),
      'is_course_admin', exists (select 1 from public."Mooc_members" where user_id = uid and role = 'admin' and status = 'active'),
      'can_edit_any', is_super or exists (select 1 from public."Mooc_members" where user_id = uid and role in ('admin', 'teacher') and status = 'active'));

  elsif act = 'overview' then
    return jsonb_build_object('ok', true,
      'projects', coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order, x.title) from public."Mooc_projects" x), '[]'::jsonb),
      'courses', coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object(
            'my_role', public.mooc_role(uid, c.id),
            'lectures', (select count(*) from public."Mooc_lectures" l where l.course_id = c.id),
            'students', (select count(*) from public."Mooc_members" m where m.course_id = c.id and m.role = 'student' and m.status = 'active'),
            'awards', (select count(*) from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id where b.course_id = c.id and not w.revoked),
            'to_grade', (select count(*) from public."Mooc_submissions" x join public."Mooc_steps" s on s.id = x.step_id
                         join public."Mooc_lectures" l on l.id = s.lecture_id where l.course_id = c.id and x.graded_at is null))
          order by c.sort_order, c.title)
        from public."Mooc_courses" c where is_super or public.mooc_role(uid, c.id) in ('admin', 'teacher')), '[]'::jsonb),
      'pending_teachers', (select count(*) from public."Mooc_people" where kind = 'teacher' and status = 'pending'));

  elsif act = 'course' then
    cid := (p->>'course_id')::uuid;
    if not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    return jsonb_build_object('ok', true, 'my_role', public.mooc_role(uid, cid), 'course', public.mooc_course_full(cid));

  elsif act = 'people' then
    if not (is_super or exists (select 1 from public."Mooc_members" where user_id = uid and role = 'admin' and status = 'active')) then
      return jsonb_build_object('ok', false, 'error', 'Only course admins and super admins manage people.');
    end if;
    return jsonb_build_object('ok', true, 'people', coalesce((select jsonb_agg(public.mooc_person(x.user_id) || jsonb_build_object(
          'kind', x.kind, 'status', x.status, 'created_at', x.created_at,
          'courses', (select count(*) from public."Mooc_members" m where m.user_id = x.user_id and m.status = 'active'))
        order by (x.status = 'pending') desc, x.created_at desc)
      from public."Mooc_people" x), '[]'::jsonb));

  elsif act = 'submissions' then
    cid := (p->>'course_id')::uuid;
    if not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    return jsonb_build_object('ok', true, 'submissions', coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object(
          'student', public.mooc_person(x.user_id), 'step_title', s.title, 'lecture_title', l.title, 'config', s.config)
        order by (x.graded_at is null) desc, x.submitted_at desc)
      from public."Mooc_submissions" x join public."Mooc_steps" s on s.id = x.step_id join public."Mooc_lectures" l on l.id = s.lecture_id
      where l.course_id = cid and (coalesce((p->>'all')::boolean, false) or x.graded_at is null)), '[]'::jsonb));

  elsif act = 'students' then
    cid := (p->>'course_id')::uuid;
    if not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    return jsonb_build_object('ok', true, 'students', coalesce((select jsonb_agg(public.mooc_person(m.user_id) || jsonb_build_object(
          'enrolled', m.added_at,
          'done', (select count(*) from public."Mooc_progress" pr join public."Mooc_steps" s on s.id = pr.step_id
                   join public."Mooc_lectures" l on l.id = s.lecture_id where l.course_id = cid and pr.user_id = m.user_id and pr.completed_at is not null),
          'score', (select round(avg(pr.score), 1) from public."Mooc_progress" pr join public."Mooc_steps" s on s.id = pr.step_id
                    join public."Mooc_lectures" l on l.id = s.lecture_id where l.course_id = cid and pr.user_id = m.user_id),
          'awards', (select coalesce(jsonb_agg(b.title), '[]'::jsonb) from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id
                     where b.course_id = cid and w.user_id = m.user_id and not w.revoked),
          'last_active', (select max(e.created_at) from public."Mooc_events" e where e.course_id = cid and e.user_id = m.user_id))
        order by m.added_at desc)
      from public."Mooc_members" m where m.course_id = cid and m.role = 'student' and m.status = 'active'), '[]'::jsonb),
      'steps', (select count(*) from public."Mooc_steps" s join public."Mooc_lectures" l on l.id = s.lecture_id
                where l.course_id = cid and l.status = 'published'));

  -- ------------------------------------------------------------ projects (super admin)
  elsif act = 'save_project' then
    if not is_super then return jsonb_build_object('ok', false, 'error', 'Only super admins manage projects.'); end if;
    rid := nullif(p->>'id', '')::uuid;
    if rid is null then
      insert into public."Mooc_projects"(slug, title, description, image_url, website, sort_order, created_by)
      values (coalesce(nullif(p->>'slug', ''), public.mooc_slug(p->>'title')), p->>'title', p->>'description', p->>'image_url',
              p->>'website', coalesce((p->>'sort_order')::int, 100), uid)
      returning id into rid;
    else
      update public."Mooc_projects" set slug = coalesce(nullif(p->>'slug', ''), slug), title = p->>'title',
        description = p->>'description', image_url = p->>'image_url', website = p->>'website',
        sort_order = coalesce((p->>'sort_order')::int, sort_order)
      where id = rid;
    end if;
    return jsonb_build_object('ok', true, 'id', rid);

  elsif act = 'delete_project' then
    if not is_super then return jsonb_build_object('ok', false, 'error', 'Only super admins manage projects.'); end if;
    delete from public."Mooc_projects" where id = (p->>'id')::uuid;   -- its courses stay, without a project
    return jsonb_build_object('ok', true);

  -- ------------------------------------------------------------ courses
  elsif act = 'save_course' then
    cid := nullif(p->>'id', '')::uuid;
    if cid is null then
      if not is_super then return jsonb_build_object('ok', false, 'error', 'Only super admins create courses.'); end if;
      insert into public."Mooc_courses"(slug, project_id, title, summary, description, outcomes, image_url, level, language,
                                        hours, pass_score, status, sort_order, created_by)
      values (coalesce(nullif(p->>'slug', ''), public.mooc_slug(p->>'title')), nullif(p->>'project_id', '')::uuid, p->>'title',
              p->>'summary', p->>'description', coalesce(p->'outcomes', '[]'::jsonb), p->>'image_url', nullif(p->>'level', ''),
              coalesce(nullif(p->>'language', ''), 'English'), nullif(p->>'hours', '')::numeric,
              coalesce((p->>'pass_score')::int, 70), 'draft', coalesce((p->>'sort_order')::int, 100), uid)
      returning id into cid;
    else
      if not public.mooc_can_manage(uid, cid) then return jsonb_build_object('ok', false, 'error', 'Only the course admin or a super admin can change this course.'); end if;
      update public."Mooc_courses" set
        slug = coalesce(nullif(p->>'slug', ''), slug), title = coalesce(p->>'title', title), summary = p->>'summary',
        description = p->>'description', outcomes = coalesce(p->'outcomes', outcomes), image_url = p->>'image_url',
        level = nullif(p->>'level', ''), language = coalesce(nullif(p->>'language', ''), language),
        hours = nullif(p->>'hours', '')::numeric, pass_score = coalesce((p->>'pass_score')::int, pass_score),
        status = coalesce(nullif(p->>'status', ''), status), sort_order = coalesce((p->>'sort_order')::int, sort_order),
        project_id = case when is_super and p ? 'project_id' then nullif(p->>'project_id', '')::uuid else project_id end,
        updated_at = now()
      where id = cid;
    end if;
    return jsonb_build_object('ok', true, 'id', cid);

  elsif act = 'delete_course' then
    if not is_super then return jsonb_build_object('ok', false, 'error', 'Only super admins delete courses.'); end if;
    cid := (p->>'id')::uuid;
    if exists (select 1 from public."Mooc_members" where course_id = cid and role = 'student') then
      return jsonb_build_object('ok', false, 'error', 'This course has students. Archive it instead of deleting it.');
    end if;
    delete from public."Mooc_courses" where id = cid;
    return jsonb_build_object('ok', true);

  -- ------------------------------------------------------------ people
  elsif act = 'set_member' then        -- {course_id, user (username or email), role, remove}
    cid := (p->>'course_id')::uuid;
    target := coalesce(nullif(p->>'user_id', '')::uuid, public.mooc_find_user(p->>'user'));
    if target is null then return jsonb_build_object('ok', false, 'error', 'No Octa account with that username or email.'); end if;
    if not public.mooc_can_manage(uid, cid) then return jsonb_build_object('ok', false, 'error', 'Only the course admin or a super admin can change course roles.'); end if;
    if (p->>'role' = 'admin' or exists (select 1 from public."Mooc_members" where course_id = cid and user_id = target and role = 'admin' and status = 'active'))
       and not is_super then
      return jsonb_build_object('ok', false, 'error', 'Only a super admin names or changes course admins.');
    end if;
    if coalesce((p->>'remove')::boolean, false) then
      update public."Mooc_members" set status = 'removed' where course_id = cid and user_id = target;
      return jsonb_build_object('ok', true);
    end if;
    if p->>'role' not in ('admin', 'teacher', 'student') then return jsonb_build_object('ok', false, 'error', 'Unknown role.'); end if;
    insert into public."Mooc_members"(course_id, user_id, role, status, added_by) values (cid, target, p->>'role', 'active', uid)
    on conflict (course_id, user_id) do update set role = excluded.role, status = 'active', added_by = uid, added_at = now();
    -- giving someone teacher or admin rights approves them as a teacher
    if p->>'role' in ('admin', 'teacher') then
      insert into public."Mooc_people"(user_id, kind, status, decided_by, decided_at) values (target, 'teacher', 'active', uid, now())
      on conflict (user_id) do update set kind = 'teacher', status = 'active', decided_by = uid, decided_at = now();
    else
      insert into public."Mooc_people"(user_id, kind) values (target, 'student') on conflict (user_id) do nothing;
      insert into public."Mooc_events"(user_id, course_id, verb) values (target, cid, 'enrolled');
    end if;
    return jsonb_build_object('ok', true, 'user', public.mooc_person(target));

  elsif act = 'decide_teacher' then    -- {user_id, approve}
    if not (is_super or exists (select 1 from public."Mooc_members" where user_id = uid and role = 'admin' and status = 'active')) then
      return jsonb_build_object('ok', false, 'error', 'Only course admins and super admins approve teachers.');
    end if;
    update public."Mooc_people" set status = case when (p->>'approve')::boolean then 'active' else 'declined' end,
      kind = 'teacher', decided_by = uid, decided_at = now()
    where user_id = (p->>'user_id')::uuid;
    get diagnostics n = row_count;
    return jsonb_build_object('ok', n = 1);

  elsif act = 'set_super' then         -- {user, on}
    if not is_super then return jsonb_build_object('ok', false, 'error', 'Only super admins name super admins.'); end if;
    target := coalesce(nullif(p->>'user_id', '')::uuid, public.mooc_find_user(p->>'user'));
    if target is null then return jsonb_build_object('ok', false, 'error', 'No Octa account with that username or email.'); end if;
    if (p->>'on')::boolean then insert into public."Mooc_super_admins"(user_id) values (target) on conflict do nothing;
    else delete from public."Mooc_super_admins" where user_id = target; end if;
    return jsonb_build_object('ok', true);

  elsif act = 'super_admins' then
    return jsonb_build_object('ok', true, 'super_admins', coalesce((select jsonb_agg(public.mooc_person(a.id) || jsonb_build_object('octa_admin', a.role = 'admin'))
      from public."User_accounts" a where a.role = 'admin' or exists (select 1 from public."Mooc_super_admins" s where s.user_id = a.id)), '[]'::jsonb));

  -- ------------------------------------------------------------ lectures, steps, questions
  elsif act = 'save_lecture' then
    rid := nullif(p->>'id', '')::uuid;
    cid := coalesce(public.mooc_course_of('lecture', rid), (p->>'course_id')::uuid);
    if not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    if rid is null then
      insert into public."Mooc_lectures"(course_id, position, title, summary, outcomes, status, created_by)
      values (cid, coalesce((p->>'position')::int, (select coalesce(max(position), 0) + 10 from public."Mooc_lectures" where course_id = cid)),
              p->>'title', p->>'summary', coalesce(p->'outcomes', '[]'::jsonb), coalesce(nullif(p->>'status', ''), 'draft'), uid)
      returning id into rid;
    else
      update public."Mooc_lectures" set title = coalesce(p->>'title', title), summary = coalesce(p->>'summary', summary),
        outcomes = coalesce(p->'outcomes', outcomes), status = coalesce(nullif(p->>'status', ''), status), updated_at = now()
      where id = rid;
    end if;
    return jsonb_build_object('ok', true, 'id', rid);

  elsif act = 'save_step' then
    rid := nullif(p->>'id', '')::uuid;
    if rid is null then cid := public.mooc_course_of('lecture', (p->>'lecture_id')::uuid);
    else cid := public.mooc_course_of('step', rid); end if;
    if not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    if rid is null then
      insert into public."Mooc_steps"(lecture_id, position, kind, title, config, required)
      values ((p->>'lecture_id')::uuid,
              coalesce((p->>'position')::int, (select coalesce(max(position), 0) + 10 from public."Mooc_steps" where lecture_id = (p->>'lecture_id')::uuid)),
              p->>'kind', p->>'title', coalesce(p->'config', '{}'::jsonb), coalesce((p->>'required')::boolean, true))
      returning id into rid;
    else
      update public."Mooc_steps" set title = coalesce(p->>'title', title), config = coalesce(p->'config', config),
        required = coalesce((p->>'required')::boolean, required), updated_at = now()
      where id = rid;
    end if;
    return jsonb_build_object('ok', true, 'id', rid);

  elsif act = 'save_question' then
    rid := nullif(p->>'id', '')::uuid;
    if rid is null then cid := public.mooc_course_of('step', (p->>'step_id')::uuid);
    else cid := public.mooc_course_of('question', rid); end if;
    if not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    if jsonb_array_length(coalesce(p->'correct', '[]'::jsonb)) = 0 then
      return jsonb_build_object('ok', false, 'error', 'Mark at least one correct answer.');
    end if;
    if rid is null then
      insert into public."Mooc_questions"(step_id, position, at_seconds, at_page, prompt, kind, options, correct, explanation, must_pass)
      values ((p->>'step_id')::uuid, coalesce((p->>'position')::int, 100), nullif(p->>'at_seconds', '')::int, nullif(p->>'at_page', '')::int,
              p->>'prompt', coalesce(nullif(p->>'kind', ''), 'single'), coalesce(p->'options', '[]'::jsonb), p->'correct',
              p->>'explanation', coalesce((p->>'must_pass')::boolean, true))
      returning id into rid;
    else
      update public."Mooc_questions" set at_seconds = nullif(p->>'at_seconds', '')::int, at_page = nullif(p->>'at_page', '')::int,
        prompt = p->>'prompt', kind = coalesce(nullif(p->>'kind', ''), kind), options = coalesce(p->'options', options),
        correct = p->'correct', explanation = p->>'explanation', must_pass = coalesce((p->>'must_pass')::boolean, must_pass)
      where id = rid;
    end if;
    return jsonb_build_object('ok', true, 'id', rid);

  elsif act = 'delete' then            -- {what: lecture|step|question|badge, id}
    rid := (p->>'id')::uuid;
    cid := public.mooc_course_of(p->>'what', rid);
    if cid is null or not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    case p->>'what'
      when 'lecture' then delete from public."Mooc_lectures" where id = rid;
      when 'step' then delete from public."Mooc_steps" where id = rid;
      when 'question' then delete from public."Mooc_questions" where id = rid;
      when 'badge' then
        if exists (select 1 from public."Mooc_awards" where badge_id = rid) then
          update public."Mooc_badges" set active = false where id = rid;   -- issued awards stay valid
        else delete from public."Mooc_badges" where id = rid; end if;
      else return jsonb_build_object('ok', false, 'error', 'Unknown item.');
    end case;
    return jsonb_build_object('ok', true);

  elsif act = 'reorder' then           -- {what: lecture|step, ids: [...]} in the new order
    if jsonb_array_length(coalesce(p->'ids', '[]'::jsonb)) = 0 then return jsonb_build_object('ok', true); end if;
    cid := public.mooc_course_of(p->>'what', (p->'ids'->>0)::uuid);
    if cid is null or not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    if p->>'what' = 'lecture' then
      update public."Mooc_lectures" l set position = x.n * 10 from jsonb_array_elements_text(p->'ids') with ordinality x(id, n)
      where l.id = x.id::uuid and l.course_id = cid;
    elsif p->>'what' = 'step' then
      update public."Mooc_steps" s set position = x.n * 10 from jsonb_array_elements_text(p->'ids') with ordinality x(id, n)
      where s.id = x.id::uuid and public.mooc_course_of('step', s.id) = cid;
    end if;
    return jsonb_build_object('ok', true);

  -- ------------------------------------------------------------ badges and certificates
  elsif act = 'save_badge' then
    rid := nullif(p->>'id', '')::uuid;
    cid := coalesce(public.mooc_course_of('badge', rid), (p->>'course_id')::uuid);
    if not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    if rid is null then
      insert into public."Mooc_badges"(course_id, kind, title, description, image_url, lecture_ids, min_score, active, created_by)
      values (cid, coalesce(nullif(p->>'kind', ''), 'badge'), p->>'title', p->>'description', p->>'image_url',
              coalesce(array(select jsonb_array_elements_text(p->'lecture_ids')::uuid), '{}'), coalesce((p->>'min_score')::int, 70),
              coalesce((p->>'active')::boolean, true), uid)
      returning id into rid;
    else
      update public."Mooc_badges" set kind = coalesce(nullif(p->>'kind', ''), kind), title = coalesce(p->>'title', title),
        description = case when p ? 'description' then p->>'description' else description end, image_url = coalesce(p->>'image_url', image_url),
        lecture_ids = case when p ? 'lecture_ids' then array(select jsonb_array_elements_text(p->'lecture_ids')::uuid) else lecture_ids end,
        min_score = coalesce((p->>'min_score')::int, min_score), active = coalesce((p->>'active')::boolean, active)
      where id = rid;
    end if;
    return jsonb_build_object('ok', true, 'id', rid);

  -- ------------------------------------------------------------ grading
  elsif act = 'grade' then             -- {submission_id, score 0-100, feedback}
    rid := (p->>'submission_id')::uuid;
    cid := public.mooc_course_of('submission', rid);
    if cid is null or not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    update public."Mooc_submissions" set score = (p->>'score')::numeric, feedback = p->>'feedback', graded_by = uid, graded_at = now()
    where id = rid returning user_id, step_id into target, rid;
    insert into public."Mooc_events"(user_id, course_id, step_id, verb, score) values (target, cid, rid, 'graded', (p->>'score')::numeric);
    -- the newest grade counts for this step
    insert into public."Mooc_progress"(user_id, step_id, completed_at, score) values (target, rid, now(), (p->>'score')::numeric)
    on conflict (user_id, step_id) do update set completed_at = coalesce(public."Mooc_progress".completed_at, now()),
      score = excluded.score, updated_at = now();
    return jsonb_build_object('ok', true, 'awarded', public.mooc_check_awards(target, cid));

  -- ------------------------------------------------------------ uploads
  elsif act = 'upload_ticket' then
    if not (is_super or exists (select 1 from public."Mooc_members" where user_id = uid and role in ('admin', 'teacher') and status = 'active')) then
      return jsonb_build_object('ok', false, 'error', 'Only teachers and admins upload files.');
    end if;
    delete from public."Mooc_upload_tickets" where expires_at < now();
    r := to_jsonb(encode(extensions.gen_random_bytes(16), 'hex'));
    insert into public."Mooc_upload_tickets"(ticket_hash, user_id, expires_at)
    values (public.octa_user_hash(r #>> '{}'), uid, now() + interval '30 minutes');
    return jsonb_build_object('ok', true, 'ticket', r #>> '{}');
  end if;

  return jsonb_build_object('ok', false, 'error', 'Unknown action.');
end $$;

-- ================================================================ API: students (used by the student website)
-- join the MOOC as student (active at once) or teacher (pending until approved)
create or replace function public.mooc_join(p_token text, p_kind text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := public.mooc_uid(p_token);
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please log in.'); end if;
  if p_kind not in ('student', 'teacher') then return jsonb_build_object('ok', false, 'error', 'Unknown kind.'); end if;
  insert into public."Mooc_people"(user_id, kind, status)
  values (uid, p_kind, case when p_kind = 'teacher' and not public.mooc_is_super(uid) then 'pending' else 'active' end)
  on conflict (user_id) do update set
    kind = case when public."Mooc_people".kind = 'teacher' then 'teacher' else excluded.kind end,
    status = case when public."Mooc_people".kind = 'student' and excluded.kind = 'teacher' then excluded.status
                  else public."Mooc_people".status end;
  return jsonb_build_object('ok', true, 'person', (select to_jsonb(x) from public."Mooc_people" x where x.user_id = uid));
end $$;

create or replace function public.mooc_enrol(p_token text, p_course uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := public.mooc_uid(p_token);
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please log in.'); end if;
  if not exists (select 1 from public."Mooc_courses" where id = p_course and status = 'published') then
    return jsonb_build_object('ok', false, 'error', 'This course is not open.');
  end if;
  insert into public."Mooc_people"(user_id, kind) values (uid, 'student') on conflict (user_id) do nothing;
  insert into public."Mooc_members"(course_id, user_id, role, added_by) values (p_course, uid, 'student', uid)
  on conflict (course_id, user_id) do update set status = 'active'
    where public."Mooc_members".status = 'removed' and public."Mooc_members".role = 'student';
  insert into public."Mooc_events"(user_id, course_id, verb) values (uid, p_course, 'enrolled');
  return jsonb_build_object('ok', true);
end $$;

-- record what a student did on a step. verb: opened | progressed | completed | joined_live.
-- 'completed' is accepted for video, pdf, text and live steps (quizzes complete through mooc_answer,
-- assignments through mooc_submit / grading) and only once every must-pass question on the step is answered.
create or replace function public.mooc_record(p_token text, p_step uuid, p_verb text, p_position numeric, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := public.mooc_uid(p_token); cid uuid := public.mooc_course_of('step', p_step); st public."Mooc_steps";
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please log in.'); end if;
  if public.mooc_role(uid, cid) is null then return jsonb_build_object('ok', false, 'error', 'Enrol in the course first.'); end if;
  select * into st from public."Mooc_steps" where id = p_step;
  if p_verb in ('opened', 'progressed', 'joined_live') then
    insert into public."Mooc_events"(user_id, course_id, lecture_id, step_id, verb, data)
    values (uid, cid, st.lecture_id, p_step, p_verb, coalesce(p_data, '{}'::jsonb) || jsonb_build_object('position', p_position));
    if p_position is not null then
      insert into public."Mooc_progress"(user_id, step_id, position) values (uid, p_step, p_position)
      on conflict (user_id, step_id) do update set position = greatest(coalesce(public."Mooc_progress".position, 0), excluded.position), updated_at = now();
    end if;
    if p_verb = 'joined_live' and st.kind = 'live' then
      return jsonb_build_object('ok', true, 'awarded', public.mooc_complete_step(uid, p_step, null));
    end if;
    return jsonb_build_object('ok', true, 'awarded', '[]'::jsonb);
  elsif p_verb = 'completed' then
    if st.kind not in ('video', 'pdf', 'text', 'live') then
      return jsonb_build_object('ok', false, 'error', 'This step is completed by answering or submitting.');
    end if;
    if exists (select 1 from public."Mooc_questions" q where q.step_id = p_step and q.must_pass
               and not exists (select 1 from public."Mooc_answers" a where a.question_id = q.id and a.user_id = uid and a.correct)) then
      return jsonb_build_object('ok', false, 'error', 'Answer the questions on this step first.');
    end if;
    return jsonb_build_object('ok', true, 'awarded', public.mooc_complete_step(uid, p_step,
      (select round(100.0 * avg(case when a.first_correct then 1 else 0 end), 1) from public."Mooc_questions" q
       join public."Mooc_answers" a on a.question_id = q.id and a.user_id = uid where q.step_id = p_step)));
  end if;
  return jsonb_build_object('ok', false, 'error', 'Unknown action.');
end $$;

-- answer an interactive question; checked here, so students never see the correct answers beforehand
create or replace function public.mooc_answer(p_token text, p_question uuid, p_answer jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := public.mooc_uid(p_token); q public."Mooc_questions"; st public."Mooc_steps"; ok boolean;
        cid uuid; awarded jsonb := '[]'::jsonb; total int; answered int;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please log in.'); end if;
  select * into q from public."Mooc_questions" where id = p_question;
  select * into st from public."Mooc_steps" where id = q.step_id;
  cid := public.mooc_course_of('step', st.id);
  if public.mooc_role(uid, cid) is null then return jsonb_build_object('ok', false, 'error', 'Enrol in the course first.'); end if;
  ok := (select coalesce(array_agg(x order by x), '{}') from jsonb_array_elements_text(coalesce(p_answer, '[]'::jsonb)) x)
      = (select coalesce(array_agg(x order by x), '{}') from jsonb_array_elements_text(q.correct) x);
  insert into public."Mooc_answers"(user_id, question_id, first_correct, correct) values (uid, q.id, ok, ok)
  on conflict (user_id, question_id) do update set correct = public."Mooc_answers".correct or excluded.correct,
    attempts = public."Mooc_answers".attempts + 1, updated_at = now();
  insert into public."Mooc_events"(user_id, course_id, lecture_id, step_id, verb, score, data)
  values (uid, cid, st.lecture_id, st.id, 'answered', case when ok then 100 else 0 end,
          jsonb_build_object('question_id', q.id, 'answer', p_answer));
  -- a quiz is complete once every question has been answered correctly; its score is first-try correctness
  if st.kind = 'quiz' then
    select count(*), count(a.*) filter (where a.correct) into total, answered
    from public."Mooc_questions" x left join public."Mooc_answers" a on a.question_id = x.id and a.user_id = uid
    where x.step_id = st.id;
    if answered = total then
      awarded := public.mooc_complete_step(uid, st.id,
        (select round(100.0 * avg(case when a.first_correct then 1 else 0 end), 1) from public."Mooc_questions" x
         join public."Mooc_answers" a on a.question_id = x.id and a.user_id = uid where x.step_id = st.id));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'correct', ok,
    'explanation', case when ok or not q.must_pass then q.explanation end,
    'correct_answer', case when not q.must_pass then q.correct end, 'awarded', awarded);
end $$;

-- hand in an assignment. Auto-graded assignments count as completed at once (score 100).
create or replace function public.mooc_submit(p_token text, p_step uuid, p_answer text, p_file_url text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := public.mooc_uid(p_token); cid uuid := public.mooc_course_of('step', p_step); st public."Mooc_steps"; sid uuid;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please log in.'); end if;
  if public.mooc_role(uid, cid) is null then return jsonb_build_object('ok', false, 'error', 'Enrol in the course first.'); end if;
  select * into st from public."Mooc_steps" where id = p_step;
  if st.kind <> 'assignment' then return jsonb_build_object('ok', false, 'error', 'This step is not an assignment.'); end if;
  insert into public."Mooc_submissions"(step_id, user_id, answer, file_url) values (p_step, uid, p_answer, p_file_url) returning id into sid;
  insert into public."Mooc_events"(user_id, course_id, lecture_id, step_id, verb) values (uid, cid, st.lecture_id, p_step, 'submitted');
  if coalesce(st.config->>'grading', 'manual') = 'auto' then
    update public."Mooc_submissions" set score = 100, graded_at = now() where id = sid;
    return jsonb_build_object('ok', true, 'id', sid, 'awarded', public.mooc_complete_step(uid, p_step, 100));
  end if;
  return jsonb_build_object('ok', true, 'id', sid, 'awarded', '[]'::jsonb);
end $$;

-- ================================================================ API: public pages (no login needed)
create or replace function public.mooc_catalogue() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'projects', coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order, x.title) from public."Mooc_projects" x), '[]'::jsonb),
    'courses', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'slug', c.slug, 'title', c.title, 'summary', c.summary,
        'image_url', c.image_url, 'level', c.level, 'language', c.language, 'hours', c.hours, 'project_id', c.project_id,
        'lectures', (select count(*) from public."Mooc_lectures" l where l.course_id = c.id and l.status = 'published'),
        'students', (select count(*) from public."Mooc_members" m where m.course_id = c.id and m.role = 'student' and m.status = 'active'),
        'teachers', (select coalesce(jsonb_agg(public.mooc_person(m.user_id) - 'email'), '[]'::jsonb) from public."Mooc_members" m
                     where m.course_id = c.id and m.role in ('admin', 'teacher') and m.status = 'active'))
      order by c.sort_order, c.title) from public."Mooc_courses" c where c.status = 'published'), '[]'::jsonb))
$$;

create or replace function public.mooc_profile(p_username text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when a.id is null or x.public_profile is not true then jsonb_build_object('ok', false) else jsonb_build_object('ok', true,
    'user', jsonb_build_object('username', a.username, 'first_name', a.first_name, 'last_name', a.last_name,
                               'affiliation', a.affiliation, 'headline', x.headline, 'since', x.created_at),
    'awards', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'kind', b.kind, 'title', b.title, 'image_url', b.image_url,
        'issued_at', w.issued_at, 'course', c.title, 'course_slug', c.slug) order by w.issued_at desc)
      from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id join public."Mooc_courses" c on c.id = b.course_id
      where w.user_id = a.id and not w.revoked), '[]'::jsonb),
    'courses', coalesce((select jsonb_agg(jsonb_build_object('title', c.title, 'slug', c.slug, 'image_url', c.image_url,
        'done', (select count(*) from public."Mooc_progress" pr join public."Mooc_steps" s on s.id = pr.step_id join public."Mooc_lectures" l on l.id = s.lecture_id
                 where l.course_id = c.id and l.status = 'published' and pr.user_id = a.id and pr.completed_at is not null),
        'steps', (select count(*) from public."Mooc_steps" s join public."Mooc_lectures" l on l.id = s.lecture_id where l.course_id = c.id and l.status = 'published')))
      from public."Mooc_members" m join public."Mooc_courses" c on c.id = m.course_id
      where m.user_id = a.id and m.role = 'student' and m.status = 'active' and c.status = 'published'), '[]'::jsonb)) end
  from (select 1) one
  left join public."User_accounts" a on lower(a.username) = lower(coalesce(p_username, ''))
  left join public."Mooc_people" x on x.user_id = a.id
$$;

create or replace function public.mooc_award(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_build_object('ok', true, 'id', w.id, 'issued_at', w.issued_at, 'score', w.score, 'revoked', w.revoked,
      'kind', b.kind, 'title', b.title, 'description', b.description, 'image_url', b.image_url,
      'course', jsonb_build_object('title', c.title, 'slug', c.slug, 'outcomes', c.outcomes),
      'project', (select jsonb_build_object('title', pj.title, 'slug', pj.slug) from public."Mooc_projects" pj where pj.id = c.project_id),
      'recipient', jsonb_build_object('username', a.username, 'first_name', a.first_name, 'last_name', a.last_name))
    from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id join public."Mooc_courses" c on c.id = b.course_id
    join public."User_accounts" a on a.id = w.user_id where w.id = p_id), jsonb_build_object('ok', false))
$$;

-- ================================================================ file uploads (storage bucket 'mooc', public read)
create or replace function public.mooc_upload_ok(p_ticket text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public."Mooc_upload_tickets" where ticket_hash = public.octa_user_hash(coalesce(p_ticket, '')) and expires_at > now())
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('mooc', 'mooc', true, 52428800, array['application/pdf', 'image/png', 'image/jpeg', 'image/webp', 'image/svg+xml', 'image/gif'])
on conflict (id) do nothing;

create policy "mooc uploads with a ticket" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'mooc' and public.mooc_upload_ok((storage.foldername(name))[1]));

-- ================================================================ privileges
do $$ declare f text; begin
  foreach f in array array['mooc_uid(text)', 'mooc_is_super(uuid)', 'mooc_role(uuid,uuid)', 'mooc_can_edit(uuid,uuid)',
                           'mooc_can_manage(uuid,uuid)', 'mooc_slug(text)', 'mooc_course_of(text,uuid)', 'mooc_find_user(text)',
                           'mooc_person(uuid)', 'mooc_course_full(uuid)', 'mooc_check_awards(uuid,uuid)',
                           'mooc_complete_step(uuid,uuid,numeric)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['mooc_manage(text,jsonb)', 'mooc_join(text,text)', 'mooc_enrol(text,uuid)',
                           'mooc_record(text,uuid,text,numeric,jsonb)', 'mooc_answer(text,uuid,jsonb)',
                           'mooc_submit(text,uuid,text,text)', 'mooc_catalogue()', 'mooc_profile(text)', 'mooc_award(uuid)',
                           'mooc_upload_ok(text)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

-- ================================================================ the MOOC in the Octa suite catalogue
insert into public."User_apps"(id, family, name, description, icon, url, status, access_mode, group_label, sort_order)
values ('octa_mooc', 'education', 'MOOC Studio', 'Create CloudEARTHi MOOC courses: lectures, interactive videos and PDFs, badges and certificates',
        '🎓', '', 'construction', 'open', 'Education', 20)
on conflict (id) do nothing;
