-- Bulk certificates and badges (applied 2026-11-21 as "mooc_bulk_awards").
-- Super admins and course admins issue a course's badges and certificates to a list of people (from an Excel file),
-- each with their own name and contribution. People need no Octa account: the award keeps their name and email, and
-- it is linked to their account when one exists with that email (now or when they register later).
-- Courses can be "certificates only" (conferences, workshops, courses with little content): kept out of the catalogue.

alter table public."Mooc_courses" add column if not exists kind text not null default 'course' check (kind in ('course', 'event'));
comment on column public."Mooc_courses".kind is 'course = a course with lectures; event = certificates only (conference, workshop), not listed on the website.';

alter table public."Mooc_awards" alter column user_id drop not null;
alter table public."Mooc_awards"
  add column if not exists recipient_name text check (char_length(recipient_name) <= 200),
  add column if not exists recipient_email text check (char_length(recipient_email) <= 320),
  add column if not exists contribution text check (char_length(contribution) <= 300),
  add column if not exists source text not null default 'auto' check (source in ('auto', 'bulk')),
  add column if not exists issued_by uuid references public."User_accounts"(id) on delete set null,
  add column if not exists email_sent_at timestamptz,
  add column if not exists email_error text check (char_length(email_error) <= 500);
alter table public."Mooc_awards" drop constraint if exists "Mooc_awards_has_recipient";
alter table public."Mooc_awards" add constraint "Mooc_awards_has_recipient" check (user_id is not null or recipient_name is not null);
create unique index if not exists "Mooc_awards_badge_email" on public."Mooc_awards" (badge_id, lower(recipient_email)) where recipient_email is not null;
comment on column public."Mooc_awards".contribution is 'Printed on the certificate, e.g. Speaker, Participant, Attended all three days.';

-- a new Octa account receives the awards already issued to its email address
create or replace function public.mooc_link_awards() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public."Mooc_awards" w set user_id = new.id
  where w.user_id is null and lower(w.recipient_email) = lower(new.email)
    and not exists (select 1 from public."Mooc_awards" x where x.badge_id = w.badge_id and x.user_id = new.id);
  return new;
end $$;
revoke execute on function public.mooc_link_awards() from public, anon, authenticated;
drop trigger if exists "User_accounts_link_mooc_awards" on public."User_accounts";
create trigger "User_accounts_link_mooc_awards" after insert or update of email on public."User_accounts"
  for each row execute function public.mooc_link_awards();

-- the public award page: name and contribution from the award itself when there is no account
create or replace function public.mooc_award(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_build_object('ok', true, 'id', w.id, 'issued_at', w.issued_at, 'score', w.score, 'revoked', w.revoked,
      'kind', b.kind, 'title', b.title, 'description', b.description, 'image_url', b.image_url, 'contribution', w.contribution,
      'course', jsonb_build_object('title', c.title, 'slug', c.slug, 'outcomes', c.outcomes, 'kind', c.kind),
      'project', (select jsonb_build_object('title', pj.title, 'slug', pj.slug) from public."Mooc_projects" pj where pj.id = c.project_id),
      'recipient', case when w.recipient_name is not null
                        then jsonb_build_object('username', a.username, 'first_name', w.recipient_name, 'last_name', '')
                        else jsonb_build_object('username', a.username, 'first_name', a.first_name, 'last_name', a.last_name) end)
    from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id join public."Mooc_courses" c on c.id = b.course_id
    left join public."User_accounts" a on a.id = w.user_id where w.id = p_id), jsonb_build_object('ok', false))
$$;

