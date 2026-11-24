# Clean-up of mooc.cloudearthi.com (24 Nov 2026)

## Plugins

Removed (deleted): Akismet, Elementor, Academy Elementor Addons (needed Elementor, did nothing), Divi Dash (for the
Divi theme; this site uses Neve), Add From Server, Site Kit by Google (not signed in to Google, sent no data).

Switched off, not yet deleted: **LearnDash LMS**. It holds no courses, lessons or quizzes (all counts 0) and its licence
is invalid. The old courses are in **Academy LMS**, which stays on, so they can still be reviewed under
wp-admin → Academy LMS → Courses (20 courses).

Waiting for a decision:

| Plugin | Status | Note |
|---|---|---|
| LearnDash LMS + 11 LearnDash add-ons | off | Empty; delete once confirmed |
| Ninja Forms | on | Forms "Contact us" (no longer on any page) and "Demographic data" (only on the old registration pages). Holds old submissions with personal data: export to CSV, then delete |
| WP Remote Users Sync | on | Copies WordPress user accounts to and from community.cloudearthi.com. The new MOOC does not use WordPress accounts |
| Duplicator | on | Backup tool, no backups made. Useful for one full backup before the deletions, then delete |
| Academy LMS, Academy Certificates | on | Keep while reviewing the old courses; remove when the review is done |
| Limit Login Attempts Reloaded, Redirection | on | In use, keep |

Themes: Neve is active; four inactive default themes (Twenty Twenty-Two to Twenty Twenty-Five). Keep one
(Twenty Twenty-Five) as WordPress's fallback, delete the other three.

## Pages not in use

In use: Welcome (home, 711), Partner with us (677), Contact us (52), Acknowledgment (76), Terms of use (15),
Privacy Policy (157).

| ID | Page | Why it is not in use |
|---|---|---|
| 67 | Partners | Menu now goes to cloudearthi.com/#partners |
| 128 | (no title) "welcome-to-the-cloudearthi-mooc-platform" | Old home page, replaced by Welcome |
| 445 | Special programs (/courses/) | Old course page, not linked |
| 50 | Contribute & upload your course | Replaced by Partner with us |
| 25 | Linked websites | Empty, the menu item is only a heading |
| 70 | Log in | Empty |
| 632–638 | Registration, Registration Success, Reset Password, Profile, Profile (2, 3, 4) | LearnDash pages (LearnDash is off) |
| 5 | Dashboard | Academy LMS page, old learners |
| 8 | All Courses | Academy LMS course list, replaced by mooc.html |
| 60 | Login | Academy LMS login |
| 6, 7 | Student Registration, Instructor Registration | Academy LMS and Ninja Forms registration |

Pages 5, 8, 60, 6 and 7 belong to Academy LMS: delete them together with Academy LMS after the review. The others can
go now. Deleted pages go to the Trash first (30 days).

## Media not in use (52 of 118 files, about 41.5 MB)

Not deleted: 66 files are in use, most of them by the new MOOC (the PDFs, slides and images of the transferred
courses link to the WordPress uploads folder), the header logo, the site icon and the EU emblem.

**A. Not used anywhere (24 files, 35.5 MB)**

| ID | File | Folder | MB |
|---|---|---|---|
| 268 | 2nd-of-May-2023-progress-presentation-wp1.pptx | 2023/08 | 19.08 |
| 306 | PRESENTATION-EMBRACING-DIVERSITY-THROUGH-SELF-AWARENESS-TOOL.pptx (older copy; the 2023/10 copy is used) | 2023/09 | 6.63 |
| 82 | HKdir-primaer-engelsk-frg-lys-bunn-rgb-e1688810535652.png | 2023/07 | 6.28 |
| 260 | Lecture1-part1.pdf | 2023/08 | 1.44 |
| 478 | PRESENTATION-CSR-AND-DIVERSITY-BUILDS-BETTER-BUSINESS.pptx.pdf | 2023/10 | 0.47 |
| 228 | icon-mooc.png (the cropped version is the site icon and stays) | 2023/07 | 0.36 |
| 139 | cropped-cropped-CloudEARTHi_MOOC_platform_Logo-e1688841102227.png | 2023/07 | 0.16 |
| 523 | 12.4-Materials.pdf | 2023/11 | 0.14 |
| 246 | Green-jobs-e1690123872628.jpg | 2023/07 | 0.11 |
| 257 | big-data-AI.jpg | 2023/08 | 0.09 |
| 84 | EIT-HEI-Initiative-logo-multicolor.png | 2023/07 | 0.09 |
| 107 | Header-of-MOOC-platform-1.png | 2023/07 | 0.08 |
| 106 | Header-of-MOOC-platform.png | 2023/07 | 0.08 |
| 86 | EIT-HEI-Initiative-logo-blue.png | 2023/07 | 0.07 |
| 87 | EIT-HEI-Initiative-logo-white.png | 2023/07 | 0.07 |
| 88 | Supported-by-EITRM_Landscape_RGB-e1688835150183.png | 2023/07 | 0.07 |
| 702 | new-logo-white-background.png | 2026/11 | 0.06 |
| 85 | EIT-HEI-Initiative-logo-black.png | 2023/07 | 0.06 |
| 102 | cropped-CloudEARTHi_MOOC_platform_Logo-1.png | 2023/07 | 0.03 |
| 99 | cropped-CloudEARTHi_MOOC_platform_Logo.png | 2023/07 | 0.03 |
| 89 | EU-Logo2.png | 2023/07 | 0.03 |
| 105 | cropped-CloudEARTHi_MOOC_platform_Logo-2.png | 2023/07 | 0.02 |
| 247 | social-inclusion.jpg | 2023/07 | 0.01 |
| 18 | certificate-nograde.png (old Academy certificate) | 2023/07 | 0.01 |

The logos (EIT HEI, HKdir, EU, EIT RawMaterials) and the certificate image may still sit on old Academy certificate
templates: delete them together with Academy Certificates.

**B. Used only on the unused Partners page (25 files, 5.8 MB)**: partner logos and two partner maps, IDs 179, 182,
184–206 (Edinburgh, UiT, Varna, FH Burgenland, Alicante, G-Force, KAU, IKU, EIT RM ×3, Fasttrack, Impact Hub,
Goodguys, Octa ×2, AI House, Solco, Kyiv-Mohyla, Karlsch, AUTH, Salerno, EU maps). Delete with the Partners page,
unless you want to keep the logos for cloudearthi.com.

**C. Used only by the old Academy courses (3 files)**: 341 seedplus.png, 267 2.jpg, 259 what-is-data.jpg. Delete
together with Academy LMS after the review.

Files outside the media library that the footer uses (keep): 2025/03/OctaInsight-Logo.png, 2025/04/new-logo.png.
