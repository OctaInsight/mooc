# CloudEARTHi MOOC

The new CloudEARTHi MOOC (mooc.cloudearthi.com), built on the Octa suite accounts. See [DESIGN.md](DESIGN.md).

| Folder | What |
|---|---|
| `studio/` | **MOOC Studio** (Streamlit): super admins, course admins and teachers build projects, courses, lectures, interactive questions, badges and certificates, grade assignments, and issue certificates to a list of people from an Excel file (conferences, workshops) |
| `supabase/migrations/` | database (Supabase project Octa_projects): `Mooc_` tables and `mooc_*` functions |
| `supabase/tests/` | end-to-end database test; it always rolls itself back |

## Run MOOC Studio on Streamlit Community Cloud
1. New app → repository `OctaInsight/mooc`, branch `main`, main file `studio/app.py`.
2. Secrets: copy `studio/.streamlit/secrets.example.toml` and fill in the server key and the Resend email settings (the same Resend key as the matchmaking platform).
3. Put the app's address in the Octa suite: `update "User_apps" set url = '<address>', status = 'live' where id = 'octa_mooc';`

## Tests
`cd studio && python -m pytest tests` (no database needed). Database tests: run the files in `supabase/tests/`
on the database; each ends with "… TEST PASSED (rolled back)" and changes nothing.

## Student website
`docs/index.html` (with `docs/assets/`) is the website students use: browse all courses or one project's courses
(Projects menu, project buttons, and a page per project at `#/project/<project address>`), create an account or
sign in with an Octa account, start a course without approval, learn (videos that pause for questions, PDFs, quizzes,
assignments, live sessions, retakes), follow progress under My learning and open their badges and certificates.
Served by GitHub Pages at https://octainsight.github.io/mooc/. To serve it at mooc.cloudearthi.com, add the domain in
Settings → Pages → Custom domain and a CNAME record `mooc` → `octainsight.github.io` at the domain provider.

### One-file version to upload to another website
`python tools/build_single_page.py` writes `upload/new_mooc.html` (with `upload/award.html` and `upload/profile.html`): the whole student website in one file (styles,
script and logo inside). Upload all three with these names into the same folder on mooc.cloudearthi.com; certificate
and profile links point to https://mooc.cloudearthi.com/award.html and profile.html. Run it again after changing the site.

## Student test page
`docs/test_lecture.html` signs in as a student, enrols, goes through a course's lectures and shows a log of every
database call. Served by GitHub Pages (Settings → Pages → branch `main`, folder `/docs`) at
https://octainsight.github.io/mooc/test_lecture.html (other courses: `?course=<course address>`).

Public pages, also in `docs/`:
- `award.html?id=<award id>`: a certificate or badge with the student's name, verification, download (image/PDF) and sharing (LinkedIn "Add to profile", LinkedIn, Facebook, X).
- `profile.html?u=<username>`: a student's public page with all awards and course progress.
