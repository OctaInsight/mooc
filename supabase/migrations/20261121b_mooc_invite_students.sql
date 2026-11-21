-- People on an issued list become students (applied 2026-11-21 as "mooc_invite_students").
-- When a super admin or course admin issues certificates from a list, everyone on it is enrolled as a student of that
-- course. People without an Octa account get one (username from their email, an unknown random password) and a
-- "set your password" link valid for 30 days, sent in the certificate email. A link is only handed out while the
-- invited account has never had its password set, and only to someone who manages the course that invited it, so
-- nobody can take over an account its owner already uses.

create table if not exists public."Mooc_invites" (
  user_id uuid primary key references public."User_accounts"(id) on delete cascade,
  course_id uuid references public."Mooc_courses"(id) on delete set null,
  invited_by uuid references public."User_accounts"(id) on delete set null,
  initial_hash text not null,               -- the account is still waiting for its owner while its password hash is this one
  created_at timestamptz not null default now()
);
alter table public."Mooc_invites" enable row level security;
revoke all on public."Mooc_invites" from anon, authenticated;
comment on table public."Mooc_invites" is 'Accounts created for people on a certificate list, until they set their own password.';

create or replace function public.mooc_invite(p_uid uuid, p_course uuid, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare x record; acc uuid; h text; base text; un text; n int; tok text; created boolean; out jsonb := '[]'::jsonb;
begin
  for x in
    select distinct on (lower(trim(r->>'email'))) lower(trim(r->>'email')) em,
           nullif(trim(coalesce(r->>'first_name', '')), '') fn, nullif(trim(coalesce(r->>'last_name', '')), '') ln,
           trim(coalesce(r->>'name', '')) nm
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
    where lower(trim(r->>'email')) ~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$'
  loop
    created := false;
    select id into acc from public."User_accounts" where email = x.em;
    if acc is null then
      base := left(lower(regexp_replace(split_part(x.em, '@', 1), '[^A-Za-z0-9._-]', '', 'g')), 30);
      if char_length(base) < 3 then base := base || '_mooc'; end if;
      un := base; n := 1;
      while exists (select 1 from public."User_accounts" where lower(username) = lower(un)) loop
        n := n + 1; un := base || n;
      end loop;
      -- a random password nobody knows (low bcrypt cost: it is never typed, and lists can be long)
      h := extensions.crypt(encode(extensions.gen_random_bytes(18), 'hex'), extensions.gen_salt('bf', 4));
      insert into public."User_accounts"(email, username, password_hash, first_name, last_name, registered_from)
      values (x.em, un, h,
              left(coalesce(x.fn, nullif(regexp_replace(x.nm, '\s+\S+$', ''), ''), x.nm), 100),
              left(coalesce(x.ln, case when x.nm ~ '\s' then substring(x.nm from '\S+$') end), 100),
              'octa_mooc')
      returning id into acc;
      insert into public."Mooc_invites"(user_id, course_id, invited_by, initial_hash) values (acc, p_course, p_uid, h);
      insert into public."User_usage"(user_id, app_id, event)
      select acc, 'octa_mooc', 'register' where exists (select 1 from public."User_apps" where id = 'octa_mooc');
      created := true;
    end if;
    insert into public."Mooc_people"(user_id, kind) values (acc, 'student') on conflict (user_id) do nothing;
    insert into public."Mooc_members"(course_id, user_id, role, added_by) values (p_course, acc, 'student', p_uid)
    on conflict (course_id, user_id) do update set status = 'active'
      where public."Mooc_members".status = 'removed' and public."Mooc_members".role = 'student';
    if created then
      insert into public."Mooc_events"(user_id, course_id, verb) values (acc, p_course, 'enrolled');
    end if;
    tok := null;
    if exists (select 1 from public."Mooc_invites" i join public."User_accounts" a on a.id = i.user_id
               where i.user_id = acc and a.password_hash = i.initial_hash
                 and (i.course_id is null or coalesce(public.mooc_can_manage(p_uid, i.course_id), false))) then
      tok := encode(extensions.gen_random_bytes(32), 'hex');
      insert into public."User_password_resets"(token_hash, user_id, expires_at, return_app)
      values (public.octa_user_hash(tok), acc, now() + interval '30 days', 'mooc_site');
    end if;
    out := out || jsonb_build_object('email', x.em, 'username', (select username from public."User_accounts" where id = acc),
                                     'created', created, 'set_password_token', tok);
  end loop;
  return out;
end $$;
revoke execute on function public.mooc_invite(uuid, uuid, jsonb) from public, anon, authenticated;

-- mooc_manage action: invite_students {course_id, rows: [{name, first_name, last_name, email}]}
do $$ declare f oid; def text; old text; begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_manage';
  def := pg_get_functiondef(f);
  old := E'  elsif act = ''upload_ticket'' then';
  if position(old in def) = 0 then raise exception 'mooc_manage: upload_ticket not found'; end if;
  if position('invite_students' in def) > 0 then raise exception 'mooc_manage: invite_students already there'; end if;
  def := replace(def, old,
       E'  elsif act = ''invite_students'' then\n'
    || E'    if not coalesce(public.mooc_can_manage(uid, (p->>''course_id'')::uuid), false) then\n'
    || E'      return jsonb_build_object(''ok'', false, ''error'', ''Only the course admin or a super admin can add people to this course.''); end if;\n'
    || E'    if jsonb_array_length(coalesce(p->''rows'', ''[]''::jsonb)) > 2000 then return jsonb_build_object(''ok'', false, ''error'', ''At most 2,000 people at a time.''); end if;\n'
    || E'    return jsonb_build_object(''ok'', true, ''people'', public.mooc_invite(uid, (p->>''course_id'')::uuid, p->''rows''));\n'
    || old);
  execute def;
end $$;

-- My learning also lists certificates-only events (applied as "mooc_my_learning_events"); they are often never published
do $$ declare f oid; def text; old text; begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_my_learning';
  def := pg_get_functiondef(f);
  old := 'm.status = ''active'' and c.status = ''published''';
  if position(old in def) = 0 then raise exception 'mooc_my_learning: filter not found'; end if;
  def := replace(def, old, 'm.status = ''active'' and (c.status = ''published'' or (c.kind = ''event'' and c.status <> ''archived''))');
  execute def;
end $$;
