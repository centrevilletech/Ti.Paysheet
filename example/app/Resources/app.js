// Ti.Paysheet example: one button per mode, talking to the test server in ../server.
// Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
//
// Start the server (see example/README.md), then on Android `adb reverse tcp:4242 tcp:4242`, so that
// http://localhost:4242 reaches it from the device or emulator. The iOS simulator shares the Mac's localhost.
'use strict';

const Paysheet = require('ti.paysheet');

const SERVER = 'http://localhost:4242';
const RETURN_URL = 'paysheetexample://stripe-redirect';
const MERCHANT = 'Example Store';

// A small design system, to show that the sheet can follow the app's look.
const APPEARANCE = {
	colors: {
		primary: '#2F6FED',
		background: '#FFFFFF',
		componentBackground: '#F4F6FA',
		componentBorder: '#D5DAE3',
		componentDivider: '#D5DAE3',
		text: '#141A26',
		textSecondary: '#5B6475',
		componentText: '#141A26',
		placeholderText: '#8A93A3',
		icon: '#5B6475',
		danger: '#C62828'
	},
	colorsDark: {
		primary: '#7EA6FF',
		background: '#11151C',
		componentBackground: '#1C222C',
		componentBorder: '#2E3644',
		componentDivider: '#2E3644',
		text: '#F1F4F9',
		textSecondary: '#A9B2C3',
		componentText: '#F1F4F9',
		placeholderText: '#7D8698',
		icon: '#A9B2C3',
		danger: '#FF6E6E'
	},
	cornerRadius: 10,
	borderWidth: 1,
	primaryButton: {
		backgroundColor: '#2F6FED',
		textColor: '#FFFFFF',
		cornerRadius: 24,
		height: 50
	}
};

// ---------------------------------------------------------------------------------------------------------------- UI

const win = Ti.UI.createWindow({ backgroundColor: '#fff', title: 'Paysheet Example' });
const scroll = Ti.UI.createScrollView({ layout: 'vertical', contentHeight: Ti.UI.SIZE, top: 40 });
win.add(scroll);

const status = Ti.UI.createLabel({
	id: 'status', top: 8, left: 16, right: 16, height: Ti.UI.SIZE, color: '#141A26',
	font: { fontSize: 14, fontWeight: 'bold' }, text: 'ready'
});
const log = Ti.UI.createLabel({
	id: 'log', top: 8, left: 16, right: 16, height: Ti.UI.SIZE, color: '#5B6475', font: { fontSize: 11 }, text: ''
});

function button(title, handler) {
	const b = Ti.UI.createButton({ title, top: 6, left: 16, right: 16, height: 40 });
	b.addEventListener('click', handler);
	scroll.add(b);
	return b;
}

function show(label, value) {
	const text = label + ': ' + (typeof value === 'string' ? value : JSON.stringify(value));
	Ti.API.info('[EXAMPLE] ' + text);
	status.text = text;
	log.text = (text + '\n' + log.text).slice(0, 3000);
}

// ------------------------------------------------------------------------------------------------------------ server

function request(method, path, body) {
	return new Promise((resolve, reject) => {
		const xhr = Ti.Network.createHTTPClient({
			timeout: 20000,
			onload: () => {
				try {
					resolve(JSON.parse(xhr.responseText));
				} catch (e) {
					reject(new Error('bad response from server'));
				}
			},
			onerror: (e) => reject(new Error('server: ' + (xhr.responseText || e.error)))
		});
		xhr.open(method, SERVER + path);
		xhr.setRequestHeader('Content-Type', 'application/json');
		xhr.send(method === 'POST' ? JSON.stringify(body || {}) : null);
	});
}

const post = (path, body) => request('POST', path, body);

async function ensureInitialized() {
	if (!Paysheet.isInitialized) {
		const config = await request('GET', '/config');
		if (!Paysheet.initialize({ publishableKey: config.publishableKey })) {
			throw new Error('initialize failed');
		}
	}
}

// What a real app does after "completed": ask its own server, which asks Stripe.
async function confirmOnServer(result) {
	if (result.status === 'completed' && result.intentId) {
		const s = await post('/intent-status', { id: result.intentId });
		show('server says', s.id + ' ' + s.status);
	}
}

// ------------------------------------------------------------------------------------------------------------- flows

async function pay(customerMode) {
	try {
		await ensureInitialized();
		show('creating', 'PaymentIntent (' + customerMode + ')');
		const s = await post('/payment-sheet', { amount: 1099, customer: customerMode });
		const customer = s.customerId
			? (s.customerSessionClientSecret
				? { id: s.customerId, customerSessionClientSecret: s.customerSessionClientSecret }
				: { id: s.customerId, ephemeralKeySecret: s.ephemeralKeySecret })
			: undefined;
		const result = await Paysheet.presentPaymentSheet({
			paymentIntentClientSecret: s.paymentIntentClientSecret,
			merchantDisplayName: MERCHANT,
			customer,
			returnURL: RETURN_URL,
			appearance: APPEARANCE,
			defaultBillingDetails: { address: { country: 'US' } }
		});
		show('payment result', result);
		await confirmOnServer(result);
	} catch (e) {
		show('error', e.message);
	}
}

