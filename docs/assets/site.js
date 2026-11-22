/* CloudEARTHi MOOC: student website.
   Reads and writes the MOOC database through its mooc_* functions with the publishable key; every call that concerns
   a student carries their Octa session token, and the database checks it. Right answers never reach the browser. */
"use strict";

const CFG = {
  db: "https://uxqeukvmnfvpgsxktgvo.supabase.co",
  key: "sb_publishable_oFEaDte2Hy-gGsqpa9kWeQ_HuMm6dou",   // publishable key: meant for web pages
  studio: "https://cloudearthi-mooc.streamlit.app/",
  app: "octa_mooc",
  mailer: "https://uxqeukvmnfvpgsxktgvo.supabase.co/functions/v1/mooc-mail",   // award emails and password links
};
const TOKEN_KEY = "cloudearthi_mooc_session";

// ------------------------------------------------------------------------------------------------ small helpers
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const mmss = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
const fullName = u => [u.first_name, u.last_name].filter(Boolean).join(" ") || u.username || "";
const initials = u => (fullName(u).split(/\s+/).map(w => w[0]).join("").slice(0, 2) || "?").toUpperCase();
const plural = (n, w) => `${n} ${w}${n === 1 ? "" : "s"}`;
const store = {
  get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch (e) { /* private mode */ } },
};

async function api(fn, args = {}) {
  let r;
  try {
    r = await fetch(`${CFG.db}/rest/v1/rpc/${fn}`, {
      method: "POST", body: JSON.stringify(args),
      headers: { apikey: CFG.key, Authorization: `Bearer ${CFG.key}`, "Content-Type": "application/json" },
    });
  } catch (e) { throw new Error("The MOOC cannot be reached. Check your internet connection and try again."); }
  const text = await r.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (e) { /* not JSON */ }
  if (!r.ok) throw new Error((data && data.message) || `The MOOC answered with an error (${r.status}).`);
  return data;
}

function toast(text, ms = 3200) {
  const t = document.createElement("div");
  t.className = "toast"; t.setAttribute("role", "status"); t.textContent = text;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), ms);
}

const ICON = {
  video: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M10 9l5 3-5 3z" fill="currentColor"/></svg>',
  pdf: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4M9 13h6M9 17h6"/></svg>',
  text: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 6h14M5 11h14M5 16h9"/></svg>',
  quiz: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 015 .5c0 1.7-2.5 2-2.5 4M12 17.5v.5"/></svg>',
  assignment: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 15V4M8 8l4-4 4 4"/><path d="M5 14v5h14v-5"/></svg>',
  live: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="9" cy="9" r="3"/><circle cx="17" cy="10" r="2.4"/><path d="M3 19c.8-3.2 3.2-5 6-5s5.2 1.8 6 5M14.5 15.5c2.6-.4 5.4.8 6.5 3.5"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><circle cx="12" cy="12" r="10" stroke-width="2"/><path d="M7.5 12.5l3 3 6-6.5"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>',
};
const KIND = { video: "Video", pdf: "Reading", text: "Reading", quiz: "Quiz", assignment: "Assignment", live: "Live session" };

// ------------------------------------------------------------------------------------------------ contour artwork
// Deterministic "map" drawings: concentric wobbly rings around a few peaks. Used for the hero and for course covers.
function rng(seed) { let s = 0; for (const ch of String(seed)) s = (s * 31 + ch.charCodeAt(0)) >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }
function ring(cx, cy, r, wob, phase) {
  const pts = [];
  for (let i = 0; i <= 48; i++) {
    const a = (i / 48) * Math.PI * 2;
    const k = 1 + wob * (Math.sin(3 * a + phase) * .55 + Math.sin(5 * a + phase * 1.7) * .3 + Math.sin(2 * a - phase) * .25);
    pts.push([cx + Math.cos(a) * r * k * 1.25, cy + Math.sin(a) * r * k * .85]);
  }
  return "M" + pts.map(p => p.map(n => n.toFixed(1)).join(",")).join("L") + "Z";
}
function contours(w, h, seed, peaks, rings) {
  const rand = rng(seed); let out = "";
  for (let p = 0; p < peaks.length; p++) {
    const [px, py, size] = peaks[p];
    const phase = rand() * 6;
    for (let i = 1; i <= rings; i++) {
      const r = (size / rings) * i;
      out += `<path class="c${i % 4 === 0 ? " k" : ""}" d="${ring(px * w, py * h, r, .08 + i * .012, phase + i * .07)}"/>`;
    }
  }
  return out;
}
const COVER_TONES = [["#e8f3dd", "#5c9e2e", "#b3d98f"], ["#e2f3ec", "#1e9b73", "#9fd6c0"], ["#fdf3e0", "#c98a12", "#f0d08f"], ["#e6f0f8", "#2a78d6", "#a9c8eb"]];
function coverArt(seed) {
  const rand = rng(seed); const [bg, strong, soft] = COVER_TONES[Math.floor(rand() * COVER_TONES.length)];
  const peaks = [[.25 + rand() * .2, .35 + rand() * .3, 120], [.7 + rand() * .2, .55 + rand() * .3, 95]];
  const paths = contours(400, 225, seed, peaks, 9).replace(/class="c k"/g, `stroke="${strong}" stroke-width="1.6" fill="none"`)
    .replace(/class="c"/g, `stroke="${soft}" stroke-width="1.2" fill="none"`);
  return `<svg viewBox="0 0 400 225" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><rect width="400" height="225" fill="${bg}"/>${paths}
    <circle cx="${(peaks[0][0] * 400).toFixed(0)}" cy="${(peaks[0][1] * 225).toFixed(0)}" r="6" fill="${strong}"/></svg>`;
}
function cover(c) { return c.image_url ? `<img src="${esc(c.image_url)}" alt="" loading="lazy">` : coverArt(c.slug || c.id); }

// ------------------------------------------------------------------------------------------------ session
const S = { token: store.get(TOKEN_KEY), me: null, mine: null, catalogue: null };

async function loadSession() {
  if (!S.token) return;
  try {
    const r = await api("octa_user_session", { p_token: S.token, p_app: CFG.app });
    if (r && r.ok) S.me = r.user; else signOutLocal();
  } catch (e) { /* offline: keep the token, try again later */ }
}
function signOutLocal() { S.token = null; S.me = null; S.mine = null; store.set(TOKEN_KEY, null); }
async function myLearning(force = false) {
  if (!S.token) return null;
  if (S.mine && !force) return S.mine;
  const r = await api("mooc_my_learning", { p_token: S.token });
  if (!r.ok) { signOutLocal(); return null; }
  S.mine = r; return r;
}
function header() {
  $("#nav-my").classList.toggle("hidden", !S.me);
  const box = $("#account");
  if (!S.me) {
    box.innerHTML = `<a class="btn ghost" href="#/join">Create account</a><a class="btn" href="#/signin">Sign in</a>`;
    return;
  }
  box.innerHTML = `<div class="menu"><button class="avatar" aria-haspopup="true" aria-expanded="false" title="${esc(fullName(S.me))}">${esc(initials(S.me))}</button>
    <div class="menu-panel hidden" role="menu">
      <div class="who"><b>${esc(fullName(S.me))}</b><div class="muted small">${esc(S.me.username)}</div></div>
      <a href="#/my" role="menuitem">My learning</a>
      <a href="profile.html?u=${encodeURIComponent(S.me.username)}" target="_blank" rel="noopener" role="menuitem">My public profile</a>
      <button data-signout role="menuitem">Sign out</button></div></div>`;
  const btn = $(".avatar", box), panel = $(".menu-panel", box);
  btn.onclick = e => { e.stopPropagation(); panel.classList.toggle("hidden"); btn.setAttribute("aria-expanded", String(!panel.classList.contains("hidden"))); };
  document.addEventListener("click", () => panel.classList.add("hidden"), { once: true });
  $("[data-signout]", box).onclick = async () => {
    try { await api("octa_user_logout", { p_token: S.token, p_app: CFG.app }); } catch (e) { /* already gone */ }
    signOutLocal(); location.hash = "#/"; toast("You are signed out.");
  };
}

