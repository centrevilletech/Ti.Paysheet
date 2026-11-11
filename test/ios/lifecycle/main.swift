/**
 * Ti.Paysheet — lifecycle tests for PaysheetPresentations.swift with a fake clock and fake "on screen" checks in
 * place of UIKit and the Stripe sheet.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
import Foundation

final class FakeScheduler: PaysheetScheduler {
  var now: TimeInterval = 0
  var tasks: [(due: TimeInterval, cancelled: Bool, run: () -> Void)] = []
  func schedule(after delay: TimeInterval, _ task: @escaping () -> Void) -> () -> Void {
    let index = tasks.count
    tasks.append((now + delay, false, task))
    return { [weak self] in self?.tasks[index].cancelled = true }
  }
  func advance(_ seconds: TimeInterval) {
    now += seconds
    for i in tasks.indices where !tasks[i].cancelled && tasks[i].due <= now {
      tasks[i].cancelled = true
      tasks[i].run()
    }
  }
}

final class Recorder {
  var results: [[String: Any]] = []
  func sink(_ r: [String: Any]) { results.append(r) }
  func code(_ i: Int) -> String? { (results[i]["error"] as? [String: Any])?["code"] as? String }
}

struct Failure: Error { let what: String }
func check(_ c: Bool, _ what: String) throws { if !c { throw Failure(what: what) } }
let completed = PaysheetResults.status(PaysheetResults.completed, intentId: "pi_1")

var clock = FakeScheduler()
var p = PaysheetPresentations(scheduler: clock)
var answers: [(String?, String?)] = []
func answer(_ s: String?, _ e: String?) { answers.append((s, e)) }

let tests: [(String, () throws -> Void)] = [
  ("busy while the first sheet is on screen, free after it settles", {
    let a = Recorder()
    let id = p.begin(intentId: "pi_1", sink: a.sink, asker: nil, isOnScreen: { true })
    try check(id != nil, "first begins")
    try check(p.begin(intentId: "pi_2", sink: Recorder().sink, asker: nil, isOnScreen: { true }) == nil, "second busy")
    p.deliver(id!, completed)
    try check(a.results.count == 1, "first settled")
    try check(p.begin(intentId: "pi_3", sink: Recorder().sink, asker: nil, isOnScreen: { true }) != nil, "later begins")
  }),
  ("a sheet that left the screen is settled as interrupted instead of answering busy", {
    let a = Recorder()
    var onScreen = true
    let id = p.begin(intentId: "pi_1", sink: a.sink, asker: nil, isOnScreen: { onScreen })!
    onScreen = false // the app closed the window under the sheet; Stripe never calls back
    let b = Recorder()
    try check(p.begin(intentId: "pi_2", sink: b.sink, asker: nil, isOnScreen: { true }) != nil, "not busy")
    try check(a.results.count == 1 && a.code(0) == "interrupted", "first interrupted")
    try check((a.results[0]["intentId"] as? String) == "pi_1", "keeps the intent id")
    p.deliver(id, completed)
    try check(a.results.count == 1, "a late Stripe result for the interrupted sheet is ignored")
    try check(b.results.isEmpty, "and does not settle the new one")
  }),
  ("deliver settles exactly once", {
    let a = Recorder()
    let id = p.begin(intentId: "pi_1", sink: a.sink, asker: nil, isOnScreen: { true })!
    p.deliver(id, completed)
    p.deliver(id, PaysheetResults.status(PaysheetResults.canceled, intentId: "pi_1"))
    try check(a.results.count == 1 && (a.results[0]["status"] as? String) == "completed", "first wins")
  }),
  ("start failure settles unavailable", {
    let a = Recorder()
    let id = p.begin(intentId: nil, sink: a.sink, asker: nil, isOnScreen: { true })!
    p.startFailed(id, "no window")
    try check(a.results.count == 1 && a.code(0) == "unavailable", "unavailable")
    try check(p.begin(intentId: nil, sink: Recorder().sink, asker: nil, isOnScreen: { true }) != nil, "free")
  }),
  ("secret request answered once, late answers ignored", {
    var asked: [PaysheetSecretRequest] = []
    let id = p.begin(intentId: nil, sink: Recorder().sink, asker: { asked.append($0) }, isOnScreen: { true })!
    p.requestSecret(id, answer: answer)
    try check(asked.count == 1, "asked")
    asked[0].resolve("seti_1_secret_x"); asked[0].reject("late"); asked[0].resolve("seti_2_secret_y")
    try check(answers.count == 1 && answers[0].0 == "seti_1_secret_x", "first answer wins")
  }),
  ("secret request times out after 60 s; a late answer is ignored", {
    var asked: [PaysheetSecretRequest] = []
    let id = p.begin(intentId: nil, sink: Recorder().sink, asker: { asked.append($0) }, isOnScreen: { true })!
    p.requestSecret(id, answer: answer)
    clock.advance(PaysheetPresentations.secretTimeout)
    try check(answers.count == 1 && answers[0].0 == nil && (answers[0].1 ?? "").contains("did not answer within 60 seconds"), "timeout")
    asked[0].resolve("seti_late_secret_z")
    try check(answers.count == 1, "late answer ignored")
  }),
  ("rejection and bad values", {
    var asked: [PaysheetSecretRequest] = []
    let id = p.begin(intentId: nil, sink: Recorder().sink, asker: { asked.append($0) }, isOnScreen: { true })!
    p.requestSecret(id, answer: answer); asked[0].reject("server down")
    p.requestSecret(id, answer: answer); asked[1].resolve(42)
    p.requestSecret(id, answer: answer); asked[2].reject(nil)
    try check(answers[0].1 == "server down", "message passed on")
    try check(answers[1].0 == nil, "non-string is an error")
    try check(answers[2].1 == "The app could not create a SetupIntent.", "default message")
  }),
  ("a throwing secret callback answers with an error at once", {
    let id = p.begin(intentId: nil, sink: Recorder().sink, asker: { _ in throw Failure(what: "JS threw") }, isOnScreen: { true })!
    p.requestSecret(id, answer: answer)
    try check(answers.count == 1 && answers[0].0 == nil, "error")
    clock.advance(PaysheetPresentations.secretTimeout)
    try check(answers.count == 1, "not again on timeout")
  }),
  ("a secret request for a presentation that is over asks to reopen", {
    p.requestSecret("unknown", answer: answer)
    try check(answers.count == 1 && (answers[0].1 ?? "").contains("close and reopen the sheet"), "reopen")
  }),
  ("no fetch function, or asked after settling", {
    let id = p.begin(intentId: nil, sink: Recorder().sink, asker: nil, isOnScreen: { true })!
    p.requestSecret(id, answer: answer)
    p.deliver(id, completed)
    p.requestSecret(id, answer: answer)
    try check(answers.count == 2 && answers[0].0 == nil && answers[1].0 == nil, "errors")
  }),
]

var passed = 0, failed = 0
for (name, body) in tests {
  clock = FakeScheduler(); p = PaysheetPresentations(scheduler: clock); answers = []
  do { try body(); passed += 1 } catch { failed += 1; print("FAIL \(name): \(error)") }
}
print("\(failed == 0 ? "PASS" : "FAIL") \(passed)/\(passed + failed) (Swift lifecycle)")
exit(failed == 0 ? 0 : 1)
