/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import JavaScriptCore
import TitaniumKit
import UIKit
@_implementationOnly import StripePaymentSheet

/// The public `presentPaymentSheet` / `presentCustomerSheet` are in assets/ti.paysheet.js (shared with Android);
/// they call the `_present…` methods below, which resolve with an outcome, a runtime condition or an argument-error
/// marker, and never throw.
@objc(TiPaysheetModule)
class TiPaysheetModule: TiModule {

  /// The stripe-ios version this module was compiled against (ios/paysheet.xcodeproj pins it exactly). The app must
  /// link exactly this version: the module's object code depends on Stripe's struct layouts.
  static let builtAgainstStripeVersion = "26.16.1"

  private lazy var presentations = PaysheetPresentations(scheduler: PaysheetMainQueueScheduler())
  private var initialized = false

  /// UIKit state of the presentation in flight, for the "still on screen" check.
  private final class Screen {
    weak var presenter: UIViewController?
    weak var sheetController: UIViewController?
    var sheet: AnyObject? // keeps the Stripe sheet alive while it is up

    var isOnScreen: Bool {
      if let vc = sheetController {
        return vc.presentingViewController != nil || vc.viewIfLoaded?.window != nil
      }
      return presenter?.viewIfLoaded?.window != nil
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
    // Stripe ignores URLs that are not its own. URLs are never logged: Stripe's return URLs carry client secrets.
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
    StripeAPI.handleURLCallback(with: url)
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
      NSLog("[ERROR] [TiPaysheet] initialize failed")
    }
    return NSNumber(value: false)
  }

  @objc public var isInitialized: NSNumber {
    return NSNumber(value: initialized)
  }

  /// The stripe-ios version the app links, and the one the module was built against (for diagnostics).
  @objc public var stripeVersion: String {
    return STPAPIClient.STPSDKVersion
  }

  @objc public var stripeVersionRequired: String {
    return TiPaysheetModule.builtAgainstStripeVersion
  }

  @objc(_presentPaymentSheet:)
  func _presentPaymentSheet(arguments: [Any]?) -> JSValue? {
    return present(arguments: arguments, customer: false)
  }

  @objc(_presentCustomerSheet:)
  func _presentCustomerSheet(arguments: [Any]?) -> JSValue? {
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
    // Without a JavaScript context there is nothing to return a Promise into; assets/ti.paysheet.js turns the
    // missing Promise into a rejected one ('unavailable'). It only happens when called outside JavaScript.
    guard let context = currentContext(), let promise = KrollPromise(in: context) else {
      return nil
    }
    let raw: Any? = arguments?.first
    let name = customer ? "presentCustomerSheet" : "presentPaymentSheet"
    func resolve(_ result: [String: Any]) {
      promise.resolve([result])
    }

    let sheet: PaysheetOptions.Sheet
    do {
      sheet = customer ? try PaysheetOptions.parseCustomerSheet(raw) : try PaysheetOptions.parsePaymentSheet(raw)
    } catch let e as PaysheetOptions.Invalid {
      NSLog("[ERROR] [TiPaysheet] %@: %@", name, e.message)
      resolve(PaysheetResults.argumentError(code: PaysheetResults.invalidArgument, option: e.option, message: e.message))
      return promise.jsValue
    } catch {
      resolve(PaysheetResults.argumentError(code: PaysheetResults.invalidArgument, option: nil, message: "invalid options"))
      return promise.jsValue
    }

    var fetch: KrollCallback?
    if customer {
      fetch = (raw as? [String: Any])?["fetchSetupIntentClientSecret"] as? KrollCallback
      if fetch == nil {
        let message = "fetchSetupIntentClientSecret must be a function"
        NSLog("[ERROR] [TiPaysheet] %@: %@", name, message)
        resolve(PaysheetResults.argumentError(code: PaysheetResults.invalidArgument,
                                              option: "fetchSetupIntentClientSecret", message: message))
        return promise.jsValue
      }
    }

    if !initialized {
      resolve(PaysheetResults.argumentError(code: PaysheetResults.notInitialized, option: nil,
                                            message: "Call initialize({ publishableKey }) before presenting a sheet."))
      return promise.jsValue
    }

    let intentId = PaysheetOptions.intentId(fromClientSecret: sheet.intentClientSecret)
    let linked = STPAPIClient.STPSDKVersion
    if linked != TiPaysheetModule.builtAgainstStripeVersion {
      NSLog("[ERROR] [TiPaysheet] stripe-ios %@ is linked, but this module was built against %@", linked,
            TiPaysheetModule.builtAgainstStripeVersion)
      resolve(PaysheetResults.moduleError(
        intentId: intentId, code: PaysheetResults.unavailable,
        message: "The app links stripe-ios \(linked), but ti.paysheet was built against stripe-ios "
          + "\(TiPaysheetModule.builtAgainstStripeVersion). Resolve exactly that version (see the module's README)."))
      return promise.jsValue
    }

    let screen = Screen()
    let asker: PaysheetPresentations.Asker? = fetch.map { fetch in
      return { [weak self] request in
        guard let self = self else { throw PaysheetSecretRequestProxy.gone }
        let proxy = PaysheetSecretRequestProxy.make(context: self.executionContext, request: request)
        fetch.call([proxy], thisObject: self)
      }
    }
    guard let id = presentations.begin(intentId: intentId, sink: { result in
      screen.sheet = nil
      resolve(result)
    }, asker: asker, isOnScreen: { screen.isOnScreen }) else {
      resolve(PaysheetResults.moduleError(intentId: intentId, code: PaysheetResults.busy,
                                          message: "Another payment sheet is already open."))
      return promise.jsValue
    }

    guard let presenter = TiApp.controller()?.topPresentedController(), presenter.view.window != nil else {
      presentations.startFailed(id, "There is no window to present the sheet from.")
      return promise.jsValue
    }
    screen.presenter = presenter
    if customer {
      presentCustomerSheet(sheet, from: presenter, id: id, screen: screen)
    } else {
      presentPaymentSheet(sheet, from: presenter, id: id, screen: screen)
    }
    // The sheet's own view controller exists once the presentation has started.
    DispatchQueue.main.async {
      if let vc = presenter.presentedViewController {
        screen.sheetController = vc
      }
    }
    return promise.jsValue
  }

