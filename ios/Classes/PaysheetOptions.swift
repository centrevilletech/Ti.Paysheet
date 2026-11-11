/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import Foundation

/// Validates the JavaScript options and turns them into plain values.
///
/// Foundation only (no UIKit, Stripe or Titanium) so it can be unit-tested with `swiftc` against the same test
/// vectors as the Android implementation (test/vectors.json). It mirrors android/src/ti/paysheet/Options.java:
/// keep the rules and the messages in step.
enum PaysheetOptions {

  struct Invalid: Error {
    let message: String
  }

  static let collectionModes = ["automatic", "never", "always"]
  static let addressModes = ["automatic", "never", "full"]
  static let layouts = ["automatic", "horizontal", "vertical"]
  static let styles = ["automatic", "light", "dark"]
  static let googlePayEnvironments = ["test", "production"]
  static let colorKeys = ["primary", "background", "componentBackground", "componentBorder", "componentDivider",
                          "text", "textSecondary", "componentText", "placeholderText", "icon", "danger"]
  static let buttonColorKeys = ["backgroundColor", "textColor", "borderColor"]

  struct Initialize {
    var publishableKey: String
    var stripeAccountId: String?
  }

  struct Billing {
    var name: String?, email: String?, phone: String?
    var hasAddress = false
    var line1: String?, line2: String?, city: String?, state: String?, postalCode: String?, country: String?
  }

  /// Colours are 0xAARRGGBB.
  struct Appearance {
    var colors: [String: UInt32] = [:]
    var colorsDark: [String: UInt32] = [:]
    var cornerRadius: Double?
    var borderWidth: Double?
    var fontFamily: String?
    var fontScale: Double?
    var button: [String: UInt32] = [:]
    var buttonDark: [String: UInt32] = [:]
    var buttonCornerRadius: Double?, buttonBorderWidth: Double?, buttonHeight: Double?, buttonFontSize: Double?
    var buttonFontFamily: String?
  }

  struct Sheet {
    /// "payment", "setup" or "customer".
    var mode = ""
    var intentClientSecret: String?
    var merchantDisplayName = ""
    var customerId: String?, customerSessionClientSecret: String?, ephemeralKeySecret: String?
    var returnURL: String?
    var allowsDelayedPaymentMethods = false
    var defaultBillingDetails: Billing?
    var hasCollection = false
    var collectName = "automatic", collectEmail = "automatic", collectPhone = "automatic", collectAddress = "automatic"
    var attachDefaultsToPaymentMethod = false
    var primaryButtonLabel: String?
    var paymentMethodLayout = "automatic"
    var style = "automatic"
    var headerTitle: String?
    var appearance: Appearance?
    var googlePayEnvironment: String?, googlePayCountryCode: String?, googlePayCurrencyCode: String?
    var googlePayEnabled = false, applePayEnabled = false
    var applePayMerchantId: String?, applePayCountryCode: String?
  }

  // MARK: - Entry points

  static func parseInitialize(_ raw: Any?) throws -> Initialize {
    let o = try object(raw, "options")
    let key = try requiredString(o, "publishableKey", "publishableKey")
    if !key.hasPrefix("pk_") {
      throw Invalid(message: "publishableKey must be a publishable key (pk_test_… or pk_live_…), never a secret key")
    }
    return Initialize(publishableKey: key, stripeAccountId: try optionalString(o, "stripeAccountId", "stripeAccountId"))
  }

