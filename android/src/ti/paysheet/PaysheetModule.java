/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import android.app.Activity;
import android.app.ActivityOptions;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import com.stripe.android.PaymentConfiguration;
import java.util.HashMap;
import java.util.Map;
import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollFunction;
import org.appcelerator.kroll.KrollModule;
import org.appcelerator.kroll.KrollObject;
import org.appcelerator.kroll.KrollPromise;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.TiApplication;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * The public presentPaymentSheet / presentCustomerSheet are in assets/ti.paysheet.js (shared with iOS); they call
 * the _present… methods below, which resolve with an outcome, a runtime condition or an argument-error marker and
 * never throw.
 */
@Kroll.module(name = "Paysheet", id = "ti.paysheet")
public class PaysheetModule extends KrollModule
{
	static final String TAG = "TiPaysheet";
	private static final String PREFS = "ti.paysheet";
	private static final String PREF_RESTORED = "restoredResult";

	private static final Handler MAIN = new Handler(Looper.getMainLooper());
	private static final Presentations PRESENTATIONS = new Presentations(
		(delayMs, task) -> {
			MAIN.postDelayed(task, delayMs);
			return () -> MAIN.removeCallbacks(task);
		},
		PaysheetModule::storeRestored);

	private static Options.Init init;
	/** The module instance of the running JavaScript context, for the "restoredresult" event. */
	private static PaysheetModule instance;

	public PaysheetModule()
	{
		super();
		instance = this;
	}

	// ---------------------------------------------------------------------------------------------------------------
	// JavaScript API

	@Kroll.method
	public boolean initialize(Object options)
	{
		try {
			Options.Init parsed = Options.parseInitialize(options);
			PaymentConfiguration.init(TiApplication.getInstance(), parsed.publishableKey, parsed.stripeAccountId);
			init = parsed;
			return true;
		} catch (Options.InvalidException e) {
			Log.e(TAG, "initialize: " + e.getMessage());
			return false;
		}
	}

	@Kroll.getProperty(name = "isInitialized")
	public boolean getIsInitialized()
	{
		return init != null;
	}

	/** stripe-android version the module was built against (android/build.gradle pins it). */
	static final String STRIPE_VERSION_REQUIRED = "23.26.0";

	/** The stripe-android version the app actually links (read at run time; Kotlin inlines the constant). */
	@Kroll.getProperty(name = "stripeVersion")
	public String getStripeVersion()
	{
		try {
			return (String) Class.forName("com.stripe.android.core.version.StripeSdkVersion")
				.getField("VERSION_NAME")
				.get(null);
		} catch (ReflectiveOperationException | RuntimeException e) {
			return "unknown";
		}
	}

	@Kroll.getProperty(name = "stripeVersionRequired")
	public String getStripeVersionRequired()
	{
		return STRIPE_VERSION_REQUIRED;
	}

	@Kroll.method
	public KrollPromise<Object> _presentPaymentSheet(@Kroll.argument(optional = true) Object options)
	{
		return present(options, false);
	}

	@Kroll.method
	public KrollPromise<Object> _presentCustomerSheet(@Kroll.argument(optional = true) Object options)
	{
		return present(options, true);
	}

	@Kroll.method
	public boolean handleURL(String url)
	{
		// Android: Stripe's own redirect activity receives the return; nothing to forward.
		return false;
	}

	@Kroll.method
	public KrollDict takeRestoredResult()
	{
		SharedPreferences prefs = TiApplication.getInstance().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
		String json = prefs.getString(PREF_RESTORED, null);
		if (json == null) {
			return null;
		}
		prefs.edit().remove(PREF_RESTORED).apply();
		try {
			KrollDict result = new KrollDict(new JSONObject(json));
			result.put("restored", true);
			return result;
		} catch (JSONException e) {
			Log.w(TAG, "discarding an unreadable restored result");
			return null;
		}
	}

	// ---------------------------------------------------------------------------------------------------------------

