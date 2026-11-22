-- Award outbox, site password reset and MOOC access for listed people. Rolled back by the final exception.
do $$
declare t text; c uuid; b uuid; u uuid; w uuid; w2 uuid; r jsonb; n int;
begin
  insert into public."User_accounts"(email, username, password_hash, role) values ('n.super@example.org', 'zz_n_super', 'x', 'admin');
  insert into public."User_accounts"(email, username, password_hash, first_name, last_name) values ('n.stud@example.org', 'zz_n_stud', 'x', 'Sam', 'Student') returning id into u;
  t := public.octa_user_new_session((select id from public."User_accounts" where username = 'zz_n_super'), null);
  c := (public.mooc_manage(t, '{"action":"save_course","title":"ZZ Notify course"}'::jsonb)->>'id')::uuid;
  b := (public.mooc_manage(t, jsonb_build_object('action', 'save_badge', 'course_id', c, 'kind', 'certificate', 'title', 'ZZ cert'))->>'id')::uuid;

  -- an earned award goes to the outbox; a bulk one does not
  insert into public."Mooc_awards"(badge_id, user_id, score) values (b, u, 90) returning id into w;
  assert (select notify_state from public."Mooc_awards" where id = w) = 'pending', 'auto pending';
  r := public.mooc_manage(t, jsonb_build_object('action', 'bulk_award', 'badge_ids', jsonb_build_array(b), 'rows', '[{"name":"Lia","email":"zz_n_lia@example.org"}]'::jsonb));
  select id into w2 from public."Mooc_awards" where recipient_email = 'zz_n_lia@example.org';
  assert (select notify_state from public."Mooc_awards" where id = w2) is null, 'bulk not in outbox';

  r := public.mooc_mail_claim(200);
  select x into r from jsonb_array_elements(r) x where (x->>'user_id')::uuid = u;
  assert r->>'email' = 'n.stud@example.org' and r->>'name' = 'Sam Student' and r->'awards'->0->>'course' = 'ZZ Notify course', 'claim ' || r::text;
  -- claimed: a second run does not take it
  assert not exists (select 1 from jsonb_array_elements(public.mooc_mail_claim(200)) x where (x->>'user_id')::uuid = u), 'claimed twice';
  -- stopped at the daily limit: put back without counting
  r := public.mooc_mail_done(array[w], false, 'limit', false);
  assert (select notify_state || email_attempts from public."Mooc_awards" where id = w) = 'pending0', 'released';
  r := public.mooc_mail_claim(200);
  r := public.mooc_mail_done(array[w], true);
  assert (select notify_state from public."Mooc_awards" where id = w) = 'sent' and (select email_sent_at from public."Mooc_awards" where id = w) is not null, 'sent';

  -- five failures and it stops trying
  update public."Mooc_awards" set notify_state = 'pending' where id = w;
  for n in 1..5 loop perform public.mooc_mail_done(array[w], false, 'bounce'); end loop;
  assert (select notify_state from public."Mooc_awards" where id = w) = 'failed', 'failed';

  -- forgot password
  r := public.mooc_site_reset('N.Stud@example.org');
  assert (r->>'exists')::boolean and public.octa_user_reset_check(r->>'token')->>'username' = 'zz_n_stud', 'reset ' || r::text;
  assert not (public.mooc_site_reset('nobody-zz@example.org')->>'exists')::boolean, 'unknown';
  assert not has_function_privilege('anon', 'public.mooc_site_reset(text)', 'execute'), 'anon reset';
  assert not has_function_privilege('anon', 'public.mooc_mail_claim(int)', 'execute'), 'anon claim';

  -- listed people get MOOC access; a revoked access stays revoked
  insert into public."User_app_access"(user_id, app_id, status) values (u, 'octa_mooc', 'revoked');
  r := public.mooc_manage(t, jsonb_build_object('action', 'invite_students', 'course_id', c, 'rows',
       '[{"name":"Lia","email":"zz_n_lia@example.org"},{"name":"Sam","email":"n.stud@example.org"}]'::jsonb));
  assert (select a.status from public."User_app_access" a join public."User_accounts" x on x.id = a.user_id
          where x.email = 'zz_n_lia@example.org' and app_id = 'octa_mooc') = 'granted', 'granted';
  assert (select status from public."User_app_access" where user_id = u and app_id = 'octa_mooc') = 'revoked', 'kept revoked';
  raise exception 'NOTIFY TEST PASSED (rolled back)';
end $$;
