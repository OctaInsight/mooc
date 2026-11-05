-- End-to-end test of the MOOC functions. Run AFTER the migration in the same transaction; it always ends with an
-- exception, so everything (migration, test accounts, data) is rolled back. "MOOC TEST PASSED" = success.
do $$
declare
  t_super text; t_admin text; t_teacher text; t_student text; t_other text;
  u_admin uuid; u_teacher uuid; u_student uuid; u_other uuid;
  r jsonb; pid uuid; cid uuid; l1 uuid; l2 uuid; s_video uuid; s_quiz uuid; s_asg uuid; s_pdf uuid;
  q_vid uuid; q1 uuid; q2 uuid; b_badge uuid; b_cert uuid; sub uuid; log text := '';
  procedure_ok boolean;
begin
  -- test accounts (one Octa admin = super admin)
  insert into public."User_accounts"(email, username, password_hash, role) values ('t.super@example.org', 'zz_t_super', 'x', 'admin');
  insert into public."User_accounts"(email, username, password_hash) values ('t.admin@example.org', 'zz_t_admin', 'x') returning id into u_admin;
  insert into public."User_accounts"(email, username, password_hash) values ('t.teacher@example.org', 'zz_t_teacher', 'x') returning id into u_teacher;
  insert into public."User_accounts"(email, username, password_hash) values ('t.student@example.org', 'zz_t_student', 'x') returning id into u_student;
  insert into public."User_accounts"(email, username, password_hash) values ('t.other@example.org', 'zz_t_other', 'x') returning id into u_other;
  t_super := public.octa_user_new_session((select id from public."User_accounts" where username = 'zz_t_super'), null);
  t_admin := public.octa_user_new_session(u_admin, null);
  t_teacher := public.octa_user_new_session(u_teacher, null);
  t_student := public.octa_user_new_session(u_student, null);
  t_other := public.octa_user_new_session(u_other, null);

  -- teacher registers: pending; student registers: active
  r := public.mooc_join(t_teacher, 'teacher'); assert r->'person'->>'status' = 'pending', 'teacher should be pending: ' || r::text;
  r := public.mooc_join(t_student, 'student'); assert r->'person'->>'status' = 'active', 'student active: ' || r::text;

  -- only the super admin creates projects and courses
  r := public.mooc_manage(t_admin, '{"action":"save_project","title":"X"}'::jsonb); assert not (r->>'ok')::boolean, 'non-super made project';
  r := public.mooc_manage(t_super, '{"action":"save_project","title":"BOOSTalent test","description":"AI and entrepreneurship"}'::jsonb);
  pid := (r->>'id')::uuid; assert pid is not null, 'project: ' || r::text;
  r := public.mooc_manage(t_teacher, '{"action":"save_course","title":"Nope"}'::jsonb); assert not (r->>'ok')::boolean, 'teacher made course';
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'save_course', 'title', 'Innovation & Entrepreneurship', 'project_id', pid,
        'outcomes', '["Explain the innovation process"]'::jsonb, 'pass_score', 60));
  cid := (r->>'id')::uuid; assert cid is not null, 'course: ' || r::text;
  assert (select slug from public."Mooc_courses" where id = cid) = 'innovation-entrepreneurship', 'slug';

  -- super names the course admin; the admin cannot name admins but adds a teacher (which approves the teacher)
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'set_member', 'course_id', cid, 'user', 'T.ADMIN@example.org', 'role', 'admin'));
  assert (r->>'ok')::boolean, 'set admin: ' || r::text;
  r := public.mooc_manage(t_admin, jsonb_build_object('action', 'set_member', 'course_id', cid, 'user', 'zz_t_other', 'role', 'admin'));
  assert not (r->>'ok')::boolean, 'admin named admin';
  r := public.mooc_manage(t_admin, '{"action":"people"}'::jsonb); assert jsonb_array_length(r->'people') >= 2, 'people: ' || r::text;
  r := public.mooc_manage(t_admin, jsonb_build_object('action', 'set_member', 'course_id', cid, 'user', 'zz_t_teacher', 'role', 'teacher'));
  assert (r->>'ok')::boolean, 'set teacher: ' || r::text;
  assert (select status from public."Mooc_people" where user_id = u_teacher) = 'active', 'teacher approved by role';
  r := public.mooc_manage(t_other, jsonb_build_object('action', 'course', 'course_id', cid)); assert not (r->>'ok')::boolean, 'stranger read course';

  -- teacher builds two lectures: video with an in-video question + PDF; quiz + assignment
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_lecture', 'course_id', cid, 'title', 'What is innovation?', 'status', 'published'));
  l1 := (r->>'id')::uuid;
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_lecture', 'course_id', cid, 'title', 'Business models', 'status', 'published'));
  l2 := (r->>'id')::uuid;
  s_video := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_step', 'lecture_id', l1, 'kind', 'video', 'title', 'Intro',
              'config', '{"youtube_id":"dQw4w9WgXcQ"}'::jsonb))->>'id')::uuid;
  q_vid := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_question', 'step_id', s_video, 'at_seconds', 30,
            'prompt', 'Innovation is...?', 'options', '["new value","old"]'::jsonb, 'correct', '["0"]'::jsonb))->>'id')::uuid;
  assert q_vid is not null, 'video question';
  s_pdf := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_step', 'lecture_id', l1, 'kind', 'pdf', 'title', 'Reading',
            'config', '{"url":"https://example.org/a.pdf"}'::jsonb))->>'id')::uuid;
  s_quiz := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_step', 'lecture_id', l2, 'kind', 'quiz', 'title', 'Check'))->>'id')::uuid;
  q1 := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_question', 'step_id', s_quiz, 'prompt', 'A?', 'options', '["a","b"]'::jsonb, 'correct', '["0"]'::jsonb))->>'id')::uuid;
  q2 := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_question', 'step_id', s_quiz, 'prompt', 'B?', 'kind', 'multiple',
         'options', '["a","b","c"]'::jsonb, 'correct', '["0","2"]'::jsonb))->>'id')::uuid;
  s_asg := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_step', 'lecture_id', l2, 'kind', 'assignment', 'title', 'Canvas',
            'config', '{"grading":"manual","instructions":"Fill a business model canvas"}'::jsonb))->>'id')::uuid;
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'reorder', 'what', 'lecture', 'ids', jsonb_build_array(l2, l1)));
  assert (select position from public."Mooc_lectures" where id = l2) < (select position from public."Mooc_lectures" where id = l1), 'reorder';

  -- badge after lecture 1; certificate for the whole course (min 50)
  b_badge := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_badge', 'course_id', cid, 'title', 'Innovation basics',
              'lecture_ids', jsonb_build_array(l1), 'min_score', 50))->>'id')::uuid;
  b_cert := (public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_badge', 'course_id', cid, 'kind', 'certificate',
             'title', 'Certificate in Innovation & Entrepreneurship', 'min_score', 50))->>'id')::uuid;
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'course', 'course_id', cid));
  assert jsonb_array_length(r->'course'->'lectures') = 2 and jsonb_array_length(r->'course'->'badges') = 2, 'course read: ' || r::text;

  -- the student cannot enrol in a draft course; the admin publishes it
  r := public.mooc_enrol(t_student, cid); assert not (r->>'ok')::boolean, 'enrolled in draft';
  r := public.mooc_manage(t_admin, jsonb_build_object('action', 'save_course', 'id', cid, 'status', 'published')); assert (r->>'ok')::boolean, 'publish: ' || r::text;
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_course', 'id', cid, 'status', 'archived')); assert not (r->>'ok')::boolean, 'teacher changed course';
  r := public.mooc_enrol(t_student, cid); assert (r->>'ok')::boolean, 'enrol: ' || r::text;

  -- video: cannot complete before the in-video question is answered correctly
  r := public.mooc_record(t_student, s_video, 'progressed', 31, '{}'); assert (r->>'ok')::boolean, 'progress: ' || r::text;
  r := public.mooc_record(t_student, s_video, 'completed', null, '{}'); assert not (r->>'ok')::boolean, 'completed without answer';
  r := public.mooc_answer(t_student, q_vid, '["1"]'::jsonb); assert not (r->>'correct')::boolean and r->>'explanation' is null, 'wrong answer: ' || r::text;
  r := public.mooc_answer(t_student, q_vid, '["0"]'::jsonb); assert (r->>'correct')::boolean, 'right answer: ' || r::text;
  r := public.mooc_record(t_student, s_video, 'completed', null, '{}'); assert (r->>'ok')::boolean, 'video done: ' || r::text;
  assert (select score from public."Mooc_progress" where user_id = u_student and step_id = s_video) = 0, 'first try was wrong -> 0';
  -- lecture 1 average is 0 -> no badge yet even after the PDF
  r := public.mooc_record(t_student, s_pdf, 'completed', null, '{}');
  assert jsonb_array_length(r->'awarded') = 0, 'badge given with low score: ' || r::text;
  -- the teacher lowers the badge rule; the next activity issues it
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'save_badge', 'id', b_badge, 'min_score', 0));
  r := public.mooc_record(t_student, s_pdf, 'completed', null, '{}');
  assert jsonb_array_length(r->'awarded') = 1 and r->'awarded'->0->>'kind' = 'badge', 'badge issued: ' || r::text;

  -- quiz: complete when all answered correctly; score = first-try correctness (q1 right, q2 wrong first) = 50
  r := public.mooc_answer(t_student, q1, '["0"]'::jsonb);
  r := public.mooc_answer(t_student, q2, '["0"]'::jsonb); assert not (r->>'correct')::boolean, 'partial multiple wrong';
  r := public.mooc_answer(t_student, q2, '["2","0"]'::jsonb); assert (r->>'correct')::boolean, 'multiple right in any order';
  assert (select score from public."Mooc_progress" where user_id = u_student and step_id = s_quiz) = 50, 'quiz score';
  r := public.mooc_record(t_student, s_quiz, 'completed', null, '{}'); assert not (r->>'ok')::boolean, 'quiz completed by record';

  -- assignment: submitted, graded 100 by the teacher -> course average of scored steps (video 0, quiz 50, assignment 100) = 50 >= 50 -> certificate
  r := public.mooc_submit(t_student, s_asg, 'My canvas', null); sub := (r->>'id')::uuid;
  assert jsonb_array_length(r->'awarded') = 0, 'manual assignment auto-awarded';
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'submissions', 'course_id', cid)); assert jsonb_array_length(r->'submissions') = 1, 'to grade';
  r := public.mooc_manage(t_other, jsonb_build_object('action', 'grade', 'submission_id', sub, 'score', 100)); assert not (r->>'ok')::boolean, 'stranger graded';
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'grade', 'submission_id', sub, 'score', 100, 'feedback', 'Great'));
  assert jsonb_array_length(r->'awarded') = 1 and r->'awarded'->0->>'kind' = 'certificate', 'certificate: ' || r::text;

  -- public pages
  r := public.mooc_profile('ZZ_T_STUDENT'); assert jsonb_array_length(r->'awards') = 2, 'profile: ' || r::text;
  assert (r->'courses'->0->>'done')::int = 4, 'profile progress: ' || r::text;
  r := public.mooc_award((select id from public."Mooc_awards" where badge_id = b_cert)); assert r->>'title' like 'Certificate%' and r->'project'->>'title' = 'BOOSTalent test', 'award page: ' || r::text;
  r := public.mooc_catalogue(); assert exists (select 1 from jsonb_array_elements(r->'courses') c where c->>'slug' = 'innovation-entrepreneurship'), 'catalogue';
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'students', 'course_id', cid)); assert jsonb_array_length(r->'students') = 1, 'students: ' || r::text;
  r := public.mooc_manage(t_super, '{"action":"overview"}'::jsonb); assert (r->>'ok')::boolean, 'overview';

  -- a badge with awards is deactivated, not deleted; uploads need a ticket
  r := public.mooc_manage(t_teacher, jsonb_build_object('action', 'delete', 'what', 'badge', 'id', b_badge));
  assert exists (select 1 from public."Mooc_badges" where id = b_badge and not active), 'badge kept';
  r := public.mooc_manage(t_student, '{"action":"upload_ticket"}'::jsonb); assert not (r->>'ok')::boolean, 'student ticket';
  r := public.mooc_manage(t_teacher, '{"action":"upload_ticket"}'::jsonb); assert public.mooc_upload_ok(r->>'ticket'), 'ticket works';
  assert not public.mooc_upload_ok('nonsense'), 'bad ticket';
  r := public.mooc_manage(t_super, jsonb_build_object('action', 'delete_course', 'id', cid)); assert not (r->>'ok')::boolean, 'deleted course with students';

  raise exception 'MOOC TEST PASSED (rolled back)';
end $$;
