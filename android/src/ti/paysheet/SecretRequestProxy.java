/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;

/**
 * Handed to {@code fetchSetupIntentClientSecret(request)}: the app answers once with {@code resolve(secret)} or
 * {@code reject(message)}. Later answers are ignored.
 */
@Kroll.proxy
public class SecretRequestProxy extends KrollProxy
{
	interface Listener {
		/** Exactly one of {@code secret} and {@code error} is non-null. */
		void onAnswer(String secret, String error);
	}

	private Listener listener;

	public SecretRequestProxy()
	{
		super();
	}

	SecretRequestProxy(Listener listener)
	{
		super();
		this.listener = listener;
	}

	@Kroll.method
	public void resolve(Object secret)
	{
		if (!(secret instanceof String) || ((String) secret).trim().isEmpty()) {
			answer(null, "fetchSetupIntentClientSecret resolved without a SetupIntent client secret");
			return;
		}
		answer((String) secret, null);
	}

	@Kroll.method
	public void reject(@Kroll.argument(optional = true) Object message)
	{
		answer(null, message instanceof String && !((String) message).isEmpty()
						 ? (String) message
						 : "The app could not create a SetupIntent.");
	}

	private synchronized void answer(String secret, String error)
	{
		Listener l = listener;
		listener = null;
		if (l != null) {
			l.onAnswer(secret, error);
		}
	}

	@Override
	public String getApiName()
	{
		return "Ti.Paysheet.SecretRequest";
	}
}
