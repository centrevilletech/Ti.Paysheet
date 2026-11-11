/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import Foundation
import TitaniumKit

/// Handed to `fetchSetupIntentClientSecret(request)`: the app answers once with `resolve(secret)` or
/// `reject(message)`. Later answers, and answers after the timeout, are ignored.
@objc(PaysheetSecretRequestProxy)
class PaysheetSecretRequestProxy: TiProxy {
  private var continuation: CheckedContinuation<String, Error>?

  /// TiProxy's `_init(withPageContext:)` calls `init()` again, so the continuation is set afterwards.
  static func make(context: TiEvaluator?, continuation: CheckedContinuation<String, Error>) -> PaysheetSecretRequestProxy {
    let proxy = PaysheetSecretRequestProxy()
    if let context = context {
      proxy._init(withPageContext: context)
    }
    proxy.continuation = continuation
    return proxy
  }

  static func error(_ message: String) -> NSError {
    return NSError(domain: "ti.paysheet", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  override func apiName() -> String! {
    return "Ti.Paysheet.SecretRequest"
  }

  func startTimeout(seconds: Double) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      self?.answer(secret: nil, error: "fetchSetupIntentClientSecret did not answer within 60 seconds")
    }
  }

  @objc(resolve:)
  func resolve(arguments: [Any]?) {
    guard let secret = arguments?.first as? String, !secret.trimmingCharacters(in: .whitespaces).isEmpty else {
      answer(secret: nil, error: "fetchSetupIntentClientSecret resolved without a SetupIntent client secret")
      return
    }
    answer(secret: secret, error: nil)
  }

  @objc(reject:)
  func reject(arguments: [Any]?) {
    let message = arguments?.first as? String
    answer(secret: nil, error: (message?.isEmpty ?? true) ? "The app could not create a SetupIntent." : message)
  }

  private func answer(secret: String?, error: String?) {
    let run = {
      guard let c = self.continuation else { return }
      self.continuation = nil
      if let secret = secret {
        c.resume(returning: secret)
      } else {
        c.resume(throwing: PaysheetSecretRequestProxy.error(error ?? "The app could not create a SetupIntent."))
      }
    }
    if Thread.isMainThread { run() } else { DispatchQueue.main.async(execute: run) }
  }
}
