/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import Foundation

/// Runs a task later; the returned closure cancels it.
protocol PaysheetScheduler: AnyObject {
  func schedule(after delay: TimeInterval, _ task: @escaping () -> Void) -> () -> Void
}

final class PaysheetMainQueueScheduler: PaysheetScheduler {
  func schedule(after delay: TimeInterval, _ task: @escaping () -> Void) -> () -> Void {
    let item = DispatchWorkItem(block: task)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    return { item.cancel() }
  }
}

/// One request for a SetupIntent client secret, answered exactly once (by the app, the timeout or an error).
final class PaysheetSecretRequest {
  private var answer: ((String?, String?) -> Void)?
  var cancelTimeout: (() -> Void)?

  init(answer: @escaping (String?, String?) -> Void) {
    self.answer = answer
  }

  func resolve(_ secret: Any?) {
    guard let s = secret as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      finish(nil, "fetchSetupIntentClientSecret resolved without a SetupIntent client secret")
      return
    }
    finish(s, nil)
  }

  func reject(_ message: Any?) {
    let text = message as? String
    finish(nil, (text?.isEmpty ?? true) ? "The app could not create a SetupIntent." : text)
  }

  func finish(_ secret: String?, _ error: String?) {
    guard let a = answer else { return }
    answer = nil
    cancelTimeout?()
    cancelTimeout = nil
    a(secret, error)
  }
}

/// The lifecycle of presentations, without UIKit, Titanium or Stripe types so it can be tested with swiftc
/// (test/ios/lifecycle). Mirrors android/src/ti/paysheet/Presentations.java. Main thread only.
final class PaysheetPresentations {
  static let secretTimeout: TimeInterval = 60

  typealias Sink = ([String: Any]) -> Void
  typealias Asker = (PaysheetSecretRequest) throws -> Void

  private final class Active {
    let id: String
    let intentId: String?
    let sink: Sink
    let asker: Asker?
    let isOnScreen: () -> Bool

    init(id: String, intentId: String?, sink: @escaping Sink, asker: Asker?, isOnScreen: @escaping () -> Bool) {
      self.id = id
      self.intentId = intentId
      self.sink = sink
      self.asker = asker
      self.isOnScreen = isOnScreen
    }
  }

  private let scheduler: PaysheetScheduler
  private var active: Active?

  init(scheduler: PaysheetScheduler) {
    self.scheduler = scheduler
  }

  /// Starts a presentation and returns its id, or nil when another sheet is still on screen (busy). A previous
  /// sheet that is no longer on screen (the app dismissed its window under it, and Stripe never called back) is
  /// settled as interrupted first.
  func begin(intentId: String?, sink: @escaping Sink, asker: Asker?, isOnScreen: @escaping () -> Bool) -> String? {
    if let a = active {
      if a.isOnScreen() {
        return nil
      }
      settle(a, PaysheetResults.moduleError(intentId: a.intentId, code: PaysheetResults.interrupted,
                                            message: "The payment sheet was closed by the app before it finished."))
    }
    let id = UUID().uuidString
    active = Active(id: id, intentId: intentId, sink: sink, asker: asker, isOnScreen: isOnScreen)
    return id
  }

  func startFailed(_ id: String, _ message: String) {
    if let a = active, a.id == id {
      settle(a, PaysheetResults.moduleError(intentId: a.intentId, code: PaysheetResults.unavailable, message: message))
    }
  }

  func isLive(_ id: String) -> Bool {
    return active?.id == id
  }

  /// Settles presentation `id` once; anything for a presentation that is already over is ignored.
  func deliver(_ id: String, _ result: [String: Any]) {
    if let a = active, a.id == id {
      settle(a, result)
    }
  }

  /// Asks JavaScript for a SetupIntent client secret; `answer` is called exactly once.
  func requestSecret(_ id: String, answer: @escaping (String?, String?) -> Void) {
    guard let a = active, a.id == id else {
      answer(nil, "The app is no longer able to create a SetupIntent; close and reopen the sheet.")
      return
    }
    guard let asker = a.asker else {
      answer(nil, "fetchSetupIntentClientSecret is not available.")
      return
    }
    let request = PaysheetSecretRequest(answer: answer)
    request.cancelTimeout = scheduler.schedule(after: PaysheetPresentations.secretTimeout) { [weak request] in
      request?.finish(nil, "fetchSetupIntentClientSecret did not answer within 60 seconds")
    }
    do {
      try asker(request)
    } catch {
      request.finish(nil, "fetchSetupIntentClientSecret failed.")
    }
  }

  private func settle(_ a: Active, _ result: [String: Any]) {
    if active === a {
      active = nil
    }
    a.sink(result)
  }
}