async function saveCard() {
	try {
		await ensureInitialized();
		const s = await post('/setup-sheet', { customer: 'session' });
		const result = await Paysheet.presentPaymentSheet({
			setupIntentClientSecret: s.setupIntentClientSecret,
			merchantDisplayName: MERCHANT,
			customer: { id: s.customerId, customerSessionClientSecret: s.customerSessionClientSecret },
			returnURL: RETURN_URL,
			appearance: APPEARANCE,
			primaryButtonLabel: 'Save card'
		});
		show('setup result', result);
		await confirmOnServer(result);
	} catch (e) {
		show('error', e.message);
	}
}

async function manageCards() {
	try {
		await ensureInitialized();
		const s = await post('/customer-sheet');
		// The callback form, to show it works too; the Promise is ignored here.
		Paysheet.presentCustomerSheet({
			merchantDisplayName: MERCHANT,
			customer: { id: s.customerId, customerSessionClientSecret: s.customerSessionClientSecret },
			returnURL: RETURN_URL,
			appearance: APPEARANCE,
			fetchSetupIntentClientSecret: (request) => {
				show('customer sheet', 'needs a SetupIntent');
				post('/setup-intent')
					.then((r) => request.resolve(r.setupIntentClientSecret))
					.catch((e) => request.reject(e.message));
			}
		}, (error, result) => show('customer sheet result', error ? error.code + ': ' + error.message : result));
	} catch (e) {
		show('error', e.message);
	}
}

async function invalidSecret() {
	try {
		await ensureInitialized();
		const result = await Paysheet.presentPaymentSheet({
			paymentIntentClientSecret: 'pi_0000000000000000000000_secret_invalid0000000000000000',
			merchantDisplayName: MERCHANT
		});
		show('invalid secret result', result);
	} catch (e) {
		show('error', e.message);
	}
}

// --------------------------------------------------------------------------------------------------------- self-test
// The JavaScript contract against the real module on the device. Logs "[SELFTEST] PASS n/n" for the test script.

async function selfTest() {
	const cases = [
		['no options', undefined, 'options'],
		['no secret', { merchantDisplayName: MERCHANT }, 'paymentIntentClientSecret'],
		['both secrets', { paymentIntentClientSecret: 'pi_1_secret_2', setupIntentClientSecret: 'seti_1_secret_2', merchantDisplayName: MERCHANT }, 'paymentIntentClientSecret'],
		['no merchant', { paymentIntentClientSecret: 'pi_1_secret_2' }, 'merchantDisplayName'],
		['customer without secret', { paymentIntentClientSecret: 'pi_1_secret_2', merchantDisplayName: MERCHANT, customer: { id: 'cus_1' } }, 'customer'],
		['customer with both secrets', { paymentIntentClientSecret: 'pi_1_secret_2', merchantDisplayName: MERCHANT, customer: { id: 'cus_1', ephemeralKeySecret: 'ek_1', customerSessionClientSecret: 'cuss_1' } }, 'customer'],
		['bad colour', { paymentIntentClientSecret: 'pi_1_secret_2', merchantDisplayName: MERCHANT, appearance: { colors: { primary: 'blue' } } }, 'appearance.colors.primary'],
		['bad style', { paymentIntentClientSecret: 'pi_1_secret_2', merchantDisplayName: MERCHANT, style: 'sepia' }, 'style'],
		['google pay setup without currency', { setupIntentClientSecret: 'seti_1_secret_2', merchantDisplayName: MERCHANT, googlePay: { countryCode: 'US' } }, 'googlePay.currencyCode']
	];
	let passed = 0;
	const total = cases.length + 6;
	const check = (name, ok, detail) => {
		if (ok) {
			passed++;
		}
		Ti.API.info('[SELFTEST] ' + (ok ? 'ok   ' : 'FAIL ') + name + (ok ? '' : ' ' + JSON.stringify(detail)));
	};
	const rejection = async (promise) => {
		try {
			return { resolved: await promise };
		} catch (e) {
			return { error: e };
		}
	};
	const isArgumentError = (r, option) => r.error instanceof Error && r.error.code === 'invalid_argument'
		&& r.error.option === option && typeof r.error.message === 'string';

	check('initialize rejects a secret key', Paysheet.initialize({ publishableKey: 'sk_test_x' }) === false, null);
	for (const [name, options, option] of cases) {
		const r = await rejection(Paysheet.presentPaymentSheet(options));
		check(name + ' rejects', isArgumentError(r, option), r.error ? { code: r.error.code, option: r.error.option } : r);
	}
	const cs = await rejection(Paysheet.presentCustomerSheet({
		merchantDisplayName: MERCHANT, customer: { id: 'cus_1', customerSessionClientSecret: 'cuss_1' }
	}));
	check('customer sheet needs fetchSetupIntentClientSecret', isArgumentError(cs, 'fetchSetupIntentClientSecret'), cs);

	let threw = false;
	try {
		Paysheet.presentPaymentSheet(42).catch(() => {});
	} catch (e) {
		threw = true;
	}
	check('never throws synchronously', !threw, null);

	// Callback (Node-style) and Promise both settle, once each.
	const calls = [];
	const viaPromise = await rejection(Paysheet.presentPaymentSheet({}, (error, result) => calls.push([error, result])));
	await new Promise((resolve) => setTimeout(resolve, 300));
	check('callback gets (error) once and the Promise rejects', calls.length === 1 && calls[0][0] instanceof Error
		&& calls[0][1] === undefined && viaPromise.error instanceof Error, { calls: calls.length });

	check('handleURL ignores foreign URLs', Paysheet.handleURL('https://example.com/') === false, null);
	Ti.API.info('[SELFTEST] stripe ' + Paysheet.stripeVersion + ' (module built against ' + Paysheet.stripeVersionRequired + ')');
	check('present functions come from the shared JavaScript layer', typeof Paysheet.presentPaymentSheet === 'function'
		&& typeof Paysheet._presentPaymentSheet === 'function', null);

	Ti.API.info('[SELFTEST] ' + (passed === total ? 'PASS ' : 'FAIL ') + passed + '/' + total);
	show('self-test', passed + '/' + total + ' passed');
}

