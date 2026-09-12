# Swift Testing Framework Rules

<objective>
You MUST write comprehensive tests using the Swift Testing framework (`@Test`) with Point-Free's Dependencies library. Tests MUST be focused, isolated, deterministic, behavior-oriented, and must leverage modern Swift Testing features for reliability, maintainability, and execution speed.
</objective>

<cognitive_triggers>
Keywords: Swift Testing, @Test, #expect, @Suite, Parameterized Tests, Test Traits, withDependencies, Test Isolation, Async Testing, Test Organization, Snapshot Testing, ViewInspector, Page Object Pattern, AccessibilityID, UI Testing, Test Pyramid, Mock Dependencies
</cognitive_triggers>

---

## Critical Rules

### Rule 0: Every SwiftUI View MUST Have Snapshot + ViewInspector Tests

**MANDATORY** — no SwiftUI view is complete without both:

1. A **snapshot test** using `swift-snapshot-testing` from Point-Free.
2. A **structure/unit test** using `ViewInspector` from `nalexn`.

SwiftUI view testing is not optional. Every view must prove both:

- **Visual correctness** through snapshot testing.
- **State-driven structure and interaction correctness** through ViewInspector.

---

### Rule 0.1: Snapshot Testing Requirements

Every SwiftUI view MUST have a snapshot test.

For macOS SwiftUI views:

- Render through SwiftUI `ImageRenderer`.
- Assert with:

```swift
assertSnapshot(
    of: image,
    as: .image(perceptualPrecision: 0.98)
)
```

Rules:

- MUST commit snapshot references under `__Snapshots__/`.
- MUST re-record snapshots only for intentional UI changes.
- MUST NOT use `.image(layout:)` for macOS views. That strategy is iOS/tvOS only.
- MUST NOT rely on off-screen `NSHostingController` for macOS snapshots because it can drop `Text`, SF Symbols, and other rendered content.
- MUST build views over inert stores or deterministic dependencies.
- MUST use a shared `make...View()` helper when the view setup is non-trivial.

Reference pattern:

```text
Packages/Journeys/Tests/AppShellTests/RecoveryViewSnapshotTests.swift
```

---

### Rule 0.2: ViewInspector Structure Testing Requirements

Every SwiftUI view MUST have a ViewInspector test.

Use ViewInspector to validate:

- Rendered text.
- Buttons.
- Conditional content.
- State-driven branches.
- Empty states.
- Error states.
- Loading states.
- Enabled/disabled behavior.
- Callback triggering.
- Local interactions that do not require a full app launch.

Example:

```swift
import Testing
import ViewInspector
@testable import MyFeature

@Suite("RecoveryView Inspection Tests")
struct RecoveryViewInspectionTests {
    @Test("Displays recovery title and primary action")
    func displaysRecoveryContent() throws {
        let view = makeRecoveryView()

        let sut = try view.inspect()

        #expect(try sut.find(text: "Recover Vault").string() == "Recover Vault")
        #expect(try sut.find(button: "Continue").isDisabled() == false)
    }
}
```

Rules:

- MUST use `.inspect().find(text:)`, `.find(button:)`, or equivalent semantic queries where possible.
- MUST NOT assert deep SwiftUI hierarchy unless there is no stable semantic alternative.
- MUST NOT use ViewInspector as a substitute for visual snapshot tests.
- MUST NOT use ViewInspector as a substitute for full user-flow UI tests.

---

### Rule 0.3: Window-Sizing Snapshot Matrix

For views with controls, forms, navigation, panels, sidebars, toolbars, or any layout-sensitive UI, snapshot tests MUST run across a window-size matrix.

Minimum required sizes:

```swift
@Test(arguments: [
    CGSize(width: 640, height: 400),
    CGSize(width: 1200, height: 800)
])
```

Rules:

- MUST include at least the enforced minimum window size: `640 × 400`.
- MUST include at least one wide layout size.
- MUST provide `named:` snapshot names per size.
- MUST catch clipped, hidden, overlapping, or disappearing controls.
- MUST enforce a window floor in production UI with:

```swift
.frame(minWidth: 640, minHeight: 400)
.windowResizability(.contentMinSize)
```

Rules:

- MUST NOT use `ScrollView` merely to hide clipping problems.
- MUST NOT use `ScrollView` as a snapshot workaround because it can render blank under `ImageRenderer`.
- MUST treat layout breakage under the minimum window size as a real product bug.

