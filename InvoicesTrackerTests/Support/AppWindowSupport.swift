import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The room the tests give the content of the window: the least the app allows (`RootView`), and a large window.
enum AppWindowSize {
    static let minimum = CGSize(width: 1_100, height: 720)
    static let large = CGSize(width: 1_600, height: 1_000)
}

/// Shows the window of the app on `app`, gives it to `body`, and closes it afterwards. The window is made as the
/// `WindowGroup` of the app makes it: titled, closable, miniaturizable and resizable, with a unified toolbar and the
/// content running under the toolbar (`.fullSizeContentView`). `size` is the size asked for its content; the window
/// grows to the least the app allows when that is less. The window shows Výpočet when `body` gets it: a window made
/// like this one has no title of the first screen it shows, only of the ones that follow it, so it starts on Přehled,
/// which no test looks at then.
///
/// The window is never a tab of another window. Where the person prefers tabs, the windows of the tests that run at the
/// same time would become tabs of one window, which share one frame: this window would take the size of another test's
/// window and follow it when that one is resized or closed.
///
/// The window is on the screen at 100, 100, where the pointer of the person who runs the tests can pass over it, or
/// not be. With `ignoringTheRealPointer` the window is closed to that pointer (`TestWindow`): it takes no event of
/// the real mouse, says for itself where its pointer is and makes the areas its views follow the pointer in anew once
/// it is laid out, so that the popover and the hover that a test brings about with events of its own do not depend on
/// where the real pointer is. A test that moves the pointer by hand (`movePointer(to:in:)`) asks for it, and the
/// helper refuses a window without it. A test that clicks or scrolls through the event handling of the app keeps the
/// ordinary window.
@MainActor
func withAppWindow(
    of app: AppModel, size: CGSize, ignoringTheRealPointer: Bool = false, _ body: (NSWindow) async throws -> Void
) async throws {
    app.screen = .overview
    let window = TestWindow(contentViewController: NSHostingController(rootView: RootView(model: app)))
    if ignoringTheRealPointer {
        window.closeToTheRealPointer()
    }
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.tabbingMode = .disallowed
    window.toolbarStyle = .unified
    window.setContentSize(size)
    window.setFrameOrigin(NSPoint(x: 100, y: 100))
    window.orderFront(nil)
    defer { window.close() }
    if ignoringTheRealPointer {
        try await window.makeTheAreasOfThePointerAnew()
    }
    app.screen = .computation
    try await waitUntil { window.title == "Výpočet" }
    try await body(window)
}

