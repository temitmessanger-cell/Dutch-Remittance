class ApiConstants {
  // Build-time configurable, so the exact same source code is safe to
  // both test locally and ship to production — nothing to remember to
  // edit and revert before a release.
  //
  // Local (default, no flag needed):
  //   flutter run -d chrome
  //
  // Production build, pointed at the real backend:
  //   flutter build web --dart-define=API_BASE_URL=https://<your-railway-backend>.up.railway.app
  //
  // See Backend/LAUNCH_SETUP.md for the actual production URL once
  // the backend is deployed.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dutch-remittance-production.up.railway.app',
  );
}
