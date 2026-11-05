# CloudEARTHi MOOC: design (5 November 2026)

The new CloudEARTHi MOOC replaces the WordPress + LearnPress site at **mooc.cloudearthi.com**. It has two parts that
share one database (Supabase project Octa_projects) and the Octa suite accounts:

| Part | Built with | Used by | Status |
|---|---|---|---|
| **MOOC Studio** (`studio/`) | Streamlit + `octa_auth` | super admins, course admins, teachers | phase 1: built |
| **MOOC website** (`site/`, to come) | Python (FastAPI + HTML templates) + small JavaScript players | students and the public | phase 2 |

## Roles

| Role | Who | Can |
|---|---|---|
| Super admin | Octa admins + `Mooc_super_admins` | everything; creates projects and courses; names course admins and super admins |
| Course admin | `Mooc_members.role = 'admin'` | course settings and publishing; gives teacher/student rights in the course; approves teachers; everything a teacher can |
| Teacher | `Mooc_members.role = 'teacher'` | lectures, steps, questions, badges and certificates; grading |
| Student | `Mooc_members.role = 'student'` | enrols in published courses and learns |

Registration: students are active at once; teachers are pending until a course admin or super admin approves them
(`Mooc_people`). Giving someone a teacher role in a course also approves them.

## Content

- **Project** (`Mooc_projects`): groups courses, e.g. BOOSTalent, SEEDplus, Inspiring the Minds.
- **Course** (`Mooc_courses`): title, summary, description, learning outcomes, level, language, hours, cover,
  pass score, status draft / published / archived.
- **Lecture** (`Mooc_lectures`): ordered, with its own learning outcomes; draft or published.
- **Step** (`Mooc_steps`), in order inside a lecture:
  - video (YouTube), pdf (uploaded), text, quiz, assignment (graded by a teacher or "handing in is enough"),
    live session (link to an online lecture or study group).
- **Question** (`Mooc_questions`): single, multiple or true/false. On a video at a time, on a PDF at a page, or in a
  quiz. "Must pass" questions stop the student until answered correctly.

## How activity becomes badges and certificates

1. Every student action is one row in `Mooc_events` (opened, progressed, answered, completed, submitted, graded,
   joined_live, awarded).
2. Step progress and score are kept in `Mooc_progress`:
   - video / PDF / text: completed when the student finishes it and has answered its must-pass questions;
     score = share of its questions right on the first try;
   - quiz: completed when all questions are answered correctly; score = first-try correctness;
   - assignment: completed when graded (score = the teacher's grade) or, for auto assignments, when handed in;
   - live: completed when the student joins.
3. Answers are checked inside the database (`mooc_answer`), so students never receive the right answers in advance.
4. `Mooc_badges` holds each badge or certificate: the design (uploaded image), the lectures to finish (empty = all
   published lectures) and the minimum average score.
5. After every completion or grade, `mooc_check_awards` checks the course's rules and issues earned awards
   (`Mooc_awards`). Each award id is its public verification address: `mooc.cloudearthi.com/badge/<id>`.

## Database functions

| For | Function |
|---|---|
| Studio | `mooc_manage(token, {action, ...})`: me, overview, course, people, submissions, students, save_project, delete_project, save_course, delete_course, set_member, decide_teacher, set_super, super_admins, save_lecture, save_step, save_question, delete, reorder, save_badge, grade, upload_ticket |
| Students | `mooc_join(token, kind)`, `mooc_enrol(token, course)`, `mooc_record(token, step, verb, position, data)`, `mooc_answer(token, question, answer)`, `mooc_submit(token, step, text, file_url)` |
| Public pages | `mooc_catalogue()`, `mooc_profile(username)`, `mooc_award(id)` |

All `Mooc_` tables have row-level security on and no public access. Files go to the public storage bucket `mooc`;
uploads need a 30-minute ticket that only teachers and admins get (`upload_ticket`), checked by the bucket policy.

## Phases

1. **Foundation (now):** database, roles, Studio (projects, courses, lectures, steps, questions, badges, grading, people).
2. **Student website:** catalogue grouped by project, course pages, the lecture player (YouTube with pop-up
   questions, PDF viewer with page questions, quizzes, assignments), student dashboard with "Continue",
   public profile and award pages with LinkedIn "Add to profile", PDF certificates, Open Badges data.
3. **Live learning:** online lectures and study groups (embedded video rooms, group chat, attendance).
4. **Switch-over:** host the website on an EU server, point mooc.cloudearthi.com to it, retire WordPress.
