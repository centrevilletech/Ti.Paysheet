/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

/**
 * One request for a SetupIntent client secret (CustomerSheet adding a payment method). Answered exactly once, by
 * the app (resolve / reject), by the timeout, or by an error; every later answer is ignored. Pure Java.
 */
public final class SecretRequest
{
	private Presentations.SecretAnswer answer;
	private Runnable cancelTimeout;

	SecretRequest(Presentations.SecretAnswer answer)
	{
		this.answer = answer;
	}

	void setCancelTimeout(Runnable cancel)
	{
		this.cancelTimeout = cancel;
	}

	public void resolve(Object secret)
	{
		if (!(secret instanceof String) || ((String) secret).trim().isEmpty()) {
			answer(null, "fetchSetupIntentClientSecret resolved without a SetupIntent client secret");
			return;
		}
		answer((String) secret, null);
	}

	public void reject(Object message)
	{
		answer(null, message instanceof String && !((String) message).isEmpty()
						 ? (String) message
						 : "The app could not create a SetupIntent.");
	}

	synchronized void answer(String secret, String error)
	{
		Presentations.SecretAnswer a = answer;
		answer = null;
		if (a == null) {
			return;
		}
		if (cancelTimeout != null) {
			cancelTimeout.run();
		}
		a.onAnswer(secret, error);
	}
}
