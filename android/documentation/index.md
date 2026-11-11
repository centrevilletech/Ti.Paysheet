# Ti.Paysheet

Stripe PaymentSheet and CustomerSheet for Titanium (iOS and Android).

```javascript
const Paysheet = require('ti.paysheet');
Paysheet.initialize({ publishableKey: 'pk_test_…' });
const result = await Paysheet.presentPaymentSheet({
    paymentIntentClientSecret: secret,
    merchantDisplayName: 'Example, Inc.'
});
// result.status: 'completed' | 'canceled' | 'failed'
```

Methods: `initialize(options)`, `presentPaymentSheet(options, [callback])`,
`presentCustomerSheet(options, [callback])`, `handleURL(url)`, `takeRestoredResult()`.
Property: `isInitialized`.

Full documentation: https://github.com/centrevilletech/Ti.Paysheet
