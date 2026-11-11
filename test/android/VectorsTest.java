/**
 * Ti.Paysheet — runs test/vectors.json against Options.java and Results.java on a plain JVM.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

public final class VectorsTest
{
	private static int passed, failed;

	public static void main(String[] args) throws Exception
	{
		Map<String, Object> v = asMap(new Json(new String(Files.readAllBytes(Paths.get(args[0])), StandardCharsets.UTF_8)).value());

		for (Object o : asList(v.get("options"))) {
			Map<String, Object> c = asMap(o);
			String name = (String) c.get("name");
			String parse = (String) c.get("parse");
			try {
				Map<String, Object> summary;
				if (parse.equals("initialize")) {
					Options.Init i = Options.parseInitialize(c.get("input"));
					summary = new LinkedHashMap<>();
					summary.put("publishableKey", i.publishableKey);
					summary.put("stripeAccountId", i.stripeAccountId);
				} else {
					summary = summarize(parse.equals("customer") ? Options.parseCustomerSheet(c.get("input"))
																  : Options.parsePaymentSheet(c.get("input")));
				}
				if (c.containsKey("error")) {
					fail(name, "expected error '" + c.get("error") + "', got success");
					continue;
				}
				boolean ok = true;
				for (Map.Entry<String, Object> e : asMap(c.get("expect")).entrySet()) {
					if (!same(e.getValue(), summary.get(e.getKey()))) {
						fail(name, e.getKey() + ": expected " + e.getValue() + ", got " + summary.get(e.getKey()));
						ok = false;
					}
				}
				if (ok) {
					pass();
				}
			} catch (Options.InvalidException e) {
				if (Objects.equals(c.get("error"), e.getMessage())) {
					pass();
				} else {
					fail(name, "expected " + (c.containsKey("error") ? "error '" + c.get("error") + "'" : "success") + ", got error '" + e.getMessage() + "'");
				}
			}
		}

		for (Object o : asList(v.get("colors"))) {
			Map<String, Object> c = asMap(o);
			Integer argb = Options.parseColor((String) c.get("input"));
			String got = argb == null ? null : String.format("%08X", argb);
			check("colour " + c.get("input"), c.get("argb"), got);
		}

		for (Object o : asList(v.get("intentIds"))) {
			Map<String, Object> c = asMap(o);
			check("intent id " + c.get("input"), c.get("id"), Options.intentIdFromClientSecret((String) c.get("input")));
		}

		for (Object o : asList(v.get("results"))) {
			Map<String, Object> c = asMap(o);
			Map<String, Object> got = Results.failed((String) c.get("intentId"), (String) c.get("apiCode"),
				(String) c.get("fallbackCode"), (String) c.get("message"), (String) c.get("declineCode"), (String) c.get("type"));
			check("result " + c.get("name"), c.get("expect"), got);
		}

		System.out.println((failed == 0 ? "PASS " : "FAIL ") + passed + "/" + (passed + failed) + " (Java)");
		System.exit(failed == 0 ? 0 : 1);
	}

	static Map<String, Object> summarize(Options.Sheet s)
	{
		Map<String, Object> m = new LinkedHashMap<>();
		m.put("mode", s.mode);
		m.put("intentClientSecret", s.intentClientSecret);
		m.put("merchantDisplayName", s.merchantDisplayName);
		m.put("customerId", s.customerId);
		m.put("customerSessionClientSecret", s.customerSessionClientSecret);
		m.put("ephemeralKeySecret", s.ephemeralKeySecret);
		m.put("returnURL", s.returnURL);
		m.put("allowsDelayedPaymentMethods", s.allowsDelayedPaymentMethods);
		m.put("style", s.style);
		m.put("paymentMethodLayout", s.paymentMethodLayout);
		m.put("primaryButtonLabel", s.primaryButtonLabel);
		m.put("headerTitle", s.headerTitle);
		m.put("collectName", s.collectName);
		m.put("collectEmail", s.collectEmail);
		m.put("collectPhone", s.collectPhone);
		m.put("collectAddress", s.collectAddress);
		m.put("attachDefaultsToPaymentMethod", s.attachDefaultsToPaymentMethod);
		m.put("googlePayEnvironment", s.googlePayEnvironment);
		m.put("googlePayCountryCode", s.googlePayCountryCode);
		m.put("googlePayCurrencyCode", s.googlePayCurrencyCode);
		m.put("googlePayEnabled", s.googlePayEnabled);
		m.put("applePayEnabled", s.applePayEnabled);
		m.put("applePayMerchantId", s.applePayMerchantId);
		m.put("applePayCountryCode", s.applePayCountryCode);
		if (s.defaultBillingDetails != null) {
			Options.Billing b = s.defaultBillingDetails;
			m.put("billing.name", b.name);
			m.put("billing.email", b.email);
			m.put("billing.phone", b.phone);
			m.put("billing.line1", b.line1);
			m.put("billing.postalCode", b.postalCode);
			m.put("billing.country", b.country);
			m.put("billing.hasAddress", b.hasAddress);
		}
		if (s.appearance != null) {
			Options.Appearance a = s.appearance;
			a.colors.forEach((k, c) -> m.put("colors." + k, String.format("%08X", c)));
			a.colorsDark.forEach((k, c) -> m.put("colorsDark." + k, String.format("%08X", c)));
			a.button.forEach((k, c) -> m.put("button." + k, String.format("%08X", c)));
			a.buttonDark.forEach((k, c) -> m.put("buttonDark." + k, String.format("%08X", c)));
			m.put("cornerRadius", a.cornerRadius);
			m.put("borderWidth", a.borderWidth);
			m.put("fontFamily", a.fontFamily);
			m.put("fontScale", a.fontScale);
			m.put("buttonCornerRadius", a.buttonCornerRadius);
			m.put("buttonHeight", a.buttonHeight);
			m.put("buttonFontSize", a.buttonFontSize);
		}
		return m;
	}

	static boolean same(Object expected, Object actual)
	{
		if (expected instanceof Number && actual instanceof Number) {
			return Math.abs(((Number) expected).doubleValue() - ((Number) actual).doubleValue()) < 1e-6;
		}
		if (expected instanceof Map && actual instanceof Map) {
			Map<?, ?> e = (Map<?, ?>) expected, a = (Map<?, ?>) actual;
			if (!e.keySet().equals(a.keySet())) {
				return false;
			}
			for (Object k : e.keySet()) {
				if (!same(e.get(k), a.get(k))) {
					return false;
				}
			}
			return true;
		}
		return Objects.equals(expected, actual);
	}

	static void check(String name, Object expected, Object actual)
	{
		if (same(expected, actual)) {
			pass();
		} else {
			fail(name, "expected " + expected + ", got " + actual);
		}
	}

	static void pass()
	{
		passed++;
	}

	static void fail(String name, String why)
	{
		failed++;
		System.out.println("FAIL " + name + ": " + why);
	}

	@SuppressWarnings("unchecked")
	static Map<String, Object> asMap(Object o)
	{
		return (Map<String, Object>) o;
	}

	@SuppressWarnings("unchecked")
	static List<Object> asList(Object o)
	{
		return (List<Object>) o;
	}

	/** Minimal JSON reader: objects become LinkedHashMap, numbers Long or Double, like Titanium's bridge. */
	static final class Json
	{
		private final String s;
		private int i;

		Json(String s)
		{
			this.s = s;
		}

		Object value()
		{
			ws();
			char c = s.charAt(i);
			if (c == '{') {
				i++;
				Map<String, Object> m = new LinkedHashMap<>();
				ws();
				if (s.charAt(i) == '}') {
					i++;
					return m;
				}
				while (true) {
					ws();
					String k = string();
					ws();
					i++; // :
					m.put(k, value());
					ws();
					if (s.charAt(i++) == '}') {
						return m;
					}
				}
			}
			if (c == '[') {
				i++;
				List<Object> l = new ArrayList<>();
				ws();
				if (s.charAt(i) == ']') {
					i++;
					return l;
				}
				while (true) {
					l.add(value());
					ws();
					if (s.charAt(i++) == ']') {
						return l;
					}
				}
			}
			if (c == '"') {
				return string();
			}
			if (s.startsWith("true", i)) {
				i += 4;
				return Boolean.TRUE;
			}
			if (s.startsWith("false", i)) {
				i += 5;
				return Boolean.FALSE;
			}
			if (s.startsWith("null", i)) {
				i += 4;
				return null;
			}
			int start = i;
			while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) {
				i++;
			}
			String n = s.substring(start, i);
			return n.contains(".") || n.contains("e") || n.contains("E") ? (Object) Double.valueOf(n) : (Object) Long.valueOf(n);
		}

		private String string()
		{
			StringBuilder b = new StringBuilder();
			i++; // opening quote
			while (true) {
				char c = s.charAt(i++);
				if (c == '"') {
					return b.toString();
				}
				if (c == '\\') {
					char e = s.charAt(i++);
					switch (e) {
						case 'n': b.append('\n'); break;
						case 't': b.append('\t'); break;
						case 'u': b.append((char) Integer.parseInt(s.substring(i, i + 4), 16)); i += 4; break;
						default: b.append(e);
					}
				} else {
					b.append(c);
				}
			}
		}

		private void ws()
		{
			while (i < s.length() && Character.isWhitespace(s.charAt(i))) {
				i++;
			}
		}
	}
}
