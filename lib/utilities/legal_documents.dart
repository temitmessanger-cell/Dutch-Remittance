/// Dutch Remit's own legal documents, written directly into the app as
/// plain text — not fetched from any external URL. This is intentional:
/// a legal document that depends on a live network call (to your own
/// server or anyone else's) can silently change, disappear, or fail to
/// load, and Settings should never put a third party's name, repo, or
/// content in front of a Dutch Remit user.
library legal_documents;

const String kPrivacyPolicy = '''
# Privacy Policy

**Dutch Remit** is operated by **Dutch Inc**.

## What we collect

We collect the information you give us when you create an account — your name, email, phone number, and the transaction details needed to send and receive money through the app.

## How we use it

We use your information to:
- Process your transfers and keep your account secure
- Show you your balance, transaction history, and linked accounts
- Improve the app and respond to support requests

## How we protect it

We do not sell your personal information. Access to your data is limited to what's needed to operate the platform and keep your account secure.

## Your choices

You can review, update, or delete your account information at any time from Settings. Deleting your account removes your locally stored data from this device.

## Contact us

Questions about this policy can be sent through the Help & Feedback option in Settings.

_Last updated: 2026_
''';

const String kTermsOfUse = '''
# Terms of Use

Welcome to **Dutch Remit**, a product of **Dutch Inc**. By using this app, you agree to these terms.

## Using Dutch Remit

You agree to provide accurate information when creating an account and to use the platform only for lawful purposes. You're responsible for keeping your login details secure.

## Transfers

Dutch Remit lets you send and receive money between accounts, linked banks, and supported payment methods. Transfer times and fees are shown before you confirm any transaction.

## Account responsibility

You're responsible for all activity on your account. If you notice anything unauthorized, contact us right away through Settings.

## Changes to the service

We may update or improve features over time. We'll do our best to communicate meaningful changes clearly.

## Limitation of liability

Dutch Remit is provided "as is." Dutch Inc is not liable for losses arising from misuse of the platform, unauthorized account access caused by user negligence, or events outside our reasonable control.

## Contact us

Questions about these terms can be sent through the Help & Feedback option in Settings.

_Last updated: 2026_
''';

const String kGettingStartedGuide = '''
# Getting Started with Dutch Remit

Welcome to **Dutch Remit**, built by **Dutch Inc**.

## What you can do

- **Send money** to friends, family, or businesses, locally or abroad
- **Get paid instantly** with real, live exchange rates on international transfers
- **Manage your cards** — add, view, and remove cards securely
- **Top up or withdraw** using mobile money, bank transfer, or crypto
- **Send gifts** for birthdays, holidays, and other occasions

## Getting set up

Create an account to save your details and send real transfers, or continue as a guest to explore the app first. You can always create an account later from your Profile tab.

## Need help?

Reach out any time through the Help & Feedback option in Settings.
''';

const String kLoginHelp = '''
# Login Help

Having trouble signing in to **Dutch Remit**? Here are a few things to check.

## Didn't get your code?

Make sure you're entering the email address you signed up with, and check your spam folder. You can request a new code with the Resend option.

## Account not found

Double-check there are no extra spaces in your email address. If you're still having trouble, you may not have created an account yet — try Sign Up instead.

## Still stuck?

You can always continue as a guest to explore the app, or reach out through the Help & Feedback option in Settings once you're signed in.
''';

const String kEndUserLicenseAgreement = '''
# End User License Agreement

This agreement is between you and **Dutch Inc**, the maker of **Dutch Remit**.

## License grant

Dutch Inc grants you a personal, non-transferable license to use the Dutch Remit app on your own devices, for your own personal or business financial activity.

## Restrictions

You may not reverse-engineer, resell, or redistribute the Dutch Remit app, or use it to build a competing product.

## Ownership

Dutch Remit, including its design, code, and branding, is the property of Dutch Inc. Nothing in this agreement transfers ownership of the app to you.

## Termination

This license ends automatically if you violate these terms. Dutch Inc may also suspend accounts found to be used fraudulently or in violation of the Terms of Use.

## Contact us

Questions about this agreement can be sent through the Help & Feedback option in Settings.

_Last updated: 2026_
''';