	private KrollPromise<Object> present(final Object options, final boolean customer)
	{
		final KrollObject owner = getKrollObject();
		return KrollPromise.create((promise) -> {
			final String name = customer ? "presentCustomerSheet" : "presentPaymentSheet";
			Options.Sheet sheet;
			try {
				sheet = customer ? Options.parseCustomerSheet(options) : Options.parsePaymentSheet(options);
			} catch (Options.InvalidException e) {
				Log.e(TAG, name + ": " + e.getMessage());
				promise.resolve(new KrollDict(Results.argumentError(Results.INVALID_ARGUMENT, e.option, e.getMessage())));
				return;
			}
			KrollFunction fetch = null;
			if (customer) {
				Object f = ((Map<?, ?>) options).get("fetchSetupIntentClientSecret");
				if (!(f instanceof KrollFunction)) {
					String message = "fetchSetupIntentClientSecret must be a function";
					Log.e(TAG, name + ": " + message);
					promise.resolve(new KrollDict(
						Results.argumentError(Results.INVALID_ARGUMENT, "fetchSetupIntentClientSecret", message)));
					return;
				}
				fetch = (KrollFunction) f;
			}
			if (init == null) {
				promise.resolve(new KrollDict(Results.argumentError(Results.NOT_INITIALIZED, null,
					"Call initialize({ publishableKey }) before presenting a sheet.")));
				return;
			}

			String intentId = Options.intentIdFromClientSecret(sheet.intentClientSecret);
			Activity activity = TiApplication.getAppCurrentActivity();
			if (activity == null || activity.isFinishing() || !TiApplication.isCurrentActivityInForeground()) {
				// Android 10+ does not let a background app start an activity; the sheet would never open.
				promise.resolve(new KrollDict(Results.moduleError(intentId, Results.UNAVAILABLE,
					"The app is not in the foreground, so the payment sheet cannot open.")));
				return;
			}

			final KrollFunction fetchFn = fetch;
			Presentations.SecretAsker asker = fetchFn == null ? null : request -> {
				fetchFn.callAsync(owner, new Object[] { new SecretRequestProxy(request) });
			};
			String id = PRESENTATIONS.begin(intentId, result -> promise.resolve(new KrollDict(result)), asker);
			if (id == null) {
				promise.resolve(new KrollDict(
					Results.moduleError(intentId, Results.BUSY, "Another payment sheet is already open.")));
				return;
			}

			sheet.publishableKey = init.publishableKey;
			sheet.stripeAccountId = init.stripeAccountId;
			Intent intent = new Intent(activity, PaysheetHostActivity.class);
			intent.putExtra(PaysheetHostActivity.EXTRA_ID, id);
			intent.putExtra(PaysheetHostActivity.EXTRA_SHEET, sheet);
			try {
				// No transition: the host activity is invisible and the sheet animates itself.
				activity.startActivity(intent, ActivityOptions.makeCustomAnimation(activity, 0, 0).toBundle());
			} catch (RuntimeException e) {
				Log.e(TAG, name + ": could not start the payment sheet (" + e.getClass().getSimpleName() + ")");
				PRESENTATIONS.startFailed(id, "The payment sheet could not be started.");
			}
		});
	}

	// ---------------------------------------------------------------------------------------------------------------
	// Called by PaysheetHostActivity (main thread)

	/** Host activity started; false means the presentation is already over and the activity must finish. */
	static boolean checkIn(String id)
	{
		return PRESENTATIONS.checkIn(id);
	}

	/** True while presentation {@code id} has a live JavaScript caller in this process. */
	static boolean isLive(String id)
	{
		return PRESENTATIONS.isLive(id);
	}

	/** Settles presentation {@code id} exactly once; kept for takeRestoredResult() after a process restart. */
	static void deliver(String id, HashMap<String, Object> result)
	{
		if (Looper.myLooper() != Looper.getMainLooper()) {
			MAIN.post(() -> deliver(id, result));
			return;
		}
		PRESENTATIONS.deliver(id, result);
	}

	/** Asks JavaScript for a SetupIntent client secret (CustomerSheet); {@code done} is called exactly once. */
	static void requestSetupIntentSecret(String id, Presentations.SecretAnswer done)
	{
		MAIN.post(() -> PRESENTATIONS.requestSecret(id, done));
	}

	private static void storeRestored(HashMap<String, Object> result)
	{
		try {
			JSONObject json = toJson(result);
			TiApplication.getInstance()
				.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
				.edit()
				.putString(PREF_RESTORED, json.toString())
				.apply();
			Log.i(TAG, "sheet finished after a process restart; result kept for takeRestoredResult()");
			PaysheetModule module = instance;
			if (module != null && module.hasListeners("restoredresult")) {
				module.fireEvent("restoredresult", new KrollDict());
			}
		} catch (JSONException e) {
			Log.w(TAG, "could not keep the restored result");
		}
	}

	@SuppressWarnings("unchecked")
	private static JSONObject toJson(Map<String, Object> map) throws JSONException
	{
		JSONObject o = new JSONObject();
		for (Map.Entry<String, Object> e : map.entrySet()) {
			Object v = e.getValue();
			o.put(e.getKey(), v instanceof Map ? toJson((Map<String, Object>) v) : (v == null ? JSONObject.NULL : v));
		}
		return o;
	}
}