async function projectsMenu(current) {
  const box = $("#nav-projects");
  if (!box) return;
  let cat;
  try { cat = await catalogue(); } catch (e) { box.innerHTML = ""; return; }
  const list = projectList(cat);
  if (!list.length) { box.innerHTML = ""; return; }
  box.innerHTML = `<button class="navbtn${current ? " on" : ""}" aria-haspopup="true" aria-expanded="false">Projects
      <svg viewBox="0 0 20 20" width="14" height="14" aria-hidden="true"><path d="M5 8l5 5 5-5" fill="none" stroke="currentColor" stroke-width="2"/></svg></button>
    <div class="menu-panel left hidden" role="menu">
      <a href="#/" role="menuitem">All courses <span class="muted">${cat.courses.length}</span></a>
      ${list.map(p => `<a href="#/project/${encodeURIComponent(p.slug)}" role="menuitem" ${current === p.slug ? 'aria-current="page"' : ""}>${esc(p.title)} <span class="muted">${p.n}</span></a>`).join("")}</div>`;
  const btn = $("button", box), panel = $(".menu-panel", box);
  const close = () => { panel.classList.add("hidden"); btn.setAttribute("aria-expanded", "false"); };
  btn.onclick = e => {
    e.stopPropagation(); const open = panel.classList.toggle("hidden") === false;
    btn.setAttribute("aria-expanded", String(open));
    if (open) { $("a", panel).focus(); document.addEventListener("click", close, { once: true }); }
  };
  panel.onkeydown = e => { if (e.key === "Escape") { close(); btn.focus(); } };
  $$("a", panel).forEach(a => (a.onclick = close));
}