do $$ declare f oid; def text; old text; begin
  -- the website's course list leaves out certificates-only courses
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_catalogue';
  def := pg_get_functiondef(f);
  old := 'from public."Mooc_courses" c where c.status = ''published''';
  if position(old in def) = 0 then raise exception 'mooc_catalogue: course filter not found'; end if;
  def := replace(def, old, old || ' and c.kind = ''course''');
  execute def;

  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_manage';
  def := pg_get_functiondef(f);

  -- course admins may create courses too; they become the new course's admin. The kind can be set.
  old := E'      if not is_super then return jsonb_build_object(''ok'', false, ''error'', ''Only super admins create courses.''); end if;';
  if position(old in def) = 0 then raise exception 'mooc_manage: create check not found'; end if;
  def := replace(def, old,
       E'      if not (is_super or exists (select 1 from public."Mooc_members" where user_id = uid and role = ''admin'' and status = ''active'')) then\n'
    || E'        return jsonb_build_object(''ok'', false, ''error'', ''Only super admins and course admins create courses.''); end if;');
  old := E'      returning id into cid;\n    else\n      if not public.mooc_can_manage(uid, cid)';
  if position(old in def) = 0 then raise exception 'mooc_manage: create insert not found'; end if;
  def := replace(def, old,
       E'      returning id into cid;\n'
    || E'      if not is_super then insert into public."Mooc_members"(course_id, user_id, role, added_by) values (cid, uid, ''admin'', uid); end if;\n'
    || E'    else\n      if not public.mooc_can_manage(uid, cid)');
  old := E'      where id = cid;\n    end if;\n    return jsonb_build_object(''ok'', true, ''id'', cid);';
  if position(old in def) = 0 then raise exception 'mooc_manage: save_course end not found'; end if;
  def := replace(def, old,
       E'      where id = cid;\n    end if;\n'
    || E'    if p->>''kind'' in (''course'', ''event'') then update public."Mooc_courses" set kind = p->>''kind'' where id = cid; end if;\n'
    || E'    return jsonb_build_object(''ok'', true, ''id'', cid);');

  -- new actions: bulk_award, awards, award_email, revoke_award
  old := E'  elsif act = ''upload_ticket'' then';
  if position(old in def) = 0 then raise exception 'mooc_manage: upload_ticket not found'; end if;
  def := replace(def, old,
       E'  elsif act = ''bulk_award'' then\n'
    || E'    -- {badge_ids: [...], rows: [{name, email, contribution}], issued_at, default_contribution}\n'
    || E'    if jsonb_array_length(coalesce(p->''badge_ids'', ''[]''::jsonb)) = 0 then return jsonb_build_object(''ok'', false, ''error'', ''Choose at least one badge or certificate.''); end if;\n'
    || E'    if jsonb_array_length(coalesce(p->''rows'', ''[]''::jsonb)) > 2000 then return jsonb_build_object(''ok'', false, ''error'', ''At most 2,000 people at a time.''); end if;\n'
    || E'    if exists (select 1 from jsonb_array_elements_text(p->''badge_ids'') x\n'
    || E'               where not coalesce(public.mooc_can_manage(uid, public.mooc_course_of(''badge'', x::uuid)), false)) then\n'
    || E'      return jsonb_build_object(''ok'', false, ''error'', ''Only the course admin or a super admin can issue these.''); end if;\n'
    || E'    with rws as (select distinct on (lower(trim(x->>''email''))) trim(x->>''name'') nm, lower(trim(x->>''email'')) em,\n'
    || E'                        nullif(trim(coalesce(nullif(trim(x->>''contribution''), ''''), p->>''default_contribution'', '''')), '''') ct\n'
    || E'                 from jsonb_array_elements(p->''rows'') x\n'
    || E'                 where coalesce(trim(x->>''name''), '''') <> '''' and lower(trim(x->>''email'')) ~ ''^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$''),\n'
    || E'         want as (select b.id bid, r.nm, r.em, r.ct, acc.id acc,\n'
    || E'                         (select z.id from public."Mooc_awards" z where z.badge_id = b.id\n'
    || E'                            and (lower(z.recipient_email) = r.em or (acc.id is not null and z.user_id = acc.id)) limit 1) had\n'
    || E'                  from rws r cross join (select x::uuid id from jsonb_array_elements_text(p->''badge_ids'') x) b\n'
    || E'                  left join public."User_accounts" acc on acc.email = r.em),\n'
    || E'         ins as (insert into public."Mooc_awards"(badge_id, user_id, recipient_name, recipient_email, contribution, source, issued_by, issued_at)\n'
    || E'                 select w.bid, w.acc, w.nm, w.em, w.ct, ''bulk'', uid, coalesce(nullif(p->>''issued_at'', '''')::timestamptz, now())\n'
    || E'                 from want w where w.had is null on conflict do nothing returning id, badge_id, recipient_email)\n'
    || E'    select jsonb_build_object(''ok'', true, ''awards'', coalesce(jsonb_agg(jsonb_build_object(''award_id'', coalesce(i.id, w.had),\n'
    || E'             ''new'', i.id is not null, ''name'', w.nm, ''email'', w.em, ''contribution'', w.ct, ''badge_id'', w.bid,\n'
    || E'             ''title'', b.title, ''kind'', b.kind,\n'
    || E'             ''email_sent_at'', (select e.email_sent_at from public."Mooc_awards" e where e.id = w.had))), ''[]''::jsonb))\n'
    || E'      into r from want w join public."Mooc_badges" b on b.id = w.bid\n'
    || E'      left join ins i on i.badge_id = w.bid and i.recipient_email = w.em;\n'
    || E'    return r;\n'
    || E'  elsif act = ''awards'' then\n'
    || E'    cid := (p->>''course_id'')::uuid;\n'
    || E'    if not public.mooc_can_manage(uid, cid) then return jsonb_build_object(''ok'', false, ''error'', ''Only the course admin or a super admin can see this.''); end if;\n'
    || E'    return jsonb_build_object(''ok'', true, ''awards'', coalesce((select jsonb_agg(jsonb_build_object(''award_id'', w.id, ''title'', b.title, ''kind'', b.kind,\n'
    || E'        ''name'', coalesce(w.recipient_name, nullif(trim(concat(a.first_name, '' '', a.last_name)), ''''), a.username),\n'
    || E'        ''email'', coalesce(w.recipient_email, a.email), ''contribution'', w.contribution, ''issued_at'', w.issued_at, ''source'', w.source,\n'
    || E'        ''email_sent_at'', w.email_sent_at, ''email_error'', w.email_error, ''revoked'', w.revoked, ''has_account'', w.user_id is not null)\n'
    || E'        order by w.issued_at desc, b.title, w.recipient_name)\n'
    || E'      from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id left join public."User_accounts" a on a.id = w.user_id\n'
    || E'      where b.course_id = cid), ''[]''::jsonb));\n'
    || E'  elsif act = ''award_email'' then\n'
    || E'    -- {ids: [...], sent: true|false, error}: what happened when the award emails were sent\n'
    || E'    if exists (select 1 from jsonb_array_elements_text(coalesce(p->''ids'', ''[]''::jsonb)) x\n'
    || E'               where not coalesce(public.mooc_can_manage(uid, (select b.course_id from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id where w.id = x::uuid)), false)) then\n'
    || E'      return jsonb_build_object(''ok'', false, ''error'', ''Only the course admin or a super admin can do this.''); end if;\n'
    || E'    update public."Mooc_awards" set email_sent_at = case when coalesce((p->>''sent'')::boolean, false) then now() else email_sent_at end,\n'
    || E'      email_error = case when coalesce((p->>''sent'')::boolean, false) then null else left(p->>''error'', 500) end\n'
    || E'    where id in (select x::uuid from jsonb_array_elements_text(p->''ids'') x);\n'
    || E'    return jsonb_build_object(''ok'', true);\n'
    || E'  elsif act = ''revoke_award'' then\n'
    || E'    select b.course_id into cid from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id where w.id = (p->>''id'')::uuid;\n'
    || E'    if cid is null or not public.mooc_can_manage(uid, cid) then return jsonb_build_object(''ok'', false, ''error'', ''Only the course admin or a super admin can do this.''); end if;\n'
    || E'    update public."Mooc_awards" set revoked = coalesce((p->>''revoked'')::boolean, true) where id = (p->>''id'')::uuid;\n'
    || E'    return jsonb_build_object(''ok'', true);\n'
    || old);
  execute def;
end $$;
