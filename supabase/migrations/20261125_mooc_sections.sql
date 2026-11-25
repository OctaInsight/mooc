-- Optional sections in a course: a course is still a series of lectures, but a teacher may group the lectures into
-- sections (for example "Part 1: Basics"). A course without sections works exactly as before.
--
-- * "Mooc_sections": the sections of a course, in order (position).
-- * "Mooc_lectures".section_id: the lecture's section, or null (no section). Deleting a section keeps its lectures.
-- * Lectures are returned in reading order: first the lectures without a section, then each section in turn, each
--   in its own lecture order. Courses without sections keep their order.
-- * mooc_manage gets the actions save_section, delete (what = section), reorder (what = section) and a section_id
--   on save_lecture. The existing function is renamed mooc_manage_base and kept unchanged; the new mooc_manage
--   handles the section actions and passes everything else on to it.

create table public."Mooc_sections" (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public."Mooc_courses"(id) on delete cascade,
  position int not null default 0,
  title text not null check (length(trim(title)) > 0),
  summary text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index "Mooc_sections_course_idx" on public."Mooc_sections" (course_id, position);
alter table public."Mooc_sections" enable row level security;
revoke all on public."Mooc_sections" from anon, authenticated;

alter table public."Mooc_lectures" add column section_id uuid references public."Mooc_sections"(id) on delete set null;
create index "Mooc_lectures_section_idx" on public."Mooc_lectures" (section_id);

-- ------------------------------------------------------------------------------------------------ course_of
create or replace function public.mooc_course_of(p_kind text, p_id uuid)
 returns uuid language sql stable security definer set search_path to ''
as $function$
  select case p_kind
    when 'lecture' then (select course_id from public."Mooc_lectures" where id = p_id)
    when 'section' then (select course_id from public."Mooc_sections" where id = p_id)
    when 'step' then (select l.course_id from public."Mooc_steps" s join public."Mooc_lectures" l on l.id = s.lecture_id where s.id = p_id)
    when 'question' then (select l.course_id from public."Mooc_questions" q join public."Mooc_steps" s on s.id = q.step_id
                          join public."Mooc_lectures" l on l.id = s.lecture_id where q.id = p_id)
    when 'badge' then (select course_id from public."Mooc_badges" where id = p_id)
    when 'submission' then (select l.course_id from public."Mooc_submissions" x join public."Mooc_steps" s on s.id = x.step_id
                            join public."Mooc_lectures" l on l.id = s.lecture_id where x.id = p_id)
  end
$function$;

-- ------------------------------------------------------------------------------------------------ course_full (Studio)
create or replace function public.mooc_course_full(p_course uuid)
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  select to_jsonb(c) || jsonb_build_object(
    'sections', coalesce((select jsonb_agg(to_jsonb(x) order by x.position, x.created_at)
                          from public."Mooc_sections" x where x.course_id = c.id), '[]'::jsonb),
    'lectures', coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object(
        'steps', coalesce((select jsonb_agg(to_jsonb(s) || jsonb_build_object(
            'questions', coalesce((select jsonb_agg(to_jsonb(q) order by coalesce(q.at_seconds, 0), coalesce(q.at_page, 0), q.position, q.created_at)
                                   from public."Mooc_questions" q where q.step_id = s.id), '[]'::jsonb))
          order by s.position, s.created_at) from public."Mooc_steps" s where s.lecture_id = l.id), '[]'::jsonb))
      order by coalesce(sec.position, -1), sec.created_at, l.position, l.created_at)
      from public."Mooc_lectures" l left join public."Mooc_sections" sec on sec.id = l.section_id
      where l.course_id = c.id), '[]'::jsonb),
    'badges', coalesce((select jsonb_agg(to_jsonb(b) || jsonb_build_object(
        'awarded', (select count(*) from public."Mooc_awards" w where w.badge_id = b.id and not w.revoked))
      order by b.kind, b.created_at) from public."Mooc_badges" b where b.course_id = c.id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(public.mooc_person(m.user_id) || jsonb_build_object('role', m.role, 'status', m.status, 'added_at', m.added_at)
      order by m.role, m.added_at) from public."Mooc_members" m where m.course_id = c.id and m.status = 'active'), '[]'::jsonb),
    'project', (select to_jsonb(p) from public."Mooc_projects" p where p.id = c.project_id))
  from public."Mooc_courses" c where c.id = p_course
$function$;