Reference pattern:

```text
AppShellViewSnapshotTests.recoveryUISurvivesWindowSizes
```

---

### Rule 0.4: Page Object UI Tests Are Mandatory for User Flows

Every user-facing flow MUST have an end-to-end UI test using the Page Object Pattern.

These tests belong in the `PumiceUITests` Tuist target:

```text
App/UITests/
```

Rules:

- MUST use one `Screen` object per screen.
- MUST resolve elements through stable `AccessibilityID`.
- MUST make the test body read as user intent.
- MUST NOT expose raw `XCUIElement` lookup chains in test bodies.
- MUST launch through the shared `launchPumice()` helper.
- MUST pass `-uiTestResetSession` for deterministic clean state.
- MUST pass `-uiTestDisableAnimations` so SwiftUI transitions are disabled in UI tests.
- MUST document exceptions where SwiftUI does not allow identifiers, such as menu items that must be matched by title.

Reference pattern:

```text
App/UITests/OpenVaultFlowUITests.swift
App/UITests/Screens/AppShellScreen.swift
App/UITests/Support/Screen.swift
App/UITests/Support/AppLauncher.swift
```

Example:

```swift
@Test("User can open an existing vault")
func openVaultFlow() throws {
    let app = launchPumice()

    let appShell = AppShellScreen(app)
    appShell.openVault()

    let openVault = OpenVaultScreen(app)
    openVault.selectVault(named: "Personal")
    openVault.confirm()

    appShell.expectVaultOpened(named: "Personal")
}
```

---

### Rule 0.5: ViewInspector Does NOT Replace the Page Object Pattern

ViewInspector does **not** replace the Page Object Pattern.

ViewInspector is the SwiftUI inspection mechanism.

Page Objects are the semantic test architecture.

Use ViewInspector directly for:

- Small component tests.
- Isolated SwiftUI structure checks.
- Local button interactions.
- Conditional rendering checks.
- State-driven content assertions.

Use Page Objects for:

- Full-screen tests.
- Repeated interactions.
- Reusable flows.
- Complex screens.
- Tests where raw hierarchy traversal would become fragile.
- End-to-end UI tests.

Mandatory distinction:

| Concern | Required Tool |
|---|---|
| Visual rendering | Snapshot Testing |
| SwiftUI structure | ViewInspector |
| Local SwiftUI interaction | ViewInspector |
| Repeated full-screen interaction | ViewInspector-backed Page Object |
| Full user-facing flow | Page-object UI Test |
| Cross-screen app behavior | Page-object UI Test |

Rules:

- MUST NOT treat ViewInspector as a replacement for Page Objects.
- MUST NOT write full-screen or flow-oriented tests that directly chain fragile inspector calls in the test body.
- MUST wrap complex ViewInspector interactions behind semantic page objects.
- MUST make tests read as behavior, not implementation.
- MUST hide SwiftUI hierarchy details inside the page object.

Wrong:

```swift
@Test("User can submit login")
func loginFlow() throws {
    let view = LoginView(store: store)
    let sut = try view.inspect()

    try sut.vStack().textField(0).setInput("bruno@example.com")
    try sut.vStack().secureField(1).setInput("123456")
    try sut.vStack().button(2).tap()

    #expect(store.didSubmitLogin)
}
```

Right:

```swift
struct LoginViewPage {
    private let view: InspectableView<ViewType.View<LoginView>>

    init(_ view: LoginView) throws {
        self.view = try view.inspect()
    }

    func enterEmail(_ value: String) throws {
        try view.find(textField: "Email").setInput(value)
    }

    func enterPassword(_ value: String) throws {
        try view.find(ViewType.SecureField.self).setInput(value)
    }

    func submit() throws {
        try view.find(button: "Continue").tap()
    }
}

@Test("User can submit login")
func loginFlow() throws {
    let view = LoginView(store: store)
    let page = try LoginViewPage(view)

    try page.enterEmail("bruno@example.com")
    try page.enterPassword("123456")
    try page.submit()

    #expect(store.didSubmitLogin)
}
```

Rule:

```text
ViewInspector is the mechanism. Page Object is the architecture.
```

Do not confuse the two.

---

### Rule 0.6: Full Matrix Per View and Flow

