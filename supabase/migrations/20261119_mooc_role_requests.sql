-- Registration with a role (applied 2026-11-19 as "mooc_role_requests").
-- People choose how they join the MOOC: student (enrolled at once), teacher of a course (approved by that course's
-- admin or a super admin) or admin of a course (approved by a super admin only).

create table if not exists public."Mooc_requests" (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  course_id uuid not null references public."Mooc_courses"(id) on delete cascade,
  role text not null check (role in ('admin', 'teacher')),
  message text check (char_length(message) <= 1000),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  created_at timestamptz not null default now(),
  decided_by uuid references public."User_accounts"(id) on delete set null,
  decided_at timestamptz
);
create unique index if not exists "Mooc_requests_one_pending" on public."Mooc_requests" (user_id, course_id, role) where status = 'pending';
create index if not exists "Mooc_requests_course_idx" on public."Mooc_requests" (course_id, status);
comment on table public."Mooc_requests" is 'Requests to teach or to be admin of a course, waiting for approval.';
alter table public."Mooc_requests" enable row level security;
revoke all on public."Mooc_requests" from anon, authenticated;

-- what the registration form needs: the courses one can join, and the user's current roles and requests
create or replace function public.mooc_join_options(p_token text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := public.mooc_uid(p_token);
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please log in.'); end if;
  return jsonb_build_object('ok', true,
    'person', (select to_jsonb(x) from public."Mooc_people" x where x.user_id = uid),
    'courses', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'slug', c.slug, 'title', c.title, 'status', c.status,
        'project', (select p.title from public."Mooc_projects" p where p.id = c.project_id),
        'my_role', (select m.role from public."Mooc_members" m where m.course_id = c.id and m.user_id = uid and m.status = 'active'))
      order by c.sort_order, c.title) from public."Mooc_courses" c where c.status <> 'archived'), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'course', c.title, 'role', r.role, 'status', r.status,
        'created_at', r.created_at, 'decided_at', r.decided_at) order by r.created_at desc)
      from public."Mooc_requests" r join public."Mooc_courses" c on c.id = r.course_id where r.user_id = uid), '[]'::jsonb));
end $$;

-- join: p_kind = student | teacher | admin, for one course
create or replace function public.mooc_register(p_token text, p_kind text, p_course uuid, p_message text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := public.mooc_uid(p_token); c public."Mooc_courses"; cur text; rid uuid;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please log in.'); end if;
  if p_kind not in ('student', 'teacher', 'admin') then return jsonb_build_object('ok', false, 'error', 'Choose student, teacher or course admin.'); end if;
  select * into c from public."Mooc_courses" where id = p_course and status <> 'archived';
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'Choose a course.'); end if;
  select role into cur from public."Mooc_members" where course_id = c.id and user_id = uid and status = 'active';

  if p_kind = 'student' then
    if c.status <> 'published' then return jsonb_build_object('ok', false, 'error', 'This course is not open to students yet.'); end if;
    if cur is not null then return jsonb_build_object('ok', true, 'status', 'member', 'role', cur, 'slug', c.slug); end if;
    insert into public."Mooc_people"(user_id, kind) values (uid, 'student') on conflict (user_id) do nothing;
    insert into public."Mooc_members"(course_id, user_id, role, added_by) values (c.id, uid, 'student', uid)
    on conflict (course_id, user_id) do update set status = 'active', role = 'student';
    insert into public."Mooc_events"(user_id, course_id, verb) values (uid, c.id, 'enrolled');
    return jsonb_build_object('ok', true, 'status', 'enrolled', 'slug', c.slug);
  end if;

  if cur = 'admin' or (cur = 'teacher' and p_kind = 'teacher') then
    return jsonb_build_object('ok', true, 'status', 'member', 'role', cur, 'slug', c.slug);
  end if;
  if public.mooc_is_super(uid) then          -- super admins need no approval
    insert into public."Mooc_members"(course_id, user_id, role, added_by) values (c.id, uid, p_kind, uid)
    on conflict (course_id, user_id) do update set role = excluded.role, status = 'active';
    return jsonb_build_object('ok', true, 'status', 'member', 'role', p_kind, 'slug', c.slug);
  end if;
  insert into public."Mooc_people"(user_id, kind, status) values (uid, 'teacher', 'pending')
  on conflict (user_id) do update set kind = 'teacher',
    status = case when public."Mooc_people".kind = 'teacher' then public."Mooc_people".status else 'pending' end;
  insert into public."Mooc_requests"(user_id, course_id, role, message) values (uid, c.id, p_kind, nullif(trim(p_message), ''))
  on conflict (user_id, course_id, role) where status = 'pending' do update set message = excluded.message
  returning id into rid;
  return jsonb_build_object('ok', true, 'status', 'requested', 'request_id', rid);
