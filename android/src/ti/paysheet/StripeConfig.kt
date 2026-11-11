/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet

import android.content.Context
import android.util.Log
import com.stripe.android.customersheet.CustomerSheet
import com.stripe.android.paymentsheet.PaymentSheet

/** Turns validated [Options.Sheet] values into Stripe configuration objects. */
internal object StripeConfig {

	fun paymentSheetConfiguration(context: Context, s: Options.Sheet): PaymentSheet.Configuration {
		val b = PaymentSheet.Configuration.Builder(s.merchantDisplayName)
			.allowsDelayedPaymentMethods(s.allowsDelayedPaymentMethods)
			.appearance(appearance(context, s))
			.paymentMethodLayout(
				when (s.paymentMethodLayout) {
					"horizontal" -> PaymentSheet.PaymentMethodLayout.Horizontal
					"vertical" -> PaymentSheet.PaymentMethodLayout.Vertical
					else -> PaymentSheet.PaymentMethodLayout.Automatic
				},
			)
		if (s.customerId != null) {
			b.customer(
				if (s.customerSessionClientSecret != null) {
					PaymentSheet.CustomerConfiguration.createWithCustomerSession(s.customerId, s.customerSessionClientSecret)
				} else {
					PaymentSheet.CustomerConfiguration(s.customerId, s.ephemeralKeySecret)
				},
			)
		}
		billingDetails(s)?.let { b.defaultBillingDetails(it) }
		if (s.hasCollection) {
			b.billingDetailsCollectionConfiguration(collection(s))
		}
		s.primaryButtonLabel?.let { b.primaryButtonLabel(it) }
		if (s.googlePayCountryCode != null) {
			b.googlePay(
				PaymentSheet.GooglePayConfiguration(
					environment = if (s.googlePayEnvironment == "production") {
						PaymentSheet.GooglePayConfiguration.Environment.Production
					} else {
						PaymentSheet.GooglePayConfiguration.Environment.Test
					},
					countryCode = s.googlePayCountryCode,
					currencyCode = s.googlePayCurrencyCode,
				),
			)
		}
		return b.build()
	}

	fun customerSheetConfiguration(context: Context, s: Options.Sheet): CustomerSheet.Configuration {
		val b = CustomerSheet.Configuration.builder(s.merchantDisplayName)
			.appearance(appearance(context, s))
			.googlePayEnabled(s.googlePayEnabled)
		s.headerTitle?.let { b.headerTextForSelectionScreen(it) }
		billingDetails(s)?.let { b.defaultBillingDetails(it) }
		if (s.hasCollection) {
			b.billingDetailsCollectionConfiguration(collection(s))
		}
		return b.build()
	}

	private fun billingDetails(s: Options.Sheet): PaymentSheet.BillingDetails? {
		val d = s.defaultBillingDetails ?: return null
		return PaymentSheet.BillingDetails(
			address = if (d.hasAddress) {
				PaymentSheet.Address(
					city = d.city,
					country = d.country,
					line1 = d.line1,
					line2 = d.line2,
					postalCode = d.postalCode,
					state = d.state,
				)
			} else {
				null
			},
			email = d.email,
			name = d.name,
			phone = d.phone,
		)
	}

	private fun collection(s: Options.Sheet): PaymentSheet.BillingDetailsCollectionConfiguration {
		fun mode(v: String) = when (v) {
			"never" -> PaymentSheet.BillingDetailsCollectionConfiguration.CollectionMode.Never
			"always" -> PaymentSheet.BillingDetailsCollectionConfiguration.CollectionMode.Always
			else -> PaymentSheet.BillingDetailsCollectionConfiguration.CollectionMode.Automatic
		}
		return PaymentSheet.BillingDetailsCollectionConfiguration(
			name = mode(s.collectName),
			phone = mode(s.collectPhone),
			email = mode(s.collectEmail),
			address = when (s.collectAddress) {
				"never" -> PaymentSheet.BillingDetailsCollectionConfiguration.AddressCollectionMode.Never
				"full" -> PaymentSheet.BillingDetailsCollectionConfiguration.AddressCollectionMode.Full
				else -> PaymentSheet.BillingDetailsCollectionConfiguration.AddressCollectionMode.Automatic
			},
			attachDefaultsToPaymentMethod = s.attachDefaultsToPaymentMethod,
		)
	}

