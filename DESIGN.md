# CloudEARTHi MOOC: design (5 November 2026)

The new CloudEARTHi MOOC replaces the WordPress + LearnPress site at **mooc.cloudearthi.com**. It has two parts that
share one database (Supabase project Octa_projects) and the Octa suite accounts:

| Part | Built with | Used by | Status |
|---|---|---|---|
| **MOOC Studio** (`studio/`) | Streamlit + `octa_auth` | super admins, course admins, teachers | phase 1: built |
| **MOOC website** (`docs/`) | static HTML, CSS and JavaScript on GitHub Pages, calling the `mooc_*` functions | students and the public | phase 2: built |

## Roles

| Role | Who | Can |
|---|---|---|
| Super admin | Octa admins + `Mooc_super_admins` | everything; creates projects and courses; names course admins and super admins; issues certificates from a list |
| Course admin | `Mooc_members.role = 'admin'` | creates new courses (and becomes their admin); course settings and publishing; gives teacher/student rights in the course; approves teachers; issues certificates from a list; everything a teacher can |
| Teacher | `Mooc_members.role = 'teacher'` | lectures, steps, questions, badges and certificates; grading |
| Student | `Mooc_members.role = 'student'` | enrols in published courses and learns |

Registration: after creating an Octa account, people choose in MOOC Studio how they join, for one course:
**student** (enrolled at once), **teacher** (approved by that course's admin or a super admin) or **admin of the
course** (approved by a super admin only). Requests wait in `Mooc_requests` and appear under People → Requests.
Giving someone a role in a course's Team tab needs no request.

## Content

- **Project** (`Mooc_projects`): groups courses, e.g. BOOSTalent, SEEDplus, Inspiring the Minds.
- **Course** (`Mooc_courses`): title, summary, description, learning outcomes, level, language, hours, cover,
  pass score, status draft / published / archived. `kind` = `course` (lectures, listed on the website) or `event`
  (certificates only: a conference, workshop or course without content here; not listed on the website).
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

## Certificates issued from a list (conferences, workshops, short courses)

In MOOC Studio, a super admin or the course admin opens the course (or a "certificates only" event) and the
**Issue certificates** tab:

1. downloads the Excel template and fills in First name, Last name, Email and, if wanted, Contribution (Speaker,
   Participant, Organiser, Attended both days…); a CSV or a single Name column also works;
2. uploads it and checks the preview (lines without a valid email or listed twice are skipped and named);
3. chooses the certificate and/or badges (made first in Badges & certificates), the date on the certificate and a
   contribution for people without one;
4. clicks **Issue**: `bulk_award` creates one award per person and badge (`source = 'bulk'`, with
   `recipient_name`, `recipient_email` and `contribution`); people already holding it are left as they are;
5. each person gets one email (Resend) with links to their own award pages; the result of every email is kept
   (`email_sent_at`, `email_error`).

Everyone on the list becomes a **student of the course** (`invite_students`, run before `bulk_award`). People without
an Octa account get one: the username comes from their email, the password is random and unknown, and the account is
noted in `Mooc_invites`. Their certificate email's main button is **Set your password**, a link to the student
website (`#/welcome?t=…`, valid 30 days) where they choose a password (and may change the username), are signed in
and land on My learning with their certificates. Sending the email again gives a fresh link. A link is only created
while the invited account's password has never been set, and only for someone who manages the course that invited
it, so nobody can take over an account its owner already uses. People who already have an account are enrolled and
get the certificate link, with a note that it is also under My learning. My learning lists certificates-only events
even when they are not published. If someone creates an account later with the same email, awards issued to that
email are linked to it (trigger on `User_accounts`). The award page prints the contribution and, for events,
says "Certificate of Participation … has taken part in". The tab lists everything issued, with **Send emails not yet
sent** (Resend's free plan: 100 emails a day for all Octa apps together; sending stops at the limit and continues
the next day), an Excel download and **Withdraw / restore**.

## Emails

Links in emails go to the student website at **https://mooc.cloudearthi.com/new_mooc.html** (sign in, My learning,
set or reset the password); each award's own page stays on GitHub Pages (`award.html`). Both addresses are set in
`studio/links.py` and can be changed in the Streamlit secrets (`[mooc] site`, `[mooc] pages`).

