/* Certificates on a course's own design: the uploaded image with the student's name and other details written where
   the teacher placed them in MOOC Studio. Used by award.html and by MOOC Studio's preview, so both look the same.

   template = {image_url, width, height, fields: [{key, x, y, size, color, align, font, bold, italic, prefix, max}]}
     key     name | contribution | course | title | date | verify
     x, y    middle of the text, as fractions of the width and height
     size    text height as a fraction of the image width; long text shrinks to fit within `max` (fraction of width)
   values  = {name, contribution, course, title, date, verify}   (a field without a value is left out)
*/
"use strict";
var CERT_FONTS = { serif: '"Cormorant Garamond", Georgia, "Times New Roman", serif', sans: 'Inter, Arial, Helvetica, sans-serif' };
var CERT_FIELDS = {
  name: "Student's name", contribution: "Contribution", course: "Course or event", title: "Certificate title",
  date: "Date", verify: "Verification address",
};

function certFont(f, px) {
  return `${f.italic ? "italic " : ""}${f.bold ? 700 : 400} ${px}px ${CERT_FONTS[f.font] || CERT_FONTS.sans}`;
}

function drawTemplateCertificate(cv, im, tpl, values) {
  const W = tpl.width || im.naturalWidth || im.width, H = tpl.height || im.naturalHeight || im.height;
  cv.width = W; cv.height = H;
  const ctx = cv.getContext("2d");
  ctx.fillStyle = "#ffffff"; ctx.fillRect(0, 0, W, H);
  ctx.drawImage(im, 0, 0, W, H);
  for (const f of tpl.fields || []) {
    const v = values[f.key];
    if (!v) continue;
    const text = (f.prefix || "") + v;
    let px = Math.max(8, Math.round((f.size || 0.04) * W));
    const maxW = (f.max || 0.85) * W;
    ctx.font = certFont(f, px);
    while (ctx.measureText(text).width > maxW && px > 8) { px -= Math.max(1, Math.round(px * 0.05)); ctx.font = certFont(f, px); }
    ctx.fillStyle = f.color || "#0b0b0b";
    ctx.textAlign = f.align || "center";
    ctx.textBaseline = "middle";
    ctx.fillText(text, (f.x ?? 0.5) * W, (f.y ?? 0.5) * H);
  }
  ctx.textBaseline = "alphabetic"; ctx.textAlign = "left";
}
