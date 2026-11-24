"""Copy "Financial analysis – part 1 (Module 7)" from the old WordPress MOOC (Academy LMS, course 373) to the new MOOC.

    python tools/migrate_old_course/module7.py > /tmp/module7.sql

Writes one SQL script that creates the course as a DRAFT (not visible to learners): course, one lecture
("Criteria for classifying costs by type"), five reading steps and a quiz step with seven questions.
The lesson HTML below was read from the old site's Academy LMS REST API on 24 Nov 2026.
"""
import json
import re
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from convert import html_to_markdown, sql_literal  # noqa: E402

OLD = json.load(open(__import__("os").path.join(__import__("os").path.dirname(__file__), "module7.json"), encoding="utf-8"))


def main():
    c = OLD["course"]
    course = {
        "slug": "financial-analysis-part-1-module-7",
        "title": "Financial analysis – part 1 (Module 7)",
        "summary": ("The art and science of financial analysis in an organisation: costs, cost price and the "
                    "investments a start-up can receive."),
        "description": html_to_markdown(c["description_html"]).replace("**", ""),   # shown as plain text
        "outcomes": ["Organise a financial analysis with a clear blueprint",
                     "Use the key business indicators that show a company's state",
                     "Explain how the key indicators depend on each other",
                     "Assess start-up companies as an investment"],
        "image_url": c["image_url"],
        "level": "beginner", "language": "English", "pass_score": 60, "status": "draft",
    }
    lecture = {"title": c["topic_title"], "summary": c["topic_summary"]}
    steps = []
    for les in OLD["lessons"]:
        title = les["title"].rstrip(":").strip()
        steps.append({"kind": "text", "title": title, "config": {"markdown": html_to_markdown(les["html"])}})

    questions = []
    for q in OLD["quiz"]["questions"]:
        opts = sorted(q["answers"], key=lambda a: a["t"].strip().lower())       # a) b) c) d) e)
        clean = [re.sub(r"^[a-e]\)\s*", "", a["t"].strip()).rstrip(";").rstrip(".;").strip() for a in opts]
        correct = [str(i) for i, a in enumerate(opts) if a["ok"]]
        prompt = re.sub(r"^\d+\.\s*", "", q["q"]).replace("Strat up", "Start-up")
        questions.append({"prompt": prompt, "options": clean, "correct": correct})

    out = ["begin;"]
    out.append(f"""with c as (
  insert into "Mooc_courses" (slug, title, summary, description, outcomes, image_url, level, language, pass_score, status)
  values ({sql_literal(course['slug'])}, {sql_literal(course['title'])}, {sql_literal(course['summary'])},
          {sql_literal(course['description'])}, {sql_literal(json.dumps(course['outcomes']))}::jsonb,
          {sql_literal(course['image_url'])}, 'beginner', 'English', 60, 'draft')
  returning id),
l as (
  insert into "Mooc_lectures" (course_id, position, title, summary, status)
  select id, 10, {sql_literal(lecture['title'])}, {sql_literal(lecture['summary'])}, 'published' from c
  returning id)""")
    parts = []
    for i, s in enumerate(steps):
        parts.append(f"""s{i} as (
  insert into "Mooc_steps" (lecture_id, position, kind, title, config, required)
  select id, {10 * (i + 1)}, 'text', {sql_literal(s['title'])}, {sql_literal(json.dumps(s['config'], ensure_ascii=False))}::jsonb, true from l
  returning id)""")
    parts.append(f"""sq as (
  insert into "Mooc_steps" (lecture_id, position, kind, title, config, required)
  select id, {10 * (len(steps) + 1)}, 'quiz', 'Quiz of Module 7', '{{}}'::jsonb, true from l
  returning id)""")
    for i, q in enumerate(questions):
        parts.append(f"""q{i} as (
  insert into "Mooc_questions" (step_id, position, prompt, kind, options, correct, must_pass)
  select id, {10 * (i + 1)}, {sql_literal(q['prompt'])}, 'single', {sql_literal(json.dumps(q['options'], ensure_ascii=False))}::jsonb,
         {sql_literal(json.dumps(q['correct']))}::jsonb, true from sq
  returning id)""")
    out[-1] += ",\n" + ",\n".join(parts)
    out.append("select (select id from c) as course_id, (select count(*) from l) as lectures;")
    out.append("commit;")
    print("\n".join(out))


if __name__ == "__main__":
    main()
