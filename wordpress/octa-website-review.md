# Octa Insight website (octainsight.com): review and rebuild plan

Written 24 November 2026, from a review of the live site, to start a new chat whose job is to fix the website step by
step over the coming month. Tamer agreed with every point below.

How to use this file in the new chat: ask Claude to read this document first, then work through the plan in section 6
one step at a time, showing each change before it goes live.

---

## 1. The site today

| Item | Value |
|---|---|
| Platform | WordPress with the **Divi** theme (v4.27.9) |
| Font | Open Sans everywhere |
| Main menu | Home, Solutions, Platforms, Ecosystem, About, Contact |
| Footer links | Vision, Mission, Contact, Internal resources, Working Hours Tracking System, Octa Proposals Tracking System, Gender Equality Plan |
| Footer line | "Designed by Octa Systems © 2025" |
| Browser-tab title | "OCTAINSIGHT \| Empowering Change with Data" |
| Analytics | Google tag (gtag, `GT-55KL7WLC`) loads on every page |
| Contact page | one form |
| Home page length | about 7,300 px on a desktop |

### Colours used (measured on the home page)

| Role | Colour |
|---|---|
| Dark background (navy) | `#0b1426` (rgb 11, 20, 38) |
| Second navy (cards on dark) | `#111e38` (rgb 17, 30, 56) |
| Teal accent, main buttons | `#00c9a7` (rgb 0, 201, 167) |
| Blue accent, gradient end, links | `#2ea3f2` (rgb 46, 163, 242) |
| Light section background | `#f7f9fc` |
| Body text on light | `#666666` (Divi default) and `#64748b` |
| Headings on light | `#0b1426` |
| Soft teal tint | `rgba(0, 201, 167, .1)` |

The hero headline uses a teal-to-blue gradient on "Sustainable Impact".

### Home page structure (top to bottom)

1. **Hero** (dark): "Innovation Ecosystems for Sustainable Impact", text, buttons *Partner with Us* and *Explore Our
   Platforms*, figures 30+ EU partners / 6 live platforms / 7+ countries.
2. **What we do** (light): "An Integrated Innovation Engine and Ecosystem Builder", 4 cards (AI & Sustainability
   Intelligence; Digital Systems & Data Infrastructure; Innovation Ecosystem Building; Venture Creation & Impact Scaling).
3. **Our process** (dark): "From Research to Real-World Impact", 5 steps (Intelligence, Systems, Ecosystem,
   Translation, Creation).
4. **Our technology** (light): "Platforms & Digital Systems", 3 cards (AccEARTH, ExplainFutures, KPI Tracking System),
   button *View All Platforms*.
5. **Track record** (white): "EU Projects & Strategic Partnerships", figures 30+ partners / 6+ EU projects / 17+
   proposals, logos (CloudEARTHi, Mind the Gap, Scale2Connect, one unnamed), box "Horizon Europe Aligned" with the EU emblem.
6. **Our differentiator** (dark): "Beyond Projects: Building Innovation Ecosystems", 4 cards plus one wide card.
7. **Why choose Octa** (light): "Why Work with Octa Insight", 4 cards with tick icons.
8. **Closing call** (dark): "Let's Build the Next Generation of Innovation Together", buttons *Partner with Us* and
   *Contact Us*.
9. **Footer**: grey Divi bar with the links above.

### Other pages (main headings)

