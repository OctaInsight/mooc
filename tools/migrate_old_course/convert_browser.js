// Runs in a signed-in WordPress admin tab on mooc.cloudearthi.com. Needs window.__old (courses, lessons),
// window.__qz.quizzes and window.__media, collected from the Academy LMS REST API. Builds one payload per course for
// public.mooc_import_course_tmp: course -> lectures (Academy topics) -> steps (video, pdf, text, quiz) -> questions.
window.MIG = (() => {
  const SITE = "https://mooc.cloudearthi.com";
  const dec = s => { const t = document.createElement("textarea"); t.innerHTML = String(s || ""); return t.value; };
  const ws = s => s.replace(/[\s ]+/g, " ");
  const fixUrl = u => {
    if (!u) return "";
    if (u.startsWith("/")) u = SITE + u;
    try { u = encodeURI(decodeURI(u)); } catch (e) { u = encodeURI(u); }
    return u.replace(/\(/g, "%28").replace(/\)/g, "%29");
  };
  const IMG = "\u0001";                                   // marks an image that must stand as its own paragraph
  function inline(n) {
    if (n.nodeType === 3) return ws(n.nodeValue);
    if (n.nodeType !== 1) return "";
    const tag = n.tagName, kids = () => [...n.childNodes].map(inline).join("");
    if (tag === "BR") return "\n";
    if (tag === "IMG") { const src = fixUrl(n.getAttribute("src")); return src ? `${IMG}![${ws(n.getAttribute("alt") || "").replace(/[\[\]]/g, "")}](${src})${IMG}` : ""; }
    if (tag === "STRONG" || tag === "B") { const t = kids(); return t.trim() ? t.replace(/^(\s*)([\s\S]*?)(\s*)$/, (m, a, b, c) => b.includes(IMG) ? m : `${a}**${b}**${c}`) : t; }
    if (tag === "EM" || tag === "I") { const t = kids(); return t.trim() ? t.replace(/^(\s*)([\s\S]*?)(\s*)$/, (m, a, b, c) => b.includes(IMG) || b.includes("**") ? m : `${a}*${b}*${c}`) : t; }
    if (tag === "A") {
      const href = n.getAttribute("href") || "", t = kids();
      if (t.includes(IMG) || !/^https?:|^\//.test(href)) return t;
      const label = t.trim().replace(/[\[\]]/g, "") || href;
      return `[${label}](${fixUrl(href)})`;
    }
    if (tag === "SCRIPT" || tag === "STYLE") return "";
    return kids();
  }
  const bareUrls = s => s.replace(/(^|[\s(])(https?:\/\/[^\s<)\]]+)/g, (m, a, u) => `${a}[${u}](${fixUrl(u)})`);
  function tidy(s) {
    s = s.split("\n").map(x => x.replace(/[ \t]+/g, " ").trim()).join("\n").trim();
    s = s.replace(/\*\*\s*\*\*/g, "").replace(/\*\*\*([^*]+)\*\*\*/g, "**$1**");
    if (!/\]\(/.test(s)) s = bareUrls(s);
    else s = s.split(/(\[[^\]]*\]\([^)]*\))/).map((p, i) => i % 2 ? p : bareUrls(p)).join("");
    return s;
  }
  function blocksOf(node, out) {
    for (const n of node.childNodes) {
      if (n.nodeType === 3) { const t = tidy(ws(n.nodeValue)); if (t) out.push(t); continue; }
      if (n.nodeType !== 1) continue;
      const tag = n.tagName;
      if (/^H[1-6]$/.test(tag)) { const t = tidy(inline(n)).replace(/\*\*/g, ""); if (t) out.push(`**${t}**`); }
      else if (tag === "UL" || tag === "OL") { const lines = []; listLines(n, lines, 0); if (lines.length) out.push(lines.join("\n")); }
      else if (tag === "TABLE") {
        const rows = [...n.querySelectorAll("tr")].map((tr, i) => {
          const cells = [...tr.children].map(td => tidy(inline(td)).replace(/\n/g, " "));
          const line = cells.join(" | ");
          return (i === 0 && tr.querySelector("th")) ? `**${line.replace(/\*\*/g, "")}**` : line;
        }).filter(Boolean);
        if (rows.length) out.push(rows.join("\n"));
      }
      else if (tag === "FIGURE") {
        const img = n.querySelector("img"), cap = n.querySelector("figcaption");
        if (img) out.push(tidy(inline(img)));
        else blocksOf(n, out);
        if (cap) { const t = tidy(inline(cap)); if (t) out.push(`*${t.replace(/\*/g, "")}*`); }
      }
      else if (tag === "IFRAME") { const src = n.getAttribute("src"); if (src) out.push(`[Open the embedded content](${fixUrl(src)})`); }
      else if (["DIV", "SECTION", "ARTICLE", "BLOCKQUOTE", "MAIN", "BODY", "CENTER"].includes(tag)) blocksOf(n, out);
      else if (["SCRIPT", "STYLE", "NOSCRIPT"].includes(tag)) continue;
      else { const t = tidy(inline(n)); if (t) out.push(t); }            // P, SPAN, A, IMG, ...
    }
  }
  function listLines(list, lines, depth) {
    let k = 0;
    for (const li of list.children) {
      if (li.tagName !== "LI") continue;
      k++;
      const own = [...li.childNodes].filter(c => !(c.nodeType === 1 && (c.tagName === "UL" || c.tagName === "OL"))).map(inline).join("");
      const t = tidy(own).replace(/\n+/g, " ");
      if (t) lines.push((list.tagName === "OL" ? `${k}. ` : "- ") + (depth ? "– " : "") + t);
      for (const sub of li.children) if (sub.tagName === "UL" || sub.tagName === "OL") listLines(sub, lines, depth + 1);
    }
  }
  function toMd(html) {
    html = String(html || "").replace(/<!--[\s\S]*?-->/g, "");
    const doc = new DOMParser().parseFromString(`<body>${html}</body>`, "text/html");
    const out = []; blocksOf(doc.body, out);
    // images marked inside paragraphs become their own paragraphs
    const md = out.join("\n\n").split(IMG).map(s => s.trim()).filter(Boolean).join("\n\n");
    return md.replace(/\n{3,}/g, "\n\n").trim();
  }
  const plain = md => md.replace(/!\[[^\]]*\]\([^)]*\)/g, "").replace(/\[([^\]]*)\]\(([^)]*)\)/g, "$1").replace(/\*\*?/g, "").replace(/\n{3,}/g, "\n\n").trim();
  function ytId(u) {
    const m = String(u).trim().match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/)|youtu\.be\/)([\w-]{11})/);
    return m ? m[1] : null;
  }
  function ytStart(u) {
    const m = String(u).match(/[?&#]t=([0-9hms]+)/); if (!m) return null;
    const t = m[1]; if (/^\d+$/.test(t)) return +t || null;
    const h = +(t.match(/(\d+)h/) || [0, 0])[1], mi = +(t.match(/(\d+)m/) || [0, 0])[1], s = +(t.match(/(\d+)s/) || [0, 0])[1];
    return (h * 3600 + mi * 60 + s) || null;
  }
  const slugify = t => dec(t).normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80).replace(/-+$/, "");

  function lessonSteps(l, report) {
    const title = dec(l.lesson_title).replace(/:\s*$/, "").trim().slice(0, 200) || "Lesson";
    const steps = [], extra = [];
    const vs = l.meta && l.meta.video_source;
    if (vs && String(vs.url || "").trim()) {
      const url = String(vs.url).trim(), id = vs.type === "youtube" ? ytId(url) : ytId(url);
      if (id) steps.push({ kind: "video", title, config: { youtube_id: id, start: ytStart(url), end: null } });
      else { extra.push(`Watch: [${url}](${fixUrl(url)})`); report.links++; }
    }
    const att = l.meta && l.meta.attachment && window.__media[l.meta.attachment];
    if (att && att.url) {
      if (att.mime === "application/pdf") steps.push({ kind: "pdf", title, config: { url: fixUrl(att.url), name: dec(att.title || "") + ".pdf" } });
      else { extra.push(`Download: [${dec(att.title || att.url.split("/").pop())}](${fixUrl(att.url)})`); report.downloads++; }
    }
    let md = toMd(l.lesson_content && (l.lesson_content.raw || l.lesson_content));
    if (extra.length) md = (extra.join("\n\n") + (md ? "\n\n" + md : "")).trim();
    if (md) steps.push({ kind: "text", title, config: { markdown: md } });
    report.images += (md.match(/!\[/g) || []).length;
    // tell steps of the same lesson apart
    if (steps.length > 1) steps.forEach(s => { s.title = (s.title + ({ video: "", pdf: " (PDF)", text: " (reading)" })[s.kind]).slice(0, 200); });
    if (!steps.length) report.empty.push(title);
    return steps;
  }
  function quizStep(qz, report) {
    const qs = [];
    for (const q of qz.questions) {
      let ans = q.answers.map(a => ({ t: ws(dec(String(a.t).replace(/<[^>]+>/g, ""))).trim(), ok: a.ok }));
      if (ans.length && ans.every(a => /^[a-hA-H][\)\.]\s/.test(a.t))) ans.sort((x, y) => x.t[0].toLowerCase().localeCompare(y.t[0].toLowerCase()));
      ans = ans.map(a => ({ t: a.t.replace(/^[a-hA-H][\)\.]\s+/, "").replace(/\s*;\s*$/, "").trim(), ok: a.ok })).filter(a => a.t);
      const correct = ans.map((a, i) => a.ok ? String(i) : null).filter(x => x !== null);
      let prompt = ws(dec(String(q.title).replace(/<[^>]+>/g, ""))).replace(/^\d+\s*[\.\-\)]+[\s\-]*/, "").trim();
      const more = ws(dec(String(q.content || "").replace(/<[^>]+>/g, " "))).trim();
      if (more) prompt += " " + more;
      if (ans.length < 2 || !correct.length) { report.skippedQuestions.push(prompt.slice(0, 80)); continue; }
      qs.push({ prompt: prompt.slice(0, 2000), kind: correct.length > 1 ? "multiple" : "single", options: ans.map(a => a.t), correct });
    }
    report.questions += qs.length;
    return { kind: "quiz", title: dec(qz.title || "Quiz").slice(0, 200), questions: qs };
  }
  function build(courseId, projectId, usedSlugs) {
    const c = window.__old.courses[courseId];
    const report = { course: dec(c.title.raw), lectures: 0, steps: 0, videos: 0, pdfs: 0, texts: 0, quizzes: 0, questions: 0,
                     images: 0, links: 0, downloads: 0, empty: [], skippedQuestions: [] };
    let slug = slugify(c.title.raw), n = 2;
    while (usedSlugs.has(slug)) slug = slugify(c.title.raw).slice(0, 76) + "-" + n++;
    usedSlugs.add(slug);
    const descMd = toMd(c.content && c.content.raw);
    const desc = plain(descMd).slice(0, 10000);
    const firstPara = desc.split(/\n\s*\n/)[0] || "";
    const summary = (firstPara.length > 480 ? firstPara.slice(0, firstPara.lastIndexOf(" ", 470)) + "…" : firstPara) || null;
    const lv = (c.meta.academy_course_difficulty_level || "").toLowerCase();
    let pass = null;
    const lectures = (c.meta.academy_course_curriculum || []).map((t, i) => {
      const steps = [];
      for (const it of (t.topics || [])) {
        if (it.type === "lesson" && window.__old.lessons[it.id]) steps.push(...lessonSteps(window.__old.lessons[it.id], report));
        else if (it.type === "quiz" && window.__qz.quizzes[it.id]) {
          const qz = window.__qz.quizzes[it.id]; if (pass == null && qz.pass) pass = +qz.pass;
          steps.push(quizStep(qz, report));
        }
      }
      report.lectures++;
      return { title: (dec(t.title || "").trim() || `Part ${i + 1}`).slice(0, 200), summary: plain(toMd(t.content || "")).slice(0, 4000) || null, steps };
    }).filter(l => l.steps.length);
    for (const l of lectures) for (const s of l.steps) { report.steps++; report[{ video: "videos", pdf: "pdfs", text: "texts", quiz: "quizzes" }[s.kind]]++; }
    const payload = {
      slug, project_id: projectId, title: dec(c.title.raw).trim().slice(0, 200), summary, description: desc || null, outcomes: [],
      image_url: c.__image || null, level: { beginner: "beginner", intermediate: "intermediate", expert: "advanced", advanced: "advanced" }[lv] || null,
      language: "English", pass_score: pass && pass >= 0 && pass <= 100 ? pass : 70,
      status: c.status === "publish" ? "published" : "draft", lectures,
    };
    return { payload, report };
  }
  return { toMd, build, ytId, ytStart, slugify };
})();
"MIG ready";
