-- What a student sees of a course (applied 2026-11-05 as "mooc_course_view").
-- Without a session, or when not enrolled: the course page (description, outcomes, lecture and step titles).
-- Enrolled students and the course team: the full published content, the student's own progress and awards.
-- Questions never include the right answers; answers are checked by mooc_answer. The team also sees draft lectures.
create or replace function public.mooc_course_view(p_token text, p_slug text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
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
       'status', c.status, 'pass_score', c.pass_score,
       'project', (select jsonb_build_object('title', p.title, 'slug', p.slug) from public."Mooc_projects" p where p.id = c.project_id)),
    'lectures', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'title', l.title, 'summary', l.summary,
        'outcomes', l.outcomes, 'status', l.status,
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
      order by l.position, l.created_at)
      from public."Mooc_lectures" l where l.course_id = c.id and (l.status = 'published' or staff)), '[]'::jsonb),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'kind', b.kind, 'title', b.title, 'description', b.description,
        'image_url', b.image_url, 'min_score', b.min_score,
        'award_id', (select w.id from public."Mooc_awards" w where w.badge_id = b.id and w.user_id = uid and not w.revoked))
      order by b.kind, b.created_at) from public."Mooc_badges" b where b.course_id = c.id and b.active), '[]'::jsonb));
end $$;

revoke execute on function public.mooc_course_view(text, text) from public;
grant execute on function public.mooc_course_view(text, text) to anon, authenticated;