/// Lays `window` out a few times over, as the window does between events, with a turn of the run loop between the
/// passes for what SwiftUI changes after a layout. A layout that never settles stops the app with an AppKit exception
/// here.
@MainActor
func layOut(_ window: NSWindow) async throws {
    for _ in 0..<3 {
        window.contentView?.needsLayout = true
        window.layoutIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
}

/// Lays `window` out, waits until `problems` finds nothing wrong with it (the split views animate the detail in and
/// out, and follow a resize, over a few frames), lays it out again and records an issue for each problem that is left,
/// so that a window that only passes through the right layout fails as well.
@MainActor
func expectSettled(
    _ window: NSWindow, sourceLocation: SourceLocation = #_sourceLocation,
    _ problems: @MainActor () -> [String]
) async throws {
    try await layOut(window)
    try await waitUntil(timeout: .seconds(5), sourceLocation: sourceLocation) { problems().isEmpty }
    try await layOut(window)
    #expect(problems() == [], sourceLocation: sourceLocation)
}

/// The split views and scroll views of `window` that are laid out beyond its edges, each as the name of its type and
/// its frame in the window, leaving out those that a scroll view scrolls. These are the views the screens are laid out
/// in, so a screen that takes more room than the window gives it sticks out in them. (The other views are SwiftUI's
/// own, such as the invisible stand-ins of buttons in the loop of the Tab key, which follow a resize a moment later.)
@MainActor
func viewsOutside(_ window: NSWindow) -> [String] {
    guard let content = window.contentView else { return [] }
    var outside: [String] = []
    collectViews(outside: content.bounds.insetBy(dx: -0.5, dy: -0.5), of: content, from: content, into: &outside)
    return outside
}

@MainActor
private func collectViews(outside room: CGRect, of content: NSView, from view: NSView, into outside: inout [String]) {
    guard !view.isHidden else { return }
    if view is NSSplitView || view is NSScrollView {
        let frame = view.convert(view.bounds, to: content)
        if !room.contains(frame) {
            outside.append("\(type(of: view)) \(frame.integral)")
        }
    }
    // What a scroll view holds is meant to run beyond it.
    guard !(view is NSClipView) else { return }
    for subview in view.subviews {
        collectViews(outside: room, of: content, from: subview, into: &outside)
    }
}

/// The frame of `view` in the coordinates of its window, whose origin is at the bottom left.
@MainActor
func frameInWindow(_ view: NSView) -> CGRect {
    view.convert(view.bounds, to: nil)
}

/// The date pickers under `view`, and `view` itself where it is one, in the order of the view tree.
@MainActor
func datePickers(in view: NSView) -> [NSDatePicker] {
    if let picker = view as? NSDatePicker {
        return [picker]
    }
    return view.subviews.flatMap { datePickers(in: $0) }
}

/// Runs `body` alone among the tests that type into a window: SwiftUI's text fields share one field editor across
/// the windows of the app. So a test that types into its window takes the editor, and with it the focus, from a field
/// that another test is typing into at the same time. Every test that types into a window, or tells whether a field
/// keeps the focus, does so in here, and so does every hosted view (`withHostedView`), whose field can take the focus
/// by itself; the others wait for their turn. A test that has the turn and asks for it again goes on with it, and the
/// turn passes on when `body` ends, also when it throws.
@MainActor
func whileTypingAlone<T>(_ body: () async throws -> T) async throws -> T {
    if TypingTurn.isHeldHere {
        return try await body()
    }
    while TypingTurn.isTaken {
        await withCheckedContinuation { continuation in
            TypingTurn.waiting.append(continuation)
        }
    }
    TypingTurn.isTaken = true
    defer {
        TypingTurn.isTaken = false
        if !TypingTurn.waiting.isEmpty {
            TypingTurn.waiting.removeFirst().resume()
        }
    }
    return try await TypingTurn.$isHeldHere.withValue(true) {
        try await body()
    }
}

/// Whose turn it is to type into a window (`whileTypingAlone(_:)`).
@MainActor
private enum TypingTurn {
    static var isTaken = false
    static var waiting: [CheckedContinuation<Void, Never>] = []

    /// Whether the task that asks has the turn, which the tasks it starts share.
    @TaskLocal static var isHeldHere = false
}

/// Runs `body` while the app makes the accessibility elements of its views, which SwiftUI makes only once an assistive
/// app such as VoiceOver asks for them: the application is asked for the enhanced user interface as VoiceOver asks it.
/// The tests that run at the same time share the application, so the first of them to come in asks for it, and the
/// last of them to leave gives the application back what it had before the first came in. `frameOfCard(labelled:in:)`
/// and the other lookups by what VoiceOver reads need the elements.
@MainActor
func withAccessibilityElements(_ body: () async throws -> Void) async throws {
    if AccessibilityElements.users == 0 {
        AccessibilityElements.hadThemBefore = hasEnhancedUserInterface()
        setEnhancedUserInterface(true)
    }
    AccessibilityElements.users += 1
    defer {
        AccessibilityElements.users -= 1
        if AccessibilityElements.users == 0 {
            setEnhancedUserInterface(AccessibilityElements.hadThemBefore)
        }
    }
    try await body()
}

/// How many tests are in `withAccessibilityElements(_:)`, and whether the application had the enhanced user interface
/// before the first of them came in.
@MainActor
private enum AccessibilityElements {
    static var users = 0
    static var hadThemBefore = false
}

/// Sets the attribute an assistive app sets on the application to have its views make their accessibility elements,
/// through the method an assistive app's attributes reach the application by. AppKit has deprecated that method for
/// apps, so it is called by its name.
@MainActor
private func setEnhancedUserInterface(_ on: Bool) {
    let setAttribute = NSSelectorFromString("accessibilitySetValue:forAttribute:")
    NSApp.perform(setAttribute, with: NSNumber(value: on), with: "AXEnhancedUserInterface")
}

/// Whether the application has the enhanced user interface, read through the method an assistive app reads the
/// attributes of the application by, called by its name as the setter is (`setEnhancedUserInterface(_:)`).
@MainActor
func hasEnhancedUserInterface() -> Bool {
    let attributeValue = NSSelectorFromString("accessibilityAttributeValue:")
    let value = NSApp.perform(attributeValue, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
    return (value as? NSNumber)?.boolValue ?? false
}

/// The frame of the card that VoiceOver reads under `label` in `window`, in the coordinates of the screen, whose origin
/// is at the bottom left: the first element with that label that holds others (`accessibilityElement(children:
/// .contain)`), so that a line or a heading with the same words is not taken for it. Nil when `window` has no such
/// card, and while its views make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func frameOfCard(labelled label: String, in window: NSWindow) -> CGRect? {
    guard let content = window.contentView else { return nil }
    return frameOfElement(role: .group, labelled: label, among: content.accessibilityChildren() ?? [])
}

/// The frame of the card whose heading reads `title` in `window`, in the coordinates of the screen, whose origin is at
/// the bottom left: the first element that holds others (`accessibilityElement(children: .contain)`) with an element
/// labelled `title` among them. It is for a card that VoiceOver reads under no label of its own, such as the cards of
/// the breakdown of Výpočet, which `frameOfCard(labelled:in:)` cannot find. Nil when `window` has no such card, and
/// while its views make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func frameOfCard(headed title: String, in window: NSWindow) -> CGRect? {
    guard let content = window.contentView else { return nil }
    let card = firstElement(among: content.accessibilityChildren() ?? []) { element in
        element.accessibilityRole?() == .group
            && (element.accessibilityChildren?() ?? []).contains { child in
                (child as AnyObject).accessibilityLabel?() == title
            }
    }
    return card?.accessibilityFrame?()
}

