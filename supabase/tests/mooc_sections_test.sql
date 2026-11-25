-- Sections test on the "test" course. Ends with an exception: everything is rolled back.
do $$
declare sup text; stu text; cid uuid; s1 uuid; s2 uuid; l1 uuid; l2 uuid; l3 uuid; v jsonb; r jsonb; ids uuid[]; other uuid;
begin
  sup := public.octa_user_new_session((select id from public."User_accounts" where role = 'admin' limit 1), null);
  stu := public.octa_user_new_session((select id from public."User_accounts" where username = 'test'), null);
  select id into cid from public."Mooc_courses" where slug = 'test';
  update public."Mooc_courses" set status = 'published' where id = cid;     -- the test course is archived

  -- courses without sections: same lectures, same order as before
  v := public.mooc_course_view(stu, 'test');
  assert jsonb_array_length(v->'sections') = 0, 'no sections yet';
  ids := array(select (x->>'id')::uuid from jsonb_array_elements(v->'lectures') x);
  assert ids = array(select id from public."Mooc_lectures" where course_id = cid and status = 'published' order by position, created_at),
    'plain order kept';

  -- two sections and three new lectures
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_section', 'course_id', cid, 'title', 'Part A'));
  assert (r->>'ok')::boolean, 'section A ' || r::text; s1 := (r->>'id')::uuid;
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_section', 'course_id', cid, 'title', 'Part B', 'summary', 'Second'));
  s2 := (r->>'id')::uuid;
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_section', 'course_id', cid, 'title', '  '));
  assert not (r->>'ok')::boolean, 'empty title refused';
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_lecture', 'course_id', cid, 'title', 'B1', 'status', 'published', 'section_id', s2));
  assert (r->>'ok')::boolean, 'lecture in B ' || r::text; l1 := (r->>'id')::uuid;
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_lecture', 'course_id', cid, 'title', 'A1', 'status', 'published', 'section_id', s1));
  l2 := (r->>'id')::uuid;
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_lecture', 'course_id', cid, 'title', 'A2', 'status', 'published', 'section_id', s1));
  l3 := (r->>'id')::uuid;

  -- reading order: lectures without a section, then A1, A2, then B1
  v := public.mooc_course_view(stu, 'test');
  ids := array(select (x->>'id')::uuid from jsonb_array_elements(v->'lectures') x);
  assert ids[array_length(ids, 1) - 2:] = array[l2, l3, l1], 'section order ' || v->'lectures'::text;
  assert jsonb_array_length(v->'sections') = 2 and v->'sections'->1->>'summary' = 'Second', 'sections listed';
  assert (select x->>'section_id' from jsonb_array_elements(v->'lectures') x where x->>'id' = l1::text) = s2::text, 'section_id shown';
  assert jsonb_array_length(public.mooc_course_full(cid)->'sections') = 2, 'studio sees sections';

  -- move B before A
  r := public.mooc_manage(sup, jsonb_build_object('action', 'reorder', 'what', 'section', 'ids', jsonb_build_array(s2, s1)));
  assert (r->>'ok')::boolean, 'reorder ' || r::text;
  ids := array(select (x->>'id')::uuid from jsonb_array_elements(public.mooc_course_view(stu, 'test')->'lectures') x);
  assert ids[array_length(ids, 1) - 2:] = array[l1, l2, l3], 'B first now';

  -- move A2 into B: it goes to the end of B
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_lecture', 'id', l3, 'section_id', s2));
  assert (r->>'ok')::boolean, 'move ' || r::text;
  ids := array(select (x->>'id')::uuid from jsonb_array_elements(public.mooc_course_view(stu, 'test')->'lectures') x);
  assert ids[array_length(ids, 1) - 2:] = array[l1, l3, l2], 'A2 at the end of B';
  -- saving a lecture without section_id leaves its section alone
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_lecture', 'id', l3, 'title', 'A2 renamed'));
  assert (select section_id from public."Mooc_lectures" where id = l3) = s2, 'section kept';

  -- a section of another course is refused
  select id into other from public."Mooc_courses" where id <> cid limit 1;
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_lecture', 'course_id', other, 'title', 'X', 'section_id', s1));
  assert not (r->>'ok')::boolean, 'foreign section refused ' || r::text;

  -- a student cannot manage sections
  r := public.mooc_manage(stu, jsonb_build_object('action', 'save_section', 'course_id', cid, 'title', 'Nope'));
  assert not (r->>'ok')::boolean, 'student refused';

  -- deleting a section keeps its lectures, without a section
  r := public.mooc_manage(sup, jsonb_build_object('action', 'delete', 'what', 'section', 'id', s2));
  assert (r->>'ok')::boolean, 'delete ' || r::text;
  assert (select count(*) from public."Mooc_lectures" where id in (l1, l3) and section_id is null) = 2, 'lectures kept';

  -- old actions still go through
  r := public.mooc_manage(sup, jsonb_build_object('action', 'course', 'course_id', cid));
  assert (r->>'ok')::boolean and jsonb_array_length(r->'course'->'sections') = 1, 'course action ' || left(r::text, 200);
  r := public.mooc_my_learning(stu); assert (r->>'ok')::boolean, 'my learning';

  raise exception 'SECTIONS TEST PASSED (rolled back)';
end $$;
