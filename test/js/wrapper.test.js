/**
 * Ti.Paysheet — tests for assets/ti.paysheet.js (the shared JavaScript layer) with a fake native module.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 *
 *   node --test test/js/*.test.js
 */
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const fs = require('node:fs');
const vm = require('node:vm');

// Load the module file the way Titanium does: CommonJS, exports merged onto the native module object.
function load(native, timers = { setTimeout }) {
	const source = fs.readFileSync(path.join(__dirname, '..', '..', 'assets', 'ti.paysheet.js'), 'utf8');
	const module = { exports: {} };
	vm.runInNewContext(`(function (exports, module) {${source}\n})`, { setTimeout: timers.setTimeout, Error, Promise, console })(module.exports, module);
	return Object.assign(native, module.exports);
}

function fakeNative(answer) {
	const calls = [];
	return {
		calls,
		_presentPaymentSheet(options) { calls.push(['payment', options]); return answer(options); },
		_presentCustomerSheet(options) { calls.push(['customer', options]); return answer(options); }
	};
}

const outcome = { status: 'completed', intentId: 'pi_1' };
const argumentError = { __argumentError: { code: 'invalid_argument', option: 'merchantDisplayName', message: 'merchantDisplayName is required' } };

test('an outcome resolves the Promise and calls back (null, result) once', async () => {
	const m = load(fakeNative(() => Promise.resolve(outcome)));
	const seen = [];
	const r = await m.presentPaymentSheet({ a: 1 }, (err, res) => seen.push([err, res]));
	assert.deepStrictEqual(r, outcome);
	assert.deepStrictEqual(seen, [[null, outcome]]);
	assert.deepStrictEqual(m.calls, [['payment', { a: 1 }]]);
});

test('runtime conditions (busy, unavailable, interrupted) resolve; they are not argument errors', async () => {
	for (const code of ['busy', 'unavailable', 'interrupted']) {
		const failed = { status: 'failed', error: { code, message: code } };
		const m = load(fakeNative(() => Promise.resolve(failed)));
		assert.deepStrictEqual(await m.presentCustomerSheet({}), failed);
	}
});

test('an argument error rejects with an Error carrying code and option, and calls back (error) once', async () => {
	const m = load(fakeNative(() => Promise.resolve(argumentError)));
	const seen = [];
	await assert.rejects(m.presentPaymentSheet({}, (err, res) => seen.push([err, res])), (e) => {
		assert.ok(e instanceof Error);
		assert.strictEqual(e.code, 'invalid_argument');
		assert.strictEqual(e.option, 'merchantDisplayName');
		assert.strictEqual(e.message, 'merchantDisplayName is required');
		return true;
	});
	assert.strictEqual(seen.length, 1);
	assert.ok(seen[0][0] instanceof Error);
	assert.strictEqual(seen[0][1], undefined);
});

test('not initialised rejects with code not_initialized', async () => {
	const m = load(fakeNative(() => Promise.resolve({ __argumentError: { code: 'not_initialized', message: 'Call initialize' } })));
	await assert.rejects(m.presentPaymentSheet({}), (e) => e instanceof Error && e.code === 'not_initialized' && e.option === undefined);
});

test('a throwing native call never throws synchronously; it rejects', async () => {
	const m = load(fakeNative(() => { throw new Error('boom'); }));
	let p;
	assert.doesNotThrow(() => { p = m.presentPaymentSheet({}); });
	await assert.rejects(p, /boom/);
});

test('a native call that returns no Promise rejects', async () => {
	const m = load(fakeNative(() => undefined));
	await assert.rejects(m.presentPaymentSheet({}), (e) => e.code === 'unavailable');
});

test('a throwing callback does not stop the Promise, and the error is rethrown asynchronously', async () => {
	const scheduled = [];
	const m = load(fakeNative(() => Promise.resolve(outcome)), { setTimeout: (fn) => scheduled.push(fn) });
	const r = await m.presentPaymentSheet({}, () => { throw new Error('app bug'); });
	assert.deepStrictEqual(r, outcome);
	await new Promise((resolve) => setImmediate(resolve));
	assert.strictEqual(scheduled.length, 1);
	assert.throws(scheduled[0], /app bug/);
});

test('a non-function callback is ignored', async () => {
	const m = load(fakeNative(() => Promise.resolve(outcome)));
	assert.deepStrictEqual(await m.presentPaymentSheet({}, 'not a function'), outcome);
});