/// The frame of the first group of `window` that holds a text which VoiceOver reads as `text`, in the coordinates of
/// the screen, whose origin is at the bottom left. A note with actions, such as the green banner with its Zavřít, is a
/// group (`accessibilityElement(children: .contain)`) that reads no label of its own, and its text is a value, not a
/// label, so `frameOfCard(labelled:in:)` and `frameOfCard(headed:in:)` cannot find it. Nil when `window` has no such
/// group, and while its views make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func frameOfGroup(holdingText text: String, in window: NSWindow) -> CGRect? {
    let group = firstElement(among: window.accessibilityChildren() ?? []) { element in
        guard element.accessibilityRole?() == .group else { return false }
        return (element.accessibilityChildren?() ?? []).contains { child in
            // The value is asked for as a function of its type, because the protocols of accessibility declare
            // `accessibilityValue()` with more than one type.
            let value: (() -> Any?)? = (child as AnyObject).accessibilityValue
            return (value?() ?? nil) as? String == text
        }
    }
    return group?.accessibilityFrame?()
}

/// The frame of the first text of `window` that VoiceOver reads as a phrase starting with `phrase`, in the coordinates
/// of the screen, whose origin is at the bottom left. A note or a tile that is read as one phrase (it combines its
/// parts) is a text with no label, whose value is the phrase, so `frameOfCard(labelled:in:)` cannot find it. Nil when
/// `window` has no such text, and while its views make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func frameOfText(startingWith phrase: String, in window: NSWindow) -> CGRect? {
    guard let content = window.contentView else { return nil }
    let element = firstText(among: content.accessibilityChildren() ?? []) { $0.hasPrefix(phrase) }
    return element?.accessibilityFrame?()
}

