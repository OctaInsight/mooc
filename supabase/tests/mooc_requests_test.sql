-- Registration with a role. Ends with an exception: everything is rolled back.
do $$
declare t_super text; t_cadmin text; t_t text; t_s text; t_a text; u_t uuid; u_a uuid; u_cadmin uuid;
        c1 uuid; c2 uuid; r jsonb; req_t uuid; req_a uuid;
begin
  insert into public."User_accounts"(email, username, password_hash, role) values ('r.super@example.org', 'zz_r_super', 'x', 'admin');
  insert into public."User_accounts"(email, username, password_hash) values ('r.cadmin@example.org', 'zz_r_cadmin', 'x') returning id into u_cadmin;
  insert into public."User_accounts"(email, username, password_hash) values ('r.t@example.org', 'zz_r_t', 'x') returning id into u_t;
  insert into public."User_accounts"(email, username, password_hash) values ('r.a@example.org', 'zz_r_a', 'x') returning id into u_a;
  insert into public."User_accounts"(email, username, password_hash) values ('r.s@example.org', 'zz_r_s', 'x');
  t_super := public.octa_user_new_session((select id from public."User_accounts" where username = 'zz_r_super'), null);
  t_cadmin := public.octa_user_new_session(u_cadmin, null);
  t_t := public.octa_user_new_session(u_t, null);
  t_a := public.octa_user_new_session(u_a, null);
  t_s := public.octa_user_new_session((select id from public."User_accounts" where username = 'zz_r_s'), null);
  c1 := (public.mooc_manage(t_super, '{"action":"save_course","title":"ZZ Req course one"}'::jsonb)->>'id')::uuid;
  c2 := (public.mooc_manage(t_super, '{"action":"save_course","title":"ZZ Req course two"}'::jsonb)->>'id')::uuid;
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'set_member', 'course_id', c1, 'user', 'zz_r_cadmin', 'role', 'admin'));

  -- options list the courses; a student cannot join a draft course, then can after publishing
  r := public.mooc_join_options(t_s);
  assert exists (select 1 from jsonb_array_elements(r->'courses') x where (x->>'id')::uuid = c1), 'options ' || r::text;
  r := public.mooc_register(t_s, 'student', c1, null); assert not (r->>'ok')::boolean, 'student in draft';
  update public."Mooc_courses" set status = 'published' where id = c1;
  r := public.mooc_register(t_s, 'student', c1, null); assert r->>'status' = 'enrolled', 'student ' || r::text;
  assert (select role from public."Mooc_members" where course_id = c1 and user_id = (select id from public."User_accounts" where username = 'zz_r_s')) = 'student', 'enrolled row';

  -- teacher request for course one; asking twice keeps one request
  r := public.mooc_register(t_t, 'teacher', c1, 'I teach AI'); assert r->>'status' = 'requested', 'teacher req ' || r::text;
  r := public.mooc_register(t_t, 'teacher', c1, 'I teach AI, really'); req_t := (r->>'request_id')::uuid;
  assert (select count(*) from public."Mooc_requests" where user_id = u_t and status = 'pending') = 1, 'one pending';
  assert (select status from public."Mooc_people" where user_id = u_t) = 'pending', 'teacher pending';
  -- admin request for course one; course two request by the teacher too
  r := public.mooc_register(t_a, 'admin', c1, null); req_a := (r->>'request_id')::uuid;
  r := public.mooc_register(t_t, 'teacher', c2, null);

  -- the course admin of course one sees only the teacher request of course one
  r := public.mooc_manage(t_cadmin, '{"action":"requests"}'::jsonb);
  assert jsonb_array_length(r->'requests') = 1 and r->'requests'->0->>'role' = 'teacher', 'cadmin sees ' || r::text;
  r := public.mooc_manage(t_cadmin, '{"action":"overview"}'::jsonb); assert (r->>'pending_requests')::int = 1, 'count ' || r::text;
  r := public.mooc_manage(t_super, '{"action":"requests"}'::jsonb); assert jsonb_array_length(r->'requests') = 3, 'super sees all';
  -- the course admin cannot approve an admin request; a stranger cannot approve anything
  r := public.mooc_manage(t_cadmin, jsonb_build_object('action', 'decide_request', 'request_id', req_a, 'approve', true));
  assert not (r->>'ok')::boolean, 'cadmin approved admin';
  r := public.mooc_manage(t_s, jsonb_build_object('action', 'decide_request', 'request_id', req_t, 'approve', true));
  assert not (r->>'ok')::boolean, 'student approved';
  -- approvals
  r := public.mooc_manage(t_cadmin, jsonb_build_object('action', 'decide_request', 'request_id', req_t, 'approve', true));
  assert (r->>'ok')::boolean, 'approve teacher ' || r::text;
  assert (select role from public."Mooc_members" where course_id = c1 and user_id = u_t) = 'teacher', 'teacher member';
  assert (select status from public."Mooc_people" where user_id = u_t) = 'active', 'teacher active';
  r := public.mooc_manage(t_cadmin, jsonb_build_object('action', 'decide_request', 'request_id', req_t, 'approve', true));
  assert not (r->>'ok')::boolean, 'decided twice';
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'decide_request', 'request_id', req_a, 'approve', true));
  assert (select role from public."Mooc_members" where course_id = c1 and user_id = u_a) = 'admin', 'admin member';
  r := public.mooc_manage(t_a, jsonb_build_object('action', 'course', 'course_id', c1)); assert (r->>'my_role') = 'admin', 'new admin works';
  -- decline the course two request; the teacher sees the outcome
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'decide_request',
       'request_id', (select id from public."Mooc_requests" where user_id = u_t and course_id = c2), 'approve', false));
  r := public.mooc_join_options(t_t);
  assert exists (select 1 from jsonb_array_elements(r->'requests') x where x->>'status' = 'declined')
     and exists (select 1 from jsonb_array_elements(r->'requests') x where x->>'status' = 'approved'), 'my requests ' || r::text;
  -- already teacher: asking again needs no approval
  r := public.mooc_register(t_t, 'teacher', c1, null); assert r->>'status' = 'member', 'already ' || r::text;
  raise exception 'REQUESTS TEST PASSED (rolled back)';
end $$;
