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
