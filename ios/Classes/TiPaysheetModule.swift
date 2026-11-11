/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import JavaScriptCore
import TitaniumKit
import UIKit
@_implementationOnly import StripePaymentSheet

@objc(TiPaysheetModule)
class TiPaysheetModule: TiModule {

  /// The one presentation in flight. Main thread only.
  private var active: Presentation?
  private var initialized = false

  private final class Presentation {
    let intentId: String?
    let promise: KrollPromise
    let callback: KrollCallback?
    let fetchSetupIntent: KrollCallback?
    var settled = false
    /// Keeps the sheet alive while it is on screen.
    var sheet: AnyObject?

    init(intentId: String?, promise: KrollPromise, callback: KrollCallback?, fetchSetupIntent: KrollCallback?) {
      self.intentId = intentId
      self.promise = promise
      self.callback = callback
      self.fetchSetupIntent = fetchSetupIntent
    }
  }

  func moduleGUID() -> String {
    return "7b25f50b-42a7-4417-9aa7-4541da46f353"
  }

  override func moduleId() -> String! {
    return "ti.paysheet"
  }

  override func startup() {
    super.startup()
    // Titanium posts this for every URL the app is opened with (application:openURL: and the scene equivalent).
    // Stripe ignores URLs that are not its own, so forwarding all of them is safe.
    NotificationCenter.default.addObserver(self, selector: #selector(didReceiveURL(_:)),
                                           name: NSNotification.Name(rawValue: kTiApplicationLaunchedFromURL),
                                           object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func didReceiveURL(_ notification: Notification) {
    guard let string = notification.userInfo?["url"] as? String, let url = URL(string: string) else {
      return
    }
    let handled = StripeAPI.handleURLCallback(with: url)
    NSLog("[DEBUG] [TiPaysheet] URL %@ %@ by Stripe", string, handled ? "handled" : "not handled")
  }

  // MARK: - JavaScript API

  @objc(initialize:)
  func initializeStripe(arguments: [Any]?) -> NSNumber {
    do {
      let parsed = try PaysheetOptions.parseInitialize(arguments?.first)
      StripeAPI.defaultPublishableKey = parsed.publishableKey
      STPAPIClient.shared.publishableKey = parsed.publishableKey
      STPAPIClient.shared.stripeAccount = parsed.stripeAccountId
      initialized = true
      return NSNumber(value: true)
    } catch let e as PaysheetOptions.Invalid {
      NSLog("[ERROR] [TiPaysheet] initialize: %@", e.message)
    } catch {
      NSLog("[ERROR] [TiPaysheet] initialize: %@", error.localizedDescription)
    }
    return NSNumber(value: false)
  }

  @objc public var isInitialized: NSNumber {
    return NSNumber(value: initialized)
  }

  @objc(presentPaymentSheet:)
  func presentPaymentSheet(arguments: [Any]?) -> JSValue? {
    return present(arguments: arguments, customer: false)
  }

  @objc(presentCustomerSheet:)
  func presentCustomerSheet(arguments: [Any]?) -> JSValue? {
    return present(arguments: arguments, customer: true)
  }

  @objc(handleURL:)
  func handleURL(arguments: [Any]?) -> NSNumber {
    guard let string = arguments?.first as? String, let url = URL(string: string) else {
      return NSNumber(value: false)
    }
    return NSNumber(value: StripeAPI.handleURLCallback(with: url))
  }

  /// Android only (process death); always null on iOS.
  @objc(takeRestoredResult:)
  func takeRestoredResult(arguments: [Any]?) -> Any? {
    return nil
  }

  // MARK: - Presentation

  private func present(arguments: [Any]?, customer: Bool) -> JSValue? {
    guard let context = currentContext() else {
      return nil
    }
    let promise = KrollPromise(in: context)!
    let raw: Any? = arguments?.first
    let callback = (arguments?.count ?? 0) > 1 ? arguments?[1] as? KrollCallback : nil
    let name = customer ? "presentCustomerSheet" : "presentPaymentSheet"

    func settleNow(_ result: [String: Any]) {
      callback?.call([result], thisObject: self)
      promise.resolve([result])
    }

    let sheet: PaysheetOptions.Sheet
    do {
      sheet = customer ? try PaysheetOptions.parseCustomerSheet(raw) : try PaysheetOptions.parsePaymentSheet(raw)
    } catch let e as PaysheetOptions.Invalid {
      NSLog("[ERROR] [TiPaysheet] %@: %@", name, e.message)
      settleNow(PaysheetResults.moduleError(intentId: nil, code: PaysheetResults.invalidArgument, message: e.message))
      return promise.jsValue
    } catch {
      settleNow(PaysheetResults.moduleError(intentId: nil, code: PaysheetResults.invalidArgument,
                                            message: error.localizedDescription))
      return promise.jsValue
    }

    var fetch: KrollCallback?
    if customer {
      fetch = (raw as? [String: Any])?["fetchSetupIntentClientSecret"] as? KrollCallback
      if fetch == nil {
        let message = "fetchSetupIntentClientSecret must be a function"
        NSLog("[ERROR] [TiPaysheet] %@: %@", name, message)
        settleNow(PaysheetResults.moduleError(intentId: nil, code: PaysheetResults.invalidArgument, message: message))
        return promise.jsValue
      }
    }

    let intentId = PaysheetOptions.intentId(fromClientSecret: sheet.intentClientSecret)
    if !initialized {
      settleNow(PaysheetResults.moduleError(intentId: intentId, code: PaysheetResults.notInitialized,
                                            message: "Call initialize({ publishableKey }) before presenting a sheet."))
      return promise.jsValue
    }
    if active != nil {
      settleNow(PaysheetResults.moduleError(intentId: intentId, code: PaysheetResults.busy,
                                            message: "Another payment sheet is already open."))
      return promise.jsValue
    }
    guard let presenter = TiApp.controller()?.topPresentedController(), presenter.view.window != nil else {
      settleNow(PaysheetResults.moduleError(intentId: intentId, code: PaysheetResults.unavailable,
                                            message: "There is no window to present the sheet from."))
      return promise.jsValue
    }

    let presentation = Presentation(intentId: intentId, promise: promise, callback: callback, fetchSetupIntent: fetch)
    active = presentation
    if customer {
      presentCustomerSheet(sheet, from: presenter, presentation)
    } else {
      presentPaymentSheet(sheet, from: presenter, presentation)
    }
    return promise.jsValue
  }

  private func presentPaymentSheet(_ s: PaysheetOptions.Sheet, from presenter: UIViewController,
                                   _ presentation: Presentation) {
    let configuration = PaysheetStripe.paymentSheetConfiguration(s)
    let paymentSheet: PaymentSheet
    if s.mode == "payment" {
      paymentSheet = PaymentSheet(paymentIntentClientSecret: s.intentClientSecret!, configuration: configuration)
    } else {
      paymentSheet = PaymentSheet(setupIntentClientSecret: s.intentClientSecret!, configuration: configuration)
    }
    presentation.sheet = paymentSheet
    paymentSheet.present(from: presenter) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .completed:
        self.deliver(presentation, PaysheetResults.status(PaysheetResults.completed, intentId: presentation.intentId))
      case .canceled:
        self.deliver(presentation, PaysheetResults.status(PaysheetResults.canceled, intentId: presentation.intentId))
      case .failed(let error):
        self.deliver(presentation, PaysheetStripe.failure(error, intentId: presentation.intentId))
      }
    }
  }

