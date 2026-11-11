/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet;

import java.io.Serializable;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Validates the JavaScript options and turns them into plain, serialisable configuration.
 *
 * Pure Java on purpose (no Android or Stripe types) so it can be unit-tested on a plain JVM against the
 * same test vectors as the iOS implementation (test/vectors.json). Keep the two in step.
 */
public final class Options
{
	private Options()
	{
	}

	/** Thrown for invalid options; the message names the offending option. */
	public static final class InvalidException extends Exception
	{
		private static final long serialVersionUID = 1L;
		/** The offending option, e.g. "customer.id" or "appearance.colors.primary". */
		public final String option;

		InvalidException(String option, String message)
		{
			super(message);
			this.option = option;
		}
	}

	static final List<String> COLLECTION_MODES = Arrays.asList("automatic", "never", "always");
	static final List<String> ADDRESS_MODES = Arrays.asList("automatic", "never", "full");
	static final List<String> LAYOUTS = Arrays.asList("automatic", "horizontal", "vertical");
	static final List<String> STYLES = Arrays.asList("automatic", "light", "dark");
	static final List<String> GOOGLE_PAY_ENVIRONMENTS = Arrays.asList("test", "production");
	static final List<String> COLOR_KEYS = Arrays.asList("primary", "background", "componentBackground",
		"componentBorder", "componentDivider", "text", "textSecondary", "componentText", "placeholderText", "icon",
		"danger");
	static final List<String> BUTTON_COLOR_KEYS = Arrays.asList("backgroundColor", "textColor", "borderColor");

	public static final class Init implements Serializable
	{
		private static final long serialVersionUID = 1L;
		public String publishableKey;
		public String stripeAccountId;
	}

	public static final class Billing implements Serializable
	{
		private static final long serialVersionUID = 1L;
		public String name, email, phone;
		public String line1, line2, city, state, postalCode, country;
		public boolean hasAddress;
	}

	public static final class Appearance implements Serializable
	{
		private static final long serialVersionUID = 1L;
		/** ARGB colours by option key; absent keys keep Stripe's default. */
		public final LinkedHashMap<String, Integer> colors = new LinkedHashMap<>();
		public final LinkedHashMap<String, Integer> colorsDark = new LinkedHashMap<>();
		public Float cornerRadius, borderWidth;
		public String fontFamily;
		public Float fontScale;
		public final LinkedHashMap<String, Integer> button = new LinkedHashMap<>();
		public final LinkedHashMap<String, Integer> buttonDark = new LinkedHashMap<>();
		public Float buttonCornerRadius, buttonBorderWidth, buttonHeight, buttonFontSize;
		public String buttonFontFamily;
	}

	public static final class Sheet implements Serializable
	{
		private static final long serialVersionUID = 1L;
		/** "payment", "setup" or "customer". */
		public String mode;
		public String intentClientSecret;
		public String merchantDisplayName;
		public String customerId, customerSessionClientSecret, ephemeralKeySecret;
		public String returnURL;
		public boolean allowsDelayedPaymentMethods;
		public Billing defaultBillingDetails;
		public boolean hasCollection;
		public String collectName = "automatic", collectEmail = "automatic", collectPhone = "automatic",
					  collectAddress = "automatic";
		public boolean attachDefaultsToPaymentMethod;
		public String primaryButtonLabel;
		public String paymentMethodLayout = "automatic";
		public String style = "automatic";
		public String headerTitle;
		public Appearance appearance;
		/** PaymentSheet Google Pay (null = off). */
		public String googlePayEnvironment, googlePayCountryCode, googlePayCurrencyCode;
		/** CustomerSheet wallet switches. */
		public boolean googlePayEnabled, applePayEnabled;
		/** iOS only, validated for parity. */
		public String applePayMerchantId, applePayCountryCode;
		/** Copied in by the module so the host activity can re-initialise after process death. */
		public String publishableKey, stripeAccountId;
	}

	// ---------------------------------------------------------------------------------------------------------------

	public static Init parseInitialize(Object raw) throws InvalidException
	{
		Map<String, Object> o = object(raw, "options");
		Init init = new Init();
		init.publishableKey = requiredString(o, "publishableKey", "publishableKey");
		if (!init.publishableKey.startsWith("pk_")) {
			throw new InvalidException("publishableKey", "publishableKey must be a publishable key (pk_test_… or pk_live_…), never a secret key");
		}
		init.stripeAccountId = optionalString(o, "stripeAccountId", "stripeAccountId");
		return init;
	}

