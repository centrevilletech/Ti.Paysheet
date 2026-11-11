# Ti.Paysheet

Stripe's [PaymentSheet](https://docs.stripe.com/payments/accept-a-payment?platform=ios)
and [CustomerSheet](https://docs.stripe.com/elements/customer-sheet) for Titanium, on
iOS and Android, built on Stripe's current SDKs:

| Platform | Stripe SDK | Minimum |
| --- | --- | --- |
| iOS | [stripe-ios](https://github.com/stripe/stripe-ios) 26.16.x (`StripePaymentSheet`, Swift Package) | iOS 15 |
| Android | [stripe-android](https://github.com/stripe/stripe-android) 23.26.0 (`com.stripe:paymentsheet`) | API 24 (Android 7.0), target/compile 36 |

Titanium SDK 13.4.0.GA or later (the iOS side relies on the Swift Package support
that arrived in 13.4).

## Why this exists

Stripe's prebuilt payment UI is the safest way to take a card in a mobile app:
card numbers never touch your code or your server, 3-D Secure, Link, saved cards
and wallets are handled for you, and Stripe keeps it compliant. Titanium has had no
maintained, openly licensed wrapper for the current SDKs. The ones that exist wrap
2023-era SDK versions, accept only ephemeral keys (which pin your server to an old
Stripe API version), and on iOS cannot hand a 3-D Secure redirect back to the app.

This module wraps the current SDKs, accepts a
[Customer Session](https://docs.stripe.com/api/customer_sessions) client secret
(preferred) or an ephemeral key, and keeps the JavaScript API identical on both
platforms.

## Install

Download the zips for your platforms from
[Releases](https://github.com/centrevilletech/Ti.Paysheet/releases) and unzip them
into your project root (each zip contains a `modules/` directory):

```bash
unzip ti.paysheet-android-1.0.0.zip -d /path/to/your/app
unzip ti.paysheet-iphone-1.0.0.zip -d /path/to/your/app
```

Then add it and the URL scheme to `tiapp.xml` (see [tiapp.xml](#tiappxml) below for
what each part is for):

```xml
<modules>
    <module>ti.paysheet</module>
</modules>
<ios>
    <plist>
        <dict>
            <key>CFBundleURLTypes</key>
            <array>
                <dict>
                    <key>CFBundleURLName</key>
                    <string>com.example.myapp</string>
                    <key>CFBundleURLSchemes</key>
                    <array>
                        <string>myapp</string>
                    </array>
                </dict>
            </array>
        </dict>
    </plist>
</ios>
```

The iOS build fetches stripe-ios as a Swift Package the first time (Xcode needs
network access to `github.com` for that build; it is cached afterwards).

## Usage

```javascript
const Paysheet = require('ti.paysheet');

// Once, at startup, with your publishable key (never a secret key).
Paysheet.initialize({ publishableKey: 'pk_test_…' });

// Your server creates a PaymentIntent and a Customer Session and returns their
// client secrets (see "What your server must provide").
const result = await Paysheet.presentPaymentSheet({
    paymentIntentClientSecret: fromServer.paymentIntentClientSecret,
    merchantDisplayName: 'Example, Inc.',
    customer: {
        id: fromServer.customerId,
        customerSessionClientSecret: fromServer.customerSessionClientSecret
    },
    returnURL: 'myapp://stripe-redirect'
});

// A rejection means the call itself was wrong (see "Errors"), never a payment outcome.
switch (result.status) {
    case 'completed':
        // The customer finished. Confirm with YOUR server (webhook-driven) before
        // showing "paid": the result alone is not proof of payment.
        break;
    case 'canceled':
        // The customer closed the sheet. The same client secret can be presented again.
        break;
    case 'failed':
        Ti.API.error(result.error.code + ': ' + result.error.message);
        break;
}
```

Save a card without paying (setup mode):

```javascript
const result = await Paysheet.presentPaymentSheet({
    setupIntentClientSecret: fromServer.setupIntentClientSecret,
    merchantDisplayName: 'Example, Inc.',
    customer: { id: fromServer.customerId, customerSessionClientSecret: fromServer.customerSessionClientSecret },
    returnURL: 'myapp://stripe-redirect'
});
```

Manage saved payment methods (CustomerSheet):

```javascript
const result = await Paysheet.presentCustomerSheet({
    merchantDisplayName: 'Example, Inc.',
    customer: { id: customerId, customerSessionClientSecret: secret },
    returnURL: 'myapp://stripe-redirect',
    // Called only when the customer adds a payment method.
    fetchSetupIntentClientSecret: function (request) {
        myApi.createSetupIntent()
            .then(r => request.resolve(r.setupIntentClientSecret))
            .catch(e => request.reject(e.message));
    }
});
if (result.status === 'selected' && result.paymentOption) {
    Ti.API.info('chosen: ' + result.paymentOption.label); // e.g. "•••• 4242"
}
```

Every `present…` call returns a Promise and also accepts an optional Node-style
callback as its second argument, `callback(error, result)`. Each presentation
settles exactly once, and the call never throws.

## API

### `initialize(options)` → `Boolean`

| Option | Type | |
| --- | --- | --- |
| `publishableKey` | String | Required. `pk_test_…` or `pk_live_…`. |
| `stripeAccountId` | String | Optional connected account (`acct_…`) for Stripe Connect direct charges. Leave it out for destination charges and separate charges and transfers. |

Returns `false` (and logs why) if the options are invalid. Call it again to change
keys. The Stripe API version is the one the SDK was built for; it cannot be set.

`isInitialized` (read-only Boolean) tells you whether a valid key is set.

`stripeVersion` and `stripeVersionRequired` (read-only Strings): the Stripe SDK
version the app links and the one the module was built against. On iOS they must
be equal (see [Stripe SDK version](#stripe-sdk-version)).

### `presentPaymentSheet(options, [callback])` → `Promise<Result>`

Resolves with the [Result](#result) of the presentation; rejects only for
[argument errors](#errors).

| Option | Type | |
| --- | --- | --- |
| `paymentIntentClientSecret` | String | Payment mode. Exactly one of this and `setupIntentClientSecret`. |
| `setupIntentClientSecret` | String | Setup mode: save a payment method without charging. |
| `merchantDisplayName` | String | Required. Your business name, shown on the sheet. |
| `customer` | Object | Optional. `{ id, customerSessionClientSecret }` (preferred) or `{ id, ephemeralKeySecret }`. Exactly one of the two secrets. Enables saved payment methods. |
| `returnURL` | String | iOS: your app's URL that Stripe returns to after a redirect (3-D Secure in a browser, bank redirects), e.g. `myapp://stripe-redirect`. Strongly recommended; required for redirect-based methods. Ignored on Android, which needs nothing (see [tiapp.xml](#tiappxml)). |
| `allowsDelayedPaymentMethods` | Boolean | Default `false`. Allow methods that settle later (ACH, SEPA debit): `completed` then means "submitted", not "paid". |
| `defaultBillingDetails` | Object | `{ name, email, phone, address: { line1, line2, city, state, postalCode, country } }` used to prefill the form. |
| `billingDetailsCollection` | Object | `{ name, email, phone }` each `'automatic'`, `'never'` or `'always'`; `address`: `'automatic'`, `'never'` or `'full'`; `attachDefaultsToPaymentMethod` Boolean. |
| `primaryButtonLabel` | String | Replaces "Pay $10.99" / "Set up". |
| `paymentMethodLayout` | String | `'automatic'` (default), `'horizontal'` or `'vertical'`. |
| `style` | String | `'automatic'` (default, follows the system), `'light'` or `'dark'`. |
| `appearance` | Object | See [Appearance](#appearance). |
| `applePay` | Object | iOS only, off unless given: `{ merchantId, merchantCountryCode }`. See [Wallets](#wallets). |
| `googlePay` | Object | Android only, off unless given: `{ environment: 'test' \| 'production', countryCode, currencyCode }`. |

### `presentCustomerSheet(options, [callback])` → `Promise<CustomerSheetResult>`

Lists, adds and removes the customer's saved payment methods and lets them pick
one. Requires a Customer Session (no ephemeral-key mode).

| Option | Type | |
| --- | --- | --- |
| `merchantDisplayName` | String | Required. |
| `customer` | Object | Required. `{ id, customerSessionClientSecret }`; the session must enable the `customer_sheet` component. |
| `fetchSetupIntentClientSecret` | Function | Required. Called with a `request` object when the customer adds a payment method; call `request.resolve(setupIntentClientSecret)` or `request.reject(message)` once. Unanswered requests fail after 60 s, later answers are ignored, and an exception thrown by the function fails the request (Stripe then shows an error in the sheet). After an Android process restart the function no longer exists: adding a card then fails with "close and reopen the sheet"; listing and selecting still work. |
| `returnURL`, `defaultBillingDetails`, `billingDetailsCollection`, `style`, `appearance` | | As for PaymentSheet. |
| `headerTitle` | String | Replaces the sheet's title ("Manage your payment methods"). |
| `applePay` | Boolean | iOS: offer Apple Pay as a selectable option (default `false`). |
| `googlePay` | Boolean | Android: offer Google Pay as a selectable option (default `false`). |

### Result

| Property | |
| --- | --- |
| `status` | PaymentSheet: `'completed'`, `'canceled'` or `'failed'`. CustomerSheet: `'selected'`, `'canceled'` or `'failed'`. |
| `intentId` | PaymentSheet: the PaymentIntent or SetupIntent id (`pi_…`, `seti_…`), taken from the client secret. |
| `paymentOption` | CustomerSheet, when one is chosen: `{ id, label }`. `id` is a payment method id (`pm_…`), `'apple_pay'` or `'google_pay'`. On `canceled` it is the option that was selected before. |
| `error` | Only with `failed`: `{ code, message, declineCode, type }` (see below). |

`error.code` is Stripe's API error code when Stripe reported one (`card_declined`,
`expired_card`, `resource_missing`, `payment_intent_unexpected_state`…, identical on
both platforms); when Stripe's API answered without a code it is the error type
(`invalid_request_error`, e.g. for a client secret from another account); otherwise
one of this module's runtime codes:

| Code | When |
| --- | --- |
| `busy` | Another sheet from this module is on screen. |
| `unavailable` | The sheet cannot open: the app is not in the foreground (Android does not let a background app open a screen), there is no window to present from, the sheet did not start within 8 seconds (Android), or the app links a different stripe-ios version than the module was built against (iOS; the message names both). |
| `interrupted` | The sheet ended without a result from Stripe: the app closed the window the sheet was presented from (iOS; reported when the next sheet is presented), or the system finished the sheet's activity (Android). |
| `intent_in_terminal_state` | The intent was already final (succeeded, canceled, processing) when the sheet loaded it. Typical after a process restart: the payment went through before the sheet could report it. Ask your server. |
| `sdk_error` | The SDK failed without an API error code (no network, bad configuration…). `message` has Stripe's text. |

`declineCode` (`insufficient_funds`, `lost_card`…) and `type` (`card_error`,
`invalid_request_error`…) are set when Stripe returned them, otherwise `null`.
`message` is Stripe's localized message, suitable to show to the customer.

A declined card does not end the sheet: Stripe shows the decline in the sheet and
lets the customer try again or pick another method. The result arrives when they
finish (`completed`) or close it (`canceled`); `failed` is for errors that end the
sheet.

### Errors

Mistakes in the call are not payment outcomes, so they never resolve the Promise.
It **rejects** with an `Error`, nothing is shown, and the callback receives that
error as its first argument:

| `error.code` | When | Also |
| --- | --- | --- |
| `invalid_argument` | An option is missing, has the wrong type or an unknown value, or both intent secrets were given. | `error.option` names it, e.g. `'merchantDisplayName'`, `'customer.id'`, `'appearance.colors.primary'`. |
| `not_initialized` | `initialize()` has not been called with a valid publishable key. | |

```javascript
try {
    const result = await Paysheet.presentPaymentSheet(options);
    // completed / canceled / failed (busy, unavailable, interrupted…): show the right screen
} catch (e) {
    // a programming error: e.code, e.option, e.message. Do not tell the customer "payment failed".
}

Paysheet.presentPaymentSheet(options, (error, result) => {
    if (error) { /* programming error */ return; }
    /* result.status … */
});
```

The JavaScript side of this contract is the module's `ti.paysheet.js` (packaged into
both platforms' zips and merged into the native module by Titanium), so it is the
same code on iOS and Android.

### `handleURL(url)` → `Boolean`

iOS: passes a URL to Stripe (`StripeAPI.handleURLCallback`) and returns `true` if
Stripe recognised it. **The module already does this for you**: it listens for
the URLs Titanium receives (`Ti.App.iOS` `handleurl`), so you only need this if
your app routes URLs some other way. Android: always `false`.

### `takeRestoredResult()` → `Result` or `null`

Android: if the app's process was killed while a sheet was open (for example while
the customer was in their bank's app or a browser for 3-D Secure) and the sheet then
finished in the restarted process, the result is stored and returned here once, with
`restored: true`. The JavaScript Promise from the old process is gone. Call it at
startup and on the module's `restoredresult` event (the sheet usually finishes just
after the restarted app's JavaScript has started), and in any case ask your server
for the intent's status: after a restart Stripe often reports `failed` with
`intent_in_terminal_state` for a payment that in fact succeeded. iOS: always `null`.

```javascript
function checkRestored() {
    const r = Paysheet.takeRestoredResult();
    if (r && r.intentId) {
        myApi.paymentStatus(r.intentId).then(showStatus);
    }
}
Paysheet.addEventListener('restoredresult', checkRestored);
checkRestored();
```

### Events

| Event | |
| --- | --- |
| `restoredresult` | Android: a restored result is waiting; call `takeRestoredResult()`. Never fires on iOS. |

### Appearance

```javascript
appearance: {
    colors: {                       // '#RRGGBB', '#AARRGGBB' (Titanium order) or '#RGB'
        primary: '#0A84FF',         // accent: selected tab, links, focus
        background: '#FFFFFF',      // sheet background
        componentBackground: '#F2F2F7',
        componentBorder: '#D1D1D6',
        componentDivider: '#D1D1D6',
        text: '#111111',
        textSecondary: '#6B6B6B',
        componentText: '#111111',
        placeholderText: '#8E8E93',
        icon: '#6B6B6B',
        danger: '#D70015'
    },
    colorsDark: { /* same keys, used in dark mode */ },
    cornerRadius: 12,               // components and sheet, in points/dp
    borderWidth: 1,
    font: {
        family: 'Inter-Regular',    // see "Fonts" below
        scale: 1.0
    },
    primaryButton: {
        backgroundColor: '#0A84FF',
        textColor: '#FFFFFF',
        borderColor: '#00000000',
        cornerRadius: 24,
        borderWidth: 0,
        height: 52,
        font: { family: 'Inter-SemiBold', size: 17 },
        dark: { backgroundColor: '#0A84FF', textColor: '#FFFFFF', borderColor: '#00000000' }
    }
}
```

Anything left out keeps Stripe's default. When `colorsDark` (or
`primaryButton.dark`) is left out, the light colours are used in dark mode too.

**Fonts.** iOS: `family` is a PostScript font name, as for Titanium's own
`fontFamily`, so fonts already registered by your app work. Android: Stripe only
accepts a font *resource*, so put the font file in your app under
`platform/android/res/font/` (lower-case name, e.g. `inter_regular.ttf`) and give the
resource name (`'inter_regular'`). A family that cannot be found is ignored with a
warning.

Stripe's full appearance API is larger (shadows, per-row styles, insets); the
subset above is what both SDKs support the same way.

### Wallets

Both are off unless configured, and the module never forces them on.

**Apple Pay** (`applePay: { merchantId: 'merchant.com.example', merchantCountryCode: 'US' }`)
needs an Apple merchant identifier, the Apple Pay capability with that identifier
in your provisioning profile (`<entitlements>` in `tiapp.xml` or your profile), and
a Stripe Apple Pay certificate for that merchant id. Without them the Apple Pay row
simply does not appear.

**Google Pay** (`googlePay: { environment: 'test', countryCode: 'US', currencyCode: 'USD' }`)
needs Google Play services on the device, Google Pay enabled in your Stripe
Dashboard, and the Google Pay API switched on in your app's manifest (the module
does not add it, so apps that do not use Google Pay are not opted in):

```xml
<android xmlns:android="http://schemas.android.com/apk/res/android">
    <manifest>
        <application>
            <meta-data android:name="com.google.android.gms.wallet.api.enabled" android:value="true" />
        </application>
    </manifest>
</android>
```

`currencyCode` is required in setup mode. On devices without Play services the
Google Pay row does not appear.

Neither wallet has been tested by the maintainers yet (see
[Verification](#verification)).

## tiapp.xml

**iOS: a URL scheme, for 3-D Secure and bank redirects.** Some authentication steps
leave the app (a bank's app, or Safari). Stripe sends the customer back to
`returnURL`, so its scheme must be registered (`CFBundleURLTypes` as in
[Install](#install)) and `returnURL` must use it: scheme `myapp` →
`returnURL: 'myapp://stripe-redirect'` (the path is up to you; Stripe matches on
the URL it was given). The module forwards incoming URLs to Stripe itself, and
Stripe ignores URLs that are not its own, so the same scheme can carry your other
deep links. No other iOS keys are needed: Stripe's camera card scanner asks for
nothing unless you add `NSCameraUsageDescription`, in which case the "Scan card"
button appears.

**Android: nothing to add for payments**, but know what stripe-android adds to
your app's merged manifest (for Play review and the Data safety form):

| Added by stripe-android | What for | Can be removed when unused |
| --- | --- | --- |
| Permissions `INTERNET`, `ACCESS_NETWORK_STATE` | API calls (Titanium declares both anyway) | no |
| Permission `NFC`, activity `com.stripe.android.common.nfcscan.NfcScanningActivity` | reading a contactless card by tapping it on the phone | yes |
| Permission `VIBRATE` | haptic feedback in the sheet | yes (harmless to keep) |
| Exported activity `com.stripe.android.payments.StripeBrowserProxyReturnActivity` (`stripesdk://payment_return_url/<application id>`) | return from 3-D Secure and bank redirects in a browser | **no** |
| Exported activity `com.stripe.android.link.LinkRedirectHandlerActivity` (`link-popup://complete`) | Stripe Link sign-in | only if Link cannot be offered (your Dashboard's payment method settings) |
| Exported activity `com.stripe.android.financialconnections.lite.FinancialConnectionsSheetLiteRedirectActivity` (`stripe://financial-connections-lite`) | linking a US bank account (ACH) | if bank debits cannot be offered |
| Exported service `com.stripe.android.googlepaylauncher.callback.StripeGooglePayPaymentDataCallbacksService`, protected by `com.google.android.gms.permission.BIND_PAYMENTS_CALLBACK_SERVICE` | Google Pay | if you do not use Google Pay |
| Service `androidx.camera.core.impl.MetadataHolderService` (not exported) | card scanning with the camera | yes |
| Activity `com.google.android.play.core.common.PlayCoreDialogWrapperActivity` (not exported) | Google Play dialogs used by Stripe's device attestation | keep |
| `<queries>` for `com.android.chrome` and `com.google.android.apps.maps` | choosing the browser for redirects; address autocomplete | keep |

The module itself adds one non-exported activity (`ti.paysheet.PaysheetHostActivity`).
No location, contacts, camera or storage permission is declared; the camera is used
only if the customer taps "Scan card", through the system permission prompt.

To drop the optional parts, add Android's manifest merge rules to `tiapp.xml`. This
set was tested: card and 3-D Secure payments still complete without them.

```xml
<android xmlns:android="http://schemas.android.com/apk/res/android">
    <manifest xmlns:tools="http://schemas.android.com/tools">
        <uses-permission android:name="android.permission.NFC" tools:node="remove" />
        <application>
            <activity android:name="com.stripe.android.common.nfcscan.NfcScanningActivity" tools:node="remove" />
            <service android:name="androidx.camera.core.impl.MetadataHolderService" tools:node="remove" />
            <activity android:name="com.stripe.android.link.LinkRedirectHandlerActivity" tools:node="remove" />
            <activity android:name="com.stripe.android.financialconnections.lite.FinancialConnectionsSheetLiteRedirectActivity" tools:node="remove" />
        </application>
    </manifest>
</android>
```

Remove the Link and Financial Connections entries only if those payment methods
cannot be offered to your customers (your Stripe Dashboard settings decide what the
sheet shows), and never remove the browser return activity.

Apple Pay additionally needs the merchant entitlement:

```xml
<ios>
    <entitlements>
        <dict>
            <key>com.apple.developer.in-app-payments</key>
            <array>
                <string>merchant.com.example</string>
            </array>
        </dict>
    </entitlements>
</ios>
```

## What your server must provide

The module never talks to your server. Your server, with your **secret** key,
creates the objects below and hands the app their client secrets. Use any
Stripe API version your account supports: Customer Sessions make the SDK's own
API version irrelevant to your server. An ephemeral key, by contrast, is created
with a `Stripe-Version` header: Stripe's current guide shows the account's latest
dated API version there. The pinned SDKs' own API versions are `2020-08-27`
(stripe-ios 26.x) and `2020-03-02` (stripe-android 23.x). One more reason to prefer
Customer Sessions.

| For | Create | Hand the app |
| --- | --- | --- |
| Payment | `POST /v1/payment_intents` with `amount`, `currency`, `customer`, `automatic_payment_methods[enabled]=true` (do not hard-code `payment_method_types`) | `client_secret` as `paymentIntentClientSecret` |
| Save a card | `POST /v1/setup_intents` with `customer`, `automatic_payment_methods[enabled]=true` | `client_secret` as `setupIntentClientSecret` |
| Saved cards in PaymentSheet | `POST /v1/customer_sessions` with `customer`, `components[mobile_payment_element][enabled]=true` and the features you want: `payment_method_save`, `payment_method_redisplay`, `payment_method_remove` (each `=enabled`) | `client_secret` as `customer.customerSessionClientSecret`, plus `customer.id` |
| CustomerSheet | `POST /v1/customer_sessions` with `components[customer_sheet][enabled]=true` (and `[features][payment_method_remove]=enabled`) | the same; one session may enable both components |
| Fallback without sessions | `POST /v1/ephemeral_keys` with `customer` and a `Stripe-Version` header (see above) | `secret` as `customer.ephemeralKeySecret` |
| Connect direct charges | the objects above on the connected account (`Stripe-Account` header) | also call `initialize({ stripeAccountId })` |

Customer Session secrets expire after 30 minutes: create one per presentation.
For Stripe Connect *destination* charges (the platform's PaymentIntent with
`transfer_data[destination]`), nothing changes in the app.

The sheet's result is **not** proof of payment. Fulfil from your server's
`payment_intent.succeeded` / `setup_intent.succeeded` webhook, and have the app ask
your server before it shows "paid".

## Platform notes

**Android.** PaymentSheet must be created while an activity is being created, which
a Titanium module cannot do in your window's activity. The module therefore starts a
small invisible activity of its own that hosts the sheet. That activity survives
rotation and other configuration changes, and if Android kills the process while the
customer is in a browser or bank app, the sheet still completes in the restarted
process (see `takeRestoredResult()`). Titanium cannot restore its own windows after
such a restart: it closes them and starts the app again, and the new window would
open on top of the still-running sheet. When the host activity finds itself restored
in a new process it therefore turns opaque, so Android does not bring the Titanium
window back until the sheet has finished. That needs Android 11 (API 30) or later; on
older versions the restarted app can cover the sheet until the customer goes back to
it.

If the host activity does not start within 8 seconds (Android blocks activity starts
from an app that has just gone to the background, or the start fails), the
presentation resolves `unavailable` and a late start shows nothing. A presentation
asked for while the app is not in the foreground resolves `unavailable` at once.

- ABIs: the module has no native code of its own beyond Titanium's generated
  bindings; it is built for arm64-v8a, armeabi-v7a, x86 and x86_64, and the 64-bit
  libraries are 16 KB page-size aligned (Android 15+; the requirement applies to
  64-bit ABIs). Stripe's AARs are pure JVM code.
- Dependencies: `com.stripe:paymentsheet:23.26.0`, which brings Kotlin stdlib 2.2,
  Jetpack Compose 1.10, AndroidX Activity 1.12 and Play services Wallet 20.0
  (the Wallet library is linked, but Google Pay is only offered when `googlePay` is
  set and your manifest enables the Wallet API). Titanium 13.4 builds with Kotlin
  2.3, compile SDK 36 and AGP 9.1, which accept these. Expect roughly 6–8 MB more in
  the APK.
- R8: Stripe's AARs ship their own consumer rules; the module adds rules that keep
  its own classes. If your app enables ProGuard, nothing else is needed.

**iOS.** The module is a static Swift framework (`TiPaysheet.xcframework`, arm64 device,
arm64 and x86_64 simulator, about 300 KB). stripe-ios is declared in the module's
`spm.json` with `"linkage": "host"`, which Titanium 13.4 turns into a Swift Package
reference (`stripe/stripe-ios-spm`, Stripe's lightweight SwiftPM mirror, exactly
26.16.1, see [Stripe SDK version](#stripe-sdk-version)) in your app's generated Xcode
project. The app links
`StripePaymentSheet` once, and Xcode copies Stripe's resource bundles and their
`PrivacyInfo.xcprivacy` files into the app. Nothing of Stripe is vendored into the
module zip, so another module that uses stripe-ios the same way shares the one copy.
The module itself collects nothing and uses no required-reason API, so it carries no
privacy manifest of its own.

Why Swift Package Manager rather than a bundled binary: Stripe publishes stripe-ios
as Swift Packages and (dynamic) XCFrameworks. Bundling the XCFrameworks would put
tens of megabytes of Stripe binaries in the module zip, pin every app to the module's copy, and need
embedding and resource handling Titanium does not do for module frameworks. CocoaPods
is in maintenance and Titanium apps do not use it. Titanium 13.4 adds Swift Packages
to the app project itself, so the app resolves, links and copies resources exactly as
a native Xcode app would. Built and run with Xcode 27.1 (iOS 27 SDK) and Titanium
13.4.1.GA.

Three details make a host-linked package work for a prebuilt module, all in this
repository (see "Building from source"): the module target compiles against Stripe
through a helper target instead of linking it (otherwise Xcode merges Stripe into the
static archive and the app gets duplicate classes); it points Swift at the generated
module map of Stripe's one Objective-C target (`Stripe3DS2`); and a module-build hook
switches off `BUILD_LIBRARY_FOR_DISTRIBUTION`, because on the command line that would
also compile Stripe with library evolution and the module would expect symbols that
the app's normal build of Stripe does not have.

### Stripe SDK version

On iOS the app must link **exactly** the stripe-ios version the module was built
against (26.16.1 for 1.0.0). Stripe's Swift packages are not built with library
evolution, so the module's compiled code contains the memory layout of Stripe's
structs (`PaymentSheet.Configuration`, `Appearance`…); a release that adds a field to
one of them would make the module read and write the wrong memory. Nothing in Swift
or in the module can remove that dependency: it would take Stripe building its
packages for distribution, or the app compiling the module's sources itself, which
Titanium modules do not do.

How it is enforced:

- **Exact pin.** Titanium 13.4 can only write `{ kind, minimumVersion }` for a
  module's Swift package (an `exactVersion` written that way does not resolve, a
  `versionRange` without a maximum makes Xcode fail to open the project). The
  module's `spm.json` therefore asks for a `versionRange` whose minimum is
  `"26.16.1; maximumVersion = 26.16.2"`: Titanium copies the string into the app
  project unchanged, which yields the range [26.16.1, 26.16.2), i.e. exactly 26.16.1.
  This relies on Titanium not quoting the value; if a later SDK does, the app build
  stops with an error instead of silently resolving another version. A change adding
  real `exactVersion` support to Titanium has been prepared.
- **Run-time guard.** Before presenting, the module compares the stripe-ios version
  the app links (`STPAPIClient.STPSDKVersion`) with its own. On a mismatch it shows
  nothing and resolves `failed` / `unavailable` with a message naming both versions.

How to check: `Paysheet.stripeVersion` must equal `Paysheet.stripeVersionRequired`,
and the app build's `Package.resolved`
(`build/iphone/*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`)
must list `stripe-ios-spm` at that version. If another module in the same app also
asks for stripe-ios, Titanium uses the first request it sees and only warns; make
sure every such module asks for the same version.

Android has no such constraint: Gradle resolves the pinned stripe-android 23.26.0,
and JVM code does not depend on field layouts.

### Security and privacy

- Client secrets and keys are never logged. The module logs option names, error
  codes and types, never URLs (Stripe's return URLs carry client secrets), Stripe's
  error messages or `userInfo`.
- Android: the sheet's options, including the client secrets, travel to the host
  activity in its Intent extras (in memory, in your app's process). The activity's
  saved state holds two booleans. A result kept for `takeRestoredResult()` holds the
  status, the intent id and the error, never a secret, in the app's private
  SharedPreferences, and is removed when read.
- iOS: nothing is stored.

## Not included (yet)

- **Deferred intents** (`IntentConfiguration`: show the sheet before the server
  creates the intent). It needs a round trip from the SDK's confirm callback into
  JavaScript and back while the sheet waits, a second server endpoint, and has
  different confirmation rules on each platform. Create the intent first, as above.
- **FlowController / Embedded Payment Element** (choose now, pay later; inline
  form). PaymentSheet and CustomerSheet cover the common cases.
- **"Set as default"** for saved cards: the Customer Session feature is not
  generally available in Stripe's API yet. CustomerSheet's selection is remembered
  on the device; send `paymentOption.id` to your server if it should become the
  customer's default.
- **Address Element, Link-only flows, Financial Connections, card scanning
  configuration, Stripe Terminal.**

## Building from source

```bash
./build.sh            # Android here; Android and iOS on macOS
./build.sh android
./build.sh ios        # needs Xcode and network access for the Swift Package
```

Needs the Titanium CLI and SDK 13.4.x. The Titanium CLI refuses to build a module
that lives inside an app project, which is why `build.sh` copies the platform folder
to a temp directory first.

How the iOS project is set up (if you regenerate it from Titanium's Swift module
template, redo these):

- The package reference in `paysheet.xcodeproj` is `exactVersion` 26.16.1, and
  `TiPaysheetModule.builtAgainstStripeVersion` names the same version; update both
  (and `spm.json`) together.
- `TiPaysheet` target: `MACH_O_TYPE = staticlib` (Titanium embeds only dynamic
  module frameworks; a static one is linked into the app), iOS 15 deployment target,
  `SWIFT_EMIT_MODULE_INTERFACE = YES`, and
  `OTHER_SWIFT_FLAGS = -Xcc -fmodule-map-file=$(GENERATED_MODULEMAP_DIR)/Stripe3DS2.modulemap`.
- A `StripeDependencies` static-library target owns the Swift Package product
  `StripePaymentSheet`; `TiPaysheet` depends on that target (for build order and the
  Swift modules) but has no package product of its own, so nothing of Stripe is
  linked into it. Check with `nm -defined-only` that the archive has no Stripe symbols.
- `hooks/ti.paysheet.buildflags.js` sets `BUILD_LIBRARY_FOR_DISTRIBUTION=NO` for the
  module's own `xcodebuild` runs. It is a module-build hook; it ships in the zip but
  does nothing in app builds.
- Stripe is imported with `@_implementationOnly`, so no Stripe type appears in the
  module's Swift interface.

Tests:

```bash
node --test test/js/*.test.js   # the shared JavaScript layer (Promise, rejections, callback), with a fake native module
test/run-android-unit.sh     # plain JVM, no device: option validation and results (test/vectors.json) and the
                             # presentation lifecycle with a fake clock (busy, watchdog, start failure, restored
                             # results, SetupIntent requests: timeout, late and repeated answers, throwing callback,
                             # process death)
test/run-ios-unit.sh         # macOS, swiftc: the same vectors and the lifecycle, plus "interrupted" when the
                             # sheet's window was closed under it
```

`test/ios-ui/` is an XCUITest runner (a [Tuist](https://tuist.dev) project) that
drives the example app's sheets on a simulator with Stripe's test cards.

The [example app](example/) has a screen per mode and a local test server; see
[example/README.md](example/README.md).

## Verification

What was run for 1.0.0, on 2026-11-11, with Stripe **test mode** keys, the example
app and its server, Titanium SDK 13.4.1.GA. "Server" means the example server then
read the intent back from Stripe's API.

| Check | Android | iOS |
| --- | --- | --- |
| Environment | Android 15 (API 35) x86_64 container image, no Google Play services | iOS 27.0 simulator (iPhone 17), Xcode 27.1, macOS 26.6 |
| Module builds; ABIs / slices | arm64-v8a, armeabi-v7a, x86, x86_64; 64-bit `.so` 16 KB aligned | arm64 device, arm64 + x86_64 simulator; static, no Stripe code inside |
| Shared JavaScript layer (`node --test test/js/*.test.js`, 8 cases) | ✅ (same file on both) | ✅ |
| Option validation and results (`test/vectors.json`, 65 cases) | ✅ JVM | ✅ swiftc |
| Lifecycle with fakes (busy, interrupted, watchdog, start failure, restored result, SetupIntent timeout / late / repeated answers, throwing callback, process death) | ✅ 13 cases | ✅ 10 cases |
| Contract through the real module (example self-test, 15 checks: rejections with `code` and `option`, no synchronous throw, callback once) | ✅ | ✅ |
| Payment, guest, card 4242 → `completed`; server: `succeeded` | ✅ | ✅ (XCUITest) |
| Payment with Customer Session, card saved, later paid with the saved card | ✅ | ✅ |
| Payment with ephemeral key | ✅ | ✅ |
| Declined card 4000…0002: shown in the sheet, close → `canceled` (once) | ✅ | ✅ |
| 3-D Secure challenge 4000…3155 → `completed`; server: `succeeded` | ✅ (Stripe's in-app web view) | ✅ |
| 3-D Secure by redirect 4000…3063, back through `returnURL` → `completed` | – (Android needs no return URL) | ✅ the app received `paysheetexample://stripe-redirect` and the payment completed |
| Setup mode (new card) → `completed`; server: SetupIntent `succeeded` | ✅ | ✅ |
| CustomerSheet: list, add (through `fetchSetupIntentClientSecret`), select → `selected` with `pm_…` | ✅ | ✅ |
| CustomerSheet: remove a card | ✅ | not run |
| Invalid client secret → `failed`, `invalid_request_error` | ✅ | ✅ |
| Rotation with the sheet open, then close → one `canceled` | ✅ (host activity recreated) | ✅ |
| Presentation requested while the app is in the background → `unavailable`, next one opens normally | ✅ | – |
| Window closed under an open sheet → next presentation settles it `interrupted` and opens | – | ✅ |
| Process killed during 3-D Secure, sheet finished after restart → `takeRestoredResult()` / `restoredresult`; server: `succeeded` | ✅ | n/a |
| App linked against another stripe-ios (26.16.0) → `unavailable` naming both versions, no sheet | n/a | ✅ |
| `spm.json` exact pin → app resolves exactly 26.16.1 (and 26.16.0 when asked for 26.16.0) | n/a | ✅ |
| Manifest entries for NFC, card scanning, Link, Financial Connections removed → card and 3-D Secure payments still complete | ✅ | – |
| App backgrounded with a sheet open (Home, back, then pay) → `completed` | ✅ | not run |
| Custom appearance (colours, radius, button) visible | ✅ | ✅ |
| Fonts (`appearance.font`) | not run | not run |
| Host-activity watchdog (start silently blocked while the app is in the foreground) | unit test only | – |
| Apple Pay | – | **not tested** (needs a merchant id, a Stripe Apple Pay certificate and a signed build) |
| Google Pay | **not tested** (no Play services on the test image) | – |
| Physical devices | **not tested** | **not tested** |
| ProGuard / R8 minified release build | **not tested** | – |

## Third-party notices

The module's binaries link these at app build time (they are fetched by Gradle and
Swift Package Manager, not copied into this repository or the release zips):

| Component | Licence |
| --- | --- |
| [stripe-ios](https://github.com/stripe/stripe-ios) (StripePaymentSheet and the Stripe packages it depends on) | MIT, Copyright (c) 2011- Stripe, Inc. stripe-ios also bundles MediaPipe card-scanning models under Apache-2.0 (its `LICENSE-MediaPipe`). |
| [stripe-android](https://github.com/stripe/stripe-android) (`paymentsheet` and its Stripe modules) | MIT, Copyright (c) 2011- Stripe, Inc. |
| AndroidX, Jetpack Compose, Kotlin, kotlinx (transitive, Android) | Apache-2.0 |
| Dagger, Accompanist (transitive, Android) | Apache-2.0 |
| Google Play services Wallet (transitive, Android) | Android Software Development Kit License |
| Poko annotations (transitive, Android) | Apache-2.0 |

`ios/hooks/ti.swiftsupport.js`, `ios/.clang-format` and the generated
`TiPaysheetModuleAssets` files come from the Titanium SDK's module template
(Apache-2.0, TiDev, Inc.). Titanium SDK is Apache-2.0. Stripe is a trademark of Stripe, Inc.; this module is
not made or endorsed by Stripe.

## License

Apache-2.0. Copyright (c) 2026 Centreville Tech LLC. See [LICENSE](LICENSE).