// ------------------------------------------------------------------------------------------------ router
let cleanup = null;
function parseHash() {
  const raw = location.hash.replace(/^#/, "") || "/";
  const [path, query] = raw.split("?");
  return { parts: path.split("/").filter(Boolean).map(decodeURIComponent), q: new URLSearchParams(query || "") };
}
async function route() {
  if (cleanup) { cleanup(); cleanup = null; }
  const { parts, q } = parseHash();
  const view = $("#view");
  $$(".nav a").forEach(a => a.classList.toggle("on", (a.dataset.nav === "home" && !parts.length) || (a.dataset.nav === "my" && parts[0] === "my")));
  header();
  projectsMenu(parts[0] === "project" ? parts[1] : null);
  try {
    if (!parts.length) await viewHome(view);
    else if (parts[0] === "course" && parts[1]) await viewCourse(view, parts[1]);
    else if (parts[0] === "learn" && parts[1]) await viewLearn(view, parts[1], parts[2]);
    else if (parts[0] === "my") await viewMy(view);
    else if (parts[0] === "project" && parts[1]) await viewProject(view, parts[1]);
    else if (parts[0] === "signin") viewSignIn(view, q.get("next"));
    else if (parts[0] === "join") viewJoin(view, q.get("next"));
    else if (parts[0] === "welcome") await viewWelcome(view, q.get("t"), q.get("r") === "1");
    else if (parts[0] === "forgot") viewForgot(view, q.get("email"));
    else view.innerHTML = `<div class="wrap auth"><div class="box"><h1>Page not found</h1><p class="muted">This address does not lead to a page of the MOOC.</p><a class="btn" href="#/">See all courses</a></div></div>`;
  } catch (e) {
    view.innerHTML = `<div class="wrap auth"><div class="box"><h1>Something went wrong</h1><div class="msg bad">${esc(e.message)}</div>
      <button class="btn" onclick="location.reload()">Try again</button></div></div>`;
  }
  if (!parts.length || parts[0] !== "learn") window.scrollTo(0, 0);
}
window.addEventListener("hashchange", route);
function needSignIn(next) { location.hash = `#/signin?next=${encodeURIComponent(next)}`; }

// ------------------------------------------------------------------------------------------------ home: the catalogue
function heroMap() {
  const w = 1400, h = 560;
  const peaks = [[.78, .30, 330], [.97, .82, 230], [.52, .95, 170], [.12, .12, 150]];
  const route = "M735,548 C800,520 790,450 850,410 S960,330 990,270 S1040,190 1092,170";
  return `<svg class="map" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
    ${contours(w, h, "cloudearthi", peaks, 14)}
    <path class="route" d="${route}"/>
    <path class="route-draw" d="${route}" style="stroke-dasharray:700 700;stroke-dashoffset:0;--len:-700"/>
    <circle class="pin" cx="735" cy="548" r="9"/>
    <g class="summit-g"><path class="summit" d="M1092,138 l20,34 h-40z"/><circle class="pin" cx="1092" cy="170" r="9"/></g>
  </svg>`;
}
function courseCard(c, mineById) {
  const m = mineById && mineById[c.id];
  const pct = m && m.steps ? Math.round(100 * m.done / m.steps) : 0;
  const facts = [];
  if (m) facts.push(m.certificate ? `<span class="fact prize">Certificate earned</span>` : `<span class="fact done">${pct}% done</span>`);
  if (c.level) facts.push(`<span class="fact">${esc(c.level[0].toUpperCase() + c.level.slice(1))}</span>`);
  if (c.lectures) facts.push(`<span class="fact">${plural(c.lectures, "lecture")}</span>`);
  if (c.hours) facts.push(`<span class="fact">${esc(String(+c.hours))} h</span>`);
  if (c.language && c.language !== "English") facts.push(`<span class="fact">${esc(c.language)}</span>`);
  return `<a class="card" href="#/course/${encodeURIComponent(c.slug)}" data-search="${esc((c.title + " " + (c.summary || "")).toLowerCase())}">
    <div class="cover">${cover(c)}</div>
    <div class="body"><h3>${esc(c.title)}</h3>${c.summary ? `<div class="sum">${esc(c.summary)}</div>` : ""}<div class="facts">${facts.join("")}</div></div></a>`;
}
async function catalogue() { if (!S.catalogue) S.catalogue = await api("mooc_catalogue"); return S.catalogue; }
function groups(cat) {
  const byProject = {};
  cat.courses.forEach(c => (byProject[c.project_id || ""] ||= []).push(c));
  return byProject;
}
// the projects that have courses, in their order, plus "Other courses" for courses without a project
function projectList(cat) {
  const by = groups(cat);
  const list = cat.projects.filter(p => by[p.id]).map(p => ({ slug: p.slug, title: p.title, n: by[p.id].length }));
  if (by[""] && list.length) list.push({ slug: "other", title: "Other courses", n: by[""].length });
  return list;
}
function chips(cat, current) {
  const list = projectList(cat);
  if (!list.length) return "";
  const chip = (href, title, n, on) => `<a class="chip${on ? " on" : ""}" href="${href}"${on ? ' aria-current="page"' : ""}>${esc(title)}<span class="n">${n}</span></a>`;
  return `<nav class="chips wrap" aria-label="Courses by project">
    ${chip("#/", "All courses", cat.courses.length, !current)}
    ${list.map(p => chip(`#/project/${encodeURIComponent(p.slug)}`, p.title, p.n, current === p.slug)).join("")}</nav>`;
}
async function viewProject(view, slug) {
  const [cat, mine] = await Promise.all([catalogue(), S.token ? myLearning().catch(() => null) : null]);
  const mineById = {}; (mine?.courses || []).forEach(c => (mineById[c.id] = c));
  const by = groups(cat);
  const p = slug === "other" ? { slug: "other", title: "Other courses", description: "Courses that are not part of a project.", id: "" }
                             : cat.projects.find(x => x.slug === slug);
  if (!p) {
    view.innerHTML = `${chips(cat, null)}<div class="wrap auth"><div class="box"><h1>Project not found</h1>
      <p class="muted">There is no project with this address on the MOOC.</p><a class="btn" href="#/">See all courses</a></div></div>`;
    return;
  }
  const courses = by[p.id] || [];
  const about = (p.description || "").split(/\n\s*\n/).map(x => x.trim()).filter(Boolean);
  document.title = `${p.title}: CloudEARTHi MOOC`;
  view.innerHTML = `
    <section class="project-hero"><div class="wrap">
      <div class="crumbs"><a href="#/">All courses</a> / ${esc(p.title)}</div>
      <div class="project-band">
        ${slug !== "other" ? `<div class="logo big">${p.image_url ? `<img src="${esc(p.image_url)}" alt="${esc(p.title)} logo">` : coverArt(p.slug)}</div>` : ""}
        <div><h1>${esc(p.title)}</h1>
          ${about.map(x => `<p class="lead">${esc(x)}</p>`).join("")}
          <div class="row">${p.website ? `<a class="btn quiet" href="${esc(p.website)}" target="_blank" rel="noopener">Visit the project website</a>` : ""}
            <span class="muted">${plural(courses.length, "course")}</span></div></div>
      </div></div></section>
    ${chips(cat, slug)}
    <section class="section" style="padding-top:20px"><div class="wrap">
      ${courses.length ? `<div class="grid">${courses.map(c => courseCard(c, mineById)).join("")}</div>`
                       : `<div class="empty">This project has no open courses yet.</div>`}</div></section>
    <div style="height:70px"></div>`;  const row = $(".chips", view), on = $(".chip.on", view);         // phones: show the chosen project in the row
  if (row && on && row.scrollWidth > row.clientWidth) row.scrollLeft = on.offsetLeft - (row.clientWidth - on.offsetWidth) / 2;
}

async function viewHome(view) {
  document.title = "CloudEARTHi MOOC";
  const [cat, mine] = await Promise.all([catalogue(), S.token ? myLearning().catch(() => null) : null]);
  const mineById = {}; (mine?.courses || []).forEach(c => (mineById[c.id] = c));
  const byProject = groups(cat);
  const sections = cat.projects.filter(p => byProject[p.id]).map(p => {
    const about = (p.description || "").split(/\n\s*\n/).map(s => s.trim()).filter(Boolean);
    const short = (about[1] || about[0] || "").slice(0, 300);
    return `<section class="section" id="p-${esc(p.slug)}" data-group>
      <div class="wrap">
        <div class="project-head">
          <div class="logo">${p.image_url ? `<img src="${esc(p.image_url)}" alt="${esc(p.title)} logo">` : coverArt(p.slug)}</div>
          <div><h2><a href="#/project/${encodeURIComponent(p.slug)}" style="color:inherit;text-decoration:none">${esc(p.title)}</a></h2>${short ? `<p>${esc(short)}${short.length >= 300 ? "…" : ""}</p>` : ""}</div>
          <a class="btn quiet site" href="#/project/${encodeURIComponent(p.slug)}">All ${esc(p.title)} courses</a>
        </div>
        <div class="grid">${byProject[p.id].map(c => courseCard(c, mineById)).join("")}</div>
      </div></section>`;
  });
  if (byProject[""]) sections.push(`<section class="section" data-group><div class="wrap">
      <div class="project-head" style="grid-template-columns:1fr"><div><h2>${sections.length ? "More courses" : "Courses"}</h2></div></div>
      <div class="grid">${byProject[""].map(c => courseCard(c, mineById)).join("")}</div></div></section>`);
  const next = (mine?.courses || []).find(c => c.next_step);
  view.innerHTML = `
    <section class="hero">${heroMap()}
      <div class="wrap">
        <h1>Courses from Europe's research and innovation projects</h1>
        <p class="lead">Free and online. Watch, answer and practise at your own pace, and earn certificates you can share.</p>
        <label class="search"><span class="sr">Search courses</span>${ICON.search}<input id="q" type="search" placeholder="Search courses" autocomplete="off"></label>
      </div>
    </section>
    ${next ? `<div class="wrap continue"><div class="panel">
        <div class="t"><div class="muted small">Pick up where you left off</div><h3>${esc(next.title)}</h3>
          <div class="bar" style="margin-top:8px;max-width:340px"><i style="width:${Math.round(100 * next.done / Math.max(next.steps, 1))}%"></i></div></div>
        <a class="btn big" href="#/learn/${encodeURIComponent(next.slug)}/${next.next_step}">Continue learning</a></div></div>` : ""}
    ${chips(cat, null)}
    ${sections.join("") || `<section class="section"><div class="wrap"><div class="empty">No courses are open yet. Come back soon.</div></div></section>`}
    <div class="wrap"><div class="empty hidden" id="nohit" style="margin-top:40px">No course matches your search.</div></div>
    <div style="height:70px"></div>`;
  $("#q").addEventListener("input", e => {
    const t = e.target.value.trim().toLowerCase(); let hits = 0;
    $$(".card[data-search]").forEach(c => { const show = !t || c.dataset.search.includes(t); c.classList.toggle("hidden", !show); hits += show; });
    $$("[data-group]").forEach(g => g.classList.toggle("hidden", !$$(".card:not(.hidden)", g).length));
    $("#nohit").classList.toggle("hidden", hits > 0);
  });
}

// ------------------------------------------------------------------------------------------------ course page
let VIEW = null;                // the mooc_course_view answer for the open course
const allSteps = () => (VIEW?.lectures || []).flatMap(l => l.steps.map(s => ({ ...s, lecture: l })));
const stepById = id => allSteps().find(s => s.id === id);
const isDone = s => !!(s.progress && s.progress.completed);

async function loadCourse(slug) {
  const r = await api("mooc_course_view", { p_token: S.token || "", p_slug: slug });
  if (!r.ok) throw new Error(r.error || "This course cannot be opened.");
  VIEW = r; return r;
}
function badgeNeeds(b) {
  const nums = (VIEW.lectures || []).map((l, i) => (b.lecture_ids || []).includes(l.id) ? i + 1 : null).filter(Boolean);
  const which = !nums.length ? "all lectures"
    : nums.length === 1 ? `lecture ${nums[0]}` : `lectures ${nums.slice(0, -1).join(", ")} and ${nums[nums.length - 1]}`;
  return `Finish ${which} with a score of at least ${b.min_score}%.`;
}
async function viewCourse(view, slug) {
  const v = await loadCourse(slug), c = v.course;
  const steps = allSteps(), done = steps.filter(isDone).length, pct = steps.length ? Math.round(100 * done / steps.length) : 0;
  const first = steps.find(s => !isDone(s)) || steps[0];
  let action;
  if (!S.me) action = `<a class="btn big block" href="#/join?next=${encodeURIComponent("/course/" + slug)}">Create a free account</a>
      <p class="small muted" style="margin:10px 0 0;text-align:center">Already have an Octa account? <a href="#/signin?next=${encodeURIComponent("/course/" + slug)}">Sign in</a></p>`;
  else if (!v.enrolled) action = `<button class="btn big block" id="enrol">Start this course</button>
      <p class="small muted" style="margin:10px 0 0;text-align:center">Free. You can start straight away.</p>`;
  else action = `<div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:6px"><b>Your progress</b><span class="muted">${done} of ${steps.length} steps</span></div>
      <div class="bar ${pct === 100 ? "done" : ""}" style="margin-bottom:16px"><i style="width:${pct}%"></i></div>
      ${first ? `<a class="btn big block" href="#/learn/${encodeURIComponent(slug)}/${first.id}">${done ? (pct === 100 ? "Review the course" : "Continue learning") : "Start the first lecture"}</a>` : ""}`;
  const facts = [c.level && c.level[0].toUpperCase() + c.level.slice(1), v.lectures.length && plural(v.lectures.length, "lecture"),
    c.hours && `${+c.hours} hours`, c.language].filter(Boolean).map(f => `<span class="fact">${esc(f)}</span>`).join("");
  const prizes = (v.badges || []).map(b => `<div class="prize-row"><div class="seal">${b.image_url ? `<img src="${esc(b.image_url)}" alt="">` : (b.kind === "certificate" ? "📜" : "🏅")}</div>
      <div><b>${esc(b.title)}</b><div class="small muted">${b.award_id ? `<a href="award.html?id=${b.award_id}" target="_blank" rel="noopener">You earned it: see and share</a>` : badgeNeeds(b)}</div></div></div>`).join("");
  const paragraphs = (c.description || "").split(/\n\s*\n/).map(s => s.trim()).filter(Boolean).map(s => `<p>${esc(s).replace(/\n/g, "<br>")}</p>`).join("");
  const outcomes = (c.outcomes || []).map(o => `<li>${ICON.check}<span>${esc(o)}</span></li>`).join("");
  const stages = v.lectures.map((l, i) => {
    const ldone = l.steps.length && l.steps.every(isDone);
    return `<li class="stage ${ldone ? "done" : ""}"><div class="marker">${ldone ? "✓" : i + 1}</div>
      <h3>${esc(l.title)}</h3>${l.summary ? `<div class="about">${esc(l.summary)}</div>` : ""}
      <ul class="steps">${l.steps.map(s => `<li class="${isDone(s) ? "done" : ""} ${v.enrolled ? "link" : ""}" ${v.enrolled ? `data-go="${s.id}" tabindex="0"` : ""}>
        ${isDone(s) ? ICON.check.replace("<svg", '<svg class="ic"') : ICON[s.kind] || ""}<span>${esc(s.title)}</span><span class="kind">${KIND[s.kind] || ""}</span></li>`).join("")}</ul></li>`;
  }).join("");
  view.innerHTML = `
    <section class="course-hero"><div class="wrap">
      <div class="crumbs"><a href="#/">All courses</a>${c.project ? ` / <a href="#/project/${encodeURIComponent(c.project.slug)}">${esc(c.project.title)}</a>` : ""}</div>
      <h1>${esc(c.title)}</h1>${c.summary ? `<p class="lead">${esc(c.summary)}</p>` : ""}<div class="facts">${facts}</div>
    </div></section>
    <div class="wrap course-layout">
      <div>
        ${paragraphs ? `<h2 style="margin-bottom:12px">About this course</h2>${paragraphs}` : ""}
        ${outcomes ? `<h2 style="margin:30px 0 14px">What you will be able to do</h2><ul class="outcomes">${outcomes}</ul>` : ""}
        <h2 style="margin:34px 0 18px">Your route through the course</h2>
        ${stages ? `<ol class="route">${stages}</ol>` : `<div class="empty">The lectures of this course are being prepared.</div>`}
      </div>
      <aside class="side">
        <div class="box"><div class="cover">${cover(c)}</div>${action}<div id="enrol-msg"></div></div>
        ${prizes ? `<div class="box"><h3>Badges and certificate</h3>${prizes}</div>` : ""}
      </aside>
    </div>`;
  const enrol = $("#enrol");
  if (enrol) enrol.onclick = async () => {
    enrol.disabled = true;
    try {
      await api("mooc_join", { p_token: S.token, p_kind: "student" }).catch(() => null);
      const r = await api("mooc_enrol", { p_token: S.token, p_course: c.id });
      if (!r.ok) throw new Error(r.error);
      S.mine = null;
      const v2 = await loadCourse(slug); const s1 = allSteps()[0];
      toast("You are enrolled. Enjoy the course!");
      location.hash = s1 ? `#/learn/${encodeURIComponent(slug)}/${s1.id}` : `#/course/${encodeURIComponent(slug)}`;
      if (!s1) route();
    } catch (e) { $("#enrol-msg").innerHTML = `<div class="msg bad" style="margin-top:12px">${esc(e.message)}</div>`; enrol.disabled = false; }
  };
  $$("[data-go]").forEach(li => {
    const go = () => (location.hash = `#/learn/${encodeURIComponent(slug)}/${li.dataset.go}`);
    li.onclick = go; li.onkeydown = e => { if (e.key === "Enter") go(); };
  });
}

// ------------------------------------------------------------------------------------------------ learning
let player = null, poll = null;
function stopPlayer() {
  clearInterval(poll); poll = null;
  if (player && player.destroy) { try { player.destroy(); } catch (e) { /* gone */ } }
  player = null;
}
let ytQueue = [];
function withYouTube(fn) {
  if (window.YT && YT.Player) return fn();
  ytQueue.push(fn);
  if (ytQueue.length > 1) return;
  window.onYouTubeIframeAPIReady = () => { ytQueue.forEach(f => f()); ytQueue = []; };
  const s = document.createElement("script"); s.src = "https://www.youtube.com/iframe_api"; document.head.appendChild(s);
}
async function record(step, verb, position = null, data = {}) {
  const r = await api("mooc_record", { p_token: S.token, p_step: step.id, p_verb: verb, p_position: position, p_data: data });
  if (r && r.ok) celebrate(r.awarded);
  return r || { ok: false };
}
function celebrate(list) {
  (list || []).forEach((a, i) => setTimeout(() => {
    const d = document.createElement("div");
    d.className = "celebrate"; d.setAttribute("role", "dialog"); d.setAttribute("aria-modal", "true");
    d.innerHTML = `<div class="box"><div class="seal">${a.image_url ? `<img src="${esc(a.image_url)}" alt="">` : (a.kind === "certificate" ? "📜" : "🏅")}</div>
      <h2>${a.kind === "certificate" ? "You earned the certificate" : "You earned a badge"}</h2>
      <p class="muted" style="margin:8px 0 20px">${esc(a.title)}</p>
      <a class="btn block" href="award.html?id=${a.award_id}" target="_blank" rel="noopener">See it with your name and share it</a>
      <button class="btn quiet block" style="margin-top:10px" data-close>Keep learning</button></div>`;
    document.body.appendChild(d);
    const close = () => d.remove();
    $("[data-close]", d).onclick = close; d.onclick = e => { if (e.target === d) close(); };
    $("[data-close]", d).focus();
    S.mine = null;
  }, i * 400));
}

async function viewLearn(view, slug, stepId) {
  if (!S.me) return needSignIn(`/learn/${slug}${stepId ? "/" + stepId : ""}`);
  await loadCourse(slug);
  if (!VIEW.enrolled) { location.hash = `#/course/${encodeURIComponent(slug)}`; return; }
  const steps = allSteps();
  if (!steps.length) { location.hash = `#/course/${encodeURIComponent(slug)}`; return; }
  const step = stepById(stepId) || steps.find(s => !isDone(s)) || steps[0];
  if (step.id !== stepId) { history.replaceState(null, "", `#/learn/${encodeURIComponent(slug)}/${step.id}`); }
  view.innerHTML = `<div class="learn"><aside class="rail" aria-label="Course route"></aside><section class="stage-main" id="stage"></section></div>`;
  drawRail(slug, step.id);
  openStep(slug, step);
  cleanup = stopPlayer;
}
function drawRail(slug, currentId) {
  const steps = allSteps(), done = steps.filter(isDone).length, pct = Math.round(100 * done / Math.max(steps.length, 1));
  const max = VIEW.course.max_retakes || 0;
  $(".rail").innerHTML = `<a class="ctitle" href="#/course/${encodeURIComponent(slug)}">${esc(VIEW.course.title)}</a>
    <div class="bar ${pct === 100 ? "done" : ""}"><i style="width:${pct}%"></i></div>
    <div class="small muted" style="margin-top:6px">${done} of ${steps.length} steps done</div>
    ${VIEW.lectures.map((l, i) => {
      const started = l.steps.some(s => s.progress), left = max ? Math.max(0, max - (l.retakes_used || 0)) : Infinity;
      return `<div class="lec"><div class="lec-t">${i + 1}. ${esc(l.title)}</div><ul class="way">
        ${l.steps.map(s => `<li class="${isDone(s) ? "done" : ""} ${s.id === currentId ? "on" : ""}"><span class="dot"></span>
          <button data-step="${s.id}" ${s.id === currentId ? 'aria-current="step"' : ""}>${esc(s.title)}<span class="k">${KIND[s.kind] || ""}${isDone(s) ? ", done" : ""}</span></button></li>`).join("")}
        </ul>${started || l.retakes_used ? `<div class="redo"><button data-redo="${l.id}" ${left === 0 || !started ? "disabled" : ""}>Redo this lecture</button>
          <span class="muted">${left === Infinity ? "" : ` ${plural(left, "retake")} left`}</span></div>` : ""}</div>`;
    }).join("")}`;
  $$(".rail [data-step]").forEach(b => (b.onclick = () => (location.hash = `#/learn/${encodeURIComponent(slug)}/${b.dataset.step}`)));
  $$(".rail [data-redo]").forEach(b => (b.onclick = async () => {
    const l = VIEW.lectures.find(x => x.id === b.dataset.redo);
    if (!confirm(`Redo "${l.title}"? Your answers there start again, so you see every question again. Your best score is kept, and badges you earned stay yours.`)) return;
    const r = await api("mooc_retake", { p_token: S.token, p_lecture: l.id, p_course: null });
    if (!r.ok) return toast(r.error, 5000);
    S.mine = null; await loadCourse(slug); toast("Ready for a new try. Start again from the first step.");
    location.hash = `#/learn/${encodeURIComponent(slug)}/${l.steps[0].id}`;
  }));
}
async function refreshAfter(slug, step, goNext) {
  await loadCourse(slug);
  const steps = allSteps(), i = steps.findIndex(s => s.id === step.id);
  if (goNext && i >= 0 && i < steps.length - 1) location.hash = `#/learn/${encodeURIComponent(slug)}/${steps[i + 1].id}`;
  else { drawRail(slug, step.id); openStep(slug, stepById(step.id)); }
}
async function complete(slug, step) {
  const r = await record(step, "completed");
  if (!r.ok) return toast(r.error || "This step could not be saved.", 5000);
  toast("Step completed");
  refreshAfter(slug, step, true);
}
function stepNav(slug, step) {
  const steps = allSteps(), i = steps.findIndex(s => s.id === step.id);
  const prev = steps[i - 1], next = steps[i + 1];
  return `<nav class="stepnav" aria-label="Steps">
    ${prev ? `<a class="btn quiet" href="#/learn/${encodeURIComponent(slug)}/${prev.id}">Previous step</a>` : "<span></span>"}
    ${next ? `<a class="btn ghost" href="#/learn/${encodeURIComponent(slug)}/${next.id}">Next step</a>`
           : `<a class="btn ghost" href="#/course/${encodeURIComponent(slug)}">Back to the course page</a>`}</nav>`;
}
function openStep(slug, step) {
  stopPlayer();
  const box = $("#stage"), cfg = step.config || {}, done = isDone(step);
  const head = `<div class="where">${esc(step.lecture.title)}</div><h1>${esc(step.title)} ${done ? `<span class="done-chip">${ICON.check.replace('<svg', '<svg width="16" height="16"')} Done</span>` : ""}</h1>`;
  record(step, "opened").catch(() => null);
  const render = { video: stepVideo, pdf: stepPdf, text: stepText, quiz: stepQuiz, assignment: stepAssignment, live: stepLive }[step.kind];
  box.innerHTML = head + `<div id="content"></div>` + stepNav(slug, step);
  if (render) render($("#content"), slug, step, cfg);
  $("#stage").focus?.();
}

// one question: on a video, a PDF or in a quiz
function question(el, q, onRight, where = "") {
  const multi = q.kind === "multiple", chosen = new Set();
  el.innerHTML = `${where ? `<div class="small muted">${esc(where)}</div>` : ""}<div class="q">${esc(q.prompt)}</div>
    ${multi ? `<div class="small muted" style="margin:-6px 0 6px">Choose all answers that apply.</div>` : ""}
    ${q.options.map((o, i) => `<button class="opt" data-i="${i}">${esc(o)}</button>`).join("")}
    ${multi ? `<button class="btn" data-check style="margin-top:6px">Check my answer</button>` : ""}<div class="feedback" aria-live="polite"></div>`;
  const fb = $(".feedback", el);
  const send = async () => {
    const r = await api("mooc_answer", { p_token: S.token, p_question: q.id, p_answer: [...chosen] });
    if (!r.ok) { fb.className = "feedback bad"; fb.textContent = r.error; return; }
    celebrate(r.awarded);
    if (r.correct) {
      fb.className = "feedback ok"; fb.textContent = "Right. " + (r.explanation || "");
      $$(".opt", el).forEach(b => { b.disabled = true; if (chosen.has(b.dataset.i)) b.classList.add("right"); });
      const c = $("[data-check]", el); if (c) c.disabled = true;
      setTimeout(() => onRight(r), 900);
    } else if (q.must_pass) {
      fb.className = "feedback bad"; fb.textContent = "Not quite. Have another look and try again.";
      chosen.clear(); $$(".opt", el).forEach(b => b.classList.remove("sel"));
    } else {
      const right = (r.correct_answer || []).map(i => q.options[+i]).join(", ");
      fb.className = "feedback bad"; fb.textContent = `Not quite. The answer is: ${right}. ${r.explanation || ""}`;
      setTimeout(() => onRight(r), 2600);
    }
  };
  $$(".opt", el).forEach(b => (b.onclick = () => {
    const i = b.dataset.i;
    if (multi) { chosen.has(i) ? chosen.delete(i) : chosen.add(i); b.classList.toggle("sel"); }
    else { chosen.clear(); chosen.add(i); b.classList.add("sel"); send(); }
  }));
  const c = $("[data-check]", el); if (c) c.onclick = () => chosen.size && send();
}

function stepVideo(el, slug, step, cfg) {
  const qs = (step.questions || []).filter(q => q.at_seconds != null);
  const answered = new Set();                 // every viewing asks every question again
  el.innerHTML = `<div class="player"><div id="yt"></div><div class="ask" id="ask"><div class="qcard" id="qcard"></div></div></div>
    <div class="status-line"><span class="grow muted" id="vstat">Press play to start.</span>
      <button class="btn" id="vdone" disabled>I have watched it</button></div>
    ${qs.length ? `<p class="small muted" style="margin-top:8px">${plural(qs.length, "question")} will pause this video. Answer to continue watching.</p>` : ""}`;
  if (!cfg.youtube_id) { $("#vstat").textContent = "The teacher has not added the video yet."; return; }
  let maxPos = 0, lastSent = 0, duration = 0, asking = null;
  const start = cfg.start || 0, end = () => cfg.end || duration;
  const canFinish = () => isDone(step) || (qs.every(q => !q.must_pass || answered.has(q.id)) && duration && maxPos >= start + .9 * (end() - start));
  const update = () => {
    $("#vdone").disabled = !canFinish();
    if (duration) $("#vstat").textContent = isDone(step) ? "You have finished this video. Watch it again any time." : `Watched up to ${mmss(maxPos)} of ${mmss(end())}`;
  };
  $("#vdone").onclick = () => complete(slug, step);
  withYouTube(() => {
    if (!$("#yt")) return;
    player = new YT.Player("yt", {
      videoId: cfg.youtube_id,
      playerVars: { start, end: cfg.end || undefined, rel: 0, modestbranding: 1, playsinline: 1 },
      events: {
        onReady: () => {
          duration = player.getDuration(); update();
          poll = setInterval(() => {
            if (!player || !player.getCurrentTime || asking) return;
            const t = player.getCurrentTime();
            const q = qs.find(x => !answered.has(x.id) && t >= x.at_seconds);
            if (q) {
              if (t > q.at_seconds + 2) player.seekTo(q.at_seconds, true);   // skipped ahead: go back to the question
              player.pauseVideo(); asking = q;
              if (document.fullscreenElement) document.exitFullscreen().catch(() => null);
              $("#ask").classList.add("show");
              question($("#qcard"), q, () => { answered.add(q.id); asking = null; $("#ask").classList.remove("show"); update(); player.playVideo(); },
                       `Question at ${mmss(q.at_seconds)}`);
              return;
            }
            if (t <= maxPos + 3 && t > maxPos) maxPos = t;               // jumping forward does not count as watching
            if (maxPos - lastSent >= 15) { lastSent = maxPos; record(step, "progressed", Math.round(maxPos)).catch(() => null); }
            update();
          }, 500);
        },
        onStateChange: e => {
          if (e.data === YT.PlayerState.ENDED) {
            maxPos = Math.max(maxPos, end()); update();
            record(step, "progressed", Math.round(maxPos)).catch(() => null);
            if (canFinish() && !isDone(step)) complete(slug, step);
          }
        },
        onError: e => { $("#vstat").textContent = `YouTube cannot play this video (error ${e.data}). Tell your teacher.`; },
      },
    });
  });
}
function stepPdf(el, slug, step, cfg) {
  const qs = step.questions || [], answered = new Set();
  el.innerHTML = cfg.url ? `<iframe class="pdf" src="${esc(cfg.url)}#view=FitH" title="${esc(step.title)}"></iframe>
      <p class="small" style="margin-top:8px"><a href="${esc(cfg.url)}" target="_blank" rel="noopener">Open the PDF in a new tab</a></p>`
    : `<div class="empty">The teacher has not uploaded this reading yet.</div>`;
  el.insertAdjacentHTML("beforeend", `<div id="pq"></div><div class="status-line"><span class="grow"></span><button class="btn" id="pdone">I have read it</button></div>`);
  const draw = () => {
    const pq = $("#pq");
    pq.innerHTML = qs.length ? `<h2 style="margin-top:22px;font-size:1.3rem">Questions on this reading</h2><div class="qlist"></div>` : "";
    qs.forEach(q => {
      const d = document.createElement("div"); d.className = "box";
      if (answered.has(q.id)) d.innerHTML = `<span class="done-chip">Answered</span> <span style="margin-left:8px">${esc(q.prompt)}</span>`;
      else question(d, q, () => { answered.add(q.id); draw(); }, q.at_page ? `Page ${q.at_page}` : "");
      $(".qlist", pq).appendChild(d);
    });
    const left = qs.filter(q => q.must_pass && !answered.has(q.id)).length;
    $("#pdone").disabled = left > 0 && !isDone(step);
    $("#pdone").title = left ? "Answer the questions first" : "";
  };
  draw();
  $("#pdone").onclick = () => complete(slug, step);
  record(step, "progressed", 1).catch(() => null);
}
function markdown(md) {
  return esc(md).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/\*(.+?)\*/g, "<i>$1</i>")
    .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
    .split(/\n\s*\n/).map(p => /^- /m.test(p) ? `<ul>${p.split(/\n/).map(x => `<li>${x.replace(/^- /, "")}</li>`).join("")}</ul>` : `<p>${p.replace(/\n/g, "<br>")}</p>`).join("");
}
function stepText(el, slug, step, cfg) {
  el.innerHTML = `<div class="reading">${markdown(cfg.markdown || "") || `<p class="muted">The teacher has not written this reading yet.</p>`}</div>
    <div class="status-line"><span class="grow"></span><button class="btn" id="tdone">I have read it</button></div>`;
  $("#tdone").onclick = () => complete(slug, step);
}
function stepQuiz(el, slug, step) {
  const qs = step.questions || [], answered = new Set();
  const best = step.progress && step.progress.score != null ? `<span class="done-chip">Your score: ${Math.round(step.progress.score)}%</span>` : "";
  el.innerHTML = (qs.length ? `<p class="muted">${plural(qs.length, "question")}. Your score counts the answers that are right on the first try. ${best}</p>` : "")
    + `<div class="qlist" id="qq"></div>`;
  if (!qs.length) { $("#qq").innerHTML = `<div class="empty">The teacher has not added questions yet.</div>`; return; }
  const draw = () => {
    const qq = $("#qq"); qq.innerHTML = "";
    qs.forEach((q, i) => {
      const d = document.createElement("div"); d.className = "box";
      if (answered.has(q.id)) d.innerHTML = `<span class="done-chip">Answered</span> <span style="margin-left:8px">${i + 1}. ${esc(q.prompt)}</span>`;
      else question(d, q, () => {
        answered.add(q.id);
        if (answered.size === qs.length) { toast("Quiz completed"); refreshAfter(slug, step, true); } else draw();
      }, `Question ${i + 1} of ${qs.length}`);
      qq.appendChild(d);
    });
  };
  draw();
}
function stepAssignment(el, slug, step, cfg) {
  const sub = step.submission;
  el.innerHTML = `<div class="reading">${markdown(cfg.instructions || "") || `<p class="muted">The teacher has not written the instructions yet.</p>`}</div>
    ${sub ? `<div class="msg ${sub.score != null ? "good" : "note"}" style="margin-top:16px">You handed this in on ${esc(new Date(sub.submitted_at).toLocaleDateString("en-GB", { day: "numeric", month: "long" }))}.
       ${sub.score != null ? `Your grade: <b>${Math.round(sub.score)}</b>. ${esc(sub.feedback || "")}` : "Your teacher will grade it."}</div>` : ""}
    <label class="field" style="margin-top:16px">Your answer<textarea id="ans" rows="8" placeholder="Write your answer here"></textarea></label>
    <div class="status-line"><span class="grow small muted">${cfg.grading === "auto" ? "Handing it in completes this step." : "A teacher grades your answer from 0 to 100."}</span>
      <button class="btn" id="send">${sub ? "Hand in again" : "Hand in"}</button></div>`;
  $("#send").onclick = async () => {
    const text = $("#ans").value.trim();
    if (!text) return toast("Write your answer first.");
    $("#send").disabled = true;
    const r = await api("mooc_submit", { p_token: S.token, p_step: step.id, p_answer: text, p_file_url: null });
    if (!r.ok) { $("#send").disabled = false; return toast(r.error, 5000); }
    celebrate(r.awarded); toast("Handed in");
    refreshAfter(slug, step, cfg.grading === "auto");
  };
}
function stepLive(el, slug, step, cfg) {
  el.innerHTML = `<div class="box"><h3>${cfg.group ? "Study group" : "Online lecture"}</h3>
      <p class="muted" style="margin:6px 0 16px">${[cfg.starts_at, cfg.minutes && `${cfg.minutes} minutes`].filter(Boolean).map(esc).join(", ") || "The teacher will share the time."}</p>
      ${cfg.room ? `<button class="btn" id="join">Join the session</button>` : `<p class="muted">The teacher has not added the meeting link yet.</p>`}</div>`;
  const j = $("#join");
  if (j) j.onclick = async () => {
    window.open(cfg.room, "_blank", "noopener");
    const r = await record(step, "joined_live");
    if (r.ok) refreshAfter(slug, step, true);
  };
}

