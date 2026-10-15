import XCTest

final class TetherUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testPersonalReadingsProfilesAndCancelledBirthTimeEdit() {
    let app = launchLoadedApp()
    let picker = app.segmentedControls["personPicker"]
    requireHittable(picker.buttons["Sam"])
    picker.buttons["Sam"].tap()
    XCTAssertTrue(app.staticTexts["FOR SAM"].waitForExistence(timeout: 8))
    attach(app, "Tether — Sam’s personal reading")
    picker.buttons["Alex"].tap()
    XCTAssertTrue(app.staticTexts["FOR ALEX"].waitForExistence(timeout: 8))

    app.tabBars.buttons["Us"].tap()
    XCTAssertTrue(app.navigationBars["A shared orbit"].waitForExistence(timeout: 5))
    let scroll = app.scrollViews.firstMatch
    let sampleCityA = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sample City A (UTC)")).firstMatch
    revealVertically(sampleCityA, in: scroll)
    XCTAssertTrue(sampleCityA.label.contains("2000-01-01"))
    let sampleCityB = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sample City B (UTC−05:00)")).firstMatch
    revealVertically(sampleCityB, in: scroll)
    XCTAssertTrue(sampleCityB.label.contains("2001-07-01"))
    attach(app, "Tether — Shared orbit and birth profile")