	public static Sheet parsePaymentSheet(Object raw) throws InvalidException
	{
		Map<String, Object> o = object(raw, "options");
		Sheet s = new Sheet();
		String pi = optionalString(o, "paymentIntentClientSecret", "paymentIntentClientSecret");
		String si = optionalString(o, "setupIntentClientSecret", "setupIntentClientSecret");
		if ((pi == null) == (si == null)) {
			throw new InvalidException("paymentIntentClientSecret", "exactly one of paymentIntentClientSecret and setupIntentClientSecret is required");
		}
		s.mode = pi != null ? "payment" : "setup";
		s.intentClientSecret = pi != null ? pi : si;
		parseCommon(o, s);

		Object customer = o.get("customer");
		if (customer != null) {
			Map<String, Object> c = object(customer, "customer");
			s.customerId = requiredString(c, "id", "customer.id");
			s.customerSessionClientSecret =
				optionalString(c, "customerSessionClientSecret", "customer.customerSessionClientSecret");
			s.ephemeralKeySecret = optionalString(c, "ephemeralKeySecret", "customer.ephemeralKeySecret");
			if ((s.customerSessionClientSecret == null) == (s.ephemeralKeySecret == null)) {
				throw new InvalidException("customer",
					"customer needs exactly one of customerSessionClientSecret and ephemeralKeySecret");
			}
		}

		s.allowsDelayedPaymentMethods = optionalBoolean(o, "allowsDelayedPaymentMethods", "allowsDelayedPaymentMethods", false);
		s.primaryButtonLabel = optionalString(o, "primaryButtonLabel", "primaryButtonLabel");
		s.paymentMethodLayout = optionalEnum(o, "paymentMethodLayout", "paymentMethodLayout", LAYOUTS, "automatic");

		Object applePay = o.get("applePay");
		if (applePay != null) {
			Map<String, Object> a = object(applePay, "applePay");
			s.applePayMerchantId = requiredString(a, "merchantId", "applePay.merchantId");
			s.applePayCountryCode = countryCode(requiredString(a, "merchantCountryCode", "applePay.merchantCountryCode"),
				"applePay.merchantCountryCode");
		}
		Object googlePay = o.get("googlePay");
		if (googlePay != null) {
			Map<String, Object> g = object(googlePay, "googlePay");
			s.googlePayEnvironment = optionalEnum(g, "environment", "googlePay.environment", GOOGLE_PAY_ENVIRONMENTS, "test");
			s.googlePayCountryCode = countryCode(requiredString(g, "countryCode", "googlePay.countryCode"),
				"googlePay.countryCode");
			String currency = optionalString(g, "currencyCode", "googlePay.currencyCode");
			if (currency != null && !currency.matches("[A-Za-z]{3}")) {
				throw new InvalidException("googlePay.currencyCode", "googlePay.currencyCode must be a three-letter ISO 4217 code");
			}
			s.googlePayCurrencyCode = currency != null ? currency.toUpperCase(java.util.Locale.ROOT) : null;
			if ("setup".equals(s.mode) && s.googlePayCurrencyCode == null) {
				throw new InvalidException("googlePay.currencyCode", "googlePay.currencyCode is required in setup mode");
			}
		}
		return s;
	}

	public static Sheet parseCustomerSheet(Object raw) throws InvalidException
	{
		Map<String, Object> o = object(raw, "options");
		Sheet s = new Sheet();
		s.mode = "customer";
		parseCommon(o, s);
		Object customer = o.get("customer");
		if (customer == null) {
			throw new InvalidException("customer", "customer is required");
		}
		Map<String, Object> c = object(customer, "customer");
		s.customerId = requiredString(c, "id", "customer.id");
		if (c.get("ephemeralKeySecret") != null) {
			throw new InvalidException("customer.ephemeralKeySecret", "presentCustomerSheet needs customer.customerSessionClientSecret; ephemeral keys are not supported");
		}
		s.customerSessionClientSecret =
			requiredString(c, "customerSessionClientSecret", "customer.customerSessionClientSecret");
		Object fetch = o.get("fetchSetupIntentClientSecret");
		if (fetch == null) {
			throw new InvalidException("fetchSetupIntentClientSecret", "fetchSetupIntentClientSecret is required");
		}
		// The function itself is checked by the platform code (it is not a plain value).
		s.headerTitle = optionalString(o, "headerTitle", "headerTitle");
		s.applePayEnabled = optionalBoolean(o, "applePay", "applePay", false);
		s.googlePayEnabled = optionalBoolean(o, "googlePay", "googlePay", false);
		return s;
	}