  static func parsePaymentSheet(_ raw: Any?) throws -> Sheet {
    let o = try object(raw, "options")
    var s = Sheet()
    let pi = try optionalString(o, "paymentIntentClientSecret", "paymentIntentClientSecret")
    let si = try optionalString(o, "setupIntentClientSecret", "setupIntentClientSecret")
    if (pi == nil) == (si == nil) {
      throw Invalid(message: "exactly one of paymentIntentClientSecret and setupIntentClientSecret is required")
    }
    s.mode = pi != nil ? "payment" : "setup"
    s.intentClientSecret = pi ?? si
    try parseCommon(o, &s)

    if let customer = value(o, "customer") {
      let c = try object(customer, "customer")
      s.customerId = try requiredString(c, "id", "customer.id")
      s.customerSessionClientSecret = try optionalString(c, "customerSessionClientSecret", "customer.customerSessionClientSecret")
      s.ephemeralKeySecret = try optionalString(c, "ephemeralKeySecret", "customer.ephemeralKeySecret")
      if (s.customerSessionClientSecret == nil) == (s.ephemeralKeySecret == nil) {
        throw Invalid(message: "customer needs exactly one of customerSessionClientSecret and ephemeralKeySecret")
      }
    }

    s.allowsDelayedPaymentMethods = try optionalBool(o, "allowsDelayedPaymentMethods", "allowsDelayedPaymentMethods", false)
    s.primaryButtonLabel = try optionalString(o, "primaryButtonLabel", "primaryButtonLabel")
    s.paymentMethodLayout = try optionalEnum(o, "paymentMethodLayout", "paymentMethodLayout", layouts, "automatic")

    if let applePay = value(o, "applePay") {
      let a = try object(applePay, "applePay")
      s.applePayMerchantId = try requiredString(a, "merchantId", "applePay.merchantId")
      s.applePayCountryCode = try countryCode(try requiredString(a, "merchantCountryCode", "applePay.merchantCountryCode"),
                                              "applePay.merchantCountryCode")
    }
    if let googlePay = value(o, "googlePay") {
      let g = try object(googlePay, "googlePay")
      s.googlePayEnvironment = try optionalEnum(g, "environment", "googlePay.environment", googlePayEnvironments, "test")
      s.googlePayCountryCode = try countryCode(try requiredString(g, "countryCode", "googlePay.countryCode"),
                                               "googlePay.countryCode")
      if let currency = try optionalString(g, "currencyCode", "googlePay.currencyCode") {
        if !matches(currency, "^[A-Za-z]{3}$") {
          throw Invalid(message: "googlePay.currencyCode must be a three-letter ISO 4217 code")
        }
        s.googlePayCurrencyCode = currency.uppercased()
      }
      if s.mode == "setup" && s.googlePayCurrencyCode == nil {
        throw Invalid(message: "googlePay.currencyCode is required in setup mode")
      }
    }
    return s
  }

  static func parseCustomerSheet(_ raw: Any?) throws -> Sheet {
    let o = try object(raw, "options")
    var s = Sheet()
    s.mode = "customer"
    try parseCommon(o, &s)
    guard let customer = value(o, "customer") else {
      throw Invalid(message: "customer is required")
    }
    let c = try object(customer, "customer")
    s.customerId = try requiredString(c, "id", "customer.id")
    if value(c, "ephemeralKeySecret") != nil {
      throw Invalid(message: "presentCustomerSheet needs customer.customerSessionClientSecret; ephemeral keys are not supported")
    }
    s.customerSessionClientSecret = try requiredString(c, "customerSessionClientSecret", "customer.customerSessionClientSecret")
    if value(o, "fetchSetupIntentClientSecret") == nil {
      throw Invalid(message: "fetchSetupIntentClientSecret is required")
    }
    s.headerTitle = try optionalString(o, "headerTitle", "headerTitle")
    s.applePayEnabled = try optionalBool(o, "applePay", "applePay", false)
    s.googlePayEnabled = try optionalBool(o, "googlePay", "googlePay", false)
    return s
  }

  // MARK: - Shared parts

