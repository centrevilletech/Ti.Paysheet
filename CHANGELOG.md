# Changelog

## 1.0.0 — unreleased

Initial release.

- `initialize({ publishableKey, stripeAccountId })`
- `presentPaymentSheet()`: payment mode (PaymentIntent) and setup mode (SetupIntent), customer by Customer
  Session client secret or ephemeral key, default billing details, billing-details collection, primary button
  label, layout, light/dark style, appearance (colours, corner radius, border, fonts, primary button)
- `presentCustomerSheet()`: list, add, remove and select saved payment methods with a Customer Session
- Apple Pay (iOS) and Google Pay (Android) as opt-in configuration
- One result per presentation (`completed` / `canceled` / `failed`, or `selected` for CustomerSheet) with Stripe's
  error code, message, decline code and type; Promise and optional callback
- iOS: 3-D Secure / redirect hand-back handled automatically from Titanium's URL notifications; `handleURL()`
- Android: invisible host activity, so results survive rotation and process death (`takeRestoredResult()`,
  `restoredresult` event); `intent_in_terminal_state` when the sheet finds the intent already final
- stripe-ios 26.16.x (Swift Package `stripe-ios-spm` via `spm.json`, linked by the app; iOS 15+);
  stripe-android 23.26.0 (API 24+, compile/target 36)
- Shared argument-validation test vectors run on the JVM and with swiftc; XCUITest runner for the example