	private static void parseCommon(Map<String, Object> o, Sheet s) throws InvalidException
	{
		s.merchantDisplayName = requiredString(o, "merchantDisplayName", "merchantDisplayName");
		s.returnURL = optionalString(o, "returnURL", "returnURL");
		if (s.returnURL != null && !s.returnURL.matches("[A-Za-z][A-Za-z0-9+.-]*:.*")) {
			throw new InvalidException("returnURL", "returnURL must be an absolute URL with your app's scheme, e.g. myapp://stripe-redirect");
		}
		s.style = optionalEnum(o, "style", "style", STYLES, "automatic");

		Object billing = o.get("defaultBillingDetails");
		if (billing != null) {
			Map<String, Object> b = object(billing, "defaultBillingDetails");
			Billing d = new Billing();
			d.name = optionalString(b, "name", "defaultBillingDetails.name");
			d.email = optionalString(b, "email", "defaultBillingDetails.email");
			d.phone = optionalString(b, "phone", "defaultBillingDetails.phone");
			Object address = b.get("address");
			if (address != null) {
				Map<String, Object> a = object(address, "defaultBillingDetails.address");
				d.hasAddress = true;
				d.line1 = optionalString(a, "line1", "defaultBillingDetails.address.line1");
				d.line2 = optionalString(a, "line2", "defaultBillingDetails.address.line2");
				d.city = optionalString(a, "city", "defaultBillingDetails.address.city");
				d.state = optionalString(a, "state", "defaultBillingDetails.address.state");
				d.postalCode = optionalString(a, "postalCode", "defaultBillingDetails.address.postalCode");
				String country = optionalString(a, "country", "defaultBillingDetails.address.country");
				d.country = country != null ? countryCode(country, "defaultBillingDetails.address.country") : null;
			}
			s.defaultBillingDetails = d;
		}

		Object collection = o.get("billingDetailsCollection");
		if (collection != null) {
			Map<String, Object> c = object(collection, "billingDetailsCollection");
			s.hasCollection = true;
			s.collectName = optionalEnum(c, "name", "billingDetailsCollection.name", COLLECTION_MODES, "automatic");
			s.collectEmail = optionalEnum(c, "email", "billingDetailsCollection.email", COLLECTION_MODES, "automatic");
			s.collectPhone = optionalEnum(c, "phone", "billingDetailsCollection.phone", COLLECTION_MODES, "automatic");
			s.collectAddress = optionalEnum(c, "address", "billingDetailsCollection.address", ADDRESS_MODES, "automatic");
			s.attachDefaultsToPaymentMethod = optionalBoolean(c, "attachDefaultsToPaymentMethod",
				"billingDetailsCollection.attachDefaultsToPaymentMethod", false);
		}

		Object appearance = o.get("appearance");
		if (appearance != null) {
			s.appearance = parseAppearance(object(appearance, "appearance"));
		}
	}

	private static Appearance parseAppearance(Map<String, Object> o) throws InvalidException
	{
		Appearance a = new Appearance();
		colors(o.get("colors"), "appearance.colors", COLOR_KEYS, a.colors);
		colors(o.get("colorsDark"), "appearance.colorsDark", COLOR_KEYS, a.colorsDark);
		a.cornerRadius = optionalNumber(o, "cornerRadius", "appearance.cornerRadius");
		a.borderWidth = optionalNumber(o, "borderWidth", "appearance.borderWidth");
		Object font = o.get("font");
		if (font != null) {
			Map<String, Object> f = object(font, "appearance.font");
			a.fontFamily = optionalString(f, "family", "appearance.font.family");
			a.fontScale = optionalNumber(f, "scale", "appearance.font.scale");
			if (a.fontScale != null && a.fontScale == 0f) {
				throw new InvalidException("appearance.font.scale", "appearance.font.scale must be greater than 0");
			}
		}
		Object button = o.get("primaryButton");
		if (button != null) {
			Map<String, Object> b = object(button, "appearance.primaryButton");
			Map<String, Object> light = new LinkedHashMap<>();
			for (String key : BUTTON_COLOR_KEYS) {
				if (b.get(key) != null) {
					light.put(key, b.get(key));
				}
			}
			colors(light, "appearance.primaryButton", BUTTON_COLOR_KEYS, a.button);
			colors(b.get("dark"), "appearance.primaryButton.dark", BUTTON_COLOR_KEYS, a.buttonDark);
			a.buttonCornerRadius = optionalNumber(b, "cornerRadius", "appearance.primaryButton.cornerRadius");
			a.buttonBorderWidth = optionalNumber(b, "borderWidth", "appearance.primaryButton.borderWidth");
			a.buttonHeight = optionalNumber(b, "height", "appearance.primaryButton.height");
			Object bf = b.get("font");
			if (bf != null) {
				Map<String, Object> f = object(bf, "appearance.primaryButton.font");
				a.buttonFontFamily = optionalString(f, "family", "appearance.primaryButton.font.family");
				a.buttonFontSize = optionalNumber(f, "size", "appearance.primaryButton.font.size");
			}
		}
		return a;
	}

