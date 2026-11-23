# "Request a package" page (WordPress)

Every card on **Partner with us** opens `https://mooc.cloudearthi.com/request-a-package/?package=<name of the package>`.
This page holds a short form; the package is already filled in from the link. WordPress emails each request to Octa
and sends the visitor a confirmation.

## 1. Install two free plugins (Plugins → Add new)

- **Contact Form 7**: the form.
- **WP Mail SMTP**: makes WordPress emails arrive (without it they often land in spam or are lost). Set it to send
  through Resend, the service the MOOC already uses:
  - Mailer: *Other SMTP*
  - SMTP host `smtp.resend.com`, encryption *SSL*, port `465`, authentication *on*
  - Username `resend`, password: your Resend API key (the same as in MOOC Studio's secrets)
  - From email: an address on your domain verified in Resend (for example `mooc@cloudearthi.com`), from name `CloudEARTHi MOOC`
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
- From: `CloudEARTHi MOOC <mooc@cloudearthi.com>` (the address set in WP Mail SMTP)
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
- From: `CloudEARTHi MOOC <mooc@cloudearthi.com>`
- Subject: `We received your request: [package]`
- Message body:

```
Dear [your-name],

Thank you for your interest in the CloudEARTHi MOOC. We received your request for: [package].
We will reply within two working days, usually with a proposal for a 30-minute online demo.

Best regards,
The CloudEARTHi MOOC team at Octa Insight
https://mooc.cloudearthi.com/
```

Save. Contact Form 7 shows a shortcode such as `[contact-form-7 id="123" title="Request a package"]`.

## 3. Make the page (Pages → Add new)

- Title: `Request a package`; address (permalink): `request-a-package`.
- A paragraph: *Tell us a little about your course, event or project. We reply within two working days.*
- A **Shortcode** block with the shortcode from step 2.
- Publish, then open `https://mooc.cloudearthi.com/request-a-package/?package=Hosting` to check that "Hosting"
  is filled in, and send a test request.
