/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import UIKit
@_implementationOnly import StripePaymentSheet

/// Turns validated `PaysheetOptions.Sheet` values into Stripe configuration, and Stripe results into module results.
enum PaysheetStripe {

  static func paymentSheetConfiguration(_ s: PaysheetOptions.Sheet) -> PaymentSheet.Configuration {
    var c = PaymentSheet.Configuration()
    c.merchantDisplayName = s.merchantDisplayName
    c.returnURL = s.returnURL
    c.allowsDelayedPaymentMethods = s.allowsDelayedPaymentMethods
    c.style = style(s.style)
    c.appearance = appearance(s)
    c.paymentMethodLayout = s.paymentMethodLayout == "horizontal"
      ? .horizontal : (s.paymentMethodLayout == "vertical" ? .vertical : .automatic)
    if let id = s.customerId {
      if let session = s.customerSessionClientSecret {
        c.customer = PaymentSheet.CustomerConfiguration(id: id, customerSessionClientSecret: session)
      } else if let key = s.ephemeralKeySecret {
        c.customer = PaymentSheet.CustomerConfiguration(id: id, ephemeralKeySecret: key)
      }
    }
    if let billing = billingDetails(s) {
      c.defaultBillingDetails = billing
    }
    if s.hasCollection {
      c.billingDetailsCollectionConfiguration = collection(s)
    }
    if let label = s.primaryButtonLabel {
      c.primaryButtonLabel = label
    }
    if let merchantId = s.applePayMerchantId, let country = s.applePayCountryCode {
      c.applePay = .init(merchantId: merchantId, merchantCountryCode: country)
    }
    return c
  }

  static func customerSheetConfiguration(_ s: PaysheetOptions.Sheet) -> CustomerSheet.Configuration {
    var c = CustomerSheet.Configuration()
    c.merchantDisplayName = s.merchantDisplayName
    c.returnURL = s.returnURL
    c.style = style(s.style)
    c.appearance = appearance(s)
    c.applePayEnabled = s.applePayEnabled
    c.headerTextForSelectionScreen = s.headerTitle
    if let billing = billingDetails(s) {
      c.defaultBillingDetails = billing
    }
    if s.hasCollection {
      c.billingDetailsCollectionConfiguration = collection(s)
    }
    return c
  }

  static func option(_ selection: CustomerSheet.PaymentOptionSelection?) -> (String?, String?) {
    switch selection {
    case .paymentMethod(let paymentMethod, let display):
      return (paymentMethod.stripeId, display.label)
    case .applePay(let display):
      return ("apple_pay", display.label)
    case nil:
      return (nil, nil)
    @unknown default:
      return (nil, nil)
    }
  }

  static func failure(_ error: Error, intentId: String?) -> [String: Any] {
    let ns = error as NSError
    let type = ns.userInfo[STPError.stripeErrorTypeKey] as? String
    let code = (ns.userInfo[STPError.stripeErrorCodeKey] as? String) ?? type
    var fallback = PaysheetResults.sdkError
    if let sheetError = error as? PaymentSheetError {
      switch sheetError {
      case .paymentIntentInTerminalState, .setupIntentInTerminalState:
        fallback = PaysheetResults.intentInTerminalState
      default:
        break
      }
    }
    NSLog("[WARN] [TiPaysheet] sheet failed: %@", String(describing: error))
    return PaysheetResults.failed(intentId: intentId, apiCode: code, fallbackCode: fallback,
                                  message: error.localizedDescription,
                                  declineCode: ns.userInfo[STPError.stripeDeclineCodeKey] as? String, type: type)
  }

  // MARK: - Pieces

  private static func style(_ s: String) -> PaymentSheet.UserInterfaceStyle {
    switch s {
    case "light": return .alwaysLight
    case "dark": return .alwaysDark
    default: return .automatic
    }
  }

  private static func billingDetails(_ s: PaysheetOptions.Sheet) -> PaymentSheet.BillingDetails? {
    guard let d = s.defaultBillingDetails else {
      return nil
    }
    var b = PaymentSheet.BillingDetails()
    b.name = d.name
    b.email = d.email
    b.phone = d.phone
    if d.hasAddress {
      b.address = PaymentSheet.Address(city: d.city, country: d.country, line1: d.line1, line2: d.line2,
                                       postalCode: d.postalCode, state: d.state)
    }
    return b
  }

