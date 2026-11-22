-- Award emails and password resets for the student website (applied 2026-11-22 as "mooc_notify").
--  * Every badge or certificate a student earns in a course goes into an email outbox (Mooc_awards.notify_state).
--    The Edge Function "mooc-mail" sends these emails (with links to view and share the award) every few minutes,
--    started by pg_cron. Awards issued from a list are emailed by MOOC Studio itself, so they are not in the outbox.
--  * "Forgot your password?" on the student website: the same function asks mooc_site_reset for a link and emails it.
--  * People on a certificate list are given access to the MOOC app in their Octa account (User_app_access).
-- The mailer functions can only be called with the service role key (inside the Edge Function), never from a page.

alter table public."Mooc_awards"
  add column if not exists notify_state text check (notify_state in ('pending', 'sent', 'failed')),
  add column if not exists email_attempts int not null default 0,
  add column if not exists email_claimed_at timestamptz;
create index if not exists "Mooc_awards_outbox" on public."Mooc_awards"(issued_at) where notify_state = 'pending';

create or replace function public.mooc_award_outbox() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(new.source, 'auto') = 'auto' and new.user_id is not null and not coalesce(new.revoked, false) then
    new.notify_state := 'pending';
  end if;
  return new;
end $$;
drop trigger if exists "Mooc_awards_outbox" on public."Mooc_awards";
create trigger "Mooc_awards_outbox" before insert on public."Mooc_awards"
  for each row execute function public.mooc_award_outbox();

-- Take up to p_limit people with awards waiting, grouped per person. A claimed award is left alone by other runs for
-- 15 minutes.
create or replace function public.mooc_mail_claim(p_limit int default 40) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ids uuid[]; out jsonb;
begin
  with people as (
    select w.user_id from public."Mooc_awards" w
    where w.notify_state = 'pending' and not w.revoked and w.user_id is not null
      and (w.email_claimed_at is null or w.email_claimed_at < now() - interval '15 minutes')
    group by w.user_id order by min(w.issued_at) limit greatest(1, least(coalesce(p_limit, 40), 200))
  )
  select array_agg(w.id) into ids from public."Mooc_awards" w join people p on p.user_id = w.user_id
  where w.notify_state = 'pending' and not w.revoked
    and (w.email_claimed_at is null or w.email_claimed_at < now() - interval '15 minutes');
  if ids is null then return '[]'::jsonb; end if;
  -- lock and claim (another run that got here first wins)
  perform 1 from public."Mooc_awards" where id = any(ids) for update skip locked;
  update public."Mooc_awards" set email_claimed_at = now() where id = any(ids);
  select coalesce(jsonb_agg(x order by x->>'email'), '[]'::jsonb) into out from (
    select jsonb_build_object('user_id', a.id, 'email', a.email, 'username', a.username,
             'name', nullif(trim(concat_ws(' ', a.first_name, a.last_name)), ''),
             'awards', jsonb_agg(jsonb_build_object('id', w.id, 'title', b.title, 'kind', b.kind,
                                 'course', c.title, 'course_kind', c.kind, 'score', w.score) order by w.issued_at)) x
    from public."Mooc_awards" w
    join public."User_accounts" a on a.id = w.user_id
    join public."Mooc_badges" b on b.id = w.badge_id
    join public."Mooc_courses" c on c.id = b.course_id
    where w.id = any(ids)
    group by a.id, a.email, a.username, a.first_name, a.last_name) t;
  return out;
end $$;

-- After sending: ok -> sent. Failed -> try again on a later run (up to 5 times), or with p_count = false (stopped at the
-- daily limit) just put back without counting a try.
create or replace function public.mooc_mail_done(p_ids uuid[], p_ok boolean, p_error text default null, p_count boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_ok then
    update public."Mooc_awards" set notify_state = 'sent', email_sent_at = now(), email_error = null, email_claimed_at = null
    where id = any(p_ids);
  else
    update public."Mooc_awards"
    set email_attempts = email_attempts + case when p_count then 1 else 0 end,
        notify_state = case when p_count and email_attempts + 1 >= 5 then 'failed' else 'pending' end,
        email_error = left(p_error, 300), email_claimed_at = null
    where id = any(p_ids);
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- "Forgot your password?" on the student website: a one-hour link, at most 5 requests per email per hour.
create or replace function public.mooc_site_reset(p_email text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare em text := lower(trim(coalesce(p_email, ''))); a public."User_accounts"; tok text;
begin
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then return jsonb_build_object('ok', false, 'error', 'Please enter a valid email address.'); end if;
  if (select count(*) from public."User_email_requests" where email = em and created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Too many requests for this email. Please try again in an hour.');
  end if;
  select * into a from public."User_accounts" where email = em;
  if a.id is null then
    insert into public."User_email_requests"(email, kind) values (em, 'not_registered');
    return jsonb_build_object('ok', true, 'exists', false);
  end if;
  insert into public."User_email_requests"(email, kind) values (em, 'reset');
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public."User_password_resets"(token_hash, user_id, expires_at, return_app)
  values (public.octa_user_hash(tok), a.id, now() + interval '1 hour', 'mooc_site');
  return jsonb_build_object('ok', true, 'exists', true, 'token', tok, 'username', a.username,
                            'name', nullif(trim(concat_ws(' ', a.first_name, a.last_name)), ''), 'email', a.email);
end $$;

revoke execute on function public.mooc_mail_claim(int) from public, anon, authenticated;
revoke execute on function public.mooc_mail_done(uuid[], boolean, text, boolean) from public, anon, authenticated;
revoke execute on function public.mooc_site_reset(text) from public, anon, authenticated;
grant execute on function public.mooc_mail_claim(int) to service_role;
grant execute on function public.mooc_mail_done(uuid[], boolean, text, boolean) to service_role;
grant execute on function public.mooc_site_reset(text) to service_role;
revoke execute on function public.mooc_award_outbox() from public, anon, authenticated;

-- People on a certificate list get access to the MOOC app in their Octa account (unless an admin took it away).
do $$ declare f oid; def text; old text; begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_invite';
  def := pg_get_functiondef(f);
  old := '    insert into public."Mooc_people"(user_id, kind) values (acc, ''student'') on conflict (user_id) do nothing;';
  if position(old in def) = 0 then raise exception 'mooc_invite: Mooc_people insert not found'; end if;
  def := replace(def, old,
       E'    insert into public."User_app_access"(user_id, app_id, status, updated_by) values (acc, ''octa_mooc'', ''granted'', p_uid)\n'
    || E'    on conflict (user_id, app_id) do update set status = ''granted'', updated_by = p_uid, updated_at = now()\n'
    || E'      where public."User_app_access".status = ''requested'';\n'
    || old);
  execute def;
end $$;