  private static func parseCommon(_ o: [String: Any], _ s: inout Sheet) throws {
    s.merchantDisplayName = try requiredString(o, "merchantDisplayName", "merchantDisplayName")
    s.returnURL = try optionalString(o, "returnURL", "returnURL")
    if let url = s.returnURL, !matches(url, "^[A-Za-z][A-Za-z0-9+.-]*:.*") {
      throw Invalid(message: "returnURL must be an absolute URL with your app's scheme, e.g. myapp://stripe-redirect")
    }
    s.style = try optionalEnum(o, "style", "style", styles, "automatic")

    if let billing = value(o, "defaultBillingDetails") {
      let b = try object(billing, "defaultBillingDetails")
      var d = Billing()
      d.name = try optionalString(b, "name", "defaultBillingDetails.name")
      d.email = try optionalString(b, "email", "defaultBillingDetails.email")
      d.phone = try optionalString(b, "phone", "defaultBillingDetails.phone")
      if let address = value(b, "address") {
        let a = try object(address, "defaultBillingDetails.address")
        d.hasAddress = true
        d.line1 = try optionalString(a, "line1", "defaultBillingDetails.address.line1")
        d.line2 = try optionalString(a, "line2", "defaultBillingDetails.address.line2")
        d.city = try optionalString(a, "city", "defaultBillingDetails.address.city")
        d.state = try optionalString(a, "state", "defaultBillingDetails.address.state")
        d.postalCode = try optionalString(a, "postalCode", "defaultBillingDetails.address.postalCode")
        if let country = try optionalString(a, "country", "defaultBillingDetails.address.country") {
          d.country = try countryCode(country, "defaultBillingDetails.address.country")
        }
      }
      s.defaultBillingDetails = d
    }

    if let collection = value(o, "billingDetailsCollection") {
      let c = try object(collection, "billingDetailsCollection")
      s.hasCollection = true
      s.collectName = try optionalEnum(c, "name", "billingDetailsCollection.name", collectionModes, "automatic")
      s.collectEmail = try optionalEnum(c, "email", "billingDetailsCollection.email", collectionModes, "automatic")
      s.collectPhone = try optionalEnum(c, "phone", "billingDetailsCollection.phone", collectionModes, "automatic")
      s.collectAddress = try optionalEnum(c, "address", "billingDetailsCollection.address", addressModes, "automatic")
      s.attachDefaultsToPaymentMethod = try optionalBool(c, "attachDefaultsToPaymentMethod",
                                                         "billingDetailsCollection.attachDefaultsToPaymentMethod", false)
    }

    if let appearance = value(o, "appearance") {
      s.appearance = try parseAppearance(try object(appearance, "appearance"))
    }
  }

  private static func parseAppearance(_ o: [String: Any]) throws -> Appearance {
    var a = Appearance()
    a.colors = try colors(value(o, "colors"), "appearance.colors", colorKeys)
    a.colorsDark = try colors(value(o, "colorsDark"), "appearance.colorsDark", colorKeys)
    a.cornerRadius = try optionalNumber(o, "cornerRadius", "appearance.cornerRadius")
    a.borderWidth = try optionalNumber(o, "borderWidth", "appearance.borderWidth")
    if let font = value(o, "font") {
      let f = try object(font, "appearance.font")
      a.fontFamily = try optionalString(f, "family", "appearance.font.family")
      a.fontScale = try optionalNumber(f, "scale", "appearance.font.scale")
      if a.fontScale == 0 {
        throw Invalid(message: "appearance.font.scale must be greater than 0")
      }
    }
    if let button = value(o, "primaryButton") {
      let b = try object(button, "appearance.primaryButton")
      var light: [String: Any] = [:]
      for key in buttonColorKeys {
        if let v = value(b, key) {
          light[key] = v
        }
      }
      a.button = try colors(light, "appearance.primaryButton", buttonColorKeys)
      a.buttonDark = try colors(value(b, "dark"), "appearance.primaryButton.dark", buttonColorKeys)
      a.buttonCornerRadius = try optionalNumber(b, "cornerRadius", "appearance.primaryButton.cornerRadius")
      a.buttonBorderWidth = try optionalNumber(b, "borderWidth", "appearance.primaryButton.borderWidth")
      a.buttonHeight = try optionalNumber(b, "height", "appearance.primaryButton.height")
      if let bf = value(b, "font") {
        let f = try object(bf, "appearance.primaryButton.font")
        a.buttonFontFamily = try optionalString(f, "family", "appearance.primaryButton.font.family")
        a.buttonFontSize = try optionalNumber(f, "size", "appearance.primaryButton.font.size")
      }
    }
    return a
  }

