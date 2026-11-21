-- People on a certificate list become students; new ones get an account and a set-password link.
-- Run after the migration text inside one transaction; ends with an exception so everything is rolled back.
do $$
declare t_super text; t_teacher text; ev uuid; r jsonb; p jsonb; tok text; u uuid; u_known uuid; tok2 text;
begin
  insert into public."User_accounts"(email, username, password_hash, role) values ('i.super@example.org', 'zz_i_super', 'x', 'admin');
  insert into public."User_accounts"(email, username, password_hash) values ('i.teacher@example.org', 'zz_i_teacher', 'x');
  insert into public."User_accounts"(email, username, password_hash, first_name) values ('i.known@example.org', 'zz_i_known', 'x', 'Kim') returning id into u_known;
  insert into public."User_accounts"(email, username, password_hash) values ('other@example.net', 'zz_ada', 'x');  -- takes the username "zz_ada"
  t_super := public.octa_user_new_session((select id from public."User_accounts" where username = 'zz_i_super'), null);
  t_teacher := public.octa_user_new_session((select id from public."User_accounts" where username = 'zz_i_teacher'), null);
  ev := (public.mooc_manage(t_super, '{"action":"save_course","title":"ZZ Invite workshop","kind":"event"}'::jsonb)->>'id')::uuid;
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'set_member', 'course_id', ev, 'user', 'zz_i_teacher', 'role', 'teacher'));

  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'invite_students', 'course_id', ev, 'rows', '[{"name":"A","email":"a@example.org"}]'::jsonb));
  assert not (r->>'ok')::boolean, 'teacher invited';

  r := public.mooc_manage(t_super, jsonb_build_object('action', 'invite_students', 'course_id', ev, 'rows',
       '[{"name":"Ada Lovelace","first_name":"Ada","last_name":"Lovelace","email":"ZZ_Ada@Example.org"},
         {"name":"Kim Known","email":"i.known@example.org"},
         {"name":"Grace Brewster Hopper","email":"gh@example.org"},
         {"name":"Bad","email":"nope"}]'::jsonb));
  assert (r->>'ok')::boolean and jsonb_array_length(r->'people') = 3, 'invite ' || r::text;
  select x into p from jsonb_array_elements(r->'people') x where x->>'email' = 'zz_ada@example.org';
  assert (p->>'created')::boolean and p->>'username' = 'zz_ada2' and p->>'set_password_token' is not null, 'new ' || p::text;
  tok := p->>'set_password_token';
  select id into u from public."User_accounts" where email = 'zz_ada@example.org';
  assert (select first_name || ' ' || last_name from public."User_accounts" where id = u) = 'Ada Lovelace', 'names';
  assert (select first_name || '|' || last_name from public."User_accounts" where email = 'gh@example.org') = 'Grace Brewster|Hopper', 'split name';
  select x into p from jsonb_array_elements(r->'people') x where x->>'email' = 'i.known@example.org';
  assert not (p->>'created')::boolean and p->>'set_password_token' is null, 'existing account gets no link ' || p::text;
  assert (select role from public."Mooc_members" where course_id = ev and user_id = u_known) = 'student', 'known enrolled';
  assert (select role from public."Mooc_members" where course_id = ev and user_id = u) = 'student', 'new enrolled';
  assert (select kind from public."Mooc_people" where user_id = u) = 'student', 'student person';
  -- the random password does not log in
  assert not (public.octa_user_login('zz_ada2', 'anything-at-all', null)->>'ok')::boolean, 'random password';

  -- sending again gives a fresh link while the password is still unset; the course teacher keeps no rights to it
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'invite_students', 'course_id', ev, 'rows', '[{"name":"Ada","email":"zz_ada@example.org"}]'::jsonb));
  tok2 := r->'people'->0->>'set_password_token';
  assert tok2 is not null and tok2 <> tok and not (r->'people'->0->>'created')::boolean, 'again ' || r::text;

  -- Ada opens the link, sets her password and signs in
  assert (public.octa_user_reset_check(tok)->>'username') = 'zz_ada2', 'check';
  r := public.octa_user_reset_complete(tok, 'a-good-password', '');
  assert (r->>'ok')::boolean, 'complete ' || r::text;
  assert (public.octa_user_login('zz_ada@example.org', 'a-good-password', null)->>'ok')::boolean, 'login';
  -- once she has her own password, no new links are handed out for her account
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'invite_students', 'course_id', ev, 'rows', '[{"name":"Ada","email":"zz_ada@example.org"}]'::jsonb));
  assert r->'people'->0->>'set_password_token' is null, 'no link after set ' || r::text;
  assert not (public.octa_user_reset_check(tok2)->>'ok')::boolean, 'older link used up';
  raise exception 'INVITE TEST PASSED (rolled back)';
end $$;