// ------------------------------------------------------------------------------------------------ my learning
async function viewMy(view) {
  if (!S.me) return needSignIn("/my");
  const m = await myLearning(true);
  if (!m) return needSignIn("/my");
  const courses = m.courses.map(c => {
    if (!c.steps) return `<div class="card"><div class="cover" aria-hidden="true">${cover(c)}</div>
      <div class="body"><h3>${esc(c.title)}</h3>${c.project ? `<div class="muted small">${esc(c.project)}</div>` : ""}
        <div class="small muted" style="margin-top:6px">Your certificate and badges for this event are below.</div>
        ${c.certificate ? `<div style="margin-top:8px"><a class="btn" href="award.html?id=${c.certificate}" target="_blank" rel="noopener">Your certificate</a></div>` : ""}</div></div>`;
    const pct = c.steps ? Math.round(100 * c.done / c.steps) : 0;
    return `<div class="card"><a class="cover" href="#/course/${encodeURIComponent(c.slug)}" tabindex="-1">${cover(c)}</a>
      <div class="body"><h3>${esc(c.title)}</h3>${c.project ? `<div class="muted small">${esc(c.project)}</div>` : ""}
        <div class="bar ${pct === 100 ? "done" : ""}" style="margin-top:6px"><i style="width:${pct}%"></i></div>
        <div class="small muted">${c.done} of ${c.steps} steps done</div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:8px">
          <a class="btn" href="#/learn/${encodeURIComponent(c.slug)}${c.next_step ? "/" + c.next_step : ""}">${c.next_step ? (c.done ? "Continue" : "Start") : "Review"}</a>
          ${c.certificate ? `<a class="btn quiet" href="award.html?id=${c.certificate}" target="_blank" rel="noopener">Your certificate</a>` : ""}</div></div></div>`;
  }).join("");
  const awards = m.awards.map(a => `<a class="medal" href="award.html?id=${a.id}" target="_blank" rel="noopener">
      <div class="seal">${a.image_url ? `<img src="${esc(a.image_url)}" alt="">` : (a.kind === "certificate" ? "📜" : "🏅")}</div>
      <b>${esc(a.title)}</b><span class="small muted">${a.kind === "certificate" ? "Certificate" : "Badge"}, ${esc(new Date(a.issued_at).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }))}</span></a>`).join("");
  view.innerHTML = `<div class="wrap" style="padding:44px 24px 80px">
      <h1 style="font-size:clamp(1.9rem,3.6vw,2.6rem)">Hello, ${esc(S.me.first_name || S.me.username)}</h1>
      <p class="muted" style="margin:8px 0 0">Your courses, your progress and what you have earned.
        <a href="profile.html?u=${encodeURIComponent(S.me.username)}" target="_blank" rel="noopener">See your public profile</a></p>
      <h2 style="margin:36px 0 16px">My courses</h2>
      ${courses ? `<div class="grid">${courses}</div>` : `<div class="empty">You have not started a course yet. <a href="#/">Choose a course</a> and start straight away.</div>`}
      <h2 style="margin:44px 0 16px">Badges and certificates</h2>
      ${awards ? `<div class="shelf">${awards}</div>` : `<div class="empty">Finish lectures to earn badges, and a whole course to earn its certificate.</div>`}
    </div>`;
}

