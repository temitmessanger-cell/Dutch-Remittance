/// Base URL the Flutter app calls for everything Plaid-related. The app
/// never holds a Plaid client_id or secret directly — these calls go to
/// our own Netlify Functions (see /netlify/functions in the project
/// root), which hold those secrets server-side.
///
/// Because the functions are deployed alongside the Flutter web build on
/// the same Netlify site, the API lives at the same domain as the app
/// itself — no separate server URL to manage. netlify.toml redirects
/// /api/plaid/* to the matching function under the hood.
///
/// - Production (deployed): 'https://dutchremit.dubiabank.com'
/// - Local development with `netlify dev` (recommended — see project
///   README): 'http://localhost:8888', which is the port the Netlify CLI
///   serves both the Flutter build and the functions on together.
class PlaidApiConstants {
  static const String baseUrl = 'https://dutchremit.dubiabank.com';
}