  private func presentCustomerSheet(_ s: PaysheetOptions.Sheet, from presenter: UIViewController,
                                    _ presentation: Presentation) {
    let customerId = s.customerId!
    let sessionSecret = s.customerSessionClientSecret!
    let intentConfiguration = CustomerSheet.IntentConfiguration(setupIntentClientSecretProvider: { [weak self] in
      guard let self = self else {
        throw NSError(domain: "ti.paysheet", code: 1, userInfo: [NSLocalizedDescriptionKey: "The module is gone."])
      }
      return try await self.requestSetupIntentSecret(presentation)
    })
    let customerSheet = CustomerSheet(configuration: PaysheetStripe.customerSheetConfiguration(s),
                                      intentConfiguration: intentConfiguration,
                                      customerSessionClientSecretProvider: {
      return CustomerSessionClientSecret(customerId: customerId, clientSecret: sessionSecret)
    })
    presentation.sheet = customerSheet
    customerSheet.present(from: presenter) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .selected(let selection):
        let (id, label) = PaysheetStripe.option(selection)
        self.deliver(presentation, PaysheetResults.customer(PaysheetResults.selected, optionId: id, optionLabel: label))
      case .canceled(let selection):
        let (id, label) = PaysheetStripe.option(selection)
        self.deliver(presentation, PaysheetResults.customer(PaysheetResults.canceled, optionId: id, optionLabel: label))
      case .error(let error):
        self.deliver(presentation, PaysheetStripe.failure(error, intentId: nil))
      }
    }
  }

  /// Settles a presentation exactly once.
  private func deliver(_ presentation: Presentation, _ result: [String: Any]) {
    let run = { [weak self] in
      if presentation.settled {
        return
      }
      presentation.settled = true
      if self?.active === presentation {
        self?.active = nil
      }
      presentation.sheet = nil
      presentation.callback?.call([result], thisObject: self)
      presentation.promise.resolve([result])
    }
    if Thread.isMainThread {
      run()
    } else {
      DispatchQueue.main.async(execute: run)
    }
  }

  /// Asks JavaScript for a SetupIntent client secret (CustomerSheet adding a payment method).
  private func requestSetupIntentSecret(_ presentation: Presentation) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async { [weak self] in
        guard let self = self, let fetch = presentation.fetchSetupIntent, !presentation.settled else {
          continuation.resume(throwing: PaysheetSecretRequestProxy.error(
            "The app is no longer able to create a SetupIntent; close and reopen the sheet."))
          return
        }
        let request = PaysheetSecretRequestProxy.make(context: self.executionContext, continuation: continuation)
        fetch.call([request], thisObject: self)
        request.startTimeout(seconds: 60)
      }
    }
  }
}
