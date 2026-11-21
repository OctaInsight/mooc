-- Bulk certificates. Ends with an exception: everything is rolled back.
do $$
declare t_super text; t_cadmin text; t_teacher text; u_known uuid; u_cadmin uuid; ev uuid; c2 uuid; cert uuid; badge uuid; r jsonb; a jsonb;
        ext uuid; n int;
begin
  insert into public."User_accounts"(email, username, password_hash, role) values ('b.super@example.org', 'zz_b_super', 'x', 'admin');
  insert into public."User_accounts"(email, username, password_hash) values ('b.cadmin@example.org', 'zz_b_cadmin', 'x') returning id into u_cadmin;
  insert into public."User_accounts"(email, username, password_hash) values ('b.teacher@example.org', 'zz_b_teacher', 'x');
  insert into public."User_accounts"(email, username, password_hash, first_name, last_name) values ('known@example.org', 'zz_b_known', 'x', 'Kim', 'Known') returning id into u_known;
  t_super := public.octa_user_new_session((select id from public."User_accounts" where username = 'zz_b_super'), null);
  t_cadmin := public.octa_user_new_session(u_cadmin, null);
  t_teacher := public.octa_user_new_session((select id from public."User_accounts" where username = 'zz_b_teacher'), null);

  -- a certificates-only event, published but not in the course list
  ev := (public.mooc_manage(t_super, '{"action":"save_course","title":"ZZ Workshop on AI 2026","kind":"event"}'::jsonb)->>'id')::uuid;
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'save_course', 'id', ev, 'status', 'published', 'title', 'ZZ Workshop on AI 2026'));
  assert (select kind from public."Mooc_courses" where id = ev) = 'event', 'kind';
  assert not exists (select 1 from jsonb_array_elements(public.mooc_catalogue()->'courses') x where (x->>'id')::uuid = ev), 'event listed';
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'set_member', 'course_id', ev, 'user', 'zz_b_cadmin', 'role', 'admin'));
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'set_member', 'course_id', ev, 'user', 'zz_b_teacher', 'role', 'teacher'));
  -- a course admin can now create a course and becomes its admin
  r := public.mooc_manage(t_cadmin, '{"action":"save_course","title":"ZZ Course by an admin"}'::jsonb);
  c2 := (r->>'id')::uuid; assert c2 is not null, 'cadmin create ' || r::text;
  assert (select role from public."Mooc_members" where course_id = c2 and user_id = u_cadmin) = 'admin', 'creator is admin';
  r := public.mooc_manage(t_teacher, '{"action":"save_course","title":"ZZ Nope"}'::jsonb); assert not (r->>'ok')::boolean, 'teacher created';

  cert := (public.mooc_manage(t_cadmin, jsonb_build_object('action', 'save_badge', 'course_id', ev, 'kind', 'certificate', 'title', 'Certificate of participation'))->>'id')::uuid;
  badge := (public.mooc_manage(t_cadmin, jsonb_build_object('action', 'save_badge', 'course_id', ev, 'title', 'AI workshop badge'))->>'id')::uuid;

  -- only the course admin or a super admin issues
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'bulk_award', 'badge_ids', jsonb_build_array(cert), 'rows', '[{"name":"A","email":"a@example.org"}]'::jsonb));
  assert not (r->>'ok')::boolean, 'teacher issued';

  r := public.mooc_manage(t_cadmin, jsonb_build_object('action', 'bulk_award', 'badge_ids', jsonb_build_array(cert, badge),
       'issued_at', '2026-10-15', 'default_contribution', 'Participant',
       'rows', '[{"name":"Ada Lovelace","email":"ADA@example.org","contribution":"Keynote speaker"},
                 {"name":"Ada again","email":"ada@example.org"},
                 {"name":"Kim Known","email":"Known@Example.org"},
                 {"name":"No email","email":"not-an-email"},
                 {"name":"","email":"noname@example.org"}]'::jsonb));
  assert (r->>'ok')::boolean, 'bulk ' || r::text;
  assert jsonb_array_length(r->'awards') = 4, 'two people x two awards: ' || r::text;
  assert (select count(*) from jsonb_array_elements(r->'awards') x where (x->>'new')::boolean) = 4, 'all new';
  select id into ext from public."Mooc_awards" where badge_id = cert and recipient_email = 'ada@example.org';
  assert (select contribution from public."Mooc_awards" where id = ext) = 'Keynote speaker', 'contribution kept';
  assert (select issued_at::date from public."Mooc_awards" where id = ext) = '2026-10-15', 'date';
  assert (select contribution from public."Mooc_awards" where badge_id = cert and recipient_email = 'known@example.org') = 'Participant', 'default contribution';
  assert (select user_id from public."Mooc_awards" where badge_id = cert and recipient_email = 'known@example.org') = u_known, 'linked to account';
  -- the same list again creates nothing new
  r := public.mooc_manage(t_cadmin, jsonb_build_object('action', 'bulk_award', 'badge_ids', jsonb_build_array(cert),
       'rows', '[{"name":"Ada Lovelace","email":"ada@example.org"}]'::jsonb));
  assert jsonb_array_length(r->'awards') = 1 and not (r->'awards'->0->>'new')::boolean and (r->'awards'->0->>'award_id')::uuid = ext, 'again ' || r::text;

  -- the public award page
  a := public.mooc_award(ext);
  assert a->'recipient'->>'first_name' = 'Ada Lovelace' and a->>'contribution' = 'Keynote speaker' and a->'course'->>'kind' = 'event', 'page ' || a::text;
  -- list, email status, withdraw
  r := public.mooc_manage(t_cadmin, jsonb_build_object('action', 'awards', 'course_id', ev));
  assert jsonb_array_length(r->'awards') = 4, 'list ' || r::text;
  r := public.mooc_manage(t_cadmin, jsonb_build_object('action', 'award_email', 'ids', jsonb_build_array(ext), 'sent', true));
  assert (select email_sent_at from public."Mooc_awards" where id = ext) is not null, 'emailed';
  r := public.mooc_manage(t_cadmin, jsonb_build_object('action', 'revoke_award', 'id', ext));
  assert (public.mooc_award(ext)->>'revoked')::boolean, 'withdrawn';
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'revoke_award', 'id', ext, 'revoked', false)); assert not (r->>'ok')::boolean, 'teacher withdrew';

  -- Ada registers later with the same email: both awards appear on her profile
  insert into public."User_accounts"(email, username, password_hash, first_name, last_name) values ('ada@example.org', 'zz_b_ada', 'x', 'Ada', 'L');
  insert into public."Mooc_people"(user_id, kind) select id, 'student' from public."User_accounts" where username = 'zz_b_ada';
  assert (select count(*) from public."Mooc_awards" w join public."User_accounts" u on u.id = w.user_id where u.username = 'zz_b_ada') = 2, 'linked on register';
  n := jsonb_array_length(public.mooc_profile('zz_b_ada')->'awards');
  assert n = 1, 'profile shows the valid award: ' || n;
  raise exception 'BULK AWARDS TEST PASSED (rolled back)';
end $$;