A SwiftUI view or user-facing flow is not complete until the following matrix is green:

| Test Type | Required For | Tool |
|---|---|---|
| Structure test | Every SwiftUI view | ViewInspector |
| Snapshot test | Every SwiftUI view | swift-snapshot-testing |
| Window-size matrix | Views with controls/layout risk | Snapshot Testing + ImageRenderer |
| ViewInspector-backed Page Object | Complex/repeated full-screen view tests | ViewInspector |
| Page-object UI test | Every user-facing flow | UI Testing + AccessibilityID |

Minimum completion rule:

```text
No view is complete without ViewInspector + Snapshot.
No user-facing flow is complete without a Page Object UI test.
```

---

## Rule 1: Swift Testing Framework Usage

ALWAYS use modern Swift Testing.

Rules:

- MUST use `@Test` for test methods.
- MUST use `@Suite` for logical grouping.
- MUST use `#expect` for assertions.
- MUST use `#require` when unwrapping required test state.
- MUST use parameterized tests for scenario matrices.
- MUST use test traits where useful for tags, conditions, time limits, or known issues.
- MUST NOT use XCTest unless absolutely required by framework limitations.
- MUST NOT mix XCTest assertions into Swift Testing tests.

Example:

```swift
import Testing

@Suite("EmailValidator Tests")
struct EmailValidatorTests {
    @Test("Accepts valid email addresses", arguments: [
        "bruno@example.com",
        "user.name@domain.com",
        "dev+test@company.io"
    ])
    func acceptsValidEmails(email: String) {
        let validator = EmailValidator()

        #expect(validator.isValid(email))
    }
}
```

---

## Rule 2: Dependency Isolation

ALWAYS control dependencies in tests.

Rules:

- MUST use `withDependencies` for dependency-controlled systems.
- MUST provide deterministic dependency values.
- MUST isolate tests from external systems.
- MUST NOT use live network calls.
- MUST NOT use live databases unless the test is explicitly an integration test.
- MUST NOT depend on wall-clock time.
- MUST NOT depend on random UUIDs.
- MUST NOT depend on real file-system state unless explicitly scoped to a temporary test directory.
- MUST NOT depend on shared process state.

Required deterministic defaults:

```swift
withDependencies {
    $0.date.now = Date(timeIntervalSince1970: 0)
    $0.uuid = .incrementing
    $0.mainQueue = .immediate
} operation: {
    SystemUnderTest()
}
```

---

## Rule 3: Test Organization

ALWAYS structure tests clearly.

Rules:

- MUST use `@Suite` for logical grouping.
- MUST use nested suites when behavior domains differ.
- MUST name tests by scenario and expected behavior.
- MUST test one behavior per test.
- MUST avoid kitchen-sink tests.
- MUST keep setup local unless shared setup improves clarity.
- MUST keep helper names explicit and domain-specific.
- MUST avoid vague names like `testWorks`, `testSuccess`, or `testFailure`.

Good test names:

```swift
@Test("Shows empty state when vault has no documents")
@Test("Disables continue button when password is empty")
@Test("Retries request after token refresh succeeds")
@Test("Returns cached result when network is unavailable")
```

Bad test names:

```swift
@Test("Test view")
@Test("Success")
@Test("Failure")
@Test("Flow")
@Test("Button")
```

---

## Rule 4: Async Testing

ALWAYS handle concurrency deterministically.

Rules:

- MUST use `async/await` for async tests.
- MUST use structured concurrency.
- MUST avoid unstructured `Task {}` unless explicitly tested.
- MUST avoid arbitrary sleeps.
- MUST avoid race conditions.
- MUST control clocks, schedulers, queues, and streams through dependencies.
- MUST cancel long-running tasks.
- MUST ensure async streams finish deterministically.
- MUST assert cancellation behavior when relevant.

Wrong:

```swift
@Test("Loads results")
func loadsResults() async {
    viewModel.search("query")

    try? await Task.sleep(for: .seconds(1))

    #expect(!viewModel.results.isEmpty)
}
```

Right:

```swift
@Test("Loads results")
func loadsResults() async {
    let viewModel = withDependencies {
        $0.apiClient.search = { _ in [.mock] }
    } operation: {
        SearchViewModel()
    }

    await viewModel.search("query")

    #expect(viewModel.results == [.mock])
}
```