// ------------------------------------------------------------------------------------------------ sign in and create account
function afterSignIn(next) { S.mine = null; header(); location.hash = "#" + (next && next.startsWith("/") ? next : "/my"); }
function viewSignIn(view, next) {
  if (S.me) return afterSignIn(next);
  view.innerHTML = `<div class="wrap auth"><div class="box">
      <h1>Sign in</h1><p class="muted">Use your Octa account: the same one you use for MOOC Studio and the other Octa Insight apps.</p>
      <div id="m"></div>
      <form id="f" novalidate>
        <label class="field">Email or username<input name="login" autocomplete="username" required></label>
        <label class="field">Password<input name="pw" type="password" autocomplete="current-password" required></label>
        <button class="btn big block" type="submit">Sign in</button>
      </form>
      <p class="small" style="margin:18px 0 0">New here? <a href="#/join${next ? "?next=" + encodeURIComponent(next) : ""}">Create a free account</a></p>
      <p class="small muted" style="margin:6px 0 0">Forgot your password or username? <a href="#/forgot">Choose a new password</a></p>
    </div></div>`;
  $("#f").onsubmit = async e => {
    e.preventDefault();
    const f = e.target, b = $("button", f);
    if (!f.login.value.trim() || !f.pw.value) return ($("#m").innerHTML = `<div class="msg bad">Enter your email or username and your password.</div>`);
    b.disabled = true;
    try {
      const r = await api("octa_user_login", { p_login: f.login.value.trim(), p_password: f.pw.value, p_app: CFG.app });
      if (!r.ok) throw new Error(r.error || "Wrong email/username or password.");
      S.token = r.token; S.me = r.user; store.set(TOKEN_KEY, r.token);
      toast(`Welcome back, ${S.me.first_name || S.me.username}.`); afterSignIn(next);
    } catch (err) { $("#m").innerHTML = `<div class="msg bad">${esc(err.message)}</div>`; b.disabled = false; }
  };
  $("input", view).focus();
}
function viewJoin(view, next) {
  if (S.me) return afterSignIn(next);
  view.innerHTML = `<div class="wrap auth" style="max-width:560px"><div class="box">
      <h1>Create your free account</h1><p class="muted">One Octa account opens every course on the MOOC. You can start learning straight away.</p>
      <div id="m"></div>
      <form id="f" novalidate>
        <div class="two"><label class="field">First name<input name="first" autocomplete="given-name" required></label>
          <label class="field">Family name<input name="last" autocomplete="family-name" required></label></div>
        <label class="field">Email<input name="email" type="email" autocomplete="email" required></label>
        <label class="field">Username<span class="hint">3 to 40 letters, numbers, dots, dashes or underscores. You can sign in with it or with your email.</span>
          <input name="user" autocomplete="username" required></label>
        <label class="field">Password<span class="hint">At least 8 characters.</span><input name="pw" type="password" autocomplete="new-password" required></label>
        <label class="field">University or organisation<span class="hint">Optional</span><input name="aff" autocomplete="organization"></label>
        <button class="btn big block" type="submit">Create account</button>
      </form>
      <p class="small" style="margin:18px 0 0">Already have an Octa account? <a href="#/signin${next ? "?next=" + encodeURIComponent(next) : ""}">Sign in</a></p>
      <p class="small muted" style="margin:6px 0 0">Want to teach? Create your account, then ask for a teacher role in <a href="${CFG.studio}" target="_blank" rel="noopener">MOOC Studio</a>.</p>
    </div></div>`;
  $("#f").onsubmit = async e => {
    e.preventDefault();
    const f = e.target, b = $("button", f), m = $("#m");
    const v = { first: f.first.value.trim(), last: f.last.value.trim(), email: f.email.value.trim(), user: f.user.value.trim(), pw: f.pw.value };
    const missing = [!v.first && "first name", !v.last && "family name", !v.email && "email", !v.user && "username", !v.pw && "password"].filter(Boolean);
    if (missing.length) return (m.innerHTML = `<div class="msg bad">Please fill in your ${missing.join(", ")}.</div>`);
    if (v.pw.length < 8) return (m.innerHTML = `<div class="msg bad">Your password needs at least 8 characters.</div>`);
    b.disabled = true;
    try {
      const r = await api("octa_user_register", { p: { email: v.email, username: v.user, password: v.pw, first_name: v.first, last_name: v.last,
        affiliation: f.aff.value.trim(), app: CFG.app, family: "education", profile: {} } });
      if (!r.ok) throw new Error(r.error || "The account could not be created.");
      S.token = r.token; S.me = r.user; store.set(TOKEN_KEY, r.token);
      await api("mooc_join", { p_token: S.token, p_kind: "student" }).catch(() => null);
      toast(`Welcome, ${v.first}. Your account is ready.`); afterSignIn(next || "/");
    } catch (err) { m.innerHTML = `<div class="msg bad">${esc(err.message)}</div>`; b.disabled = false; }
  };
  $("input", view).focus();
}

