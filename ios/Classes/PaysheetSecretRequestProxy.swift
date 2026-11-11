/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import Foundation
import TitaniumKit

/// Handed to `fetchSetupIntentClientSecret(request)`: the app answers once with `resolve(secret)` or
/// `reject(message)`. Later answers, and answers after the timeout, are ignored (PaysheetSecretRequest).
@objc(PaysheetSecretRequestProxy)
class PaysheetSecretRequestProxy: TiProxy {
  private var request: PaysheetSecretRequest?

  static let gone = error("The payment sheet is no longer available.")

  /// TiProxy's `_init(withPageContext:)` calls `init()` again, so the request is set afterwards.
  static func make(context: TiEvaluator?, request: PaysheetSecretRequest) -> PaysheetSecretRequestProxy {
    let proxy = PaysheetSecretRequestProxy()
    if let context = context {
      proxy._init(withPageContext: context)
    }
    proxy.request = request
    return proxy
  }

  static func error(_ message: String) -> NSError {
    return NSError(domain: "ti.paysheet", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  override func apiName() -> String! {
    return "Ti.Paysheet.SecretRequest"
  }

  @objc(resolve:)
  func resolve(arguments: [Any]?) {
    request?.resolve(arguments?.first)
  }

  @objc(reject:)
  func reject(arguments: [Any]?) {
    request?.reject(arguments?.first)
  }
}