  private func presentPaymentSheet(_ s: PaysheetOptions.Sheet, from presenter: UIViewController, id: String,
                                   screen: Screen) {
    let configuration = PaysheetStripe.paymentSheetConfiguration(s)
    let intentId = PaysheetOptions.intentId(fromClientSecret: s.intentClientSecret)
    let paymentSheet = s.mode == "payment"
      ? PaymentSheet(paymentIntentClientSecret: s.intentClientSecret!, configuration: configuration)
      : PaymentSheet(setupIntentClientSecret: s.intentClientSecret!, configuration: configuration)
    screen.sheet = paymentSheet
    paymentSheet.present(from: presenter) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .completed:
        self.presentations.deliver(id, PaysheetResults.status(PaysheetResults.completed, intentId: intentId))
      case .canceled:
        self.presentations.deliver(id, PaysheetResults.status(PaysheetResults.canceled, intentId: intentId))
      case .failed(let error):
        self.presentations.deliver(id, PaysheetStripe.failure(error, intentId: intentId))
      }
    }
  }

  private func presentCustomerSheet(_ s: PaysheetOptions.Sheet, from presenter: UIViewController, id: String,
                                    screen: Screen) {
    let customerId = s.customerId!
    let sessionSecret = s.customerSessionClientSecret!
    let intentConfiguration = CustomerSheet.IntentConfiguration(setupIntentClientSecretProvider: { [weak self] in
      guard let self = self else { throw PaysheetSecretRequestProxy.gone }
      return try await self.requestSetupIntentSecret(id)
    })
    let customerSheet = CustomerSheet(configuration: PaysheetStripe.customerSheetConfiguration(s),
                                      intentConfiguration: intentConfiguration,
                                      customerSessionClientSecretProvider: {
      return CustomerSessionClientSecret(customerId: customerId, clientSecret: sessionSecret)
    })
    screen.sheet = customerSheet
    customerSheet.present(from: presenter) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .selected(let selection):
        let (optionId, label) = PaysheetStripe.option(selection)
        self.presentations.deliver(id, PaysheetResults.customer(PaysheetResults.selected, optionId: optionId, optionLabel: label))
      case .canceled(let selection):
        let (optionId, label) = PaysheetStripe.option(selection)
        self.presentations.deliver(id, PaysheetResults.customer(PaysheetResults.canceled, optionId: optionId, optionLabel: label))
      case .error(let error):
        self.presentations.deliver(id, PaysheetStripe.failure(error, intentId: nil))
      }
    }
  }

  /// Asks JavaScript for a SetupIntent client secret (CustomerSheet adding a payment method).
  private func requestSetupIntentSecret(_ id: String) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async { [weak self] in
        guard let self = self else {
          continuation.resume(throwing: PaysheetSecretRequestProxy.gone)
          return
        }
        self.presentations.requestSecret(id) { secret, error in
          if let secret = secret {
            continuation.resume(returning: secret)
          } else {
            continuation.resume(throwing: PaysheetSecretRequestProxy.error(error ?? "The app could not create a SetupIntent."))
          }
        }
      }
    }
  }
}
