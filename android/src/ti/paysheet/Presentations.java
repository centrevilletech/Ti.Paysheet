/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

/**
 * The lifecycle of presentations, without Android or Stripe types so it can be tested on a plain JVM
 * (test/android/PresentationsTest.java). One presentation at a time; each settles exactly once.
 *
 * Called on the main thread only; the module supplies a Handler-based scheduler.
 */
public final class Presentations
{
	/** How long the host activity has to start (onCreate) before the presentation is settled as unavailable. */
	public static final long HOST_CHECK_IN_MS = 8000;
	/** How long the app has to answer fetchSetupIntentClientSecret. */
	public static final long SECRET_TIMEOUT_MS = 60000;

	public interface Sink {
		void settle(HashMap<String, Object> result);
	}

	public interface Scheduler {
		/** Runs {@code task} after {@code delayMs}; the returned Runnable cancels it. */
		Runnable schedule(long delayMs, Runnable task);
	}

	public interface Store {
		void keepRestored(HashMap<String, Object> result);
	}

	public interface SecretAnswer {
		/** Exactly one of {@code secret} and {@code error} is non-null. */
		void onAnswer(String secret, String error);
	}

	public interface SecretAsker {
		/** Hands the request to JavaScript. */
		void ask(SecretRequest request) throws Exception;
	}

	private static final class Active
	{
		final String id;
		final String intentId;
		final Sink sink;
		final SecretAsker asker;
		Runnable cancelWatchdog;

		Active(String id, String intentId, Sink sink, SecretAsker asker)
		{
			this.id = id;
			this.intentId = intentId;
			this.sink = sink;
			this.asker = asker;
		}
	}

	private final Scheduler scheduler;
	private final Store store;
	private Active active;
	/** Ids issued by this process (a result for any other id comes from before a process restart). */
	private final Set<String> issued = new HashSet<>();

	public Presentations(Scheduler scheduler, Store store)
	{
		this.scheduler = scheduler;
		this.store = store;
	}

	/** Starts a presentation; returns its id, or null when another one is in progress (busy). */
	public String begin(String intentId, Sink sink, SecretAsker asker)
	{
		if (active != null) {
			return null;
		}
		final String id = UUID.randomUUID().toString();
		final Active a = new Active(id, intentId, sink, asker);
		issued.add(id);
		active = a;
		a.cancelWatchdog = scheduler.schedule(HOST_CHECK_IN_MS, () -> {
			if (active == a) {
				settle(a, Results.moduleError(a.intentId, Results.UNAVAILABLE,
					"The payment sheet did not open. The app may have been in the background; try again."));
			}
		});
		return id;
	}

	/** The host activity could not be started at all. */
	public void startFailed(String id, String message)
	{
		if (active != null && active.id.equals(id)) {
			settle(active, Results.moduleError(active.intentId, Results.UNAVAILABLE, message));
		}
	}

	/** Called by the host activity's onCreate; false means this presentation is over and the host must finish. */
	public boolean checkIn(String id)
	{
		if (active == null || !active.id.equals(id)) {
			return false;
		}
		if (active.cancelWatchdog != null) {
			active.cancelWatchdog.run();
			active.cancelWatchdog = null;
		}
		return true;
	}

	public boolean isLive(String id)
	{
		return active != null && active.id.equals(id);
	}

	public String intentIdFor(String id)
	{
		return isLive(id) ? active.intentId : null;
	}

	/** Settles presentation {@code id} once; a result for an id from before a process restart is kept instead. */
	public void deliver(String id, HashMap<String, Object> result)
	{
		if (active != null && active.id.equals(id)) {
			settle(active, result);
		} else if (!issued.contains(id)) {
			store.keepRestored(result);
		}
		// otherwise: already settled (watchdog, start failure, second result): ignore
	}

	/** Asks JavaScript for a SetupIntent client secret; {@code answer} is called exactly once. */
	public void requestSecret(String id, SecretAnswer answer)
	{
		if (!isLive(id)) {
			answer.onAnswer(null, "The app is no longer able to create a SetupIntent; close and reopen the sheet.");
			return;
		}
		if (active.asker == null) {
			answer.onAnswer(null, "fetchSetupIntentClientSecret is not available.");
			return;
		}
		final SecretRequest request = new SecretRequest(answer);
		request.setCancelTimeout(scheduler.schedule(SECRET_TIMEOUT_MS,
			() -> request.answer(null, "fetchSetupIntentClientSecret did not answer within 60 seconds")));
		try {
			active.asker.ask(request);
		} catch (Exception e) {
			request.answer(null, "fetchSetupIntentClientSecret failed.");
		}
	}

	private void settle(Active a, HashMap<String, Object> result)
	{
		active = null;
		if (a.cancelWatchdog != null) {
			a.cancelWatchdog.run();
			a.cancelWatchdog = null;
		}
		a.sink.settle(result);
	}
}