	private static void colors(Object raw, String path, List<String> allowed, Map<String, Integer> out)
		throws InvalidException
	{
		if (raw == null) {
			return;
		}
		Map<String, Object> m = object(raw, path);
		for (Map.Entry<String, Object> e : m.entrySet()) {
			if (!allowed.contains(e.getKey())) {
				throw new InvalidException(path + "." + e.getKey(), path + "." + e.getKey() + " is not a known colour");
			}
			if (e.getValue() == null) {
				continue;
			}
			if (!(e.getValue() instanceof String)) {
				throw new InvalidException(path + "." + e.getKey(), path + "." + e.getKey() + " must be a colour string such as '#0A84FF'");
			}
			Integer argb = parseColor((String) e.getValue());
			if (argb == null) {
				throw new InvalidException(path + "." + e.getKey(), path + "." + e.getKey() + ": invalid colour '" + e.getValue()
										   + "' (use #RGB, #RRGGBB or #AARRGGBB)");
			}
			out.put(e.getKey(), argb);
		}
	}

	/** Parses "#RGB", "#RRGGBB" or "#AARRGGBB" (Titanium's alpha-first order) to ARGB; null if invalid. */
	public static Integer parseColor(String s)
	{
		if (s == null || !s.matches("#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})")) {
			return null;
		}
		String hex = s.substring(1);
		if (hex.length() == 3) {
			hex = "" + hex.charAt(0) + hex.charAt(0) + hex.charAt(1) + hex.charAt(1) + hex.charAt(2) + hex.charAt(2);
		}
		if (hex.length() == 6) {
			hex = "FF" + hex;
		}
		return (int) Long.parseLong(hex, 16);
	}

	/** The intent id ("pi_…" / "seti_…") in a client secret, or null. */
	public static String intentIdFromClientSecret(String secret)
	{
		if (secret == null) {
			return null;
		}
		int i = secret.indexOf("_secret_");
		return i > 0 ? secret.substring(0, i) : null;
	}

	// ---------------------------------------------------------------------------------------------------------------

	@SuppressWarnings("unchecked")
	private static Map<String, Object> object(Object raw, String path) throws InvalidException
	{
		if (!(raw instanceof Map)) {
			throw new InvalidException(path, path + " must be an object");
		}
		return (Map<String, Object>) raw;
	}

	private static String requiredString(Map<String, Object> o, String key, String path) throws InvalidException
	{
		String s = optionalString(o, key, path);
		if (s == null) {
			throw new InvalidException(path, path + " is required");
		}
		return s;
	}

	private static String optionalString(Map<String, Object> o, String key, String path) throws InvalidException
	{
		Object v = o.get(key);
		if (v == null) {
			return null;
		}
		if (!(v instanceof String)) {
			throw new InvalidException(path, path + " must be a string");
		}
		String s = ((String) v).trim();
		if (s.isEmpty()) {
			throw new InvalidException(path, path + " must not be empty");
		}
		return s;
	}

	private static boolean optionalBoolean(Map<String, Object> o, String key, String path, boolean fallback)
		throws InvalidException
	{
		Object v = o.get(key);
		if (v == null) {
			return fallback;
		}
		if (!(v instanceof Boolean)) {
			throw new InvalidException(path, path + " must be a boolean");
		}
		return (Boolean) v;
	}

	private static Float optionalNumber(Map<String, Object> o, String key, String path) throws InvalidException
	{
		Object v = o.get(key);
		if (v == null) {
			return null;
		}
		if (!(v instanceof Number)) {
			throw new InvalidException(path, path + " must be a number");
		}
		float f = ((Number) v).floatValue();
		if (Float.isNaN(f) || Float.isInfinite(f) || f < 0) {
			throw new InvalidException(path, path + " must be a number of 0 or more");
		}
		return f;
	}

	private static String optionalEnum(Map<String, Object> o, String key, String path, List<String> allowed,
									   String fallback) throws InvalidException
	{
		String s = optionalString(o, key, path);
		if (s == null) {
			return fallback;
		}
		if (!allowed.contains(s)) {
			throw new InvalidException(path, path + " must be one of " + String.join(", ", allowed));
		}
		return s;
	}

	private static String countryCode(String s, String path) throws InvalidException
	{
		if (!s.matches("[A-Za-z]{2}")) {
			throw new InvalidException(path, path + " must be a two-letter ISO 3166 country code");
		}
		return s.toUpperCase(java.util.Locale.ROOT);
	}
}
