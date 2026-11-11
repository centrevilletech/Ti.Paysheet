# Ti.Paysheet example

A classic Titanium app with one button per mode, and a tiny Node server that makes the
Stripe calls a real backend would make, in **test mode**.

```
server/server.js    PaymentIntents, SetupIntents, Customer Sessions, ephemeral keys
app/                the Titanium app (tiapp.xml, Resources/app.js)
build.sh            builds the app against ../dist/*.zip
```

## 1. Keys

Use a Stripe **test-mode** key pair from your own Stripe account (Dashboard → Developers →
API keys). Never commit them. Either export them:

```bash
export STRIPE_SECRET_KEY=sk_test_…  STRIPE_PUBLISHABLE_KEY=pk_test_…
```

or copy `server/config.example.json` to `server/config.json` (git-ignored) and fill it
in. The server refuses live keys. It creates one anonymous Customer per run
("ti.paysheet example customer") and sends Stripe nothing else about anyone.

## 2. Run

```bash
node server/server.js                 # http://127.0.0.1:4242 (Node 18+)
../build.sh android && ./build.sh android
adb reverse tcp:4242 tcp:4242         # so the app's http://localhost:4242 reaches the server
adb install -r app/build/android/app/build/outputs/apk/debug/app-debug.apk
```

On macOS for iOS, run the server on the Mac (the simulator shares its localhost):

```bash
../build.sh ios && ./build.sh ios
xcrun simctl install <simulator> "app/build/iphone/build/Products/Debug-iphonesimulator/Paysheet Example.app"
```

The app's publishable key comes from the server (`GET /config`); nothing is stored in
the app.

## 3. What each button does

| Button | Exercises |
| --- | --- |
| Pay $10.99 (Customer Session) | payment mode, saved cards via `customerSessionClientSecret`, custom appearance |
| Pay $10.99 (ephemeral key) | payment mode with the ephemeral-key fallback |
| Pay $10.99 (guest) | payment mode without a customer |
| Save a card (setup mode) | SetupIntent, `primaryButtonLabel` |
| Manage saved cards (CustomerSheet) | list / add / remove / select; `fetchSetupIntentClientSecret` round trip; callback style |
| Invalid client secret | a clean `failed` result |
| Run self-test | argument validation against the real module (also runs at launch; logs `[SELFTEST] PASS n/n`) |

After `completed` the app asks the server for the intent's status, as a real app must.

Stripe test cards: `4242 4242 4242 4242` (succeeds), `4000 0000 0000 0002` (declined),
`4000 0025 0000 3155` (3-D Secure challenge), `4000 0000 0000 3063` (3-D Secure by
redirect, exercises `returnURL` on iOS). Any future expiry, any CVC, any ZIP.
