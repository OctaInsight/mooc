-- Emails are sent by MOOC Studio (Python, Resend settings in the Streamlit secrets), like the password reset
-- (applied 2026-11-22 as "mooc_mail_from_app"). The database only keeps the outbox.
--  * Removes the 5-minute database schedule and the pg_cron / pg_net extensions added for it.
--  * The outbox and the "forgot password" link are reached with the app's server key, exactly like
--    octa_user_reset_request: only an app holding the key (MOOC Studio) can read who is waiting for an email.

select cron.unschedule(jobid) from cron.job where jobname = 'mooc-mail-outbox';
drop extension if exists pg_cron;
drop extension if exists pg_net;

create or replace function public.mooc_mail_claim_app(p_server_key text, p_limit int default 40) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.octa_user_server_ok(p_server_key) then return jsonb_build_object('ok', false, 'error', 'not allowed'); end if;
  return jsonb_build_object('ok', true, 'people', public.mooc_mail_claim(p_limit));
end $$;

create or replace function public.mooc_mail_done_app(p_server_key text, p_ids uuid[], p_ok boolean,
                                                     p_error text default null, p_count boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.octa_user_server_ok(p_server_key) then return jsonb_build_object('ok', false, 'error', 'not allowed'); end if;
  return public.mooc_mail_done(p_ids, p_ok, p_error, p_count);
end $$;

-- How many award emails are waiting (and the last problem), for the Email section in Studio.
create or replace function public.mooc_mail_status(p_server_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.octa_user_server_ok(p_server_key) then return jsonb_build_object('ok', false, 'error', 'not allowed'); end if;
  return jsonb_build_object('ok', true,
    'pending', (select count(*) from public."Mooc_awards" where notify_state = 'pending' and not revoked),
    'failed', (select count(*) from public."Mooc_awards" where notify_state = 'failed'),
    'last_error', (select email_error from public."Mooc_awards" where notify_state in ('pending', 'failed')
                   and email_error is not null order by issued_at desc limit 1));
end $$;

create or replace function public.mooc_site_reset_app(p_server_key text, p_email text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.octa_user_server_ok(p_server_key) then return jsonb_build_object('ok', false, 'error', 'not allowed'); end if;
  return public.mooc_site_reset(p_email);
end $$;

grant execute on function public.mooc_mail_claim_app(text, int) to anon, authenticated;
grant execute on function public.mooc_mail_done_app(text, uuid[], boolean, text, boolean) to anon, authenticated;
grant execute on function public.mooc_mail_status(text) to anon, authenticated;
grant execute on function public.mooc_site_reset_app(text, text) to anon, authenticated;
