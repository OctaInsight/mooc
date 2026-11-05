-- Retakes (applied 2026-11-05 as "mooc_retakes").
-- A student can redo a lecture (or the whole course): their answers and progress on it start again, so every
-- question is asked again. The scores of earlier tries are kept in Mooc_attempts and the best score of all tries
-- counts. Earned awards are never taken away. The course admin sets how many retakes a lecture allows (0 = no limit).

alter table public."Mooc_courses" add column if not exists max_retakes integer not null default 0
  check (max_retakes between 0 and 99);
comment on column public."Mooc_courses".max_retakes is 'How many times a student may redo each lecture (0 = no limit).';

create table if not exists public."Mooc_attempts" (
  id bigint generated always as identity primary key,
  user_id uuid not null references public."User_accounts"(id) on delete cascade,
  lecture_id uuid not null references public."Mooc_lectures"(id) on delete cascade,
  step_id uuid not null references public."Mooc_steps"(id) on delete cascade,
  attempt integer not null,
  score numeric(5,1),
  completed_at timestamptz,
  archived_at timestamptz not null default now()
);
create index if not exists "Mooc_attempts_user_step_idx" on public."Mooc_attempts" (user_id, step_id);
create index if not exists "Mooc_attempts_user_lecture_idx" on public."Mooc_attempts" (user_id, lecture_id);
comment on table public."Mooc_attempts" is 'Earlier tries of a lecture, saved when a student redoes it. The best score of all tries counts.';
alter table public."Mooc_attempts" enable row level security;
revoke all on public."Mooc_attempts" from anon, authenticated;

alter table public."Mooc_events" drop constraint if exists "Mooc_events_verb_check";
alter table public."Mooc_events" add constraint "Mooc_events_verb_check" check (verb in ('enrolled', 'opened', 'progressed',
  'answered', 'completed', 'submitted', 'graded', 'joined_live', 'awarded', 'retake'));

-- best score of all tries counts
create or replace function public.mooc_complete_step(p_user uuid, p_step uuid, p_score numeric) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare cid uuid := public.mooc_course_of('step', p_step); lid uuid; best numeric;
begin
  select lecture_id into lid from public."Mooc_steps" where id = p_step;
  select max(score) into best from public."Mooc_attempts" where user_id = p_user and step_id = p_step;
  insert into public."Mooc_progress"(user_id, step_id, completed_at, score)
  values (p_user, p_step, now(), case when p_score is null then best else greatest(p_score, best) end)
  on conflict (user_id, step_id) do update set
    completed_at = coalesce(public."Mooc_progress".completed_at, now()),
    score = case when excluded.score is null then public."Mooc_progress".score
                 when public."Mooc_progress".score is null then excluded.score
                 else greatest(public."Mooc_progress".score, excluded.score) end,
    updated_at = now();
  insert into public."Mooc_events"(user_id, course_id, lecture_id, step_id, verb, score)
  values (p_user, cid, lid, p_step, 'completed', p_score);
  return public.mooc_check_awards(p_user, cid);
end $$;
revoke execute on function public.mooc_complete_step(uuid, uuid, numeric) from public, anon, authenticated;

-- redo one lecture (p_lecture) or every published lecture of a course (p_course)
create or replace function public.mooc_retake(p_token text, p_lecture uuid, p_course uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := public.mooc_uid(p_token); cid uuid; lim int; lects uuid[]; l record; used int; done_any boolean := false;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'Please log in.'); end if;
  cid := coalesce(p_course, public.mooc_course_of('lecture', p_lecture));
  if cid is null or public.mooc_role(uid, cid) is null then return jsonb_build_object('ok', false, 'error', 'Enrol in the course first.'); end if;
  select max_retakes into lim from public."Mooc_courses" where id = cid;
  lects := case when p_lecture is not null then array[p_lecture]
                else array(select id from public."Mooc_lectures" where course_id = cid and status = 'published') end;
  -- check every lecture first, so nothing changes when one has no retakes left
  for l in select id, title from public."Mooc_lectures" where id = any(lects) and course_id = cid loop
    select coalesce(max(attempt), 0) into used from public."Mooc_attempts" where user_id = uid and lecture_id = l.id;
    if lim > 0 and used >= lim then
      return jsonb_build_object('ok', false, 'error', format('No retakes left for "%s" (%s allowed).', l.title, lim));
    end if;
  end loop;
  for l in select id from public."Mooc_lectures" where id = any(lects) and course_id = cid loop
    select coalesce(max(attempt), 0) into used from public."Mooc_attempts" where user_id = uid and lecture_id = l.id;
    if not exists (select 1 from public."Mooc_progress" p join public."Mooc_steps" s on s.id = p.step_id
                   where s.lecture_id = l.id and p.user_id = uid)
       and not exists (select 1 from public."Mooc_answers" a join public."Mooc_questions" q on q.id = a.question_id
                       join public."Mooc_steps" s on s.id = q.step_id where s.lecture_id = l.id and a.user_id = uid) then
      continue;                                   -- nothing done yet: nothing to redo
    end if;
    insert into public."Mooc_attempts"(user_id, lecture_id, step_id, attempt, score, completed_at)
    select uid, l.id, p.step_id, used + 1, p.score, p.completed_at
    from public."Mooc_progress" p join public."Mooc_steps" s on s.id = p.step_id where s.lecture_id = l.id and p.user_id = uid;
    delete from public."Mooc_progress" p using public."Mooc_steps" s where s.id = p.step_id and s.lecture_id = l.id and p.user_id = uid;
    delete from public."Mooc_answers" a using public."Mooc_questions" q, public."Mooc_steps" s
      where q.id = a.question_id and s.id = q.step_id and s.lecture_id = l.id and a.user_id = uid;
    insert into public."Mooc_events"(user_id, course_id, lecture_id, verb, data)
    values (uid, cid, l.id, 'retake', jsonb_build_object('attempt', used + 2));
    done_any := true;
  end loop;
  if not done_any then return jsonb_build_object('ok', false, 'error', 'There is nothing to redo yet.'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.mooc_retake(text, uuid, uuid) from public;
grant execute on function public.mooc_retake(text, uuid, uuid) to anon, authenticated;

-- the course admin sets the number of retakes; students see how many they have used
do $$ declare f oid; def text; old text; begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_manage';
  def := pg_get_functiondef(f);
  old := 'pass_score = coalesce((p->>''pass_score'')::int, pass_score),';
  if position(old in def) = 0 then raise exception 'mooc_manage: save_course not found'; end if;
  def := replace(def, old, old || ' max_retakes = coalesce((p->>''max_retakes'')::int, max_retakes),');
  execute def;

  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_course_view';
  def := pg_get_functiondef(f);
  old := '''status'', c.status, ''pass_score'', c.pass_score,';
  if position(old in def) = 0 then raise exception 'mooc_course_view: course fields not found'; end if;
  def := replace(def, old, old || ' ''max_retakes'', c.max_retakes,');
  old := '''outcomes'', l.outcomes, ''status'', l.status,';
  if position(old in def) = 0 then raise exception 'mooc_course_view: lecture fields not found'; end if;
  def := replace(def, old, old || E'\n        ''retakes_used'', (select coalesce(max(a.attempt), 0) from public."Mooc_attempts" a where a.lecture_id = l.id and a.user_id = uid),'
                               || E'\n        ''best_scores'', (select jsonb_object_agg(a.step_id, a.best) from (select step_id, max(score) best from public."Mooc_attempts" a2'
                               || E' where a2.lecture_id = l.id and a2.user_id = uid and score is not null group by step_id) a),');
  execute def;
end $$;