  private static func colors(_ raw: Any?, _ path: String, _ allowed: [String]) throws -> [String: UInt32] {
    guard let raw = raw else {
      return [:]
    }
    let m = try object(raw, path)
    var out: [String: UInt32] = [:]
    for key in m.keys.sorted() {
      guard allowed.contains(key) else {
        throw Invalid(message: "\(path).\(key) is not a known colour")
      }
      guard let v = value(m, key) else {
        continue
      }
      guard let s = v as? String else {
        throw Invalid(message: "\(path).\(key) must be a colour string such as '#0A84FF'")
      }
      guard let argb = parseColor(s) else {
        throw Invalid(message: "\(path).\(key): invalid colour '\(s)' (use #RGB, #RRGGBB or #AARRGGBB)")
      }
      out[key] = argb
    }
    return out
  }

  /// Parses "#RGB", "#RRGGBB" or "#AARRGGBB" (Titanium's alpha-first order) to 0xAARRGGBB; nil if invalid.
  static func parseColor(_ s: String) -> UInt32? {
    guard matches(s, "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$") else {
      return nil
    }
    var hex = String(s.dropFirst())
    if hex.count == 3 {
      hex = hex.map { "\($0)\($0)" }.joined()
    }
    if hex.count == 6 {
      hex = "FF" + hex
    }
    return UInt32(hex, radix: 16)
  }

  /// The intent id ("pi_…" / "seti_…") in a client secret, or nil.
  static func intentId(fromClientSecret secret: String?) -> String? {
    guard let secret = secret, let range = secret.range(of: "_secret_"), range.lowerBound > secret.startIndex else {
      return nil
    }
    return String(secret[..<range.lowerBound])
  }

  // MARK: - Value helpers

  /// A value, treating NSNull (JavaScript null) as absent.
  static func value(_ o: [String: Any], _ key: String) -> Any? {
    guard let v = o[key], !(v is NSNull) else {
      return nil
    }
    return v
  }

  private static func object(_ raw: Any?, _ path: String) throws -> [String: Any] {
    guard let o = raw as? [String: Any] else {
      throw Invalid(message: "\(path) must be an object")
    }
    return o
  }

  private static func requiredString(_ o: [String: Any], _ key: String, _ path: String) throws -> String {
    guard let s = try optionalString(o, key, path) else {
      throw Invalid(message: "\(path) is required")
    }
    return s
  }

  private static func optionalString(_ o: [String: Any], _ key: String, _ path: String) throws -> String? {
    guard let v = value(o, key) else {
      return nil
    }
    guard let s = v as? String else {
      throw Invalid(message: "\(path) must be a string")
    }
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw Invalid(message: "\(path) must not be empty")
    }
    return trimmed
  }

  private static func isBoolean(_ v: Any) -> Bool {
    guard let n = v as? NSNumber else {
      return false
    }
    return CFGetTypeID(n) == CFBooleanGetTypeID()
  }

  private static func optionalBool(_ o: [String: Any], _ key: String, _ path: String, _ fallback: Bool) throws -> Bool {
    guard let v = value(o, key) else {
      return fallback
    }
    guard isBoolean(v), let n = v as? NSNumber else {
      throw Invalid(message: "\(path) must be a boolean")
    }
    return n.boolValue
  }

  private static func optionalNumber(_ o: [String: Any], _ key: String, _ path: String) throws -> Double? {
    guard let v = value(o, key) else {
      return nil
    }
    guard !isBoolean(v), let n = v as? NSNumber else {
      throw Invalid(message: "\(path) must be a number")
    }
    let d = n.doubleValue
    if d.isNaN || d.isInfinite || d < 0 {
      throw Invalid(message: "\(path) must be a number of 0 or more")
    }
    return d
  }

  private static func optionalEnum(_ o: [String: Any], _ key: String, _ path: String, _ allowed: [String],
                                   _ fallback: String) throws -> String {
    guard let s = try optionalString(o, key, path) else {
      return fallback
    }
    guard allowed.contains(s) else {
      throw Invalid(message: "\(path) must be one of \(allowed.joined(separator: ", "))")
    }
    return s
  }

  private static func countryCode(_ s: String, _ path: String) throws -> String {
    guard matches(s, "^[A-Za-z]{2}$") else {
      throw Invalid(message: "\(path) must be a two-letter ISO 3166 country code")
    }
    return s.uppercased()
  }

  private static func matches(_ s: String, _ pattern: String) -> Bool {
    return s.range(of: pattern, options: .regularExpression) != nil
  }
}
