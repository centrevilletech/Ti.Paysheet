/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import com.stripe.android.PaymentConfiguration;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.UUID;
import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollFunction;
import org.appcelerator.kroll.KrollModule;
import org.appcelerator.kroll.KrollObject;
import org.appcelerator.kroll.KrollPromise;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.TiApplication;
import org.json.JSONException;
import org.json.JSONObject;

@Kroll.module(name = "Paysheet", id = "ti.paysheet")
public class PaysheetModule extends KrollModule
{
	static final String TAG = "TiPaysheet";
	private static final String PREFS = "ti.paysheet";
	private static final String PREF_RESTORED = "restoredResult";

	/** The one presentation in flight (the module allows one at a time). Main thread only. */
	private static Pending active;
	private static Options.Init init;
	/** The module instance of the running JavaScript context, for the "restoredresult" event. */
	private static PaysheetModule instance;

	private static final class Pending
	{
		final String id;
		final String intentId;
		final KrollPromise<Object> promise;
		final KrollFunction callback;
		final KrollFunction fetchSetupIntent;
		final KrollObject owner;
		boolean settled;

		Pending(String id, String intentId, KrollPromise<Object> promise, KrollFunction callback,
				KrollFunction fetchSetupIntent, KrollObject owner)
		{
			this.id = id;
			this.intentId = intentId;
			this.promise = promise;
			this.callback = callback;
			this.fetchSetupIntent = fetchSetupIntent;
			this.owner = owner;
		}
	}

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

	@Kroll.method
	public KrollPromise<Object> presentPaymentSheet(Object options, @Kroll.argument(optional = true) KrollFunction callback)
	{
		return present(options, callback, false);
	}

	@Kroll.method
	public KrollPromise<Object> presentCustomerSheet(Object options, @Kroll.argument(optional = true) KrollFunction callback)
	{
		return present(options, callback, true);
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
			Log.w(TAG, "discarding unreadable restored result", e);
			return null;
		}
	}

	// ---------------------------------------------------------------------------------------------------------------

	private KrollPromise<Object> present(final Object options, final KrollFunction callback, final boolean customer)
	{
		final KrollObject owner = getKrollObject();
		return KrollPromise.create((promise) -> {
			Options.Sheet sheet;
			try {
				sheet = customer ? Options.parseCustomerSheet(options) : Options.parsePaymentSheet(options);
			} catch (Options.InvalidException e) {
				Log.e(TAG, (customer ? "presentCustomerSheet: " : "presentPaymentSheet: ") + e.getMessage());
				settleNow(promise, callback, owner, Results.moduleError(null, Results.INVALID_ARGUMENT, e.getMessage()));
				return;
			}
			KrollFunction fetch = null;
			if (customer) {
				Object f = ((Map<?, ?>) options).get("fetchSetupIntentClientSecret");
				if (!(f instanceof KrollFunction)) {
					String message = "fetchSetupIntentClientSecret must be a function";
					Log.e(TAG, "presentCustomerSheet: " + message);
					settleNow(promise, callback, owner, Results.moduleError(null, Results.INVALID_ARGUMENT, message));
					return;
				}
				fetch = (KrollFunction) f;
			}
			String intentId = Options.intentIdFromClientSecret(sheet.intentClientSecret);
			if (init == null) {
				settleNow(promise, callback, owner, Results.moduleError(intentId, Results.NOT_INITIALIZED,
					"Call initialize({ publishableKey }) before presenting a sheet."));
				return;
			}
			if (active != null) {
				settleNow(promise, callback, owner,
					Results.moduleError(intentId, Results.BUSY, "Another payment sheet is already open."));
				return;
			}
			Activity activity = TiApplication.getAppCurrentActivity();
			if (activity == null || activity.isFinishing()) {
				settleNow(promise, callback, owner, Results.moduleError(intentId, Results.UNAVAILABLE,
					"There is no activity to present the sheet from."));
				return;
			}
			sheet.publishableKey = init.publishableKey;
			sheet.stripeAccountId = init.stripeAccountId;
			String id = UUID.randomUUID().toString();
			active = new Pending(id, intentId, promise, callback, fetch, owner);
			Intent intent = new Intent(activity, PaysheetHostActivity.class);
			intent.putExtra(PaysheetHostActivity.EXTRA_ID, id);
			intent.putExtra(PaysheetHostActivity.EXTRA_SHEET, sheet);
			activity.startActivity(intent);
			activity.overridePendingTransition(0, 0);
		});
	}

	private static void settleNow(KrollPromise<Object> promise, KrollFunction callback, KrollObject owner,
								  HashMap<String, Object> result)
	{
		KrollDict dict = new KrollDict(result);
		if (callback != null) {
			callback.callAsync(owner, new Object[] { dict });
		}
		promise.resolve(dict);
	}

	// ---------------------------------------------------------------------------------------------------------------
	// Called by PaysheetHostActivity (main thread)

	/** True while presentation {@code id} has a live JavaScript caller in this process. */
	static boolean isLive(String id)
	{
		return active != null && active.id.equals(id) && !active.settled;
	}

	static String intentIdFor(String id)
	{
		return active != null && active.id.equals(id) ? active.intentId : null;
	}

	/**
	 * Settles presentation {@code id}. Exactly once: later calls are ignored. When the caller is gone (the process
	 * was restarted while the sheet was open) the result is kept for {@link #takeRestoredResult()}.
	 */
	static void deliver(String id, HashMap<String, Object> result)
	{
		if (Looper.myLooper() != Looper.getMainLooper()) {
			new Handler(Looper.getMainLooper()).post(() -> deliver(id, result));
			return;
		}
		if (active == null || !active.id.equals(id)) {
			storeRestored(result);
			return;
		}
		Pending p = active;
		active = null;
		if (p.settled) {
			return;
		}
		p.settled = true;
		settleNow(p.promise, p.callback, p.owner, result);
	}

	/** Asks JavaScript for a SetupIntent client secret (CustomerSheet); {@code done} is called exactly once. */
	static void requestSetupIntentSecret(String id, SecretRequestProxy.Listener done)
	{
		new Handler(Looper.getMainLooper()).post(() -> {
			if (active == null || !active.id.equals(id) || active.fetchSetupIntent == null) {
				done.onAnswer(null, "The app is no longer able to create a SetupIntent; close and reopen the sheet.");
				return;
			}
			SecretRequestProxy request = new SecretRequestProxy(done);
			active.fetchSetupIntent.callAsync(active.owner, new Object[] { request });
		});
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
			// The restarted app's JavaScript may already be running (it usually is by the time the sheet ends).
			PaysheetModule module = instance;
			if (module != null && module.hasListeners("restoredresult")) {
				module.fireEvent("restoredresult", new KrollDict());
			}
		} catch (JSONException e) {
			Log.w(TAG, "could not keep restored result", e);
		}
	}

	@SuppressWarnings("unchecked")
	private static JSONObject toJson(Map<String, Object> map) throws JSONException
	{
		JSONObject o = new JSONObject();
		Iterator<Map.Entry<String, Object>> it = map.entrySet().iterator();
		while (it.hasNext()) {
			Map.Entry<String, Object> e = it.next();
			Object v = e.getValue();
			o.put(e.getKey(), v instanceof Map ? toJson((Map<String, Object>) v) : (v == null ? JSONObject.NULL : v));
		}
		return o;
	}
}
