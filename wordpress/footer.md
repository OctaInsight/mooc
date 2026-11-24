# New footer for mooc.cloudearthi.com (Neve theme)

Two parts:

- `footer-main.html`: the green part, with the MOOC's name, social media, and links under Learn, Work with us and About.
- `footer-bottom.html`: the white part, with CloudEARTHi, Octa Insight, the EU funding statement, who pays for what,
  and the legal links.

The site uses the **Neve** theme. Its footer is made of rows (Top, Main, Bottom) that hold items, and widget areas
(Footer One to Four) that hold blocks.

## 0. Keep a copy of the old footer

Appearance → Widgets: open each Footer area, and copy the content of each block into a text file, so you can go back.

## 1. Put the new HTML into two widget areas

Appearance → Widgets:

1. **Footer One**: remove the blocks in it (the social icons), add a **Custom HTML** block and paste all of
   `footer-main.html`.
2. **Footer Two**: remove its blocks, add a **Custom HTML** block and paste all of `footer-bottom.html`.
3. **Footer Three** and **Footer Four**: remove their blocks (the old logos, the EU emblem and "Teaching a course?
   Open MOOC Studio"); everything they held is now in the new footer.
4. Update.

## 2. Arrange the footer rows

Appearance → Customize → **Footer** (the footer builder at the bottom of the screen):

1. **Top row**: drag everything out of it (it stays empty and disappears).
2. **Main row**: keep only **Footer One**, stretched over the whole row. Drag out **Footer Menu** (Terms and
   Privacy are now in the new footer) and **Footer Three/Four**.
3. **Bottom row**: keep only **Footer Two**, stretched over the whole row. Drag out **Copyright**
   ("Neve | Powered by WordPress").
4. Click the **Main row**'s settings (cog): Layout *Full width contained*, Background colour `#0f3d27`, padding top and
   bottom `0`.
5. Click the **Bottom row**'s settings: Background colour `#ffffff`, padding top and bottom `0`.
6. Switch the builder to **tablet/mobile** (icons at the bottom of the Customizer) and arrange the mobile footer the
   same way: Footer One in Main, Footer Two in Bottom, nothing else.
7. Publish.

## 3. Check

Open the site on a computer and a phone. The footer should show a dark green part with four columns (one under the
other on a phone), and a white part with the logos, the EU statement and the legal links.

## Notes

- The year in "© 2023–2026 CloudEARTHi" is plain text: change it at the start of each year.
- The EU emblem now comes with its disclaimer and the explanation that it applies to courses from EU-funded projects,
  as the EU's rules require, and links to the Acknowledgment page.

## Done on 24 Nov 2026

The footer above was put in place directly on mooc.cloudearthi.com: Footer One and Two hold the new HTML (block-9 and
block-15), the old Footer Three/Four blocks were moved to *Inactive widgets* (block-16, block-10, block-17), and the
Customizer layout and colours were set as described. The theme's "Neve | Powered by WordPress" line is hidden by a CSS
rule in `footer-bottom.html`. The previous widgets and settings are saved in `wordpress/backup/` to go back if needed.

## Home page and menu bar (24 Nov 2026)

- **Home page**: mooc.cloudearthi.com sends visitors to `/allcourses/` with a temporary (302) redirect from the
  Redirection plugin (Tools → Redirection, rule "Home page goes to All Courses"). Only the plain home address is
  redirected; searches and other addresses are not. Logging and IP storage are off. To undo: disable that rule.
  (Setting All Courses as the WordPress front page does not work: Academy LMS shows its course list only at the page's
  own address.)
- **Menu bar**: white with dark green text (`#0f3d27`), a 3 px dark green line underneath, and `#127a45` for hover and
  the current page, matching the footer. Previous values are in `backup/header-customizer-2026-11-24.json`.