// --------------------------------------------------------------------------------------------- lifecycle scenarios

// Android: start a presentation while the app is in the background (press Home within 5 s). Android does not let a
// background app open an activity; the result must be 'unavailable', and the next presentation must not be 'busy'.
function payInBackground() {
	show('background', 'press Home now; paying in 5 s');
	setTimeout(() => pay('none'), 5000);
}

// iOS: present from a modal window, then close that window under the sheet (as an app's sign-out flow would).
// Stripe never reports a result for it; the next presentation must settle it as 'interrupted' instead of 'busy'.
async function closeWindowUnderSheet() {
	try {
		await ensureInitialized();
		const s = await post('/payment-sheet', { amount: 1099, customer: 'none' });
		const modal = Ti.UI.createWindow({ backgroundColor: '#fff', modal: true });
		modal.add(Ti.UI.createLabel({ text: 'modal window' }));
		modal.addEventListener('open', () => {
			Paysheet.presentPaymentSheet({ paymentIntentClientSecret: s.paymentIntentClientSecret, merchantDisplayName: MERCHANT })
				.then((r) => show('closed-under result', r));
			setTimeout(() => {
				modal.close();
				show('closed-under', 'window closed under the sheet; now pay again');
			}, 6000);
		});
		modal.open();
	} catch (e) {
		show('error', e.message);
	}
}

// ------------------------------------------------------------------------------------------------------------ screen

button('Pay $10.99 (Customer Session)', () => pay('session'));
button('Pay $10.99 (ephemeral key)', () => pay('ephemeral'));
button('Pay $10.99 (guest)', () => pay('none'));
button('Save a card (setup mode)', saveCard);
button('Manage saved cards (CustomerSheet)', manageCards);
button('Invalid client secret', invalidSecret);
button('Run self-test', selfTest);
if (Ti.Platform.osname === 'android') {
	button('Pay in 5 s (press Home: background start)', payInBackground);
} else {
	button('Close the window under the sheet', closeWindowUnderSheet);
}
scroll.add(status);
scroll.add(log);
win.open();

// Android: a sheet that finished after the process was restarted (see README, takeRestoredResult).
function checkRestored() {
	const restored = Paysheet.takeRestoredResult();
	if (restored) {
		show('restored result', restored);
		// Whatever the status, only the server knows whether the money moved.
		if (restored.intentId) {
			post('/intent-status', { id: restored.intentId })
				.then((s) => show('server says', s.id + ' ' + s.status))
				.catch((e) => show('error', e.message));
		}
	}
}
Paysheet.addEventListener('restoredresult', checkRestored);

// iOS: show URLs the app is opened with. The module forwards each one to Stripe by itself (no code needed);
// this only makes the 3-D Secure / redirect return visible in the example.
if (Ti.Platform.osname === 'iphone') {
	Ti.App.iOS.addEventListener('handleurl', (e) => show('url received', e.launchOptions.url));
}
checkRestored();
selfTest();