All emails are sent by **MOOC Studio** (Python, `octa_auth/mail.py`, Resend settings in the Streamlit secrets), the
same way as the Octa password reset. The database only keeps the outbox; nothing is sent from Supabase.

| When | Says |
|---|---|
| Certificates issued from a list, new person | what they received and for which course; an account was made (username); **Set your password** (30-day link); view, download and LinkedIn links |
| Certificates issued from a list, existing account | it is on their profile and the course is under My learning; sign in with the usual Octa password; link to choose a new one if forgotten; view and LinkedIn links |
| A student earns a badge or certificate in a course (also after a teacher's grade) | congratulations, course name, **View and share**, a LinkedIn share link per award, how to sign in or reset the password |
| "Forgot your password?" on the student website | `#/forgot` opens MOOC Studio at `?mooc=forgot`, which emails a one-hour link back to `#/welcome?t=…&r=1`; it never says whether the email is registered |

Earned awards enter an outbox (`Mooc_awards.notify_state = 'pending'`, set by a trigger for `source = 'auto'`).
MOOC Studio empties it (`outbox.py`): a background thread checks every 5 minutes while the app is running, a few go
out each time anyone opens the app, and People → Email shows how many are waiting with **Send waiting award emails
now**. Streamlit Cloud puts a quiet app to sleep; waiting emails then go out the next time someone opens MOOC Studio.
At the Resend daily limit sending stops and the rest wait; an address that keeps failing is given up after 5 tries.
The outbox and the reset link are reached with the app's server key (`mooc_mail_claim_app`, `mooc_mail_done_app`,
`mooc_mail_status`, `mooc_site_reset_app`), like `octa_user_reset_request`.
People on a certificate list are also given access to the MOOC app in their Octa account (`User_app_access`
granted), unless an admin had taken it away.

## Database functions

| For | Function |
|---|---|
| Studio | `mooc_manage(token, {action, ...})`: me, overview, course, people, submissions, students, save_project, delete_project, save_course, delete_course, set_member, decide_teacher, set_super, super_admins, save_lecture, save_step, save_question, delete, reorder, save_badge, grade, upload_ticket, requests, decide_request, bulk_award, awards, award_email, revoke_award, invite_students |
| Students | `mooc_join_options(token)`, `mooc_register(token, kind, course, message)`, `mooc_join(token, kind)`, `mooc_enrol(token, course)`, `mooc_retake(token, lecture, course)` (redo a lecture or the course; the best score of all tries counts), `mooc_record(token, step, verb, position, data)`, `mooc_answer(token, question, answer)`, `mooc_submit(token, step, text, file_url)` |
| Public pages | `mooc_my_learning(token)` (signed-in student's courses, progress, next step, awards), `mooc_catalogue()`, `mooc_course_view(token, slug)` (course page; full content for enrolled students and the course team), `mooc_profile(username)`, `mooc_award(id)` |

All `Mooc_` tables have row-level security on and no public access. Files go to the public storage bucket `mooc`;
uploads need a 30-minute ticket that only teachers and admins get (`upload_ticket`), checked by the bucket policy.

## Phases

1. **Foundation (now):** database, roles, Studio (projects, courses, lectures, steps, questions, badges, grading, people).
2. **Student website:** catalogue grouped by project, course pages, the lecture player (YouTube with pop-up
   questions, PDF viewer with page questions, quizzes, assignments), student dashboard with "Continue",
   public profile and award pages with LinkedIn "Add to profile", PDF certificates, Open Badges data.
3. **Live learning:** online lectures and study groups (embedded video rooms, group chat, attendance).
4. **Switch-over:** host the website on an EU server, point mooc.cloudearthi.com to it, retire WordPress.
