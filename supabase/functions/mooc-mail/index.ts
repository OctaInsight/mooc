// CloudEARTHi MOOC mailer (Supabase Edge Function "mooc-mail", deployed with verify_jwt off).
//
//   POST {"action":"outbox"}           sends the emails waiting in the award outbox: one email per student, for every
//                                      badge or certificate earned in a course, with links to view and share it.
//                                      Started every 5 minutes by pg_cron; running it more often only sends sooner.
//   POST {"action":"forgot","email"}   "Forgot your password?" on the student website: emails a one-hour link to
//                                      choose a new password (#/welcome?t=…&r=1). Never says whether the email exists.
//
// Secrets (Supabase dashboard > Edge Functions > Secrets): RESEND_API_KEY and MOOC_FROM_EMAIL (or RESEND_FROM_EMAIL),
// optional MOOC_FROM_NAME, MOOC_REPLY_TO and MOOC_SITE. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by
// Supabase. The database functions used here can only be called with the service role key.

const SITE = (Deno.env.get("MOOC_SITE") || "https://octainsight.github.io/mooc/").replace(/\/?$/, "/");
const DB = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_KEY = Deno.env.get("RESEND_API_KEY") || "";
const FROM_EMAIL = Deno.env.get("MOOC_FROM_EMAIL") || Deno.env.get("RESEND_FROM_EMAIL") || "";
const FROM_NAME = Deno.env.get("MOOC_FROM_NAME") || "CloudEARTHi MOOC";
const REPLY_TO = Deno.env.get("MOOC_REPLY_TO") || "";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class MailError extends Error {
  constructor(msg: string, public stop = false) { super(msg); }
}

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

async function rpc(fn: string, args: Record<string, unknown>) {
  const r = await fetch(`${DB}/rest/v1/rpc/${fn}`, {
    method: "POST", body: JSON.stringify(args),
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" },
  });
  if (!r.ok) throw new Error(`${fn}: ${r.status} ${await r.text()}`);
  return await r.json();
}

// The same look as the Octa apps' emails (octa_auth/mail.py). Paragraphs are HTML: escape what comes from people.
function render(paragraphs: string[], button: [string, string] | null, after: string[]) {
  const p = (s: string) => `<p style='margin:0 0 14px 0'>${s}</p>`;
  const btn = button
    ? `<p style='margin:20px 0'><a href='${esc(button[1])}' style='background:#2a78d6;color:#ffffff;text-decoration:none;` +
      `padding:10px 18px;border-radius:6px;font-weight:600'>${esc(button[0])}</a></p>` +
      `<p style='font-size:12px;color:#6b6a66;margin:0 0 14px 0'>Or copy this link: ${esc(button[1])}</p>`
    : "";
  const html = "<div style='font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#0b0b0b;max-width:560px'>" +
    paragraphs.map(p).join("") + btn + after.map(p).join("") +
    "<p style='color:#52514e;margin-top:24px'>— CloudEARTHi MOOC, Octa Insight</p></div>";
  const strip = (s: string) => s.replace(/<a [^>]*href='([^']*)'[^>]*>([^<]*)<\/a>/g, "$2 ($1)").replace(/<br>/g, "\n")
    .replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
  const text = [...paragraphs.map(strip), ...(button ? [`${button[0]}: ${button[1]}`] : []), ...after.map(strip)].join("\n\n") +
    "\n\n— CloudEARTHi MOOC, Octa Insight";
  return { html, text };
}

