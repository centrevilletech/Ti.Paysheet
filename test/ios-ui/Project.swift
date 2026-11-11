// Ti.Paysheet: XCUITest runner that drives the example app (ti.paysheet.example) on a simulator.
// Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
//
//   tuist generate --no-open && xcodebuild test -scheme PaysheetUITests -destination "id=<simulator>" ...
import ProjectDescription

let project = Project(
    name: "PaysheetUITests",
    targets: [
        // UI test bundles need a host app; the tests drive the example app by bundle id instead.
        .target(name: "Host", destinations: .iOS, product: .app, bundleId: "ti.paysheet.uitests.host",
                deploymentTargets: .iOS("15.0"), infoPlist: .default, sources: ["Host/**"]),
        .target(name: "PaysheetUITests", destinations: .iOS, product: .uiTests, bundleId: "ti.paysheet.uitests",
                deploymentTargets: .iOS("15.0"), infoPlist: .default, sources: ["Tests/**"],
                dependencies: [.target(name: "Host")]),
    ]
)