/// The button of `window` that VoiceOver reads under `label`, on the page or in the toolbar: the element VoiceOver
/// presses (`accessibilityPerformPress()`). Nil when `window` has no such button, and while its views make no
/// accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func accessibilityButton(labelled label: String, in window: NSWindow) -> AnyObject? {
    firstElement(among: window.accessibilityChildren() ?? []) { element in
        element.accessibilityRole?() == .button && element.accessibilityLabel?() == label
    }
}

/// The element of `window` that VoiceOver reads under `label`, whatever its role: a card that scrolls is read as a
/// scroll area, not as a group, so `frameOfCard(labelled:in:)` cannot find it. Nil when `window` has no such element,
/// and while its views make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func accessibilityElement(labelled label: String, in window: NSWindow) -> AnyObject? {
    firstElement(among: window.accessibilityChildren() ?? []) { element in
        element.accessibilityLabel?() == label
    }
}

/// The names VoiceOver reads for the containers of `window`, however deep they are: the label of every element that is
/// not a control, a text, a heading or a link, such as a card, a section of a detail, a group of chips or the picture
/// of a bar.
/// Empty while the views of `window` make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func containerLabels(in window: NSWindow) -> Set<String> {
    var labels: Set<String> = []
    collectContainerLabels(among: window.accessibilityChildren() ?? [], into: &labels)
    return labels
}

/// Adds the labels of the containers among `elements` and of their children to `labels`.
@MainActor
private func collectContainerLabels(among elements: [Any], into labels: inout Set<String>) {
    let controls: Set<String> = [
        "AXButton", "AXCheckBox", "AXComboBox", "AXDateTimeArea", "AXHeading", "AXIncrementor", "AXLink",
        "AXMenuButton", "AXPopUpButton", "AXRadioButton", "AXSlider", "AXStaticText", "AXTextArea", "AXTextField",
    ]
    for item in elements {
        let element = item as AnyObject
        let role = element.accessibilityRole?()?.rawValue ?? ""
        let label: String? = element.accessibilityLabel?() ?? nil
        if let label, !label.isEmpty, !controls.contains(role) {
            labels.insert(label)
        }
        collectContainerLabels(among: element.accessibilityChildren?() ?? [], into: &labels)
    }
}

/// Expects `names` among the containers of `window` (`containerLabels(in:)`), giving the views up to ten seconds to
/// show them, with a look every 50 milliseconds. The time is counted as `waitUntil` counts it
/// (`holdsWithin(_:every:_:)`). The missing names are in the failure, so that a table of names says which one a
/// screen lacks.
@MainActor
func expectContainers(
    _ names: [String], in window: NSWindow, _ screen: String, sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    var missing = Set(names)
    _ = try await holdsWithin(.seconds(10), every: .milliseconds(50)) {
        missing = Set(names).subtracting(containerLabels(in: window))
        return missing.isEmpty
    }
    let named = missing.sorted().map { "„\($0)“" }.joined(separator: ", ")
    #expect(missing.isEmpty, "\(screen) has no container named \(named)", sourceLocation: sourceLocation)
}

/// The element of `window` that VoiceOver reads under `label` with `role`, such as the heading of a sheet whose title
/// is also the name of the sheet: `accessibilityElement(labelled:in:)` finds the first element under that label, which
/// is the sheet. Nil when `window` has no such element, and while its views make no accessibility elements
/// (`withAccessibilityElements(_:)`).
@MainActor
func accessibilityElement(role: NSAccessibility.Role, labelled label: String, in window: NSWindow) -> AnyObject? {
    firstElement(among: window.accessibilityChildren() ?? []) { element in
        element.accessibilityRole?() == role && element.accessibilityLabel?() == label
    }
}

