# "Request a package" form on octainsight.com/mooc (WordPress)

The packages and prices live on Octa Insight's site, at `https://octainsight.com/mooc`
(`wordpress/octa-mooc-packages.html`). Every card there opens `https://octainsight.com/mooc/?package=<name>#request`:
the same page, scrolled to the form at the bottom, with the package already filled in. WordPress emails each request
to Octa and sends the visitor a confirmation.

The MOOC's own **Partner with us** page (`wordpress/partner-with-us.html`) has only two cards: *CloudEARTHi projects*
(free, opens the MOOC's Contact us page) and *Other organisations and courses* (opens `https://octainsight.com/mooc`).
No form is needed on the MOOC site for this.

All steps below are done in **Octa Insight's WordPress**. If octainsight.com does not run WordPress, use that site's own
form tool with the same fields, and read the package from the `package` part of the address.

## 1. Install two free plugins (Plugins → Add new)

- **Contact Form 7**: the form.
- **WP Mail SMTP**: makes WordPress emails arrive (without it they often land in spam or are lost). Set it to send
  through Resend, the service the MOOC already uses:
  - Mailer: *Other SMTP*
  - SMTP host `smtp.resend.com`, encryption *SSL*, port `465`, authentication *on*
  - Username `resend`, password: your Resend API key (the same as in MOOC Studio's secrets)
  - From email: an address on octainsight.com, with the domain verified in Resend (for example `mooc@octainsight.com`),
    from name `Octa Insight`
  - Send a test email from the plugin's settings.

## 2. Make the form (Contact → Add new)

Title: `Request a package`. Replace the **Form** tab with:

```
<label> Package
    [text* package default:get placeholder "Which package?"] </label>

<label> Your name
    [text* your-name autocomplete:name] </label>

<label> Organisation
    [text* organisation] </label>

<label> Email
    [email* your-email autocomplete:email] </label>

<label> Country
    [text* country] </label>

<label> Number of courses, or participants for an event
    [text amount] </label>

<label> Tell us about your course, event or project
    [textarea* your-message] </label>

[acceptance consent] I agree that Octa Insight stores my details to answer this request. [/acceptance]

[submit "Send request"]
```

`default:get` takes the package from the link, so a visitor who clicked "Hosting" sees "Hosting" already filled in.

**Mail** tab (the email to Octa):

- To: `<Octa's email address>`
- From: `Octa Insight <mooc@octainsight.com>` (the address set in WP Mail SMTP)
- Subject: `[MOOC request] [package] from [organisation]`
- Additional headers: `Reply-To: [your-email]` (so you can answer by pressing Reply)
- Message body:

```
New request on the CloudEARTHi MOOC

Package: [package]
Name: [your-name]
Organisation: [organisation]
Email: [your-email]
Country: [country]
Courses or participants: [amount]

[your-message]
```

**Mail (2)** (tick *Use Mail (2)*: the confirmation to the visitor):

- To: `[your-email]`
- From: `Octa Insight <mooc@octainsight.com>`
- Subject: `We received your request: [package]`
- Message body:

```
Dear [your-name],

Thank you for your interest in publishing on the CloudEARTHi MOOC. We received your request for: [package].
We will reply within two working days, usually with a proposal for a 30-minute online demo.

Best regards,
Octa Insight, developer and operator of the CloudEARTHi MOOC
https://octainsight.com/mooc
```

Save. Contact Form 7 shows a shortcode such as `[contact-form-7 id="123" title="Request a package"]`.

## 3. Make the page (Pages → Add new)

- Title: `CloudEARTHi MOOC`; address (permalink): `mooc`.
- A **Custom HTML** block with everything in `wordpress/octa-mooc-packages.html`. It ends with the heading
  "Send a request" (the place the cards jump to).
- Straight under it, a **Shortcode** block with the shortcode from step 2.
- Publish, then open `https://octainsight.com/mooc/?package=Hosting#request` to check that the page scrolls to the form
  with "Hosting" filled in, and send a test request.
