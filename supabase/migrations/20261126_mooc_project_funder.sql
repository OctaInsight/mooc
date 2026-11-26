-- A funder logo for each project, shown next to the project logo in the course catalogue.
-- "Mooc_projects".funder_logo_url: the image (for example the EU emblem with "Funded by the European Union");
-- "Mooc_projects".funder_name: who funds the project, used as the image's text for screen readers.
-- mooc_catalogue already returns every project column, so the website gets them without other changes.

alter table public."Mooc_projects" add column funder_logo_url text, add column funder_name text;

create or replace function public.mooc_manage(p_token text, p jsonb)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  uid uuid := public.mooc_uid(p_token);
  act text := p->>'action';
  cid uuid; rid uuid; sid uuid; r jsonb;
begin
  if act = 'save_section' then
    if uid is null then return jsonb_build_object('ok', false, 'error', 'Your session has ended. Please log in again.'); end if;
    rid := nullif(p->>'id', '')::uuid;
    cid := coalesce(public.mooc_course_of('section', rid), nullif(p->>'course_id', '')::uuid);
    if cid is null or not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    if length(trim(coalesce(p->>'title', ''))) = 0 then return jsonb_build_object('ok', false, 'error', 'Give the section a title.'); end if;
    if rid is null then
      insert into public."Mooc_sections"(course_id, position, title, summary, created_by)
      values (cid, coalesce((p->>'position')::int, (select coalesce(max(position), 0) + 10 from public."Mooc_sections" where course_id = cid)),
              trim(p->>'title'), nullif(trim(coalesce(p->>'summary', '')), ''), uid)
      returning id into rid;
    else
      update public."Mooc_sections" set title = trim(p->>'title'),
        summary = case when p ? 'summary' then nullif(trim(coalesce(p->>'summary', '')), '') else summary end, updated_at = now()
      where id = rid;
    end if;
    return jsonb_build_object('ok', true, 'id', rid);

  elsif act = 'delete' and p->>'what' = 'section' then
    if uid is null then return jsonb_build_object('ok', false, 'error', 'Your session has ended. Please log in again.'); end if;
    rid := nullif(p->>'id', '')::uuid;
    cid := public.mooc_course_of('section', rid);
    if cid is null or not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    delete from public."Mooc_sections" where id = rid;          -- its lectures stay, without a section
    return jsonb_build_object('ok', true);

  elsif act = 'reorder' and p->>'what' = 'section' then
    if uid is null then return jsonb_build_object('ok', false, 'error', 'Your session has ended. Please log in again.'); end if;
    if jsonb_array_length(coalesce(p->'ids', '[]'::jsonb)) = 0 then return jsonb_build_object('ok', true); end if;
    cid := public.mooc_course_of('section', (p->'ids'->>0)::uuid);
    if cid is null or not public.mooc_can_edit(uid, cid) then return jsonb_build_object('ok', false, 'error', 'You do not teach this course.'); end if;
    update public."Mooc_sections" x set position = o.n * 10 from jsonb_array_elements_text(p->'ids') with ordinality o(id, n)
    where x.id = o.id::uuid and x.course_id = cid;
    return jsonb_build_object('ok', true);
  end if;

  -- everything else as before
  if act = 'save_lecture' and p ? 'section_id' then
    sid := nullif(p->>'section_id', '')::uuid;
    cid := coalesce(public.mooc_course_of('lecture', nullif(p->>'id', '')::uuid), nullif(p->>'course_id', '')::uuid);
    if sid is not null and public.mooc_course_of('section', sid) is distinct from cid then
      return jsonb_build_object('ok', false, 'error', 'This section belongs to another course.');
    end if;
  end if;
  r := public.mooc_manage_base(p_token, p);
  -- funder logo of a project (super admins only; the base function has checked that)
  if act = 'save_project' and coalesce((r->>'ok')::boolean, false) and (p ? 'funder_logo_url' or p ? 'funder_name') then
    update public."Mooc_projects" set
      funder_logo_url = case when p ? 'funder_logo_url' then nullif(trim(coalesce(p->>'funder_logo_url', '')), '') else funder_logo_url end,
      funder_name = case when p ? 'funder_name' then nullif(trim(coalesce(p->>'funder_name', '')), '') else funder_name end
    where id = (r->>'id')::uuid;
  end if;
  if act = 'save_lecture' and p ? 'section_id' and coalesce((r->>'ok')::boolean, false) then
    rid := (r->>'id')::uuid;
    -- a lecture that moves to another section goes to the end of that section
    update public."Mooc_lectures" set section_id = sid,
      position = (select coalesce(max(position), 0) + 10 from public."Mooc_lectures"
                  where course_id = cid and section_id is not distinct from sid and id <> rid)
    where id = rid and section_id is distinct from sid;
  end if;
  return r;
end $function$;
grant execute on function public.mooc_manage(text, jsonb) to anon, authenticated, service_role;
