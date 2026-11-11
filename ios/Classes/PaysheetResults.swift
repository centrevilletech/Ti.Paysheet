/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import Foundation

/// Builds the result objects handed to JavaScript. Foundation only; mirrors android/src/ti/paysheet/Results.java
/// and is unit-tested with test/vectors.json.
enum PaysheetResults {
  static let completed = "completed"
  static let canceled = "canceled"
  static let failed = "failed"
  static let selected = "selected"

  static let invalidArgument = "invalid_argument"
  static let notInitialized = "not_initialized"
  static let busy = "busy"
  static let unavailable = "unavailable"
  static let interrupted = "interrupted"
  static let sdkError = "sdk_error"
  static let intentInTerminalState = "intent_in_terminal_state"

  static func status(_ status: String, intentId: String?) -> [String: Any] {
    var r: [String: Any] = ["status": status]
    if let intentId = intentId {
      r["intentId"] = intentId
    }
    return r
  }

  /// A failed result. `apiCode` is Stripe's API error code (or type) when Stripe reported one; without it the
  /// code is `fallbackCode` (one of this module's codes).
  static func failed(intentId: String?, apiCode: String?, fallbackCode: String?, message: String?,
                     declineCode: String?, type: String?) -> [String: Any] {
    var r = status(failed, intentId: intentId)
    r["error"] = [
      "code": nonEmpty(apiCode) ?? nonEmpty(fallbackCode) ?? sdkError,
      "message": nonEmpty(message) ?? "Something went wrong with the payment sheet.",
      "declineCode": nonEmpty(declineCode) ?? NSNull(),
      "type": nonEmpty(type) ?? NSNull()
    ] as [String: Any]
    return r
  }

  static func moduleError(intentId: String?, code: String, message: String) -> [String: Any] {
    return failed(intentId: intentId, apiCode: nil, fallbackCode: code, message: message, declineCode: nil, type: nil)
  }

  /// An argument error (or no publishable key). Not an outcome: assets/ti.paysheet.js turns it into a rejected
  /// Promise with an Error carrying `code` and `option`.
  static func argumentError(code: String, option: String?, message: String) -> [String: Any] {
    var info: [String: Any] = ["code": code, "message": message]
    if let option = option {
      info["option"] = option
    }
    return ["__argumentError": info]
  }

  /// CustomerSheet result; `optionId` nil when nothing is selected.
  static func customer(_ status: String, optionId: String?, optionLabel: String?) -> [String: Any] {
    var r = self.status(status, intentId: nil)
    if let optionId = optionId {
      r["paymentOption"] = ["id": optionId, "label": optionLabel ?? NSNull()] as [String: Any]
    }
    return r
  }

  private static func nonEmpty(_ s: String?) -> String? {
    guard let s = s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return s
  }
}
