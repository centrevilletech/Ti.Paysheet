/**
 * Ti.Paysheet — runs test/vectors.json against PaysheetOptions.swift and PaysheetResults.swift.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import Foundation

var passed = 0, failed = 0
func fail(_ name: String, _ why: String) { failed += 1; print("FAIL \(name): \(why)") }

func hex(_ c: UInt32) -> String { String(format: "%08X", c) }

func normalize(_ v: Any?) -> Any? {
  guard let v = v, !(v is NSNull) else { return nil }
  return v
}

func same(_ expected: Any?, _ actual: Any?) -> Bool {
  let e = normalize(expected), a = normalize(actual)
  if e == nil || a == nil { return e == nil && a == nil }
  if let en = e as? NSNumber, CFGetTypeID(en) == CFBooleanGetTypeID() {
    return (a as? Bool) == en.boolValue
  }
  if let en = e as? NSNumber, let ad = a as? Double { return abs(en.doubleValue - ad) < 1e-6 }
  if let es = e as? String { return (a as? String) == es }
  if let em = e as? [String: Any], let am = a as? [String: Any] {
    let keys = Set(em.keys).union(am.keys)
    return keys.allSatisfy { same(em[$0], am[$0]) }
  }
  return false
}

func summarize(_ s: PaysheetOptions.Sheet) -> [String: Any?] {
  var m: [String: Any?] = [
    "mode": s.mode, "intentClientSecret": s.intentClientSecret, "merchantDisplayName": s.merchantDisplayName,
    "customerId": s.customerId, "customerSessionClientSecret": s.customerSessionClientSecret,
    "ephemeralKeySecret": s.ephemeralKeySecret, "returnURL": s.returnURL,
    "allowsDelayedPaymentMethods": s.allowsDelayedPaymentMethods, "style": s.style,
    "paymentMethodLayout": s.paymentMethodLayout, "primaryButtonLabel": s.primaryButtonLabel,
    "headerTitle": s.headerTitle, "collectName": s.collectName, "collectEmail": s.collectEmail,
    "collectPhone": s.collectPhone, "collectAddress": s.collectAddress,
    "attachDefaultsToPaymentMethod": s.attachDefaultsToPaymentMethod,
    "googlePayEnvironment": s.googlePayEnvironment, "googlePayCountryCode": s.googlePayCountryCode,
    "googlePayCurrencyCode": s.googlePayCurrencyCode, "googlePayEnabled": s.googlePayEnabled,
    "applePayEnabled": s.applePayEnabled, "applePayMerchantId": s.applePayMerchantId,
    "applePayCountryCode": s.applePayCountryCode,
  ]
  if let b = s.defaultBillingDetails {
    m["billing.name"] = b.name; m["billing.email"] = b.email; m["billing.phone"] = b.phone
    m["billing.line1"] = b.line1; m["billing.postalCode"] = b.postalCode; m["billing.country"] = b.country
    m["billing.hasAddress"] = b.hasAddress
  }
  if let a = s.appearance {
    a.colors.forEach { m["colors.\($0.key)"] = hex($0.value) }
    a.colorsDark.forEach { m["colorsDark.\($0.key)"] = hex($0.value) }
    a.button.forEach { m["button.\($0.key)"] = hex($0.value) }
    a.buttonDark.forEach { m["buttonDark.\($0.key)"] = hex($0.value) }
    m["cornerRadius"] = a.cornerRadius; m["borderWidth"] = a.borderWidth; m["fontFamily"] = a.fontFamily
    m["fontScale"] = a.fontScale; m["buttonCornerRadius"] = a.buttonCornerRadius
    m["buttonHeight"] = a.buttonHeight; m["buttonFontSize"] = a.buttonFontSize
  }
  return m
}

let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let v = try! JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as! [String: Any]

for case let c as [String: Any] in v["options"] as! [Any] {
  let name = c["name"] as! String
  let input = c["input"]
  let expectedError = c["error"] as? String
  do {
    let summary: [String: Any?]
    switch c["parse"] as! String {
    case "initialize":
      let i = try PaysheetOptions.parseInitialize(input)
      summary = ["publishableKey": i.publishableKey, "stripeAccountId": i.stripeAccountId]
    case "customer":
      summary = summarize(try PaysheetOptions.parseCustomerSheet(input))
    default:
      summary = summarize(try PaysheetOptions.parsePaymentSheet(input))
    }
    if let expectedError = expectedError {
      fail(name, "expected error '\(expectedError)', got success")
      continue
    }
    var ok = true
    for (k, e) in c["expect"] as! [String: Any] where !same(e, summary[k] ?? nil) {
      fail(name, "\(k): expected \(e), got \(String(describing: summary[k] ?? nil))")
      ok = false
    }
    if ok { passed += 1 }
  } catch let e as PaysheetOptions.Invalid {
    if e.message == expectedError && (c["option"] == nil || (c["option"] as? String) == e.option) { passed += 1 } else {
      fail(name, "expected \(expectedError.map { "error '\($0)'" } ?? "success"), got error '\(e.message)' on '\(e.option)'")
    }
  } catch {
    fail(name, "unexpected \(error)")
  }
}

for case let c as [String: Any] in v["colors"] as! [Any] {
  let got = PaysheetOptions.parseColor(c["input"] as! String).map(hex)
  if same(c["argb"], got) { passed += 1 } else { fail("colour \(c["input"]!)", "expected \(c["argb"]!), got \(String(describing: got))") }
}

for case let c as [String: Any] in v["intentIds"] as! [Any] {
  let got = PaysheetOptions.intentId(fromClientSecret: c["input"] as? String)
  if same(c["id"], got) { passed += 1 } else { fail("intent id \(c["input"]!)", "expected \(c["id"]!), got \(String(describing: got))") }
}

for case let c as [String: Any] in v["results"] as! [Any] {
  let got = PaysheetResults.failed(intentId: normalize(c["intentId"]) as? String, apiCode: normalize(c["apiCode"]) as? String,
                                   fallbackCode: normalize(c["fallbackCode"]) as? String, message: normalize(c["message"]) as? String,
                                   declineCode: normalize(c["declineCode"]) as? String, type: normalize(c["type"]) as? String)
  if same(c["expect"], got) { passed += 1 } else { fail("result \(c["name"]!)", "expected \(c["expect"]!), got \(got)") }
}

for case let c as [String: Any] in v["argumentErrors"] as! [Any] {
  let got = PaysheetResults.argumentError(code: c["code"] as! String, option: normalize(c["option"]) as? String,
                                          message: c["message"] as! String)
  if same(c["expect"], got) { passed += 1 } else { fail("argument error \(c["code"]!)", "expected \(c["expect"]!), got \(got)") }
}

print("\(failed == 0 ? "PASS" : "FAIL") \(passed)/\(passed + failed) (Swift)")
exit(failed == 0 ? 0 : 1)