---

## Rule 5: Test Pyramid

ALWAYS follow the testing hierarchy.

Target distribution:

| Test Type | Target Share | Purpose |
|---|---:|---|
| Unit tests | ~70% | Fast, isolated logic/state tests |
| Integration tests | ~20% | Component interaction and adapter boundaries |
| UI/E2E tests | ~10% | Critical user paths |

Rules:

- MUST favor unit tests for business logic.
- MUST use integration tests for real component boundaries.
- MUST use UI/E2E tests for user-critical flows.
- MUST NOT invert the pyramid.
- MUST NOT test every edge case through UI automation.
- MUST NOT skip UI tests for critical flows.
- MUST NOT rely only on snapshots for UI correctness.

---

## Test Type Decision Tree

```text
What are you testing?
├─ Pure logic/calculations?
│   └─ Unit Test → Direct function tests
├─ State management?
│   └─ Unit Test → ViewModel/Model tests with controlled dependencies
├─ Dependency behavior?
│   └─ Unit Test → withDependencies + deterministic clients
├─ Component interaction?
│   └─ Integration Test → Multi-component boundary test
├─ Persistence adapter?
│   └─ Integration Test → Temporary isolated database/file store
├─ User interface?
│   ├─ Visual correctness?
│   │   └─ Snapshot Test
│   ├─ Local state-driven structure?
│   │   └─ ViewInspector Test
│   ├─ Local SwiftUI interaction?
│   │   └─ ViewInspector Test
│   ├─ Repeated full-screen interactions?
│   │   └─ ViewInspector-backed Page Object
│   └─ User-facing flow?
│       └─ Page-object UI Test using AccessibilityID
└─ Complete user flow?
    └─ E2E Test → Page-object UI test
```

---

## Testing Patterns

### Pattern 1: Basic Swift Testing Structure

```swift
import Testing
import Dependencies
@testable import MyApp

@Suite("Feature Name Tests")
struct FeatureNameTests {
    @Suite("Specific Behavior")
    struct SpecificBehaviorTests {
        let mockData = MockData()

        @Test("Returns expected value when action succeeds")
        func actionSucceeds() async throws {
            let sut = withDependencies {
                $0.apiClient.fetch = { _ in self.mockData }
            } operation: {
                SystemUnderTest()
            }

            let result = try await sut.performAction()

            #expect(result == expectedValue)
        }
    }
}
```

Rules:

- Arrange dependencies first.
- Act once.
- Assert behavior.
- Keep assertions focused.
- Avoid testing private implementation details.

---

### Pattern 2: Parameterized Testing

Use parameterized tests for scenario matrices.

```swift
@Test("Validates email formats", arguments: [
    ("valid@email.com", true),
    ("invalid-email", false),
    ("", false),
    ("user@", false),
    ("@domain.com", false)
])
func emailValidation(email: String, isValid: Bool) {
    let validator = EmailValidator()

    #expect(validator.isValid(email) == isValid)
}
```

For complex scenarios, use named test cases.

```swift
struct ProcessingTestCase: CustomTestStringConvertible {
    let input: String
    let expectedOutput: String
    let expectedError: ProcessingError?

    var testDescription: String {
        "input: \(input), expected: \(expectedOutput)"
    }
}

@Test("Processes input scenarios", arguments: [
    ProcessingTestCase(
        input: "hello",
        expectedOutput: "HELLO",
        expectedError: nil
    ),
    ProcessingTestCase(
        input: "",
        expectedOutput: "",
        expectedError: nil
    ),
    ProcessingTestCase(
        input: "123",
        expectedOutput: "",
        expectedError: .invalidInput
    )
])
func processingScenarios(testCase: ProcessingTestCase) async throws {
    let processor = TextProcessor()

    if let expectedError = testCase.expectedError {
        await #expect(throws: expectedError) {
            try await processor.process(testCase.input)
        }
        return
    }

    let result = try await processor.process(testCase.input)

    #expect(result == testCase.expectedOutput)
}
```

---

### Pattern 3: ViewModel Testing

