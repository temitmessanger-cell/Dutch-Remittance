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

Welcome to **Dutch Remit**, Cameroon's biggest cross-border remittance platform and one of Africa's leading platforms, a product of **Dutch Inc**. By using this app, you agree to these terms.

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

Welcome to **Dutch Remit** — Cameroon's biggest cross-border remittance platform, and one of Africa's leading platforms for sending money and spending online. Built by **Dutch Inc**.

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

const String kAboutDutchRemit = '''
# About Dutch Remit

**Dutch Remit** is Cameroon's biggest cross-border remittance and virtual card platform, and one of Africa's leading platforms for sending money and spending online — built for Cameroonians and the wider African diaspora, wherever they've landed.

## What we do

We move money across borders in minutes, not days — mobile money and bank transfers across a growing list of African corridors — and give you a virtual USD card to spend online anywhere Visa or Mastercard is accepted, funded straight from your wallet.

## Why Dutch Remit

- **Real, live exchange rates** — a transparent margin on top of the mid-market rate, never a hidden markup buried in the FX
- **Fast delivery** — mobile money arrives in minutes; bank transfers in minutes to hours
- **One wallet, two products** — remittances and cards share the same balance, so your money works the way you actually use it
- **Built for the diaspora** — corridors, currencies, and payout methods chosen around how Cameroonians and other Africans abroad actually send money home

## Who's behind it

Dutch Remit is built and operated by **Dutch Inc**.

## Get in touch

Reach us any time through the Help & Feedback option in Settings, or chat with support on WhatsApp.

_Last updated: 2026_
''';

const String kFrequentlyAskedQuestions = '''
# Frequently Asked Questions

## Is Dutch Remit safe to use?

Yes. Dutch Remit works with licensed payment partners for every transfer, deposit, and withdrawal — we never move your money outside those real, regulated rails.

## How fast do transfers arrive?

Mobile money transfers typically arrive in about a minute. Bank transfers usually take minutes to a few hours, depending on the destination bank.

## What currencies can I hold in my wallet?

Your wallet balance is shown in XAF, USD, or USDT. Naira (NGN) and Cedi (GHS) become available once you set up a bank account in that currency — see Bank Accounts in your Profile.

## How do I deposit money?

From the Home screen, tap Deposit and choose mobile money, Orange Money, bank transfer, or crypto. Each method shows you exactly what currency you're depositing in before you confirm.

## How do I send money abroad?

Open Send Abroad from the bottom navigation and pick the corridor that matches what you need — Global Transfer, Diaspora to Africa, Africa to Africa, or Quick Transfer. Enter an amount and recipient details, and you'll see the exact rate and fee before you send.

## Can I deposit or withdraw crypto?

Yes. Choose Crypto as your method on the Deposit or Withdraw screen. Deposits give you a real wallet address to send to; withdrawals ask for your destination wallet address. A small network fee plus Dutch Remit's 1% applies on top of what our processor charges.

## What's a bank account, and why do I need one?

For corridors our main provider doesn't directly cover, we route your money through a real local bank account in that currency first, then complete the transfer. It's a one-time setup per currency, with a small one-time fee.

## How do virtual cards work?

Create a card from the Cards tab, fund it from your USD or XAF wallet balance, and spend it anywhere Visa or Mastercard is accepted online. You can freeze, top up, or close a card at any time.

## What if my transfer doesn't arrive?

Check the transaction's status in your Payments tab first — most delays resolve within the stated delivery window. If it's been longer, reach out through Help & Feedback in Settings or chat with support on WhatsApp.

## How do I invite friends to Dutch Remit?

From your Profile, tap "Not on Dutch Remit?" and choose how you'd like to share your invite — SMS, WhatsApp, Facebook, Telegram, or any other app on your phone.

_Last updated: 2026_
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
