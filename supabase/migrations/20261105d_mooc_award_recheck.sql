-- Applied 2026-11-05 as "mooc_award_recheck".
-- 1. Saving a badge or certificate checks every student of the course against the (new) rule at once, so a lowered
--    minimum score or a new badge is awarded immediately to students who already meet it.
-- 2. mooc_course_view also returns each badge's lectures, so the student page can show what is still needed.
do $$ declare f oid; def text; old text; begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'mooc_manage';
  def := pg_get_functiondef(f);
  old := E'    return jsonb_build_object(''ok'', true, ''id'', rid);\n  elsif act = ''grade'' then';
  if position(old in def) = 0 then raise exception 'mooc_manage: save_badge end not found'; end if;
  def := replace(def, old,
    E'    select coalesce(jsonb_agg(t.x), ''[]''::jsonb) into r from (select public.mooc_check_awards(m.user_id, cid) x\n'
    || E'      from public."Mooc_members" m where m.course_id = cid and m.role = ''student'' and m.status = ''active'') t\n'
    || E'      where jsonb_array_length(t.x) > 0;\n'
    || E'    return jsonb_build_object(''ok'', true, ''id'', rid, ''students_awarded'', jsonb_array_length(r));\n'
    || E'  elsif act = ''grade'' then');
  execute def;

  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'mooc_course_view';
  def := pg_get_functiondef(f);
  old := '''image_url'', b.image_url, ''min_score'', b.min_score,';
  if position(old in def) = 0 then raise exception 'mooc_course_view: badge fields not found'; end if;
  def := replace(def, old, '''image_url'', b.image_url, ''min_score'', b.min_score, ''lecture_ids'', b.lecture_ids,');
  execute def;
end $$;