```swift
import Testing
import Dependencies
@testable import MyFeature

@Suite("UserProfileViewModel Tests")
struct UserProfileViewModelTests {
    @Test("Initial state is idle")
    func initialState() {
        let viewModel = UserProfileViewModel()

        #expect(viewModel.user == nil)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
    }

    @Test("Loading user stores returned user")
    func loadingUserStoresReturnedUser() async {
        let viewModel = withDependencies {
            $0.apiClient.fetchUser = { _ in .mock }
            $0.logger.log = { _, _ in }
        } operation: {
            UserProfileViewModel()
        }

        await viewModel.loadUser(id: UUID())

        #expect(viewModel.user == .mock)
        #expect(viewModel.error == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("Loading user stores error when client fails")
    func loadingUserStoresErrorWhenClientFails() async {
        struct TestError: Error, Equatable {}

        let viewModel = withDependencies {
            $0.apiClient.fetchUser = { _ in throw TestError() }
            $0.logger.log = { _, _ in }
        } operation: {
            UserProfileViewModel()
        }

        await viewModel.loadUser(id: UUID())

        #expect(viewModel.error as? TestError == TestError())
        #expect(viewModel.user == nil)
        #expect(viewModel.isLoading == false)
    }
}
```

Rules:

- MUST validate initial state.
- MUST validate success state.
- MUST validate failure state.
- MUST validate loading transitions when relevant.
- MUST silence logging dependencies unless logging behavior is under test.

---

### Pattern 4: Async Stream Testing

```swift
@Suite("Real-time Message Tests")
struct RealTimeMessageTests {
    @Test("Processes message stream")
    func messageStream() async throws {
        let messages = ["Hello", "World", "!"]

        let viewModel = withDependencies {
            $0.webSocketClient.messages = {
                AsyncStream { continuation in
                    for message in messages {
                        continuation.yield(message)
                    }

                    continuation.finish()
                }
            }
        } operation: {
            ChatViewModel()
        }

        var received: [String] = []

        for await message in viewModel.messageStream {
            received.append(message)
        }

        #expect(received == messages)
    }

    @Test("Propagates stream errors")
    func streamErrorHandling() async throws {
        struct StreamError: Error {}

        let viewModel = withDependencies {
            $0.webSocketClient.messages = {
                AsyncThrowingStream { continuation in
                    continuation.yield("First")
                    continuation.finish(throwing: StreamError())
                }
            }
        } operation: {
            ChatViewModel()
        }

        var messages: [String] = []
        var errorCaught = false

        do {
            for try await message in viewModel.messageStream {
                messages.append(message)
            }
        } catch is StreamError {
            errorCaught = true
        }

        #expect(messages == ["First"])
        #expect(errorCaught)
    }
}
```

Rules:

- MUST finish streams.
- MUST test error propagation.
- MUST avoid sleep-based stream tests.
- MUST avoid infinite streams unless cancellation is explicitly tested.

---

### Pattern 5: ViewInspector Component Test

```swift
import Testing
import ViewInspector
@testable import MyFeature

@Suite("ProductCardView Tests")
struct ProductCardViewTests {
    @Test("Displays product information")
    func productDisplay() throws {
        let product = Product(name: "iPhone", price: 999.99)
        let view = ProductCardView(product: product)

        let sut = try view.inspect()

        let nameText = try sut.find(text: "iPhone")
        #expect(try nameText.string() == "iPhone")

        let priceText = try sut.find(text: "$999.99")
        #expect(try priceText.string() == "$999.99")
    }

    @Test("Tapping add to cart triggers callback")
    func buttonInteraction() throws {
        var tapped = false

        let view = ProductCardView(
            product: .mock,
            onTap: { tapped = true }
        )

        let sut = try view.inspect()
        let button = try sut.find(button: "Add to Cart")

        try button.tap()

        #expect(tapped)
    }
}
```

Rules:

- Use ViewInspector directly for small components.
- Use semantic `.find(...)` queries before structural traversal.
- Escalate to a ViewInspector-backed Page Object when the test becomes screen-like or repetitive.

---

### Pattern 6: ViewInspector-Backed Page Object