    let settings = app.buttons["Birth times & settings"]
    requireHittable(settings)
    settings.tap()
    XCTAssertTrue(app.navigationBars["Your sky"].waitForExistence(timeout: 5))
    let knownTime = app.switches.matching(identifier: "Birth time known").firstMatch
    revealVertically(knownTime, in: app.scrollViews.firstMatch)
    let original = knownTime.value as? String ?? ""
    XCTAssertFalse(original.isEmpty)
    // A SwiftUI Form toggle may expose its whole row as the switch frame.
    // Tap the actual trailing thumb, not the row's otherwise inert center.
    knownTime.coordinate(withNormalizedOffset: CGVector(dx: knownTime.frame.width > 70 ? 0.91 : 0.5, dy: 0.5)).tap()
    wait(NSPredicate(format: "value != %@", original), on: knownTime,
         message: "The birth-time toggle changes its draft value")
    app.buttons["Cancel"].tap()
    wait(NSPredicate(format: "exists == false"), on: app.navigationBars["Your sky"],
         message: "Cancel dismisses the profile draft")
    settings.tap()
    XCTAssertTrue(app.navigationBars["Your sky"].waitForExistence(timeout: 5))
    revealVertically(knownTime, in: app.scrollViews.firstMatch)
    XCTAssertEqual(knownTime.value as? String, original, "Cancel must preserve the saved birth profile.")
    app.buttons["Cancel"].tap()
  }

  @MainActor
  func testEveryProjectionRotatesAndPlaybackAdvancesTheSharedTimeline() {
    let app = launchLoadedApp()
    app.tabBars.buttons["Explore"].tap()
    let canvas = app.descendants(matching: .any).matching(identifier: "cosmicCanvas").firstMatch
    requireHittable(canvas)
    let selector = projectionSelector(in: app)
    let modes = [
      ("orbit2D", "Zodiac plane"), ("orbit3D", "Orbital space"),
      ("worldlines", "Worldlines"), ("cylinder", "Time cylinder"),
      ("torus", "Time torus"), ("tracks", "Orbital tracks")]
    for (id, title) in modes {
      let button = app.buttons["mode_\(id)"]
      revealHorizontally(button, in: selector)
      let visible = button.frame.intersection(selector.frame)
      button.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: visible.midX - button.frame.minX,
                             dy: visible.midY - button.frame.minY)).tap()
      wait(NSPredicate(format: "label BEGINSWITH %@", title), on: canvas,
           message: "The canvas changes to \(title)")
      let readout = app.staticTexts["cameraReadout"]
      let cameraStatus = readout.exists ? readout : canvas
      let cameraAttribute = readout.exists ? "label" : "value"
      let before = readout.exists ? readout.label : (canvas.value as? String ?? "")
      XCTAssertFalse(before.isEmpty)
      canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.50))
        .press(forDuration: 0.08,
               thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.64, dy: 0.56)))
      wait(NSPredicate(format: "%K != %@", cameraAttribute, before),
           on: cameraStatus, message: "Dragging rotates \(title)")
      XCTAssertFalse(app.staticTexts["Renderer unavailable"].exists)
      XCTAssertTrue(canvas.label.contains("Alex and Sam"))
      if id == "torus" { attach(app, "Tether — Rotated time torus") }
    }
    let play = app.buttons["playTimeline"]
    revealVertically(play, in: app.scrollViews.firstMatch)
    XCTAssertEqual(play.label, "Play")
    let initialEpoch = app.buttons["openTimeline"].label
    play.tap()
    wait(NSPredicate(format: "label == %@", "Pause"), on: play, message: "Playback starts")
    wait(NSPredicate(format: "label != %@", initialEpoch), on: app.buttons["openTimeline"],
         message: "Playback advances the same timeline used by the reading")
    play.tap()
    wait(NSPredicate(format: "label == %@", "Play"), on: play, message: "Playback pauses")
  }

  @MainActor
  func testTimeTravelBirthJumpsAndNowStaySynchronizedAcrossTabs() throws {
    let app = launchLoadedApp()
    app.buttons["openTimeline"].tap()
    let epoch = app.staticTexts["selectedEpoch"]
    XCTAssertTrue(epoch.waitForExistence(timeout: 5))
    let timelineScroll = visibleScroll(in: app)
    let initial = epoch.label
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "d MMM yyyy · HH:mm 'UT'"
    let initialDate = try XCTUnwrap(formatter.date(from: initial))
    let next = app.buttons["+1 day"]
    revealVertically(next, in: timelineScroll)
    next.tap()
    wait(NSPredicate(format: "label == %@", formatter.string(from: initialDate.addingTimeInterval(86400))),
         on: epoch, message: "One day advances by exactly 24 hours in UT")
    for (name, year) in [("Alex", "2000"), ("Sam", "2001")] {
      let arrival = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name)’s arrival")).firstMatch
      revealVertically(arrival, in: timelineScroll)
      arrival.tap()
      wait(NSPredicate(format: "label CONTAINS %@", year), on: epoch,
           message: "\(name)’s arrival changes the timeline")
    }
    let birthEpoch = epoch.label
    attach(app, "Tether — Time travel to Sam’s arrival")
    app.buttons["Done"].tap()
    wait(NSPredicate(format: "label CONTAINS %@", birthEpoch), on: app.buttons["openTimeline"],
         message: "The reading retains the selected birth instant")
    app.tabBars.buttons["Explore"].tap()
    wait(NSPredicate(format: "label CONTAINS %@", birthEpoch), on: app.buttons["openTimeline"],
         message: "The sky uses the same selected instant")
    app.buttons["openTimeline"].tap()
    XCTAssertTrue(epoch.waitForExistence(timeout: 5))
    let now = app.buttons["timelineNow"]
    revealVertically(now, in: visibleScroll(in: app))
    now.tap()
    wait(NSPredicate { _, _ in
      guard let shown = formatter.date(from: epoch.label) else { return false }
      return abs(shown.timeIntervalSinceNow) < 120
    }, on: epoch, message: "Now returns to the current instant within display precision")
    app.buttons["Done"].tap()
  }

  @MainActor
  func testLunarJumpAndSymbolicCosmicScrubberKeepSeparateClocks() {
    let app = launchLoadedApp()
    app.tabBars.buttons["Cycles"].tap()
    let epoch = app.staticTexts["cyclesEpoch"]
    XCTAssertTrue(epoch.waitForExistence(timeout: 5))
    let initial = epoch.label
    let nextMoon = app.buttons["next-newMoon"]
    revealVertically(nextMoon, in: app.scrollViews.firstMatch)
    nextMoon.tap()
    wait(NSPredicate(format: "label != %@", initial), on: epoch,
         message: "The next New Moon jumps the shared astronomical timeline", timeout: 15)
    let astronomicalEpoch = epoch.label
    let cosmic = app.sliders["cosmicScrubber"]
    revealVertically(cosmic, in: app.scrollViews.firstMatch)
    let symbolicYear = app.staticTexts["cosmicYear"]
    let before = symbolicYear.label
    cosmic.adjust(toNormalizedSliderPosition: 0.7)
    wait(NSPredicate(format: "label != %@", before), on: symbolicYear,
         message: "The traditional cycle scrubber traverses symbolic time")
    XCTAssertTrue(app.tabBars.buttons["Cycles"].isSelected, "Scrubbing must not hit the overlapping tab bar.")
    let independent = app.staticTexts["Independent symbolic exploration. The sky and readings keep their selected date."]
    revealVertically(independent, in: app.scrollViews.firstMatch)
    XCTAssertTrue(independent.exists)
    attach(app, "Tether — Independent Hindu cosmic time")
    // SwiftUI removes sufficiently distant text from the accessibility tree.
    // Check the shared moment through a visible reading control instead.
    app.tabBars.buttons["Reading"].tap()
    let sharedEpoch = app.buttons["openTimeline"]
    requireHittable(sharedEpoch)
    XCTAssertTrue(sharedEpoch.label.contains(astronomicalEpoch),
                  "Cosmic exploration must not extrapolate the ephemeris.")
  }

  @MainActor
  private func launchLoadedApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launch()
    let reading = app.tabBars.buttons["Reading"]
    XCTAssertTrue(reading.waitForExistence(timeout: 30))
    wait(NSPredicate(format: "hittable == true"), on: reading,
         message: "The bundled ephemeris finishes loading", timeout: 30)
    reading.tap()
    requireHittable(app.segmentedControls["personPicker"])
    return app
  }

  @MainActor
  private func projectionSelector(in app: XCUIApplication) -> XCUIElement {
    let named = app.scrollViews["projectionSelector"]
    if named.exists { return named }
    return app.scrollViews.allElementsBoundByIndex.first {
      $0.frame.height < 110 && $0.buttons["mode_orbit2D"].exists
    } ?? app.scrollViews.firstMatch
  }

  @MainActor
  private func revealHorizontally(_ target: XCUIElement, in scroll: XCUIElement) {
    for _ in 0..<10 {
      let visible = target.exists ? target.frame.intersection(scroll.frame) : .zero
      if target.isHittable && visible.width >= min(44, target.frame.width) { return }
      let right = target.exists && target.frame.minX < scroll.frame.minX
      scroll.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.3 : 0.7, dy: 0.5))
        .press(forDuration: 0.05,
               thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.6 : 0.4, dy: 0.5)))
    }
    XCTFail("Could not reveal projection \(target.identifier)")
  }

  @MainActor
  private func revealVertically(_ target: XCUIElement, in scroll: XCUIElement) {
    let app = XCUIApplication()
    for _ in 0..<10 {
      let safe = safeViewport(of: scroll, in: app)
      let targetFrame = target.exists ? target.frame : .zero
      if target.exists && target.isHittable && safe.contains(targetFrame) { return }
      let down = target.exists && targetFrame.minY < safe.minY
      // Use fixed coordinates within the currently unobscured viewport. A
      // scroll view may extend behind the tab bar even when it is hittable.
      let x = safe.maxX - 8
      let startY = safe.minY + safe.height * (down ? 0.25 : 0.8)
      let endY = safe.minY + safe.height * (down ? 0.8 : 0.25)
      let origin = app.coordinate(withNormalizedOffset: .zero)
      origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
        .press(forDuration: 0.05,
               thenDragTo: origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY)))
    }
    requireHittable(target)
    XCTAssertTrue(safeViewport(of: scroll, in: app).contains(target.frame),
                  "Control must be fully visible clear of navigation and tab bars: \(target.identifier)")
  }

  @MainActor
  private func visibleScroll(in app: XCUIApplication) -> XCUIElement {
    app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable && $0.frame.height > 200 })
      ?? app.scrollViews.firstMatch
  }

  @MainActor
  private func safeViewport(of scroll: XCUIElement, in app: XCUIApplication) -> CGRect {
    let frame = scroll.frame.intersection(app.frame)
    let navigationBottom = app.navigationBars.allElementsBoundByIndex
      .filter { $0.isHittable }.map { $0.frame.maxY }.max() ?? frame.minY
    let tabTop = app.tabBars.allElementsBoundByIndex
      .filter { $0.isHittable }.map { $0.frame.minY }.min() ?? frame.maxY
    let top = max(frame.minY, navigationBottom) + 10
    let bottom = min(frame.maxY, tabTop) - 12
    return CGRect(x: frame.minX + 4, y: top, width: max(1, frame.width - 8), height: max(1, bottom - top))
  }

  @MainActor
  private func requireHittable(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 8))
    wait(NSPredicate(format: "hittable == true"), on: element, message: "Control is reachable: \(element.identifier)")
  }

  @MainActor
  private func wait(_ predicate: NSPredicate, on element: XCUIElement, message: String, timeout: TimeInterval = 8) {
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                                timeout: timeout), .completed, message)
  }

  @MainActor
  private func attach(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