  private static func collection(_ s: PaysheetOptions.Sheet) -> PaymentSheet.BillingDetailsCollectionConfiguration {
    func mode(_ v: String) -> PaymentSheet.BillingDetailsCollectionConfiguration.CollectionMode {
      switch v {
      case "never": return .never
      case "always": return .always
      default: return .automatic
      }
    }
    var c = PaymentSheet.BillingDetailsCollectionConfiguration()
    c.name = mode(s.collectName)
    c.email = mode(s.collectEmail)
    c.phone = mode(s.collectPhone)
    c.address = s.collectAddress == "never" ? .never : (s.collectAddress == "full" ? .full : .automatic)
    c.attachDefaultsToPaymentMethod = s.attachDefaultsToPaymentMethod
    return c
  }

  private static func uiColor(_ argb: UInt32) -> UIColor {
    return UIColor(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                   blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }

  /// A colour for `key`, light/dark aware, or nil to keep Stripe's default. `style` 'light' / 'dark' pins one
  /// palette, matching Android.
  private static func color(_ key: String, light: [String: UInt32], dark: [String: UInt32], style: String) -> UIColor? {
    let darkPalette = dark.isEmpty ? light : dark
    switch style {
    case "light": return light[key].map(uiColor)
    case "dark": return darkPalette[key].map(uiColor)
    default:
      guard let l = light[key] else {
        return darkPalette[key].map(uiColor)
      }
      let lc = uiColor(l)
      let dc = darkPalette[key].map(uiColor) ?? lc
      return UIColor { $0.userInterfaceStyle == .dark ? dc : lc }
    }
  }

  private static func appearance(_ s: PaysheetOptions.Sheet) -> PaymentSheet.Appearance {
    var a = PaymentSheet.Appearance()
    guard let o = s.appearance else {
      return a
    }
    func c(_ key: String) -> UIColor? { color(key, light: o.colors, dark: o.colorsDark, style: s.style) }
    if let v = c("primary") { a.colors.primary = v }
    if let v = c("background") { a.colors.background = v }
    if let v = c("componentBackground") { a.colors.componentBackground = v }
    if let v = c("componentBorder") { a.colors.componentBorder = v }
    if let v = c("componentDivider") { a.colors.componentDivider = v }
    if let v = c("text") { a.colors.text = v }
    if let v = c("textSecondary") { a.colors.textSecondary = v }
    if let v = c("componentText") { a.colors.componentText = v }
    if let v = c("placeholderText") { a.colors.componentPlaceholderText = v }
    if let v = c("icon") { a.colors.icon = v }
    if let v = c("danger") { a.colors.danger = v }
    if let v = o.cornerRadius { a.cornerRadius = CGFloat(v) }
    if let v = o.borderWidth { a.borderWidth = CGFloat(v) }
    if let v = o.fontScale { a.font.sizeScaleFactor = CGFloat(v) }
    if let family = o.fontFamily {
      if let font = UIFont(name: family, size: UIFont.labelFontSize) {
        a.font.base = font
      } else {
        NSLog("[WARN] [TiPaysheet] appearance.font.family: no font named '%@'", family)
      }
    }

    func b(_ key: String) -> UIColor? { color(key, light: o.button, dark: o.buttonDark, style: s.style) }
    if let v = b("backgroundColor") { a.primaryButton.backgroundColor = v }
    if let v = b("textColor") { a.primaryButton.textColor = v }
    if let v = b("borderColor") { a.primaryButton.borderColor = v }
    if let v = o.buttonCornerRadius { a.primaryButton.cornerRadius = CGFloat(v) }
    if let v = o.buttonBorderWidth { a.primaryButton.borderWidth = CGFloat(v) }
    if let v = o.buttonHeight { a.primaryButton.height = CGFloat(v) }
    if o.buttonFontFamily != nil || o.buttonFontSize != nil {
      let size = CGFloat(o.buttonFontSize ?? 17)
      if let family = o.buttonFontFamily {
        if let font = UIFont(name: family, size: size) {
          a.primaryButton.font = font
        } else {
          NSLog("[WARN] [TiPaysheet] appearance.primaryButton.font.family: no font named '%@'", family)
        }
      } else {
        a.primaryButton.font = UIFont.systemFont(ofSize: size, weight: .semibold)
      }
    }
    return a
  }
}