```swift
import ViewInspector
@testable import MyFeature

struct RecoveryViewPage {
    private let view: InspectableView<ViewType.View<RecoveryView>>

    init(_ view: RecoveryView) throws {
        self.view = try view.inspect()
    }

    func expectTitleVisible() throws {
        #expect(try view.find(text: "Recover Vault").string() == "Recover Vault")
    }

    func enterRecoveryKey(_ value: String) throws {
        try view.find(textField: "Recovery Key").setInput(value)
    }

    func continueRecovery() throws {
        try view.find(button: "Continue").tap()
    }

    func expectContinueDisabled() throws {
        #expect(try view.find(button: "Continue").isDisabled())
    }
}

@Suite("RecoveryView Flow Tests")
struct RecoveryViewFlowTests {
    @Test("Allows recovery when valid key is entered")
    func validRecoveryKey() throws {
        let view = makeRecoveryView()
        let page = try RecoveryViewPage(view)

        try page.expectTitleVisible()
        try page.enterRecoveryKey("valid-key")
        try page.continueRecovery()

        #expect(store.didStartRecovery)
    }
}
```

Rules:

- Page object methods MUST describe user intent.
- Page object methods MUST hide hierarchy traversal.
- Test body MUST not expose `.vStack()`, `.hStack()`, `.button(0)`, or index-based traversal.
- Prefer named controls and stable accessibility labels.

---

### Pattern 7: Snapshot Testing with Window Matrix

```swift
import Testing
import SnapshotTesting
import SwiftUI
@testable import MyFeature

@Suite("RecoveryView Snapshot Tests")
struct RecoveryViewSnapshotTests {
    @Test("Recovery UI survives supported window sizes", arguments: [
        SnapshotSize(name: "minimum", size: CGSize(width: 640, height: 400)),
        SnapshotSize(name: "wide", size: CGSize(width: 1200, height: 800))
    ])
    @MainActor
    func recoveryUISurvivesWindowSizes(snapshot: SnapshotSize) throws {
        let view = makeRecoveryView()
            .frame(width: snapshot.size.width, height: snapshot.size.height)

        let renderer = ImageRenderer(content: view)

        let image = try #require(renderer.nsImage)

        assertSnapshot(
            of: image,
            as: .image(perceptualPrecision: 0.98),
            named: snapshot.name
        )
    }
}

struct SnapshotSize: CustomTestStringConvertible {
    let name: String
    let size: CGSize

    var testDescription: String {
        name
    }
}
```

Rules:

- MUST run snapshots on `@MainActor`.
- MUST use deterministic data.
- MUST name each snapshot.
- MUST include minimum and wide sizes.
- MUST not rely on hidden environment state.

---

### Pattern 8: Page Object UI Test

```swift
import Testing

@Suite("Open Vault Flow UI Tests")
struct OpenVaultFlowUITests {
    @Test("User can open an existing vault")
    func userCanOpenExistingVault() throws {
        let app = launchPumice()

        let appShell = AppShellScreen(app)
        appShell.openVault()

        let openVault = OpenVaultScreen(app)
        openVault.selectVault(named: "Personal")
        openVault.confirmSelection()

        appShell.expectVaultOpened(named: "Personal")
    }
}
```

Screen object:

```swift
struct OpenVaultScreen: Screen {
    let app: XCUIApplication

    init(_ app: XCUIApplication) {
        self.app = app
    }

    func selectVault(named name: String) {
        app.buttons[AccessibilityID.openVaultRow(name)].click()
    }

    func confirmSelection() {
        app.buttons[AccessibilityID.confirmOpenVault].click()
    }
}
```

Rules:

- UI tests MUST use `AccessibilityID`.
- UI tests MUST avoid raw lookup chains in the test body.
- UI tests MUST launch with deterministic state.
- UI tests MUST disable animations.
- UI tests MUST cover critical user paths, not every edge case.

---

## Dependency Mocking Patterns

### Pattern 1: Test Dependency Configuration

```swift
extension DependencyValues {
    static func testValue(
        configuring: (inout DependencyValues) -> Void = { _ in }
    ) -> DependencyValues {
        var dependencies = DependencyValues()

        dependencies.apiClient = .noop
        dependencies.date.now = Date(timeIntervalSince1970: 0)
        dependencies.uuid = .incrementing
        dependencies.mainQueue = .immediate
        dependencies.logger = .noop

        configuring(&dependencies)

        return dependencies
    }
}
```

Usage:

```swift
@Test("Loads user with configured dependency")
func testWithConfiguration() async {
    let viewModel = withDependencies {
        $0 = .testValue { dependencies in
            dependencies.apiClient.fetchUser = { _ in .mock }
        }
    } operation: {
        UserViewModel()
    }

    await viewModel.loadUser()

    #expect(viewModel.user == .mock)
}
```