/// The element under `container` that VoiceOver reads under `label` with `role`, such as a control of a card that was
/// found by its label (`accessibilityElement(labelled:in:)`). It is for a control that another one of the page reads
/// like, such as the Zkontrolovat teď of two cards, or a switch that reads like the text beside it, so the control is
/// found in its own card and by its role. Nil when `container` holds no such element, and while its views make no
/// accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func accessibilityElement(
    labelled label: String, role: NSAccessibility.Role, under container: AnyObject
) -> AnyObject? {
    firstElement(among: container.accessibilityChildren?() ?? []) { element in
        element.accessibilityRole?() == role && element.accessibilityLabel?() == label
    }
}

/// The first element of `window` whose label VoiceOver reads starts with `prefix`, whatever its role: the picture of
/// the levy bar, whose label starts with what the bar shows and goes on with its three parts. Nil when `window` has no
/// such element, and while its views make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func accessibilityElement(labelStartingWith prefix: String, in window: NSWindow) -> AnyObject? {
    firstElement(among: window.accessibilityChildren() ?? []) { element in
        // The label is asked for as an optional of an optional, as the elements of SwiftUI answer by name.
        let label: String? = element.accessibilityLabel?() ?? nil
        return label?.hasPrefix(prefix) == true
    }
}

/// Moves the pointer over `point` in `window`, given in the coordinates of the window (the origin at its bottom left),
/// as a mouse does for the views of SwiftUI that follow it (`onHover`): SwiftUI hears of the pointer on its hosting
/// view, the one that has the tracking area, as the pointer coming in and moving. The window does not pass a synthetic
/// event on to it (`NSWindow.sendEvent(_:)` changes nothing), so the events are handed to the view itself. A point
/// outside what follows the pointer, such as the corner of the window, takes the pointer away again. The real cursor
/// does not move, and no event is posted to the system.
///
/// The window must be closed to the real pointer (`withAppWindow(of:size:ignoringTheRealPointer:_:)`), and its pointer
/// is put at `point` as the events arrive. SwiftUI follows the pointer only while the window says the pointer is
/// inside it, and in any other window that is the real pointer of the person who runs the tests: the test would pass
/// or fail by where that pointer is, and the pointer passing over the window would move what the test has opened.
/// The helper refuses such a window.
@MainActor
func movePointer(to point: CGPoint, in window: NSWindow) throws {
    let testWindow = try #require(window as? TestWindow, "The window is not a window of the test helpers")
    try #require(
        testWindow.isClosedToTheRealPointer,
        "The window is open to the real pointer: open it with ignoringTheRealPointer: true")
    testWindow.putPointer(at: point)
    let view = try #require(hostingViewTrackingThePointer(in: window.contentView), "No view follows the pointer")
    let entered = try #require(
        NSEvent.enterExitEvent(
            with: .mouseEntered, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    let moved = try #require(
        NSEvent.mouseEvent(
            with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
    view.mouseEntered(with: entered)
    view.mouseMoved(with: moved)
}

/// The hosting view of SwiftUI under `view` that has a tracking area, which is where SwiftUI follows the pointer.
@MainActor
private func hostingViewTrackingThePointer(in view: NSView?) -> NSView? {
    guard let view else { return nil }
    if !view.trackingAreas.isEmpty, String(describing: type(of: view)).contains("NSHostingView") {
        return view
    }
    for subview in view.subviews {
        if let found = hostingViewTrackingThePointer(in: subview) {
            return found
        }
    }
    return nil
}

/// The colour of the picture of `window`, as its bytes, at the middle of the part of the social insurance in a levy bar
/// that stands at `bar` (its frame in the window, the origin at the bottom left) and shares its width as `weights` say,
/// one for each authority in the order of `Authority.allCases`. The part fades while the popover of another part is
/// open, so its colour changes when the pointer comes over the part of the tax or over its item in the legend, and
/// comes back when the pointer is taken away: a test that moves the pointer waits for the one and the other before it
/// checks anything else, and so cannot pass when the pointer moved nothing.
@MainActor
func colourOfTheSocialPartOfTheLevyBar(weights: [Int64], bar: CGRect, in window: NSWindow) throws -> [Int] {
    let content = try #require(window.contentView)
    let widths = LevyBarLayout.partWidths(weights: weights, width: bar.width)
    let centres = LevyBarLayout.partCentres(widths: widths)
    let social = try #require(Authority.allCases.firstIndex(of: .social))
    let point = CGPoint(x: bar.minX + centres[social], y: content.bounds.height - bar.midY)
    return try WindowPicture(of: window).bytes(at: point)
}

/// The element of `window` that carries the accessibility identifier `identifier`: a group that a test measures or
/// looks into (`accessibilityChildren()`) and that VoiceOver reads nothing for, as it has no label. Nil when `window`
/// has no such element, and while its views make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func accessibilityElement(identifiedBy identifier: String, in window: NSWindow) -> AnyObject? {
    firstElement(among: window.accessibilityChildren() ?? []) { element in
        element.accessibilityIdentifier?() == identifier
    }
}

