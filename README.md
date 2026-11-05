# CloudEARTHi MOOC

The new CloudEARTHi MOOC (mooc.cloudearthi.com), built on the Octa suite accounts. See [DESIGN.md](DESIGN.md).

| Folder | What |
|---|---|
| `studio/` | **MOOC Studio** (Streamlit): super admins, course admins and teachers build projects, courses, lectures, interactive questions, badges and certificates, and grade assignments |
| `supabase/migrations/` | database (Supabase project Octa_projects): `Mooc_` tables and `mooc_*` functions |
| `supabase/tests/` | end-to-end database test; it always rolls itself back |

## Run MOOC Studio on Streamlit Community Cloud
1. New app → repository `OctaInsight/mooc`, branch `main`, main file `studio/app.py`.
2. Secrets: copy `studio/.streamlit/secrets.example.toml` and fill in the server key and Gmail app password.
3. Put the app's address in the Octa suite: `update "User_apps" set url = '<address>', status = 'live' where id = 'octa_mooc';`

## Tests
`cd studio && python -m pytest tests` (no database needed). Database test: run `supabase/tests/mooc_flow_test.sql`
on the database; it ends with "MOOC TEST PASSED (rolled back)".

## Student test page
`docs/test_lecture.html` signs in as a student, enrols, goes through a course's lectures and shows a log of every
database call. Served by GitHub Pages (Settings → Pages → branch `main`, folder `/docs`) at
https://octainsight.github.io/mooc/test_lecture.html (other courses: `?course=<course address>`).

Public pages, also in `docs/`:
- `award.html?id=<award id>`: a certificate or badge with the student's name, verification, download (image/PDF) and sharing (LinkedIn "Add to profile", LinkedIn, Facebook, X).
- `profile.html?u=<username>`: a student's public page with all awards and course progress.
