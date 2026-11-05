-- Fix (applied 2026-11-05 as "mooc_badge_update_fix"): editing a badge without sending lecture_ids or description
-- cleared them. Now only the fields that are sent are changed.
do $$ declare f oid; def text; begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'mooc_manage';
  def := pg_get_functiondef(f);
  def := replace(def,
    'lecture_ids = coalesce(array(select jsonb_array_elements_text(p->''lecture_ids'')::uuid), lecture_ids),',
    'lecture_ids = case when p ? ''lecture_ids'' then array(select jsonb_array_elements_text(p->''lecture_ids'')::uuid) else lecture_ids end,');
  def := replace(def,
    'description = p->>''description'', image_url = coalesce(p->>''image_url'', image_url),',
    'description = case when p ? ''description'' then p->>''description'' else description end, image_url = coalesce(p->>''image_url'', image_url),');
  if def not like '%when p ? ''lecture_ids''%' or def not like '%when p ? ''description'' then p->>''description'' else description end, image_url%' then
    raise exception 'mooc_manage text not found; nothing changed';
  end if;
  execute def;
end $$;