-- ------------------------------------------------------------------------------------------------ course_view (website)
create or replace function public.mooc_course_view(p_token text, p_slug text)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; c public."Mooc_courses"; role text; full_access boolean; staff boolean;
begin
  if coalesce(p_token, '') <> '' then uid := public.mooc_uid(p_token); end if;
  select * into c from public."Mooc_courses" where slug = lower(coalesce(p_slug, ''));
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'No course with this address.'); end if;
  role := case when uid is null then null else public.mooc_role(uid, c.id) end;
  staff := coalesce(role in ('super', 'admin', 'teacher'), false);
  if c.status <> 'published' and not staff then return jsonb_build_object('ok', false, 'error', 'This course is not open yet.'); end if;
  full_access := role is not null;
  return jsonb_build_object('ok', true, 'signed_in', uid is not null, 'role', role, 'enrolled', full_access,
    'course', jsonb_build_object('id', c.id, 'slug', c.slug, 'title', c.title, 'summary', c.summary, 'description', c.description,
       'outcomes', c.outcomes, 'image_url', c.image_url, 'level', c.level, 'language', c.language, 'hours', c.hours,
       'status', c.status, 'pass_score', c.pass_score, 'max_retakes', c.max_retakes,
       'project', (select jsonb_build_object('title', p.title, 'slug', p.slug) from public."Mooc_projects" p where p.id = c.project_id)),
    'sections', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'summary', x.summary) order by x.position, x.created_at)
                          from public."Mooc_sections" x where x.course_id = c.id), '[]'::jsonb),
    'lectures', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'title', l.title, 'summary', l.summary,
        'outcomes', l.outcomes, 'status', l.status, 'section_id', l.section_id,
        'retakes_used', (select coalesce(max(a.attempt), 0) from public."Mooc_attempts" a where a.lecture_id = l.id and a.user_id = uid),
        'best_scores', (select jsonb_object_agg(a.step_id, a.best) from (select step_id, max(score) best from public."Mooc_attempts" a2 where a2.lecture_id = l.id and a2.user_id = uid and score is not null group by step_id) a),
        'steps', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'kind', s.kind, 'title', s.title, 'required', s.required)
            || case when full_access then jsonb_build_object('config', s.config,
                 'questions', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'at_seconds', q.at_seconds, 'at_page', q.at_page,
                     'prompt', q.prompt, 'kind', q.kind, 'options', q.options, 'must_pass', q.must_pass)
                   order by coalesce(q.at_seconds, 0), coalesce(q.at_page, 0), q.position, q.created_at)
                   from public."Mooc_questions" q where q.step_id = s.id), '[]'::jsonb),
                 'progress', (select jsonb_build_object('completed', pr.completed_at is not null, 'score', pr.score, 'position', pr.position)
                              from public."Mooc_progress" pr where pr.step_id = s.id and pr.user_id = uid),
                 'answered', coalesce((select jsonb_agg(a.question_id) from public."Mooc_answers" a join public."Mooc_questions" q on q.id = a.question_id
                                       where q.step_id = s.id and a.user_id = uid and a.correct), '[]'::jsonb),
                 'submission', (select jsonb_build_object('submitted_at', x.submitted_at, 'score', x.score, 'feedback', x.feedback)
                                from public."Mooc_submissions" x where x.step_id = s.id and x.user_id = uid order by x.submitted_at desc limit 1))
               else '{}'::jsonb end
          order by s.position, s.created_at) from public."Mooc_steps" s where s.lecture_id = l.id), '[]'::jsonb))
      order by coalesce(sec.position, -1), sec.created_at, l.position, l.created_at)
      from public."Mooc_lectures" l left join public."Mooc_sections" sec on sec.id = l.section_id
      where l.course_id = c.id and (l.status = 'published' or staff)), '[]'::jsonb),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'kind', b.kind, 'title', b.title, 'description', b.description,
        'image_url', b.image_url, 'min_score', b.min_score, 'lecture_ids', b.lecture_ids,
        'award_id', (select w.id from public."Mooc_awards" w where w.badge_id = b.id and w.user_id = uid and not w.revoked))
      order by b.kind, b.created_at) from public."Mooc_badges" b where b.course_id = c.id and b.active), '[]'::jsonb));
end $function$;

-- ------------------------------------------------------------------------------------------------ my_learning: next step in reading order
create or replace function public.mooc_my_learning(p_token text)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid := public.mooc_uid(p_token);
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please sign in.'); end if;
  return jsonb_build_object('ok', true,
    'courses', coalesce((select jsonb_agg(x order by x->>'last_active' desc nulls last) from (
      select jsonb_build_object('id', c.id, 'slug', c.slug, 'title', c.title, 'summary', c.summary, 'image_url', c.image_url,
        'project', (select p.title from public."Mooc_projects" p where p.id = c.project_id),
        'steps', (select count(*) from public."Mooc_steps" s join public."Mooc_lectures" l on l.id = s.lecture_id
                  where l.course_id = c.id and l.status = 'published'),
        'done', (select count(*) from public."Mooc_progress" pr join public."Mooc_steps" s on s.id = pr.step_id
                 join public."Mooc_lectures" l on l.id = s.lecture_id
                 where l.course_id = c.id and l.status = 'published' and pr.user_id = uid and pr.completed_at is not null),
        'next_step', (select s.id from public."Mooc_steps" s join public."Mooc_lectures" l on l.id = s.lecture_id
                      left join public."Mooc_sections" sec on sec.id = l.section_id
                      where l.course_id = c.id and l.status = 'published'
                        and not exists (select 1 from public."Mooc_progress" pr where pr.step_id = s.id and pr.user_id = uid
                                        and pr.completed_at is not null)
                      order by coalesce(sec.position, -1), sec.created_at, l.position, l.created_at, s.position, s.created_at limit 1),
        'last_active', (select max(e.created_at) from public."Mooc_events" e where e.course_id = c.id and e.user_id = uid),
        'certificate', (select w.id from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id
                        where b.course_id = c.id and b.kind = 'certificate' and w.user_id = uid and not w.revoked limit 1)) x
      from public."Mooc_members" m join public."Mooc_courses" c on c.id = m.course_id
      where m.user_id = uid and m.role = 'student' and m.status = 'active' and (c.status = 'published' or (c.kind = 'event' and c.status <> 'archived'))) t), '[]'::jsonb),
    'awards', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'kind', b.kind, 'title', b.title, 'image_url', b.image_url,
        'issued_at', w.issued_at, 'course', c.title) order by w.issued_at desc)
      from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id join public."Mooc_courses" c on c.id = b.course_id
      where w.user_id = uid and not w.revoked), '[]'::jsonb));
end $function$;

-- ------------------------------------------------------------------------------------------------ manage: section actions
alter function public.mooc_manage(text, jsonb) rename to mooc_manage_base;
revoke execute on function public.mooc_manage_base(text, jsonb) from public, anon, authenticated;

create function public.mooc_manage(p_token text, p jsonb)
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