	/**
	 * Appearance. Android's sheet follows the system theme and Stripe does not let apps force it, so `style: 'light'`
	 * uses the light palette in both modes and `style: 'dark'` the dark one; the result matches iOS.
	 */
	private fun appearance(context: Context, s: Options.Sheet): PaymentSheet.Appearance {
		val a = s.appearance ?: Options.Appearance()
		val light = colors(PaymentSheet.Colors.Builder.light(), a.colors)
		val dark = colors(PaymentSheet.Colors.Builder.dark(), if (a.colorsDark.isEmpty()) a.colors else a.colorsDark)
		val buttonLight = buttonColors(PaymentSheet.PrimaryButtonColors.Builder.light(), a.button)
		val buttonDark = buttonColors(
			PaymentSheet.PrimaryButtonColors.Builder.dark(),
			if (a.buttonDark.isEmpty()) a.button else a.buttonDark,
		)

		val builder = PaymentSheet.Appearance.Builder()
		when (s.style) {
			"light" -> builder.colorsLight(light).colorsDark(light)
			"dark" -> builder.colorsLight(dark).colorsDark(dark)
			else -> builder.colorsLight(light).colorsDark(dark)
		}

		val shapes = PaymentSheet.Shapes.Builder()
		a.cornerRadius?.let { shapes.cornerRadiusDp(it) }
		a.borderWidth?.let { shapes.borderStrokeWidthDp(it) }
		builder.shapes(shapes.build())

		val typography = PaymentSheet.Typography.Builder()
		a.fontScale?.let { typography.sizeScaleFactor(it) }
		fontResource(context, a.fontFamily, "appearance.font.family")?.let { typography.fontResId(it) }
		builder.typography(typography.build())

		val (bLight, bDark) = when (s.style) {
			"light" -> buttonLight to buttonLight
			"dark" -> buttonDark to buttonDark
			else -> buttonLight to buttonDark
		}
		builder.primaryButton(
			PaymentSheet.PrimaryButton(
				colorsLight = bLight,
				colorsDark = bDark,
				shape = PaymentSheet.PrimaryButtonShape(
					cornerRadiusDp = a.buttonCornerRadius,
					borderStrokeWidthDp = a.buttonBorderWidth,
					heightDp = a.buttonHeight,
				),
				typography = PaymentSheet.PrimaryButtonTypography(
					fontResId = fontResource(context, a.buttonFontFamily, "appearance.primaryButton.font.family"),
					fontSizeSp = a.buttonFontSize,
				),
			),
		)
		return builder.build()
	}

	private fun colors(b: PaymentSheet.Colors.Builder, m: Map<String, Int>): PaymentSheet.Colors {
		m["primary"]?.let { b.primary(it) }
		m["background"]?.let { b.surface(it) }
		m["componentBackground"]?.let { b.component(it) }
		m["componentBorder"]?.let { b.componentBorder(it) }
		m["componentDivider"]?.let { b.componentDivider(it) }
		m["text"]?.let { b.onSurface(it) }
		m["textSecondary"]?.let { b.subtitle(it) }
		m["componentText"]?.let { b.onComponent(it) }
		m["placeholderText"]?.let { b.placeholderText(it) }
		m["icon"]?.let { b.appBarIcon(it) }
		m["danger"]?.let { b.error(it) }
		return b.build()
	}

	private fun buttonColors(
		b: PaymentSheet.PrimaryButtonColors.Builder,
		m: Map<String, Int>,
	): PaymentSheet.PrimaryButtonColors {
		m["backgroundColor"]?.let { b.background(it) }
		m["textColor"]?.let { b.onBackground(it) }
		m["borderColor"]?.let { b.border(it) }
		return b.build()
	}

	/** Stripe takes fonts as resources: the app ships them in platform/android/res/font/. */
	private fun fontResource(context: Context, name: String?, option: String): Int? {
		if (name == null) {
			return null
		}
		val id = context.resources.getIdentifier(name, "font", context.packageName)
		if (id == 0) {
			Log.w(PaysheetModule.TAG, "$option: no font resource named '$name' (put it in platform/android/res/font/)")
			return null
		}
		return id
	}
}
