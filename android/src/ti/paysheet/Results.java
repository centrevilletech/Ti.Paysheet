/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import java.util.HashMap;
import java.util.Map;

/**
 * Builds the result objects handed to JavaScript. Pure Java (unit-tested with test/vectors.json, mirrored by the
 * iOS implementation).
 */
public final class Results
{
	private Results()
	{
	}

	public static final String COMPLETED = "completed";
	public static final String CANCELED = "canceled";
	public static final String FAILED = "failed";
	public static final String SELECTED = "selected";

	public static final String INVALID_ARGUMENT = "invalid_argument";
	public static final String NOT_INITIALIZED = "not_initialized";
	public static final String BUSY = "busy";
	public static final String UNAVAILABLE = "unavailable";
	public static final String INTERRUPTED = "interrupted";
	public static final String SDK_ERROR = "sdk_error";
	/** The intent was already succeeded / canceled / processing when the sheet loaded it (e.g. after a restart). */
	public static final String INTENT_IN_TERMINAL_STATE = "intent_in_terminal_state";

	public static HashMap<String, Object> status(String status, String intentId)
	{
		HashMap<String, Object> r = new HashMap<>();
		r.put("status", status);
		if (intentId != null) {
			r.put("intentId", intentId);
		}
		return r;
	}

	/**
	 * A failed result. {@code apiCode} is Stripe's API error code when Stripe reported one; without it the code
	 * is {@code fallbackCode} (one of this module's codes).
	 */
	public static HashMap<String, Object> failed(String intentId, String apiCode, String fallbackCode,
												 String message, String declineCode, String type)
	{
		HashMap<String, Object> r = status(FAILED, intentId);
		Map<String, Object> error = new HashMap<>();
		error.put("code", nonEmpty(apiCode) != null ? apiCode : (nonEmpty(fallbackCode) != null ? fallbackCode : SDK_ERROR));
		error.put("message", nonEmpty(message) != null ? message : "Something went wrong with the payment sheet.");
		error.put("declineCode", nonEmpty(declineCode));
		error.put("type", nonEmpty(type));
		r.put("error", error);
		return r;
	}

	public static HashMap<String, Object> moduleError(String intentId, String code, String message)
	{
		return failed(intentId, null, code, message, null, null);
	}

	/** CustomerSheet result; {@code optionId} null when nothing is selected. */
	public static HashMap<String, Object> customer(String status, String optionId, String optionLabel)
	{
		HashMap<String, Object> r = status(status, null);
		if (optionId != null) {
			Map<String, Object> option = new HashMap<>();
			option.put("id", optionId);
			option.put("label", optionLabel);
			r.put("paymentOption", option);
		}
		return r;
	}

	private static String nonEmpty(String s)
	{
		return s == null || s.trim().isEmpty() ? null : s;
	}
}
