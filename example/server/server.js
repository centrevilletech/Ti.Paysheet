/**
 * Ti.Paysheet example server: the few Stripe calls a real backend makes for PaymentSheet, in test mode.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 *
 *   STRIPE_SECRET_KEY=sk_test_… STRIPE_PUBLISHABLE_KEY=pk_test_… node server.js
 *   (or put both in config.json, which git ignores: { "secretKey": "sk_test_…", "publishableKey": "pk_test_…" })
 *
 * Test mode only: it refuses live keys. It creates one anonymous Customer per run and sends Stripe nothing else
 * about anyone. No dependencies; Node 18+.
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT || 4242);
let config = {};
try {
	config = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
} catch (e) {
	// environment only
}
const SECRET_KEY = process.env.STRIPE_SECRET_KEY || config.secretKey;
const PUBLISHABLE_KEY = process.env.STRIPE_PUBLISHABLE_KEY || config.publishableKey;
// Ephemeral keys carry the API version of the SDK that will use them (see README, "What your server must provide").
const EPHEMERAL_KEY_VERSION = '2020-08-27';

if (!SECRET_KEY || !PUBLISHABLE_KEY || !SECRET_KEY.startsWith('sk_test_') || !PUBLISHABLE_KEY.startsWith('pk_test_')) {
	console.error('Set STRIPE_SECRET_KEY=sk_test_… and STRIPE_PUBLISHABLE_KEY=pk_test_… (test mode only).');
	process.exit(1);
}

function form(params, prefix, out = []) {
	for (const [key, value] of Object.entries(params)) {
		const name = prefix ? `${prefix}[${key}]` : key;
		if (value !== null && typeof value === 'object') {
			form(value, name, out);
		} else if (value !== undefined) {
			out.push(`${encodeURIComponent(name)}=${encodeURIComponent(value)}`);
		}
	}
	return out.join('&');
}

async function stripe(method, endpoint, params, headers = {}) {
	const res = await fetch(`https://api.stripe.com/v1/${endpoint}`, {
		method,
		headers: {
			Authorization: `Bearer ${SECRET_KEY}`,
			'Content-Type': 'application/x-www-form-urlencoded',
			...headers
		},
		body: method === 'GET' ? undefined : form(params || {})
	});
	const body = await res.json();
	if (!res.ok) {
		const err = new Error(body.error ? body.error.message : `Stripe ${res.status}`);
		err.status = res.status;
		throw err;
	}
	return body;
}

let customerId = null;
async function customer() {
	if (!customerId) {
		customerId = (await stripe('POST', 'customers', { description: 'ti.paysheet example customer' })).id;
	}
	return customerId;
}

async function customerAccess(mode, components) {
	const id = await customer();
	if (mode === 'ephemeral') {
		const key = await stripe('POST', 'ephemeral_keys', { customer: id }, { 'Stripe-Version': EPHEMERAL_KEY_VERSION });
		return { customerId: id, ephemeralKeySecret: key.secret };
	}
	const session = await stripe('POST', 'customer_sessions', { customer: id, components });
	return { customerId: id, customerSessionClientSecret: session.client_secret };
}

const SHEET_COMPONENTS = {
	mobile_payment_element: {
		enabled: true,
		features: {
			payment_method_save: 'enabled',
			payment_method_redisplay: 'enabled',
			payment_method_remove: 'enabled'
		}
	}
};
const CUSTOMER_SHEET_COMPONENTS = {
	customer_sheet: { enabled: true, features: { payment_method_remove: 'enabled' } }
};

const routes = {
	'GET /config': async () => ({ publishableKey: PUBLISHABLE_KEY }),

	// Payment mode. body: { amount (cents, default 1099), customer: 'session' | 'ephemeral' | 'none' }
	'POST /payment-sheet': async (body) => {
		const mode = body.customer || 'session';
		const access = mode === 'none' ? {} : await customerAccess(mode, SHEET_COMPONENTS);
		const intent = await stripe('POST', 'payment_intents', {
			amount: Number(body.amount) || 1099,
			currency: 'usd',
			customer: access.customerId,
			automatic_payment_methods: { enabled: true }
		});
		return { paymentIntentClientSecret: intent.client_secret, ...access };
	},

	// Setup mode: save a card without paying.
	'POST /setup-sheet': async (body) => {
		const access = await customerAccess(body.customer || 'session', SHEET_COMPONENTS);
		const intent = await stripe('POST', 'setup_intents', {
			customer: access.customerId,
			automatic_payment_methods: { enabled: true }
		});
		return { setupIntentClientSecret: intent.client_secret, ...access };
	},

	// CustomerSheet: a session with the customer_sheet component; SetupIntents come from /setup-intent on demand.
	'POST /customer-sheet': async () => customerAccess('session', CUSTOMER_SHEET_COMPONENTS),

	'POST /setup-intent': async () => {
		const intent = await stripe('POST', 'setup_intents', {
			customer: await customer(),
			automatic_payment_methods: { enabled: true }
		});
		return { setupIntentClientSecret: intent.client_secret };
	},

	// What the app's server would check before showing "paid". body: { id: 'pi_…' | 'seti_…' }
	'POST /intent-status': async (body) => {
		const id = String(body.id || '');
		if (!/^(pi|seti)_[A-Za-z0-9]+$/.test(id)) {
			throw Object.assign(new Error('bad id'), { status: 400 });
		}
		const intent = await stripe('GET', `${id.startsWith('pi_') ? 'payment_intents' : 'setup_intents'}/${id}`);
		return { id: intent.id, status: intent.status, lastError: intent.last_payment_error || intent.last_setup_error || null };
	}
};

http.createServer((req, res) => {
	let raw = '';
	req.on('data', (chunk) => { raw += chunk; });
	req.on('end', async () => {
		const route = routes[`${req.method} ${req.url.split('?')[0]}`];
		res.setHeader('Content-Type', 'application/json');
		if (!route) {
			res.statusCode = 404;
			return res.end('{"error":"not found"}');
		}
		try {
			const result = await route(raw ? JSON.parse(raw) : {});
			console.log(`${req.method} ${req.url} -> 200`);
			res.end(JSON.stringify(result));
		} catch (e) {
			console.log(`${req.method} ${req.url} -> ${e.status || 500} ${e.message}`);
			res.statusCode = e.status || 500;
			res.end(JSON.stringify({ error: e.message }));
		}
	});
}).listen(PORT, '127.0.0.1', () => console.log(`ti.paysheet example server on http://127.0.0.1:${PORT}`));