Rules:

- MUST provide safe defaults.
- MUST fail loudly for unexpected dependency calls when appropriate.
- MUST use `.noop` only when the dependency behavior is irrelevant.
- MUST use `.failing` or explicit traps when unexpected calls should fail the test.

---

### Pattern 2: Mock Implementations

```swift
extension APIClient {
    static let noop = APIClient(
        fetchUser: { _ in throw CancellationError() },
        updateUser: { _ in throw CancellationError() },
        deleteUser: { _ in throw CancellationError() }
    )

    static func succeeding(
        user: User = .mock,
        delay: Duration = .zero
    ) -> APIClient {
        APIClient(
            fetchUser: { _ in
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }

                return user
            },
            updateUser: { _ in
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            },
            deleteUser: { _ in
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            }
        )
    }

    static func failing(
        error: Error = TestError()
    ) -> APIClient {
        APIClient(
            fetchUser: { _ in throw error },
            updateUser: { _ in throw error },
            deleteUser: { _ in throw error }
        )
    }
}
```

Rules:

- MUST keep mocks predictable.
- MUST avoid mocks with hidden mutable global state.
- MUST prefer value-based dependency clients.
- MUST make success, failure, cancellation, and timeout behavior explicit.

---

## Testing Anti-Patterns

### Anti-Pattern 1: Testing Implementation Details

Wrong:

```swift
@Test
func badTest() {
    let viewModel = UserViewModel()

    let mirror = Mirror(reflecting: viewModel)

    #expect(mirror.children.count > 0)
}
```

Right:

```swift
@Test
func updatesDisplayName() {
    let viewModel = UserViewModel()

    viewModel.updateName("New Name")

    #expect(viewModel.displayName == "New Name")
}
```

Rule:

```text
Test behavior through public API. Do not test private structure.
```

---

### Anti-Pattern 2: Arbitrary Delays

Wrong:

```swift
@Test
func badAsyncTest() async {
    let viewModel = SearchViewModel()

    viewModel.search("query")

    try? await Task.sleep(for: .seconds(1))

    #expect(!viewModel.results.isEmpty)
}
```

Right:

```swift
@Test
func goodAsyncTest() async {
    let viewModel = withDependencies {
        $0.apiClient.search = { _ in [.mock] }
    } operation: {
        SearchViewModel()
    }

    await viewModel.search("query")

    #expect(viewModel.results == [.mock])
}
```

Rule:

```text
If the test needs sleep to pass, the test is probably wrong.
```

---

### Anti-Pattern 3: Shared Mutable State

Wrong:

```swift
final class SharedCache {
    static let shared = SharedCache()

    var data: [String: Any] = [:]
}

@Test
func badTest1() {
    SharedCache.shared.data["key"] = "value"
}

@Test
func badTest2() {
    let value = SharedCache.shared.data["key"]

    #expect(value as? String == "value")
}
```

Right:

```swift
@Test
func isolatedCacheTest() {
    let cache = TestCache()

    cache.set("value", forKey: "key")

    #expect(cache.value(forKey: "key") == "value")
}
```

Rule:

```text
Every test must be independently executable.
```

---

### Anti-Pattern 4: Fragile SwiftUI Hierarchy Traversal

Wrong:

```swift
@Test("Submits login")
func submitsLogin() throws {
    let view = LoginView(store: store)
    let sut = try view.inspect()

    try sut.vStack().hStack(1).textField(0).setInput("bruno@example.com")
    try sut.vStack().hStack(1).secureField(1).setInput("123456")
    try sut.vStack().button(3).tap()

    #expect(store.didLogin)
}
```

Right:

```swift
@Test("Submits login")
func submitsLogin() throws {
    let view = LoginView(store: store)
    let page = try LoginViewPage(view)

    try page.enterEmail("bruno@example.com")
    try page.enterPassword("123456")
    try page.submit()

    #expect(store.didLogin)
}
```

Rule:

```text
Tests should fail when behavior breaks, not when a VStack is rearranged.
```

---

### Anti-Pattern 5: Snapshot-Only UI Coverage

Wrong:

```swift
@Test("Login view looks correct")
func loginSnapshot() {
    assertSnapshot(...)
}
```

Right:

```swift
@Test("Login view looks correct")
func loginSnapshot() {
    assertSnapshot(...)
}

@Test("Disables submit when fields are empty")
func disablesSubmitWhenFieldsAreEmpty() throws {
    let page = try LoginViewPage(makeLoginView())

    try page.expectSubmitDisabled()
}
```

Rule:

```text
Snapshots prove pixels. They do not prove behavior.
```

---

## Test Organization Checklist

Before submitting tests, verify:

- [ ] Tests use `@Test`, not XCTest.
- [ ] Tests use `#expect` and `#require`.
- [ ] Tests are grouped with `@Suite`.
- [ ] Each test has one clear purpose.
- [ ] Test names describe scenario and outcome.
- [ ] Dependencies are controlled with `withDependencies`.
- [ ] No live network calls are used.
- [ ] No live database calls are used outside integration tests.
- [ ] No wall-clock time dependency exists.
- [ ] No random UUID dependency exists.
- [ ] No arbitrary delays are used.
- [ ] Async tests use deterministic synchronization.
- [ ] Test data is deterministic.
- [ ] Error cases are tested.
- [ ] Edge cases are tested.
- [ ] Tests run in isolation.
- [ ] Tests follow the 70/20/10 test pyramid.
- [ ] Critical paths have E2E tests.
- [ ] Every SwiftUI view has ViewInspector tests.
- [ ] Every SwiftUI view has snapshot tests.
- [ ] Views with controls have window-size snapshot matrices.
- [ ] SwiftUI component tests use ViewInspector for local structure and interaction assertions.
- [ ] Complex SwiftUI screen tests wrap ViewInspector calls in semantic Page Objects.
- [ ] User-facing flows use page-object UI tests with stable `AccessibilityID`.
- [ ] Test bodies read as user intent, not SwiftUI hierarchy traversal.
- [ ] ViewInspector is not treated as a replacement for Page Objects.
- [ ] Visual changes update snapshots intentionally.
- [ ] Snapshot re-recording is reviewed as a UI contract change.

---

## Testing Decision Flowchart

```text
Writing a new test:
├─ Can it be a unit test?
│   ├─ YES
│   │   └─ Write focused unit test
│   └─ NO
│       └─ Identify why unit scope is insufficient
│
├─ Does it need multiple components?
│   ├─ YES
│   │   └─ Write integration test
│   └─ NO
│       └─ Keep it isolated
│
├─ Does it test SwiftUI?
│   ├─ YES
│   │   ├─ Visual rendering?
│   │   │   └─ Snapshot test
│   │   ├─ Local state-driven structure?
│   │   │   └─ ViewInspector test
│   │   ├─ Complex repeated screen interaction?
│   │   │   └─ ViewInspector-backed Page Object
│   │   └─ User-facing flow?
│   │       └─ Page-object UI test
│   └─ NO
│       └─ Continue
│
├─ Is it deterministic?
│   ├─ NO
│   │   └─ Fix dependency/time/randomness/concurrency source
│   └─ YES
│       └─ Continue
│
├─ Does it run fast?
│   ├─ YES
│   │   └─ Good
│   └─ NO
│       ├─ Can it be optimized?
│       │   ├─ YES
│       │   │   └─ Optimize
│       │   └─ NO
│       │       └─ Mark/tag as slow or integration/UI
│       └─ Continue
│
└─ Does the test body read as behavior?
    ├─ YES
    │   └─ Good
    └─ NO
        └─ Extract helper, fixture, or Page Object
```

---

## Final Enforcement Rules

- Always pipe tests commands `swift test` with `swift test | xcbeautify -q` this outputs only warnings and errors keeping context window with less data.
- A feature without tests is incomplete.
- A SwiftUI view without ViewInspector coverage is incomplete.
- A SwiftUI view without snapshot coverage is incomplete.
- A layout-sensitive view without a window-size snapshot matrix is incomplete.
- A user-facing flow without a Page Object UI test is incomplete.
- A test using live dependencies is invalid unless explicitly classified as integration.
- A test requiring arbitrary sleep is invalid.
- A test that exposes fragile SwiftUI hierarchy traversal is invalid.
- A Page Object that exposes implementation details is invalid.
- A snapshot change without intentional review is invalid.
- ViewInspector is the mechanism.
- Page Object is the architecture.