/// The help VoiceOver reads for `element`, such as the tooltip of a button of the toolbar, or nil for none.
@MainActor
func accessibilityHelp(of element: AnyObject) -> String? {
    let help: (() -> String?)? = element.accessibilityHelp
    return help?() ?? nil
}

/// What is wrong with the button of `window` that VoiceOver reads under `label`, in words, if it is not disabled and
/// reads `help`: there is no such button, it can be pressed, or it reads other help. Empty when it is disabled and
/// reads `help`, such as "K datu" on a screen that does not depend on it. A button of the toolbar follows a change of
/// the screen a moment later, so a test waits for this to be empty (`expectSettled(_:_:)`). Needs the accessibility
/// elements (`withAccessibilityElements(_:)`).
@MainActor
func disabledButtonProblems(labelled label: String, reading help: String, in window: NSWindow) -> [String] {
    guard let button = accessibilityButton(labelled: label, in: window) else {
        return ["No button '\(label)'"]
    }
    var found: [String] = []
    if button.isAccessibilityEnabled?() != false {
        found.append("'\(label)' is not disabled")
    }
    let read = accessibilityHelp(of: button)
    if read != help {
        found.append("'\(label)' reads \(String(describing: read)), not '\(help)'")
    }
    return found
}

/// The current toolbar keeps its actions enabled and offers no reporting-date or return-to-today button.
@MainActor
func mainToolbarProblems(in window: NSWindow) -> [String] {
    var problems: [String] = []
    if yearMenu(in: window)?.isAccessibilityEnabled?() != true {
        problems.append("The year menu is unavailable")
    }
    if accessibilityButton(labelled: "Nová faktura", in: window)?.isAccessibilityEnabled?() != true {
        problems.append("New invoice is unavailable")
    }
    if accessibilityButton(labelled: "Dnes", in: window) != nil
        || accessibilityReadings(in: window).contains(where: { $0.hasPrefix("K datu ") })
    {
        problems.append("A reporting-date control is present")
    }
    return problems
}

/// The year menu of the toolbar of `window`: the menu button in its toolbar, which VoiceOver reads under no label. Nil
/// when the window has no such button, and while its views make no accessibility elements
/// (`withAccessibilityElements(_:)`).
@MainActor
func yearMenu(in window: NSWindow) -> AnyObject? {
    let toolbar = firstElement(among: window.accessibilityChildren() ?? []) { $0.accessibilityRole?() == .toolbar }
    return toolbar.flatMap { toolbar in
        firstElement(among: toolbar.accessibilityChildren?() ?? []) { $0.accessibilityRole?() == .menuButton }
    }
}

/// The text field of `window` that VoiceOver reads under `label`: the field whose frame is that of the text field
/// element with the label. Nil when `window` has no such field, and while its views make no accessibility elements
/// (`withAccessibilityElements(_:)`).
@MainActor
func textField(labelled label: String, in window: NSWindow) -> NSTextField? {
    guard let content = window.contentView,
        let frame = frameOfElement(role: .textField, labelled: label, among: content.accessibilityChildren() ?? [])
    else {
        return nil
    }
    return editableTextFields(in: content).first { field in
        let onScreen = window.convertToScreen(frameInWindow(field))
        return (onScreen.minX - frame.minX).magnitude < 0.5 && (onScreen.minY - frame.minY).magnitude < 0.5
            && (onScreen.width - frame.width).magnitude < 0.5
    }
}

