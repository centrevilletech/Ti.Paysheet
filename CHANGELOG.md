# Changelog

## 1.0.0 — 2026-11-11

Initial release.

- `initialize({ publishableKey, stripeAccountId })`
- `presentPaymentSheet()`: payment mode (PaymentIntent) and setup mode (SetupIntent), customer by Customer
  Session client secret or ephemeral key, default billing details, billing-details collection, primary button
  label, layout, light/dark style, appearance (colours, corner radius, border, fonts, primary button)
- `presentCustomerSheet()`: list, add, remove and select saved payment methods with a Customer Session
- Apple Pay (iOS) and Google Pay (Android) as opt-in configuration
- One result per presentation (`completed` / `canceled` / `failed`, or `selected` for CustomerSheet) with Stripe's
  error code, message, decline code and type; runtime conditions `busy`, `unavailable`, `interrupted`
- Argument errors reject the Promise with an `Error` (`code: 'invalid_argument'` and `option`, or
  `'not_initialized'`); the optional callback is Node-style, `callback(error, result)`; nothing throws synchronously.
  The public functions live in a shared JavaScript layer packaged with both platforms
- iOS: refuses to present when the app links a different stripe-ios than the module was built against; `spm.json`
  pins stripe-ios exactly; `stripeVersion` / `stripeVersionRequired`
- iOS: a sheet whose window the app closed is settled as `interrupted` instead of blocking later presentations
- Android: `unavailable` when the app is not in the foreground or the sheet's activity does not start in 8 s
- No URLs, secrets or Stripe error messages in logs
- iOS: 3-D Secure / redirect hand-back handled automatically from Titanium's URL notifications; `handleURL()`
- Android: invisible host activity, so results survive rotation and process death (`takeRestoredResult()`,
  `restoredresult` event); `intent_in_terminal_state` when the sheet finds the intent already final
- stripe-ios 26.16.x (Swift Package `stripe-ios-spm` via `spm.json`, linked by the app; iOS 15+);
  stripe-android 23.26.0 (API 24+, compile/target 36)
- Shared argument-validation test vectors run on the JVM and with swiftc; XCUITest runner for the example
