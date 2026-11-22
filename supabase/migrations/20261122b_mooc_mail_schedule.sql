-- Run the award-email outbox every 5 minutes (applied 2026-11-22 as "mooc_mail_schedule").
-- The Edge Function "mooc-mail" is only called when an award is waiting, so quiet periods cost nothing.
create extension if not exists pg_net;
create extension if not exists pg_cron;

select cron.unschedule(jobid) from cron.job where jobname = 'mooc-mail-outbox';
select cron.schedule('mooc-mail-outbox', '*/5 * * * *', $job$
  select net.http_post(
    url := 'https://uxqeukvmnfvpgsxktgvo.supabase.co/functions/v1/mooc-mail',
    body := '{"action":"outbox"}'::jsonb,
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 60000)
  where exists (select 1 from public."Mooc_awards" where notify_state = 'pending' and not revoked
                  and (email_claimed_at is null or email_claimed_at < now() - interval '15 minutes'));
$job$);