// ------------------------------------------------------------------------------------------------ set your password
// The link in a certificate email (#/welcome?t=…): people put on a list by the organisers got an account; here they
// choose its password, are signed in and land on My learning with their certificates.
async function viewWelcome(view, token, reset) {
  const box = inner => (view.innerHTML = `<div class="wrap auth"><div class="box">${inner}</div></div>`);
  const expired = msg => box(`<h1>This link no longer works</h1><div class="msg bad">${esc(msg)}</div>
      <p class="muted">If you have already chosen your password, just sign in. Otherwise ask for a new link: it arrives
      by email within a minute.</p>
      <a class="btn" href="#/signin">Sign in</a> <a class="btn ghost" href="#/forgot">Get a new link</a>`);
  if (!/^[0-9a-f]{64}$/.test(token || "")) return expired("The link is not complete. Open it again from your email.");
  const c = await api("octa_user_reset_check", { p_token: token });
  if (!c.ok) return expired(c.error || "This link has expired or was already used.");
  box(`<h1>${reset ? "Choose a new password" : "Choose your password"}</h1>
      <p class="muted">${reset ? "For your Octa account: the new password works in all Octa Insight apps."
        : "Your CloudEARTHi MOOC account is ready: your certificates are waiting under My learning."}
        Sign in later with your email <b>${esc(c.email)}</b> or your username.</p>
      <div id="m"></div>
      <form id="f" novalidate>
        <label class="field">Username<span class="hint">You may keep it or choose another: 3 to 40 letters, numbers, dots, dashes or underscores.</span>
          <input name="user" autocomplete="username" value="${esc(c.username)}" required></label>
        <label class="field">Password<span class="hint">At least 8 characters.</span><input name="pw" type="password" autocomplete="new-password" required></label>
        <label class="field">Password again<input name="pw2" type="password" autocomplete="new-password" required></label>
        <button class="btn big block" type="submit">Save password and sign in</button>
      </form>`);
  $("#f").onsubmit = async e => {
    e.preventDefault();
    const f = e.target, b = $("button", f), m = $("#m"), user = f.user.value.trim();
    if (f.pw.value.length < 8) return (m.innerHTML = `<div class="msg bad">Your password needs at least 8 characters.</div>`);
    if (f.pw.value !== f.pw2.value) return (m.innerHTML = `<div class="msg bad">The two passwords are not the same.</div>`);
    b.disabled = true;
    try {
      const r = await api("octa_user_reset_complete", { p_token: token, p_new_password: f.pw.value, p_new_username: user === c.username ? "" : user });
      if (!r.ok) throw new Error(r.error || "The password could not be saved.");
      const s = await api("octa_user_login", { p_login: r.username || c.email, p_password: f.pw.value, p_app: CFG.app });
      if (!s.ok) { toast("Your password is saved. Please sign in."); location.hash = "#/signin?next=/my"; return; }
      S.token = s.token; S.me = s.user; store.set(TOKEN_KEY, s.token);
      toast(`Welcome, ${S.me.first_name || S.me.username}. Your password is saved.`); afterSignIn("/my");
    } catch (err) { m.innerHTML = `<div class="msg bad">${esc(err.message)}</div>`; b.disabled = false; }
  };
  $("input[name=pw]", view).focus();
}

