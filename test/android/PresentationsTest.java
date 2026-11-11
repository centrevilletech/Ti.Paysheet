/**
 * Ti.Paysheet — lifecycle tests for Presentations.java on a plain JVM, with a fake clock in place of Android's
 * main-thread Handler and plain sinks in place of the Promise and the Stripe sheet.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class PresentationsTest
{
	private static int passed, failed;

	/** A fake main-thread scheduler: tasks run when the test advances the clock. */
	static final class FakeScheduler implements Presentations.Scheduler
	{
		long now;
		final List<long[]> due = new ArrayList<>();
		final List<Runnable> tasks = new ArrayList<>();

		@Override
		public Runnable schedule(long delayMs, Runnable task)
		{
			final int index = tasks.size();
			due.add(new long[] { now + delayMs, 0 });
			tasks.add(task);
			return () -> due.get(index)[1] = 1; // cancelled
		}

		void advance(long ms)
		{
			now += ms;
			for (int i = 0; i < tasks.size(); i++) {
				long[] d = due.get(i);
				if (d[1] == 0 && d[0] <= now) {
					d[1] = 1;
					tasks.get(i).run();
				}
			}
		}
	}

	static final class Recorder implements Presentations.Sink
	{
		final List<Map<String, Object>> results = new ArrayList<>();

		@Override
		public void settle(HashMap<String, Object> result)
		{
			results.add(result);
		}

		String code(int i)
		{
			Object error = results.get(i).get("error");
			return error == null ? null : (String) ((Map<?, ?>) error).get("code");
		}
	}

	static final class Store implements Presentations.Store
	{
		final List<Map<String, Object>> kept = new ArrayList<>();

		@Override
		public void keepRestored(HashMap<String, Object> result)
		{
			kept.add(result);
		}
	}

	static final class Answers
	{
		final List<String[]> got = new ArrayList<>();

		Presentations.SecretAnswer listener()
		{
			return (secret, error) -> got.add(new String[] { secret, error });
		}
	}

	FakeScheduler clock;
	Store store;
	Presentations p;

	void setUp()
	{
		clock = new FakeScheduler();
		store = new Store();
		p = new Presentations(clock, store);
	}

	public static void main(String[] args) throws Exception
	{
		PresentationsTest t = new PresentationsTest();
		for (java.lang.reflect.Method m : PresentationsTest.class.getDeclaredMethods()) {
			if (!m.getName().startsWith("test")) {
				continue;
			}
			t.setUp();
			try {
				m.invoke(t);
				passed++;
			} catch (java.lang.reflect.InvocationTargetException e) {
				failed++;
				System.out.println("FAIL " + m.getName() + ": " + e.getCause());
			}
		}
		System.out.println((failed == 0 ? "PASS " : "FAIL ") + passed + "/" + (passed + failed) + " (Java lifecycle)");
		System.exit(failed == 0 ? 0 : 1);
	}

	static void check(boolean condition, String what)
	{
		if (!condition) {
			throw new AssertionError(what);
		}
	}

	static HashMap<String, Object> completed()
	{
		return Results.status(Results.COMPLETED, "pi_1");
	}

	// ------------------------------------------------------------------------------------------------------------

	void testSecondPresentationIsBusyUntilTheFirstSettles()
	{
		Recorder a = new Recorder();
		String id = p.begin("pi_1", a, null);
		check(id != null, "first begins");
		check(p.begin("pi_2", new Recorder(), null) == null, "second is busy");
		p.checkIn(id);
		p.deliver(id, completed());
		check(a.results.size() == 1, "first settled");
		check(p.begin("pi_3", new Recorder(), null) != null, "a later one begins");
	}

	void testDeliverSettlesExactlyOnce()
	{
		Recorder a = new Recorder();
		String id = p.begin("pi_1", a, null);
		p.checkIn(id);
		p.deliver(id, completed());
		p.deliver(id, Results.status(Results.CANCELED, "pi_1"));
		check(a.results.size() == 1, "one result, got " + a.results.size());
		check("completed".equals(a.results.get(0).get("status")), "the first result wins");
		check(store.kept.isEmpty(), "nothing kept as restored");
	}

	void testWatchdogSettlesUnavailableWhenTheHostNeverStarts()
	{
		Recorder a = new Recorder();
		String id = p.begin("pi_1", a, null);
		clock.advance(Presentations.HOST_CHECK_IN_MS - 1);
		check(a.results.isEmpty(), "not yet");
		clock.advance(1);
		check(a.results.size() == 1 && "unavailable".equals(a.code(0)), "unavailable after the watchdog");
		check("pi_1".equals(a.results.get(0).get("intentId")), "keeps the intent id");
		check(p.begin("pi_2", new Recorder(), null) != null, "no longer busy");
		check(!p.checkIn(id), "a host that starts late is told it is stale");
		p.deliver(id, completed());
		check(a.results.size() == 1, "a late result is ignored");
		check(store.kept.isEmpty(), "and not kept as a restored result");
	}

	void testCheckInCancelsTheWatchdog()
	{
		Recorder a = new Recorder();
		String id = p.begin("pi_1", a, null);
		check(p.checkIn(id), "host is live");
		clock.advance(Presentations.HOST_CHECK_IN_MS * 3);
		check(a.results.isEmpty(), "no watchdog result after check-in");
	}

	void testStartFailureSettlesUnavailable()
	{
		Recorder a = new Recorder();
		String id = p.begin("pi_1", a, null);
		p.startFailed(id, "blocked");
		check(a.results.size() == 1 && "unavailable".equals(a.code(0)), "unavailable");
		clock.advance(Presentations.HOST_CHECK_IN_MS * 2);
		check(a.results.size() == 1, "the watchdog does not settle it again");
		check(p.begin("pi_2", new Recorder(), null) != null, "no longer busy");
	}

	void testUnknownIdIsKeptAsARestoredResult()
	{
		// After process death the host activity delivers for an id this process never issued.
		p.deliver("from-the-old-process", completed());
		check(store.kept.size() == 1, "kept for takeRestoredResult()");
	}

	void testThrowingSinkStillFreesTheModule()
	{
		String id = p.begin("pi_1", r -> { throw new RuntimeException("callback threw"); }, null);
		p.checkIn(id);
		try {
			p.deliver(id, completed());
		} catch (RuntimeException expected) {
			// propagates to the caller's logging; the state must already be clean
		}
		check(p.begin("pi_2", new Recorder(), null) != null, "not stuck busy");
	}

	void testSecretRequestIsAnsweredOnceAndLateAnswersAreIgnored()
	{
		List<SecretRequest> asked = new ArrayList<>();
		String id = p.begin(null, new Recorder(), asked::add);
		p.checkIn(id);
		Answers answers = new Answers();
		p.requestSecret(id, answers.listener());
		check(asked.size() == 1, "JavaScript was asked");
		asked.get(0).resolve("seti_1_secret_x");
		asked.get(0).reject("too late");
		asked.get(0).resolve("seti_2_secret_y");
		check(answers.got.size() == 1, "one answer");
		check("seti_1_secret_x".equals(answers.got.get(0)[0]), "the first answer wins");
	}

	void testSecretRequestTimesOut()
	{
		List<SecretRequest> asked = new ArrayList<>();
		String id = p.begin(null, new Recorder(), asked::add);
		p.checkIn(id);
		Answers answers = new Answers();
		p.requestSecret(id, answers.listener());
		clock.advance(Presentations.SECRET_TIMEOUT_MS);
		check(answers.got.size() == 1 && answers.got.get(0)[0] == null, "timed out");
		check(answers.got.get(0)[1].contains("did not answer within 60 seconds"), answers.got.get(0)[1]);
		asked.get(0).resolve("seti_late_secret_z");
		check(answers.got.size() == 1, "a late answer is ignored");
	}

	void testSecretRequestRejectAndBadValues()
	{
		List<SecretRequest> asked = new ArrayList<>();
		String id = p.begin(null, new Recorder(), asked::add);
		p.checkIn(id);
		Answers a1 = new Answers(), a2 = new Answers(), a3 = new Answers();
		p.requestSecret(id, a1.listener());
		asked.get(0).reject("server down");
		check(a1.got.get(0)[0] == null && "server down".equals(a1.got.get(0)[1]), "rejection message passed on");
		p.requestSecret(id, a2.listener());
		asked.get(1).resolve(42);
		check(a2.got.get(0)[0] == null, "a non-string secret is an error");
		p.requestSecret(id, a3.listener());
		asked.get(2).reject(null);
		check("The app could not create a SetupIntent.".equals(a3.got.get(0)[1]), "default rejection message");
	}

	void testThrowingSecretCallbackAnswersWithAnError()
	{
		String id = p.begin(null, new Recorder(), r -> { throw new RuntimeException("JS threw"); });
		p.checkIn(id);
		Answers answers = new Answers();
		p.requestSecret(id, answers.listener());
		check(answers.got.size() == 1 && answers.got.get(0)[0] == null, "answered with an error at once");
		clock.advance(Presentations.SECRET_TIMEOUT_MS);
		check(answers.got.size() == 1, "and not again by the timeout");
	}

	void testSecretRequestAfterProcessDeathAsksToReopen()
	{
		// CustomerSheet restored in a new process: its provider asks for an id this process never issued.
		Answers answers = new Answers();
		p.requestSecret("from-the-old-process", answers.listener());
		check(answers.got.size() == 1 && answers.got.get(0)[0] == null, "error");
		check(answers.got.get(0)[1].contains("close and reopen the sheet"), answers.got.get(0)[1]);
	}

	void testSecretRequestWithoutACallbackOrAfterSettling()
	{
		String id = p.begin(null, new Recorder(), null);
		p.checkIn(id);
		Answers a1 = new Answers();
		p.requestSecret(id, a1.listener());
		check(a1.got.size() == 1 && a1.got.get(0)[0] == null, "no fetch function: error");
		p.deliver(id, completed());
		Answers a2 = new Answers();
		p.requestSecret(id, a2.listener());
		check(a2.got.size() == 1 && a2.got.get(0)[0] == null, "after settling: error");
	}
}
