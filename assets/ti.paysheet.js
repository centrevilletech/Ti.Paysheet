/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 *
 * Shared JavaScript layer, packaged into both platforms' module zips. Titanium merges these exports into the native
 * module, so `require('ti.paysheet').presentPaymentSheet` is the function below and `this` is the native module.
 *
 * Contract (identical on iOS and Android):
 *   - present…() never throws; it returns a Promise.
 *   - Outcomes of a presentation (completed, canceled, failed, selected) and runtime conditions (busy, unavailable,
 *     interrupted: status 'failed' with that error code) RESOLVE the Promise.
 *   - Argument errors REJECT it with an Error whose `code` is 'invalid_argument' (and `option` names the option) or
 *     'not_initialized'. Nothing was shown.
 *   - The optional callback is Node-style and called exactly once: callback(error, result).
 */
'use strict';

function argumentError(info) {
	const error = new Error(info.message);
	error.code = info.code;
	if (info.option) {
		error.option = info.option;
	}
	return error;
}

function present(native, method, options, callback) {
	let pending;
	try {
		pending = native[method](options);
	} catch (e) {
		pending = Promise.reject(e);
	}
	if (!pending || typeof pending.then !== 'function') {
		const e = new Error('The payment sheet could not be started.');
		e.code = 'unavailable';
		pending = Promise.reject(e);
	}
	const settled = Promise.resolve(pending).then(function (result) {
		if (result && result.__argumentError) {
			throw argumentError(result.__argumentError);
		}
		return result;
	});
	if (typeof callback === 'function') {
		const call = function (error, result) {
			try {
				callback(error, result);
			} catch (e) {
				// The app's own bug: report it like any uncaught error, without touching the Promise.
				setTimeout(function () {
					throw e;
				}, 0);
			}
		};
		settled.then(function (result) {
			call(null, result);
		}, function (error) {
			call(error);
		});
	}
	return settled;
}

exports.presentPaymentSheet = function (options, callback) {
	return present(this, '_presentPaymentSheet', options, callback);
};

exports.presentCustomerSheet = function (options, callback) {
	return present(this, '_presentCustomerSheet', options, callback);
};
