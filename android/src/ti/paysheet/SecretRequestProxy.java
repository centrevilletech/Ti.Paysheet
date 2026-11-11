/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;

/**
 * Handed to {@code fetchSetupIntentClientSecret(request)}: the app answers once with {@code resolve(secret)} or
 * {@code reject(message)}. Later answers, and answers after the timeout, are ignored (see SecretRequest).
 */
@Kroll.proxy
public class SecretRequestProxy extends KrollProxy
{
	private SecretRequest request;

	public SecretRequestProxy()
	{
		super();
	}

	SecretRequestProxy(SecretRequest request)
	{
		super();
		this.request = request;
	}

	@Kroll.method
	public void resolve(@Kroll.argument(optional = true) Object secret)
	{
		if (request != null) {
			request.resolve(secret);
		}
	}

	@Kroll.method
	public void reject(@Kroll.argument(optional = true) Object message)
	{
		if (request != null) {
			request.reject(message);
		}
	}

	@Override
	public String getApiName()
	{
		return "Ti.Paysheet.SecretRequest";
	}
}
