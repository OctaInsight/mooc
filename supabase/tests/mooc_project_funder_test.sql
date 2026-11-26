-- Funder logo test. Ends with an exception: everything is rolled back.
do $$
declare sup text; stu text; pid uuid; r jsonb; c jsonb;
begin
  sup := public.octa_user_new_session((select id from public."User_accounts" where role = 'admin' limit 1), null);
  stu := public.octa_user_new_session((select id from public."User_accounts" where username = 'test'), null);
  select id into pid from public."Mooc_projects" where slug = 'seedplus';
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_project', 'id', pid, 'title', 'SEEDplus',
         'funder_logo_url', 'https://example.org/eu.png', 'funder_name', 'Funded by the European Union'));
  assert (r->>'ok')::boolean, 'save ' || r::text;
  c := public.mooc_catalogue();
  assert (select x->>'funder_logo_url' from jsonb_array_elements(c->'projects') x where x->>'id' = pid::text) = 'https://example.org/eu.png', 'catalogue';
  -- saving without the funder fields keeps them; an empty value clears
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_project', 'id', pid, 'title', 'SEEDplus'));
  assert (select funder_name from public."Mooc_projects" where id = pid) = 'Funded by the European Union', 'kept';
  r := public.mooc_manage(sup, jsonb_build_object('action', 'save_project', 'id', pid, 'title', 'SEEDplus', 'funder_logo_url', ''));
  assert (select funder_logo_url from public."Mooc_projects" where id = pid) is null, 'cleared';
  -- not a super admin: refused, nothing changes
  r := public.mooc_manage(stu, jsonb_build_object('action', 'save_project', 'id', pid, 'title', 'SEEDplus', 'funder_name', 'X'));
  assert not (r->>'ok')::boolean and (select funder_name from public."Mooc_projects" where id = pid) = 'Funded by the European Union', 'student refused';
  raise exception 'FUNDER TEST PASSED (rolled back)';
end $$;