end $$;

revoke execute on function public.mooc_join_options(text) from public;
grant execute on function public.mooc_join_options(text) to anon, authenticated;
revoke execute on function public.mooc_register(text, text, uuid, text) from public;
grant execute on function public.mooc_register(text, text, uuid, text) to anon, authenticated;

-- approvals in MOOC Studio: actions 'requests' and 'decide_request'; 'overview' counts waiting requests
do $$ declare f oid; def text; old text; begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_manage';
  def := pg_get_functiondef(f);

  old := E'  elsif act = ''upload_ticket'' then';
  if position(old in def) = 0 then raise exception 'mooc_manage: upload_ticket not found'; end if;
  def := replace(def, old,
       E'  elsif act = ''requests'' then\n'
    || E'    return jsonb_build_object(''ok'', true, ''requests'', coalesce((select jsonb_agg(public.mooc_person(q.user_id) || jsonb_build_object(\n'
    || E'        ''request_id'', q.id, ''course_id'', q.course_id, ''course'', c.title, ''role'', q.role, ''message'', q.message,\n'
    || E'        ''created_at'', q.created_at) order by q.created_at)\n'
    || E'      from public."Mooc_requests" q join public."Mooc_courses" c on c.id = q.course_id\n'
    || E'      where q.status = ''pending'' and (is_super or (q.role = ''teacher'' and public.mooc_can_manage(uid, q.course_id)))), ''[]''::jsonb));\n'
    || E'  elsif act = ''decide_request'' then\n'
    || E'    select course_id, user_id, role into cid, target, r from (select course_id, user_id, to_jsonb(role) role\n'
    || E'      from public."Mooc_requests" where id = (p->>''request_id'')::uuid and status = ''pending'') x;\n'
    || E'    if cid is null then return jsonb_build_object(''ok'', false, ''error'', ''This request was already decided.''); end if;\n'
    || E'    if (r #>> ''{}'') = ''admin'' and not is_super then return jsonb_build_object(''ok'', false, ''error'', ''Only a super admin approves course admins.''); end if;\n'
    || E'    if not public.mooc_can_manage(uid, cid) then return jsonb_build_object(''ok'', false, ''error'', ''Only the course admin or a super admin can decide this.''); end if;\n'
    || E'    if coalesce((p->>''approve'')::boolean, false) then\n'
    || E'      insert into public."Mooc_members"(course_id, user_id, role, status, added_by) values (cid, target, r #>> ''{}'', ''active'', uid)\n'
    || E'      on conflict (course_id, user_id) do update set role = excluded.role, status = ''active'', added_by = uid, added_at = now();\n'
    || E'      insert into public."Mooc_people"(user_id, kind, status, decided_by, decided_at) values (target, ''teacher'', ''active'', uid, now())\n'
    || E'      on conflict (user_id) do update set kind = ''teacher'', status = ''active'', decided_by = uid, decided_at = now();\n'
    || E'    end if;\n'
    || E'    update public."Mooc_requests" set status = case when coalesce((p->>''approve'')::boolean, false) then ''approved'' else ''declined'' end,\n'
    || E'      decided_by = uid, decided_at = now() where id = (p->>''request_id'')::uuid;\n'
    || E'    return jsonb_build_object(''ok'', true, ''user'', public.mooc_person(target));\n'
    || old);

  old := E'''pending_teachers'', (select count(*) from public."Mooc_people" where kind = ''teacher'' and status = ''pending'')';
  if position(old in def) = 0 then raise exception 'mooc_manage: pending_teachers not found'; end if;
  def := replace(def, old, old || E',\n      ''pending_requests'', (select count(*) from public."Mooc_requests" q where q.status = ''pending''\n'
    || E'        and (is_super or (q.role = ''teacher'' and public.mooc_can_manage(uid, q.course_id))))');
  execute def;
end $$;
