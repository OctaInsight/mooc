-- Retake test on the "test" course and its "test" student. Ends with an exception: everything is rolled back.
do $$
declare stu text; sup text; v jsonb; r jsonb; lid uuid; cid uuid; s1 uuid; q record; before_score numeric;
begin
  stu := public.octa_user_new_session((select id from public."User_accounts" where username = 'test'), null);
  sup := public.octa_user_new_session((select id from public."User_accounts" where role = 'admin' limit 1), null);
  select id into cid from public."Mooc_courses" where slug = 'test';
  v := public.mooc_course_view(stu, 'test');
  lid := (v->'lectures'->0->>'id')::uuid;
  s1 := (v->'lectures'->0->'steps'->0->>'id')::uuid;
  before_score := (v->'lectures'->0->'steps'->0->'progress'->>'score')::numeric;
  assert (v->'lectures'->0->'steps'->0->'progress'->>'completed')::boolean, 'step 1 was done before: ' || v::text;

  -- limit 1 retake per lecture
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_course', 'id', cid, 'max_retakes', 1, 'status', 'published',
       'title', 'test', 'summary', '', 'description', '', 'language', 'English', 'level', '', 'hours', ''));
  assert (r->>'ok')::boolean, 'set max_retakes ' || r::text;

  r := public.mooc_retake(stu, lid, null); assert (r->>'ok')::boolean, 'retake ' || r::text;
  v := public.mooc_course_view(stu, 'test');
  assert v->'lectures'->0->'steps'->0->'progress' = 'null'::jsonb, 'progress cleared ' || (v->'lectures'->0->'steps'->0)::text;
  assert jsonb_array_length(v->'lectures'->0->'steps'->0->'answered') = 0, 'answers cleared';
  assert (v->'lectures'->0->>'retakes_used')::int = 1 and (v->'course'->>'max_retakes')::int = 1, 'retakes shown ' || v::text;
  assert (v->'lectures'->0->'best_scores'->>s1::text)::numeric = before_score, 'best kept ' || (v->'lectures'->0)::text;

  -- the step cannot be completed until its questions are answered again
  r := public.mooc_record(stu, s1, 'completed', null, '{}');
  assert not (r->>'ok')::boolean or not exists (select 1 from public."Mooc_questions" where step_id = s1), 'needs answers again';
  -- answer every question right on the first try now -> 100, which beats the old score
  for q in select id, correct from public."Mooc_questions" where step_id = s1 loop
    r := public.mooc_answer(stu, q.id, q.correct); assert (r->>'correct')::boolean, 'answer ' || r::text;
  end loop;
  r := public.mooc_record(stu, s1, 'completed', null, '{}'); assert (r->>'ok')::boolean, 'completed ' || r::text;
  assert (select score from public."Mooc_progress" p join public."User_accounts" a on a.id = p.user_id
          where a.username = 'test' and p.step_id = s1) = 100, 'new best score';

  -- a second retake is refused (limit 1); with no limit it works, and a worse try keeps the best score
  r := public.mooc_retake(stu, lid, null); assert not (r->>'ok')::boolean and r->>'error' like 'No retakes left%', 'limit ' || r::text;
  update public."Mooc_courses" set max_retakes = 0 where id = cid;
  r := public.mooc_retake(stu, null, cid); assert (r->>'ok')::boolean, 'course retake ' || r::text;
  for q in select id, correct, options from public."Mooc_questions" where step_id = s1 loop
    r := public.mooc_answer(stu, q.id, '["99"]'::jsonb);       -- wrong first
    r := public.mooc_answer(stu, q.id, q.correct);
  end loop;
  r := public.mooc_record(stu, s1, 'completed', null, '{}');
  assert (select score from public."Mooc_progress" p join public."User_accounts" a on a.id = p.user_id
          where a.username = 'test' and p.step_id = s1) = 100, 'worse try keeps best';
  raise exception 'RETAKE TEST PASSED (rolled back)';
end $$;