async function send(to: string, subject: string, paragraphs: string[], button: [string, string] | null, after: string[] = []) {
  if (!RESEND_KEY || !FROM_EMAIL) throw new MailError("Email is not set up (RESEND_API_KEY / MOOC_FROM_EMAIL secrets).", true);
  const { html, text } = render(paragraphs, button, after);
  const from = FROM_EMAIL.includes("<") ? FROM_EMAIL : `${FROM_NAME} <${FROM_EMAIL}>`;
  let r: Response;
  try {
    r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND_KEY}`, "Content-Type": "application/json", "Idempotency-Key": crypto.randomUUID() },
      body: JSON.stringify({ from, to: [to], subject, html, text, ...(REPLY_TO ? { reply_to: REPLY_TO } : {}) }),
    });
  } catch (_) {
    throw new MailError("Could not reach Resend.", true);
  }
  if (r.status >= 400) {
    const why: Record<number, [string, boolean]> = {
      401: ["Resend rejected the API key.", true],
      403: ["Resend refused the sender address (domain not verified for this key).", true],
      422: ["Resend rejected the email (address or settings).", false],
      429: ["The daily Resend sending limit was reached.", true],
    };
    const [msg, stop] = why[r.status] || [`Resend answered ${r.status}.`, r.status >= 500];
    throw new MailError(msg, stop);
  }
}

const awardUrl = (id: string) => `${SITE}award.html?id=${id}`;
const linkedin = (id: string) => `https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(awardUrl(id))}`;
type Award = { id: string; title: string; kind: string; course: string; course_kind: string; score: number | null };
type Person = { user_id: string; email: string; username: string; name: string | null; awards: Award[] };

async function emailEarned(p: Person) {
  const certs = p.awards.filter(a => a.kind === "certificate");
  const one = p.awards.length === 1;
  const what = one ? (certs.length ? "certificate" : "badge") : certs.length ? "certificate and badges" : "badges";
  const courses = [...new Set(p.awards.map(a => a.course))];
  const list = p.awards.map(a => `<b>${esc(a.title)}</b>`).join(" and ");
  const paragraphs = [
    `Dear ${esc(p.name || p.username)},`,
    `Congratulations! You have earned the ${what} ${list} in ${courses.map(c => `<b>${esc(c)}</b>`).join(" and ")} on the CloudEARTHi MOOC.`,
    `It is on your public profile and under <b>My learning</b> at <a href='${SITE}#/my'>${SITE}</a>. ` +
      "Its own page shows your name, lets you download it, add it to your LinkedIn profile and share it, and lets anyone check that it is genuine.",
  ];
  const after = p.awards.flatMap(a => [
    `${esc(a.title)}: <a href='${awardUrl(a.id)}'>view and download</a> · <a href='${linkedin(a.id)}'>share on LinkedIn</a>`,
  ]);
  after.push(`To sign in, use your email or username (${esc(p.username)}) and your Octa password. ` +
    `Forgot it? <a href='${SITE}#/forgot?email=${encodeURIComponent(p.email)}'>Choose a new password</a>.`);
  const subject = one ? `You earned the ${what} "${p.awards[0].title}"` : `You earned new ${what}: ${courses.join(", ")}`;
  await send(p.email, subject, paragraphs, [`View and share your ${one ? what : certs.length ? "certificate" : "badge"}`, awardUrl(p.awards[0].id)], after);
}

async function runOutbox() {
  const people: Person[] = await rpc("mooc_mail_claim", { p_limit: 40 });
  let sent = 0, failed = 0, stopped: string | null = null;
  for (let i = 0; i < people.length; i++) {
    const ids = people[i].awards.map(a => a.id);
    try {
      await emailEarned(people[i]);
      await rpc("mooc_mail_done", { p_ids: ids, p_ok: true });
      sent++;
    } catch (e) {
      const err = e instanceof MailError ? e : new MailError(String(e));
      if (err.stop) {                  // the same for everyone: put this one and the rest back, try on a later run
        stopped = err.message;
        const rest = people.slice(i).flatMap(p => p.awards.map(a => a.id));
        await rpc("mooc_mail_done", { p_ids: rest, p_ok: false, p_error: err.message, p_count: false });
        break;
      }
      failed++;
      await rpc("mooc_mail_done", { p_ids: ids, p_ok: false, p_error: err.message, p_count: true });
    }
    await sleep(600);                  // Resend allows 2 emails a second
  }
  return { ok: true, people: people.length, sent, failed, stopped };
}

async function forgot(email: string) {
  if (!RESEND_KEY || !FROM_EMAIL) return { ok: false, error: "Password emails are not set up yet. Please contact the course organisers." };
  const r = await rpc("mooc_site_reset", { p_email: email });
  if (!r.ok) return r;
  if (r.exists) {
    try {
      await send(r.email, "Choose a new password for the CloudEARTHi MOOC", [
        `Dear ${esc(r.name || r.username)},`,
        "Someone (hopefully you) asked to choose a new password for your Octa account on the CloudEARTHi MOOC. " +
          `Your username is <b>${esc(r.username)}</b>; you can also sign in with this email address.`,
        "The link below works for one hour. If you did not ask for it, ignore this email: your password stays as it is.",
      ], ["Choose a new password", `${SITE}#/welcome?t=${r.token}&r=1`],
        ["The same password works in all Octa Insight apps."]);
    } catch (e) {
      return { ok: false, error: e instanceof MailError && e.message.includes("limit")
        ? "Too many emails were sent today. Please try again tomorrow." : "The email could not be sent. Please try again later." };
    }
  }
  return { ok: true };
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) { /* empty */ }
  try {
    if (body.action === "outbox") return json(await runOutbox());
    if (body.action === "forgot") return json(await forgot(String(body.email || "").slice(0, 200)));
    return json({ ok: false, error: "Unknown action" }, 400);
  } catch (e) {
    console.error(e);
    return json({ ok: false, error: "Something went wrong. Please try again later." }, 500);
  }
});
