// Ti.Paysheet: drives the example app's sheets with Stripe test cards. Needs the example server running.
// Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
import XCTest

final class ExampleFlows: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "ti.paysheet.example")
        app.launch()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'self-test'")).firstMatch
            .waitForExistence(timeout: 30), "self-test did not finish")
    }

    // MARK: helpers

    func tapButton(_ label: String, timeout: TimeInterval = 20) {
        let b = app.buttons[label].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "no button \(label)\n\(app.debugDescription)")
        b.tap()
    }

    func waitForText(_ fragment: String, timeout: TimeInterval = 40) {
        let t = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
        XCTAssertTrue(t.waitForExistence(timeout: timeout), "no text containing '\(fragment)'\n\(app.debugDescription)")
    }

    /// Taps a field until it has keyboard focus (the sheet may still be animating in).
    func focus(_ field: XCUIElement) {
        for _ in 0..<10 {
            field.tap()
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                return
            }
            usleep(500_000)
        }
        XCTFail("could not focus \(field)")
    }

    func fillCard(_ number: String) {
        let card = app.textFields["Card number"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "no card field\n\(app.debugDescription)")
        focus(card)
        card.typeText(number)
        // Stripe moves the focus on by itself: expiry, then CVC
        app.typeText("1230")
        app.typeText("123")
        let zip = app.textFields["ZIP"].firstMatch
        if zip.waitForExistence(timeout: 3) {
            focus(zip)
            zip.typeText("35004")
        }
    }

    func payButton() -> XCUIElement {
        return app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pay $' OR label == 'Save card' OR label == 'Set up'")).firstMatch
    }

    func submit() {
        // dismiss the keyboard by tapping the sheet's title area, then press the primary button
        let pay = payButton()
        XCTAssertTrue(pay.waitForExistence(timeout: 10), "no primary button\n\(app.debugDescription)")
        if !pay.isHittable, app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
        pay.tap()
    }

    // MARK: flows

    func test1GuestPayment() {
        tapButton("Pay $10.99 (guest)")
        fillCard("4242424242424242")
        submit()
        waitForText("succeeded")
    }

    func test2DeclinedThenCancel() {
        tapButton("Pay $10.99 (guest)")
        fillCard("4000000000000002")
        submit()
        let declined = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'declined'")).firstMatch
        XCTAssertTrue(declined.waitForExistence(timeout: 30), "no decline message\n\(app.debugDescription)")
        app.buttons["Close"].firstMatch.tap()
        waitForText("\"status\":\"canceled\"")
    }

    func test3ThreeDSecure() {
        tapButton("Pay $10.99 (guest)")
        fillCard("4000002500003155")
        submit()
        // Stripe's test challenge: a web page with "Complete" / "Fail"
        let complete = app.buttons.matching(NSPredicate(format: "label ==[c] 'Complete' OR label ==[c] 'COMPLETE' OR label CONTAINS[c] 'Complete authentication'")).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 60), "no 3DS challenge\n\(app.debugDescription)")
        complete.tap()
        waitForText("succeeded", timeout: 60)
    }

    func test4SessionPaymentAndSave() {
        tapButton("Pay $10.99 (Customer Session)")
        // first run for this server's customer: card form; later runs: saved cards, pay with the selected one
        if app.textFields["Card number"].firstMatch.waitForExistence(timeout: 20) {
            fillCard("4242424242424242")
            let save = app.switches.firstMatch
            if save.exists { save.tap() }
            let check = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save payment details'")).firstMatch
            if check.exists { check.tap() }
        }
        submit()
        waitForText("succeeded")
    }

    func test5EphemeralKeyPayment() {
        tapButton("Pay $10.99 (ephemeral key)")
        if app.textFields["Card number"].firstMatch.waitForExistence(timeout: 15) {
            fillCard("4242424242424242")
        }
        submit()
        waitForText("succeeded")
    }

    func test6SetupMode() {
        tapButton("Save a card (setup mode)")
        let add = app.buttons.matching(NSPredicate(format: "identifier == '+ Add' OR label ==[c] 'Add new payment method'")).firstMatch
        if add.waitForExistence(timeout: 15) { add.tap() }
        fillCard("5555555555554444")
        submit()
        waitForText("seti_")
        waitForText("succeeded")
    }

    func test7CustomerSheet() {
        tapButton("Manage saved cards (CustomerSheet)")
        let add = app.buttons.matching(NSPredicate(format: "identifier == '+ Add' OR label ==[c] 'Add new payment method'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30), "no add button\n\(app.debugDescription)")
        add.tap()
        fillCard("4000056655665556")
        let save = app.buttons.matching(NSPredicate(format: "label ==[c] 'Save' OR label ==[c] 'Add'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no save button\n\(app.debugDescription)")
        save.tap()
        // Back on the list with the new card selected. Confirm only appears when the selection changes, so pick
        // another saved card (any that is not selected) and confirm that.
        let other = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Visa ending' OR label BEGINSWITH 'Mastercard ending'"))
        XCTAssertTrue(other.firstMatch.waitForExistence(timeout: 40), "card list did not come back\n\(app.debugDescription)")
        for i in 0..<other.count where !other.element(boundBy: i).isSelected {
            other.element(boundBy: i).tap()
            break
        }
        let confirm = app.buttons.matching(NSPredicate(format: "label ==[c] 'Confirm'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 40), "no confirm\n\(app.debugDescription)")
        confirm.tap()
        waitForText("\"status\":\"selected\"")
    }

    func test8InvalidSecret() {
        tapButton("Invalid client secret")
        waitForText("invalid_request_error")
    }

    func test9Rotation() {
        tapButton("Pay $10.99 (guest)")
        XCTAssertTrue(app.textFields["Card number"].firstMatch.waitForExistence(timeout: 30))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        app.buttons["Close"].firstMatch.tap()
        waitForText("\"status\":\"canceled\"")
    }

    /// 3-D Secure by redirect: Stripe opens the bank page in a browser view and only finishes when the app
    /// receives returnURL (paysheetexample://stripe-redirect) and the module hands it to Stripe.
    func test10RedirectReturnURL() {
        tapButton("Pay $10.99 (guest)")
        fillCard("4000000000003063")
        submit()
        let complete = app.buttons.matching(NSPredicate(format: "label ==[c] 'Complete' OR label CONTAINS[c] 'Complete authentication' OR label CONTAINS[c] 'Authorize'")).firstMatch
        let web = complete.waitForExistence(timeout: 60)
        XCTAssertTrue(web, "no redirect page\n\(app.debugDescription)")
        complete.tap()
        waitForText("url received: paysheetexample://stripe-redirect", timeout: 60)
        waitForText("succeeded", timeout: 60)
    }
}
