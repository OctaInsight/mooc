-- Certificates on the course's own design (applied 2026-11-22 as "mooc_certificate_template").
-- Mooc_badges.template: null = the standard CloudEARTHi design; otherwise the uploaded design (PNG, or a PDF turned
-- into PNG by MOOC Studio) and where each piece of text goes:
--   {"image_url": "...png", "width": 3508, "height": 2480,
--    "fields": [{"key": "name", "x": 0.5, "y": 0.45, "size": 0.045, "color": "#0b0b0b", "align": "center",
--                "font": "serif", "bold": false, "italic": true}, ...]}
-- x and y are fractions of the width and height (the middle of the text), size a fraction of the width.
-- Field keys: name, contribution, course, title, date, verify.
alter table public."Mooc_badges" add column if not exists template jsonb
  check (template is null or (jsonb_typeof(template) = 'object' and (template->>'image_url') ~ '^https://'
                              and jsonb_typeof(template->'fields') = 'array' and octet_length(template::text) < 20000));

do $$ declare f oid; def text; n int; begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_manage';
  def := pg_get_functiondef(f);
  -- new badge
  if position('insert into public."Mooc_badges"(course_id, kind, title, description, image_url, lecture_ids, min_score, active, created_by)' in def) = 0
    then raise exception 'save_badge insert not found'; end if;
  def := replace(def, 'insert into public."Mooc_badges"(course_id, kind, title, description, image_url, lecture_ids, min_score, active, created_by)',
                      'insert into public."Mooc_badges"(course_id, kind, title, description, image_url, lecture_ids, min_score, active, created_by, template)');
  if position('coalesce((p->>''active'')::boolean, true), uid)' in def) = 0 then raise exception 'save_badge values not found'; end if;
  def := replace(def, 'coalesce((p->>''active'')::boolean, true), uid)',
                      'coalesce((p->>''active'')::boolean, true), uid, case when jsonb_typeof(p->''template'') = ''object'' then p->''template'' end)');
  -- edited badge: "template": null switches back to the standard design; leaving it out keeps the current one
  if position('active = coalesce((p->>''active'')::boolean, active)' || E'\n' || '      where id = rid;' in def) = 0
    then raise exception 'save_badge update not found'; end if;
  def := replace(def, 'active = coalesce((p->>''active'')::boolean, active)' || E'\n' || '      where id = rid;',
                      'active = coalesce((p->>''active'')::boolean, active),' || E'\n'
                   || '        template = case when p ? ''template'' then case when jsonb_typeof(p->''template'') = ''object'' then p->''template'' end else template end' || E'\n'
                   || '      where id = rid;');
  execute def;

  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'mooc_award';
  def := pg_get_functiondef(f);
  if position('''image_url'', b.image_url,' in def) = 0 then raise exception 'mooc_award image_url not found'; end if;
  def := replace(def, '''image_url'', b.image_url,', '''image_url'', b.image_url, ''template'', b.template,');
  execute def;
end $$;