// "Forgot your password?": the mooc-mail function emails a one-hour link to #/welcome. It never says whether an
// account uses the email, so the page cannot be used to find out who is registered.
function viewForgot(view, email) {
  view.innerHTML = `<div class="wrap auth"><div class="box">
      <h1>Choose a new password</h1>
      <p class="muted">Enter the email address of your Octa account. We will email you a link to choose a new password
        and remind you of your username.</p>
      <div id="m"></div>
      <form id="f" novalidate>
        <label class="field">Email address<input name="email" type="email" autocomplete="email" value="${esc(email || "")}" required></label>
        <button class="btn big block" type="submit">Email me a link</button>
      </form>
      <p class="small" style="margin:18px 0 0">Remembered it? <a href="#/signin">Sign in</a></p>
    </div></div>`;
  $("#f").onsubmit = async e => {
    e.preventDefault();
    const f = e.target, b = $("button", f), m = $("#m"), em = f.email.value.trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(em)) return (m.innerHTML = `<div class="msg bad">Enter a valid email address.</div>`);
    b.disabled = true;
    try {
      const r = await fetch(CFG.mailer, { method: "POST", headers: { "Content-Type": "application/json" },
                                          body: JSON.stringify({ action: "forgot", email: em }) }).then(x => x.json());
      if (!r.ok) throw new Error(r.error || "The email could not be sent. Please try again later.");
      $(".box", view).innerHTML = `<h1>Check your email</h1>
        <p>If an Octa account uses <b>${esc(em)}</b>, a link to choose a new password is on its way. It works for one hour.</p>
        <p class="muted small">Nothing after a few minutes? Look in your spam folder, or check that this is the address you registered with.</p>
        <a class="btn" href="#/signin">Back to sign in</a>`;
    } catch (err) { m.innerHTML = `<div class="msg bad">${esc(err.message === "Failed to fetch" ? "The MOOC cannot be reached. Check your internet connection." : err.message)}</div>`; b.disabled = false; }
  };
  $("input", view).focus();
}

// ------------------------------------------------------------------------------------------------ start
(async () => {
  const p = new URLSearchParams(location.search);          // a link from another Octa app may carry ?session=
  if (p.get("session")) { S.token = p.get("session"); store.set(TOKEN_KEY, S.token); history.replaceState(null, "", location.pathname + location.hash); }
  await loadSession();
  route();
})();