/// Everything VoiceOver can read in `window`, on the page, in the sidebar and in the toolbar: the label and the value
/// of every element, in the order of the tree. Empty while its views make no accessibility elements
/// (`withAccessibilityElements(_:)`).
@MainActor
func accessibilityReadings(in window: NSWindow) -> [String] {
    var readings: [String] = []
    collectReadings(among: window.accessibilityChildren() ?? [], into: &readings)
    return readings
}

/// What VoiceOver can read in `element`, such as a card found by its label: its own label and value, and those of
/// every element in it, in the order of the tree.
@MainActor
func accessibilityReadings(under element: AnyObject) -> [String] {
    var readings: [String] = []
    collectReadings(among: [element], into: &readings)
    return readings
}

/// The label and the value of each of `elements` and of their children, in the order of the tree.
@MainActor
private func collectReadings(among elements: [Any], into readings: inout [String]) {
    for item in elements {
        let element = item as AnyObject
        // The value is asked for as a function of its type, because the protocols of accessibility declare
        // `accessibilityValue()` with more than one type.
        let value: (() -> Any?)? = element.accessibilityValue
        let words = [element.accessibilityLabel?() ?? nil, (value?() ?? nil) as? String]
        readings.append(contentsOf: words.compactMap { $0 }.filter { !$0.isEmpty })
        collectReadings(among: element.accessibilityChildren?() ?? [], into: &readings)
    }
}

/// Whether `window` shows a line of text that reads `text`, such as the message under a field. False while its views
/// make no accessibility elements (`withAccessibilityElements(_:)`).
@MainActor
func showsText(_ text: String, in window: NSWindow) -> Bool {
    guard let content = window.contentView else { return false }
    return firstText(among: content.accessibilityChildren() ?? []) { $0 == text } != nil
}

/// The text fields under `view` that can be typed in.
@MainActor
func editableTextFields(in view: NSView) -> [NSTextField] {
    var found: [NSTextField] = []
    if let field = view as? NSTextField, field.isEditable {
        found.append(field)
    }
    for subview in view.subviews {
        found.append(contentsOf: editableTextFields(in: subview))
    }
    return found
}

/// The frame of the first element among `elements` and their children with `role` and `label`, in the coordinates of
/// the screen.
@MainActor
private func frameOfElement(
    role: NSAccessibility.Role, labelled label: String, among elements: [Any]
) -> CGRect? {
    let element = firstElement(among: elements) { element in
        element.accessibilityRole?() == role && element.accessibilityLabel?() == label
    }
    return element?.accessibilityFrame?()
}

/// The first text element among `elements` and their children, in the order of the tree, whose value, the words
/// VoiceOver reads, `matches`.
@MainActor
private func firstText(among elements: [Any], where matches: (String) -> Bool) -> AnyObject? {
    firstElement(among: elements) { element in
        // The value is asked for as a function of its type, because the protocols of accessibility declare
        // `accessibilityValue()` with more than one type.
        let value: (() -> Any?)? = element.accessibilityValue
        guard element.accessibilityRole?() == .staticText, let words = (value?() ?? nil) as? String else {
            return false
        }
        return matches(words)
    }
}

/// The first element among `elements` and their children, in the order of the tree, for which `matches` holds.
@MainActor
private func firstElement(among elements: [Any], where matches: (AnyObject) -> Bool) -> AnyObject? {
    for item in elements {
        // SwiftUI's elements answer the methods of the accessibility protocol without declaring it, so they are asked
        // by name.
        let element = item as AnyObject
        if matches(element) {
            return element
        }
        if let found = firstElement(among: element.accessibilityChildren?() ?? [], where: matches) {
            return found
        }
    }
    return nil
}
