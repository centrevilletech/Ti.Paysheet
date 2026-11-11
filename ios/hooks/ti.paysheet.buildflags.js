/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 *
 * Module-build hook (fires only when this module itself is built, never in an app build).
 *
 * Titanium builds Swift module frameworks with BUILD_LIBRARY_FOR_DISTRIBUTION=YES, and on the xcodebuild command
 * line that also applies to Swift packages, so stripe-ios would be compiled with library evolution and this
 * module would call it through resilient "dispatch thunks". Apps compile stripe-ios normally (the package is
 * linked by the app, see spm.json), without those thunks, so the app would fail to link. This framework is a
 * static library that apps reach through the Objective-C runtime, never through its Swift interface, so it does
 * not need library evolution.
 */
'use strict';

exports.id = 'ti.paysheet.buildflags';
exports.cliVersion = '>=3.2';

exports.init = function (logger, config, cli) {
	cli.on('build.module.ios.xcodebuild', {
		pre: function (data) {
			const args = data.args[1];
			const i = args.indexOf('BUILD_LIBRARY_FOR_DISTRIBUTION=YES');
			if (i !== -1) {
				args[i] = 'BUILD_LIBRARY_FOR_DISTRIBUTION=NO';
				logger.info('[ti.paysheet] building with BUILD_LIBRARY_FOR_DISTRIBUTION=NO (see hooks/ti.paysheet.buildflags.js)');
			}
		}
	});
};