- **Solutions**: 10 sections ("Building Innovation Ecosystems at Scale", "Strategic Partner Across the Full Project
  Lifecycle", "Digital Backbone for Data-Driven Projects", "From Research to Real-World Application", "Ensuring Impact
  Beyond Project Lifetime", "From Results to Visibility and Influence", "Supporting Early-Stage Innovation", "Ensuring
  Quality, Alignment, and Delivery", "Deep Tech. Ecosystems. Exploitation.", "An Integrated Innovation Architecture").
- **Platforms**: "Digital Platforms, Apps, and Research Tools"; "Octa-Built Platforms and Applications"; "Selected
  Platforms Developed by Current Team Members Before Octa"; "From Research Infrastructure to AI-Powered Systems".
- **Ecosystem**: "Engineering Innovation Ecosystems Across Europe and beyond"; "The Octa Ecosystem Engine"; "How the
  Ecosystem Creates Value Across Stakeholders"; "From Innovation to Policy Impact".
- **About**: "An Ecosystem Builder at the Intersection of Technology and Impact"; vision; "Built on Strong
  Collaborations".
- **Contact**: heading and one form.
- **Vision / Mission**: older pages ("Harnessing AI and Data for Global Impact"), only linked from the footer.
- **/mooc**: does **not exist yet** (404).
- **/privacy-policy**: does **not exist** (404); no page on the site mentions privacy or cookies.
- Internal pages (Internal resources, WHTS, Proposals Tracking, GEP) are password-protected.

---

## 2. What works and should be kept

- The dark navy with teal/blue accents looks modern and fits "deep tech".
- Dark and light sections alternate, which gives the page a good rhythm.
- The home page tells a sound story: what we do → process → platforms → EU track record → why us → call to action.
- Headlines are short and readable; the main menu is simple.

---

## 3. Findings, in order of priority

### A. Legal and broken (fix first)

1. **Google Analytics runs with no consent and no privacy policy.** Under the GDPR this needs a cookie-consent banner and
   a privacy page (or Analytics removed). Fix: a privacy policy page plus a consent tool (Complianz or CookieYes), with
   Analytics loaded only after consent; link "Privacy" in the footer.
2. **octainsight.com/mooc does not exist (404)**, but the CloudEARTHi MOOC's *Partner with us* page sends "Other projects
   and organisations" there. Fix: publish the MOOC page (section 5).
3. **The footer shows internal tools to the public**: Internal resources, Working Hours Tracking System, Octa Proposals
   Tracking System. They are password-protected but should not be advertised. Fix: remove them from the footer; reach
   them from one unlinked staff page or bookmarks.
4. **Wrong company name and old year**: "Designed by Octa Systems © 2025". Fix: "© 2026 Octa Insight AS", organisation
   number 930 841 366, address Strandvegen 53, 9007 Tromsø, LinkedIn, Privacy, and the Gender Equality Plan.

### B. Credibility: the figures disagree

- Hero: "6 live platforms", but the home page shows 3 platforms.
- Track record: "6+ EU projects" (the same 6 means something else).
- Hero "30+ EU partners" and "7+ countries"; track record "30+ partners" and "17+ proposals".
- Fix: one agreed set of figures, used the same way everywhere, each one that can be backed up.

### C. Layout and design

1. **Phone view of the hero is broken**: the 30+ / 6 / 7+ figures sit beside the text and are cut off at the right edge.
   Fix: put the figures under the text on phones.
2. **The burger menu icon is almost invisible**: dark grey (`rgba(0,0,0,.6)`) on navy. Fix: white.
3. **The hero is too tall**: on a laptop the figures, and on smaller screens the buttons, are below the fold, with a
   large empty area on the right. Fix: a real visual on the right (platform screenshot, map, or a small live chart), and
   the figures moved up.
4. **The logo is tiny** and the "OCTAINSIGHT" wordmark under it cannot be read. Fix: a horizontal logo, at least 40 px
   high.
5. **Mixed icon styles**: line icons in some sections, emoji (🌍 📊 📄 🌱) in "Beyond Projects". Fix: one icon set.
6. **Platform cards use placeholder graphics** (dots on a grid). Fix: real screenshots of AccEARTH, ExplainFutures, KPI
   Tracking System (and the other platforms).
7. **Partner logos**: Mind the Gap is cropped ("IND THE GAP"); the fourth logo has no name. Fix: proper logo files, each
   with its name as alt text and a link.
8. **Low-contrast grey text on the dark sections**. Fix: lighter text (for example `#c7d2e0` on `#0b1426`), at least
   WCAG AA.
9. **The footer is the default Divi grey bar** and does not match the site. Fix: a navy footer in the site's style.
10. **The EU emblem is used as a decoration** ("Horizon Europe Aligned"). EU rules allow the emblem only with a funding
    statement, never as a badge suggesting endorsement. Fix: a neutral icon.

### D. Structure and content

1. **Three different taglines**: tab title "Empowering Change with Data", hero "Innovation Ecosystems for Sustainable
   Impact", Vision page "Harnessing AI and Data for Global Impact". Fix: choose one; update or remove Vision/Mission.
2. **Solutions (10 sections) repeats Home and Ecosystem**; Solutions, Ecosystem and About overlap heavily. Fix: merge
   Ecosystem into About or Solutions; shorten Solutions.
3. **No team page and no project list.** For an EU partner company, evaluators look for people, CVs, and named projects
   with Octa's role. This is the biggest content gap. Fix: a Team page and a Projects page (project, programme, grant
   number, Octa's role, years, link).
4. **No meta descriptions on any page.** Fix: one per page (for example with Yoast or Rank Math).
5. **The MOOC offer is not in the menu.** Fix: once /mooc is live, add it under Platforms.

---

## 4. The MOOC set-up: three tools and who pays (agreed facts)

These facts must be the same on octainsight.com/mooc, the CloudEARTHi MOOC's *Partner with us* page and its
*Acknowledgment* page.

1. **The CloudEARTHi MOOC** (mooc.cloudearthi.com): the MOOC of the CloudEARTHi initiative. It publishes only courses that
   are free for learners. Learners never pay there.
2. **Octa MOOC Studio**: the tool used to build the courses and run the MOOCs (courses, learners, certificates, badges
   and the Octa database). Designed and paid for **exclusively by Octa Insight**, with no contribution from any project.
3. **Other MOOCs built by Octa**: MOOCs Octa builds with Octa MOOC Studio for organisations and projects, under their own
   name, colours and web address; nothing to do with CloudEARTHi. The organisation pays Octa for building and running
   it, and decides whether courses are free or paid. If paid, the money goes straight to that organisation (Octa takes
   no share), and the organisation, as the seller, charges and pays the VAT on course sales.

Who may publish on the CloudEARTHi MOOC:

| Who | Terms |
|---|---|
| CloudEARTHi projects | Free, always |
| CloudEARTHi partners | Free to publish their own free courses that are not linked to a CloudEARTHi project; €50 a year covers only database hosting and Octa MOOC Studio, at a reduced price (below the real cost) |
| Other projects and organisations | May publish free courses; they pay for database hosting and technical help, through an Octa package or by having Octa Insight as a partner in their project |

Not part of the plan: no separate "Octa MOOC" launch, and no hosting of other platforms (Moodle, edX).

Funding history (Acknowledgment page): the CloudEARTHi MOOC student website was set up in 2023–2024 with BOOSTalent
(project 10048, EIT HEI Initiative); 2025 operating costs were covered by Inspiring the Minds (Erasmus+ KA2,
2022-1-NO01-KA220-HED-000087789); from 2026 it is covered by Octa Insight's own resources.

---

## 5. The MOOC page for octainsight.com/mooc (to be published)

**Ready-made code**: `wordpress/octa-mooc-packages.html` in the GitHub repo **OctaInsight/mooc** (one Custom HTML block,
styles scoped to `.octa-mooc`, no scripts). The form set-up is in `wordpress/request-a-package.md` in the same repo.

### 5.1 Colours: switch to the Octa palette

The page was built with placeholder colours, set at the top of its style. Replace them with the measured Octa colours:

| Token in the page | Placeholder now | Octa colour |
|---|---|---|
| `--brand` (headings, closing box, Studio card) | `#0f3d5e` | `#0b1426` |
| `--accent` (tags, highlights, card hover border) | `#0a8f8a` | `#00c9a7` (use `#00a88c` for text on white, for contrast) |
| `--accent-soft` (light panels, hero) | `#e6f4f3` | `rgba(0,201,167,.1)` or `#e6f9f5` |
| `--button` | `#0f3d5e` | `#00c9a7` with navy text, or `#0b1426` with white text |
| `--button-hover` | `#0b2d46` | `#111e38` |
| `--page` | `#f5f8fa` | `#f7f9fc` |
| `--quiet` (body text) | `#4f5b66` | `#64748b` |

Optionally give the hero the site's dark navy background with the teal-to-blue gradient on the key words, so the page
looks like the rest of octainsight.com.

### 5.2 Sections and content

1. **Hero**: kicker "Octa MOOC Studio"; heading "Build your courses. Publish them free on the CloudEARTHi MOOC, or on a
   MOOC of your own."; text that Octa MOOC Studio is Octa Insight's tool, designed and paid for exclusively by Octa
   Insight; buttons *Send a request* (to #request) and *See the two ways*. Side box: "Learners never pay on the
   CloudEARTHi MOOC" (open worldwide, no limit on learners, certificates and badges included).
2. **Three tools, clearly separated**: three cards: CloudEARTHi MOOC (the CloudEARTHi initiative); Octa MOOC Studio (Octa
   Insight); Your own MOOC (Octa Insight, for your organisation).
3. **What Octa MOOC Studio gives you**: 8 cards with a hover effect (lift, accent border, shadow); the first card, Octa
   MOOC Studio, is dark:
   - Octa MOOC Studio: one place to build courses, manage learners and teachers, design certificates and badges, follow
     progress, no technical skills needed.
   - Your courses online: video, PDF, text, quizzes, assignments and live sessions.
   - Certificates on your design: funders' and partners' logos; names filled in automatically.
   - Badges: awarded automatically by your rules.
   - Certificates from a list: Excel list after an event; each person gets their certificate by email.
   - Checkable by anyone: each certificate has its own verification page, ready for LinkedIn.
   - Figures for your reports: learners, completions, certificates.
   - Free for learners: one Octa account; all certificates and badges on their learner profile.
4. **Two ways to work with us**: Way 1, publish free courses on the CloudEARTHi MOOC; Way 2, your own MOOC built by Octa.
5. **Way 1 packages** (launch prices 2027, excluding VAT; each card opens `/mooc/?package=<name>#request`):

   | Package | Price | Main points |
   |---|---|---|
   | CloudEARTHi projects | Free | Unlimited courses, learners, certificates, badges; Studio and help included; links to the MOOC's Contact us |
   | CloudEARTHi partners | €50 a year | Free to publish own free courses not linked to a CloudEARTHi project; covers only hosting and Studio, at a reduced price |
   | Hosting | €690 a year | Up to 10 courses, unlimited learners, own certificate design, badges, yearly figures, 1-hour set-up, email answers within 3 working days |
   | EU project package | €5,900 once | Hosting for the project plus 3 years after; 3 courses included (€600 per extra); funder logos; reach figures |
   | Hosting Plus | €1,190 a year | Up to 20 courses (€50 per extra a year); programme page; priority help; over 50 courses on offer |
   | Low- and middle-income countries | 75% off | World Bank list; e.g. Hosting €170 a year |
   | Women, equality and inclusion | 50% off | Non-profits in high-income countries |
   | Certificates for an event | €99 per event | Up to 200 participants; own design; each checkable |
   | We build the course for you | Per day | Quote on request |

   Note under the cards: technical help is a 1-hour set-up session and email answers within 3 working days; further work
   at the day rate; offered and invoiced by Octa Insight AS; reduced rates cannot be combined.
6. **Way 2: your own MOOC** (launch prices 2027, excluding VAT):

   | Package | Price | Main points |
   |---|---|---|
   | Own MOOC | €4,900 set-up + €2,400 a year | Own name, logo, colours, web address; up to 20 courses; Studio for your team; hosting, updates, backups; training |
   | Project MOOC | €12,900 once | Everything in Own MOOC; hosting for the project plus 3 years; up to 5 courses (€600 per extra); funding statement |
   | Own MOOC Plus | €6,900 set-up + €3,900 a year | Up to 60 courses, programme pages, priority help, yearly review |

   Box "Free or paid courses: your choice": online payment set up in the buyer's own payment account for a one-time
   €900; money goes straight to the buyer, Octa takes no share; the buyer charges and pays the VAT on course sales;
   Octa invoices only for building and running the MOOC.
7. **Octa as a project partner**: "Planning a new project? Bring Octa into the consortium." Octa joins EU and
   international proposals, bringing digital platforms, applied AI and project monitoring; with Octa as a partner the
   project's free courses can go on the CloudEARTHi MOOC with hosting in Octa's budget. Points: applied AI tools and
   platforms, KPI/monitoring/financial dashboards, training and certificates, dissemination and exploitation that stay
   online. Button *Invite Octa to your proposal*.
8. **Questions** (8): Do learners pay? Difference between the two ways? Who pays for Octa MOOC Studio? If learners pay,
   who gets the money? What happens when the project ends? Can a project pay from its EU grant? Who owns the content?
   How do the reduced rates work?
9. **Send a request** (anchor `#request`): reply within two working days, usually with a 30-minute online demo offer.

### 5.3 The request form

- Contact Form 7 form "Request a package": package (pre-filled from the link with `default:get`), name, organisation,
  email, country, number of courses or participants, message, consent tick box.
- Email to Octa with Reply-To the visitor; confirmation email to the visitor.
- WP Mail SMTP through Resend (`smtp.resend.com`, SSL, port 465, user `resend`, the Resend API key), from
  `mooc@octainsight.com` with the domain verified in Resend.
- **Still open**: which Octa address receives the requests.

### 5.4 Publishing steps

1. Pages → Add new, title "CloudEARTHi MOOC" (or "Octa MOOC Studio"), permalink `mooc`.
2. A Custom HTML block with `octa-mooc-packages.html` (colours switched as in 5.1), then a Shortcode block with the form.
3. Add "MOOC" under Platforms in the menu.
4. Test `https://octainsight.com/mooc/?package=Hosting#request`, send a test request, and check the *Other projects
   and organisations* card on mooc.cloudearthi.com/partner-with-us/ now lands on it.

---

## 6. Step-by-step plan for the new chat

1. **Legal first**: privacy policy page; cookie consent tool with Analytics only after consent; footer link.
2. **Footer**: navy footer in the site's style with © 2026 Octa Insight AS, org number, address, LinkedIn, Privacy, GEP,
   Vision/Mission decision; internal tools removed.
3. **Publish /mooc** (section 5), with the Octa colours and the request form; add it to the menu.
4. **Phone fixes**: hero figures under the text; white burger icon; check every page at phone width.
5. **Agree the figures** (partners, projects, platforms, countries, proposals) and use them consistently.
6. **Hero redesign**: shorter hero, a real visual on the right, figures visible above the fold; larger horizontal logo.
7. **Visual consistency**: one icon set, real platform screenshots, proper partner logos, lighter text on dark, EU
   emblem removed from decoration.
8. **Content structure**: one tagline; merge or trim Solutions/Ecosystem/About; update or retire Vision/Mission.
9. **New pages**: Team (people, roles, short CVs) and Projects (programme, grant number, Octa's role, years).
10. **Search basics**: meta description and title for each page.

---

## 7. Working rules from the earlier chats

- Claude does not type passwords; Tamer signs in to WordPress in the built-in browser himself, then Claude can make
  changes through WordPress's own interface or REST API.
- Before changing a live page, save a copy of the current content (as was done for the MOOC site in
  `wordpress/backup/` of the OctaInsight/mooc repo), and show Tamer the change first.
- Secrets (API keys, passwords) never go into GitHub or the chat; they live in Streamlit secrets or the hosting panel.
- Real data is deleted or changed only when Tamer asks explicitly.
- Tamer normally codes in Python.

## 8. Related sites and files

- CloudEARTHi MOOC: https://mooc.cloudearthi.com (WordPress with Neve; student pages mooc.html, award.html,
  profile.html).
- Octa MOOC Studio: https://cloudearthi-mooc.streamlit.app/
- GitHub repo OctaInsight/mooc, folder `wordpress/`: `octa-mooc-packages.html` (the /mooc page),
  `request-a-package.md` (the form), `partner-with-us.html`, `acknowledgment.html`, `roles-and-funding.md`,
  `footer-main.html`, `footer-bottom.html`, `terms.html`, `privacy.html` (the MOOC's privacy text, which can serve as
  a starting point for octainsight.com's privacy policy).
- Project doc `claude/mooc_roles_and_funding.md` in the Octa Suite project.
