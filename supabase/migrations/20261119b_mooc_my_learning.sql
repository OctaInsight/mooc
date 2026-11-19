-- "My learning" for the student website (applied 2026-11-19 as "mooc_my_learning"): the signed-in user's courses as a
-- student with progress and the next step to continue with, and their awards.
create or replace function public.mooc_my_learning(p_token text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
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
                      where l.course_id = c.id and l.status = 'published'
                        and not exists (select 1 from public."Mooc_progress" pr where pr.step_id = s.id and pr.user_id = uid
                                        and pr.completed_at is not null)
                      order by l.position, l.created_at, s.position, s.created_at limit 1),
        'last_active', (select max(e.created_at) from public."Mooc_events" e where e.course_id = c.id and e.user_id = uid),
        'certificate', (select w.id from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id
                        where b.course_id = c.id and b.kind = 'certificate' and w.user_id = uid and not w.revoked limit 1)) x
      from public."Mooc_members" m join public."Mooc_courses" c on c.id = m.course_id
      where m.user_id = uid and m.role = 'student' and m.status = 'active' and c.status = 'published') t), '[]'::jsonb),
    'awards', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'kind', b.kind, 'title', b.title, 'image_url', b.image_url,
        'issued_at', w.issued_at, 'course', c.title) order by w.issued_at desc)
      from public."Mooc_awards" w join public."Mooc_badges" b on b.id = w.badge_id join public."Mooc_courses" c on c.id = b.course_id
      where w.user_id = uid and not w.revoked), '[]'::jsonb));
end $$;
revoke execute on function public.mooc_my_learning(text) from public;
grant execute on function public.mooc_my_learning(text) to anon, authenticated;
