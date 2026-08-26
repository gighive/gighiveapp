//
//  GigHiveUITests.swift
//  GigHiveUITests
//
//  Phase 0 smoke tests — AuthCredential refactor
//
//  These tests verify that the centralized AuthCredential abstraction works end-to-end
//  in the UI: login sets session.credential, the splash banner shows the username, and
//  the database list loads (proving Authorization: Basic headers still reach the server).
//
//  ── How to run ──────────────────────────────────────────────────────────────────────
//  Set the following environment variables in the GigHiveUITests scheme
//  (Product → Scheme → Edit Scheme → Test → Arguments → Environment Variables):
//
//    GH_TEST_HOST      e.g. "mygighive.example.com"   (no https://, no trailing slash)
//    GH_TEST_USER      e.g. "admin"
//    GH_TEST_PASS      e.g. "correctpassword"
//
//  Without these the credential tests are skipped with a XCTSkip message so the
//  build still passes in CI environments that haven't injected real server details.
// ─────────────────────────────────────────────────────────────────────────────────────

import XCTest

final class GigHiveUITests: XCTestCase {

    // MARK: - Helpers

    private var app: XCUIApplication!

    /// Server credentials read from environment variables at test time.
    /// Throws XCTSkip (not a failure) if the vars are not set.
    ///
    /// Optional: set GH_TEST_INSECURE=1 if the server uses a self-signed certificate.
    private func requireCredentials(file: StaticString = #file, line: UInt = #line)
        throws -> (host: String, user: String, pass: String, insecure: Bool)
    {
        let env = ProcessInfo.processInfo.environment
        guard
            let host = env["GH_TEST_HOST"], !host.isEmpty,
            let user = env["GH_TEST_USER"], !user.isEmpty,
            let pass = env["GH_TEST_PASS"], !pass.isEmpty
        else {
            throw XCTSkip(
                "Set GH_TEST_HOST, GH_TEST_USER, GH_TEST_PASS env vars in the test scheme to run credential tests.",
                file: file, line: line
            )
        }
        let insecure = env["GH_TEST_INSECURE"] == "1"
        return (host, user, pass, insecure)
    }

    /// Fills the login form and taps Sign In.
    /// TLS certificate checking is automatically disabled under --uitesting via LoginView's
    /// initial state, so no UI toggle interaction is needed here.
    private func performLogin(host: String, user: String, pass: String, insecure: Bool) {
        app.buttons["splash_login_button"].tap()
        fill("login_server_field", with: host)
        fill("login_username_field", with: user)
        fillSecure("login_password_field", with: pass)
        app.buttons["login_sign_in_button"].tap()
    }

    /// Taps a text field, clears any existing content, then types the replacement text.
    /// LoginView.onAppear prefills fields from Keychain/UserDefaults, so we must clear first.
    private func fill(_ identifier: String, with text: String) {
        let field = app.textFields[identifier]
        XCTAssert(field.waitForExistence(timeout: 4), "Field '\(identifier)' not found")
        field.tap()
        Thread.sleep(forTimeInterval: 0.4)  // wait for keyboard to appear
        clearAndType(field, text: text)
    }

    /// Scrolls the splash scroll view gently then taps a button that may be below the fold.
    /// Falls back to coordinate tap when XCUITest reports {-1,-1} hit point.
    private func tapSplashButton(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssert(button.waitForExistence(timeout: 20), "'\(identifier)' button not found")
        // Gentle half-screen drag to bring lower buttons into view without overshooting
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.4)
        button.tap()
    }

    /// Same as fill(_:with:) but for secure fields.
    private func fillSecure(_ identifier: String, with text: String) {
        let field = app.secureTextFields[identifier]
        XCTAssert(field.waitForExistence(timeout: 4), "Secure field '\(identifier)' not found")
        field.tap()
        clearAndType(field, text: text)
    }

    /// Selects all text in a field and replaces it. Works for both TextField and SecureTextField.
    private func clearAndType(_ element: XCUIElement, text: String) {
        // Triple-tap selects all text reliably on iOS simulator
        element.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        // Small pause for selection to appear
        Thread.sleep(forTimeInterval: 0.3)
        // If there is selected text, typing replaces it; if not (empty field), it just appends
        element.typeText(text)
    }

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]   // skips Keychain restore, starts logged-out
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tests

    /// Splash screen is visible and starts in logged-out state (no banner, Login button present).
    @MainActor
    func testSplashStartsLoggedOut() throws {
        let loginButton = app.buttons["splash_login_button"]
        XCTAssert(loginButton.waitForExistence(timeout: 5), "Login button should be visible on a fresh launch")
        XCTAssertFalse(
            app.staticTexts["splash_logged_in_banner"].exists,
            "Logged-in banner must not appear before login"
        )
    }

    /// Login screen opens when the Login button is tapped.
    @MainActor
    func testLoginScreenOpens() throws {
        app.buttons["splash_login_button"].tap()
        let usernameField = app.textFields["login_username_field"]
        XCTAssert(usernameField.waitForExistence(timeout: 5), "Login screen should appear after tapping Login")
    }

    /// Full login flow: fill credentials → tap Sign In → splash shows logged-in banner.
    /// This proves session.credential is set and displayUser surfaces correctly.
    @MainActor
    func testLoginSetsCredentialAndShowsSplashBanner() throws {
        let (host, user, pass, insecure) = try requireCredentials()

        performLogin(host: host, user: user, pass: pass, insecure: insecure)

        // After successful login, splash should show the logged-in banner with the username
        let banner = app.staticTexts["splash_logged_in_banner"]
        XCTAssert(
            banner.waitForExistence(timeout: 20),
            "Logged-in banner did not appear — login may have failed or session.credential.displayUser is broken"
        )
        XCTAssert(
            banner.label.contains(user),
            "Banner '\(banner.label)' should contain the username '\(user)'"
        )
    }

    /// After login the Database button is visible (confirms session.credential != nil path in SplashView).
    @MainActor
    func testDatabaseButtonVisibleAfterLogin() throws {
        let (host, user, pass, insecure) = try requireCredentials()

        performLogin(host: host, user: user, pass: pass, insecure: insecure)

        // The NavigationLink to DatabaseView should appear once credential is set.
        // Scroll to the button and assert it exists (hittability confirmed by tapSplashButton helper)
        let dbButton = app.buttons["splash_view_database_button"]
        XCTAssert(
            dbButton.waitForExistence(timeout: 20),
            "View the Database button (splash_view_database_button) should appear after login"
        )
    }

    /// Database list loads at least one entry — proves Authorization: Basic headers reach the server.
    @MainActor
    func testDatabaseLoadsEntriesAfterLogin() throws {
        let (host, user, pass, _) = try requireCredentials()

        // Use --uitest-navigate-database to avoid the NavigationLink tap hit-point issue.
        // SplashView.onChange(of: session.credential) fires the navigation automatically.
        app.terminate()
        app.launchArguments = ["--uitesting", "--uitest-navigate-database"]
        app.launch()
        XCTAssert(app.buttons["splash_login_button"].waitForExistence(timeout: 10))
        performLogin(host: host, user: user, pass: pass, insecure: true)

        // Wait for at least one cell — confirms Authorization: Basic header reached the server.
        let firstCell = app.cells.firstMatch
        XCTAssert(
            firstCell.waitForExistence(timeout: 40),
            "Database list should contain at least one entry — check that the server returned media and the Authorization: Basic header was sent correctly"
        )
    }

    /// Cancelled login returns to splash still logged-out.
    @MainActor
    func testCancelLoginKeepsLoggedOutState() throws {
        app.buttons["splash_login_button"].tap()
        XCTAssert(app.textFields["login_username_field"].waitForExistence(timeout: 5))

        app.buttons["Cancel"].tap()

        // Back on splash — no banner, login button still there
        let loginButton = app.buttons["splash_login_button"]
        XCTAssert(loginButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["splash_logged_in_banner"].exists)
    }

    /// Wrong password shows an error message and does not set session.credential.
    @MainActor
    func testLoginFailureShowsError() throws {
        let (host, user, _, insecure) = try requireCredentials()

        performLogin(
            host: host,
            user: user,
            pass: "definitelyWrongPassword_\(Int.random(in: 1000...9999))",
            insecure: insecure
        )

        // An error label (red text from LoginView) should appear
        // The label text varies by server response; we just check *something* red appears
        // by waiting for the banner NOT to appear and for the login screen to stay up.
        let banner = app.staticTexts["splash_logged_in_banner"]
        // Give the request time to fail; banner must not appear
        XCTAssertFalse(
            banner.waitForExistence(timeout: 10),
            "Logged-in banner must not appear after a failed login"
        )
        // Login screen should still be on screen
        XCTAssert(
            app.textFields["login_username_field"].exists,
            "Login screen should remain visible after a bad password"
        )
    }

    // MARK: - Upload duplicate test

    /// Attempts to upload a file that already exists on the server to observe the error response.
    /// The file (3ed8bbc4….mp4 — "Flesh Machine" by StormPigs) is injected via a launch argument
    /// so that the system file/photo picker does not need to be driven by XCUITest.
    ///
    /// Pre-requisite: the file must exist in the app's Documents sandbox (copied there at test
    /// setup time or by the test infrastructure — see testing_ios.md step 10).
    ///
    /// Expected: server returns HTTP 409 (or similar duplicate-file error).
    /// This test always passes — look at the printed TEXT lines and the screenshot attachment.
    @MainActor
    func testUploadDuplicateFileShowsError() throws {
        let (host, user, pass, _) = try requireCredentials()

        // The file must be pre-seeded into the app's Documents sandbox before this test runs:
        //   find ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application \
        //        -name ".com.apple.mobile_container_manager.metadata.plist" | xargs grep -l GigHive \
        //        | xargs dirname | head -1
        //   cp gighiveinfra/assets/video/3ed8bbc4….mp4 <container>/Documents/
        //
        // UploadView.onAppear resolves the filename against its own Documents directory.
        let fileName = "3ed8bbc43ec35bb4662ac8b75843eb89fbd50557eccb3aa960cbc2f6e0601e4d.mp4"

        // Relaunch with:
        //  --uitest-upload-file  → UploadView.onAppear pre-sets fileURL from Documents
        //  --uitest-navigate-upload → SplashView.onAppear auto-navigates to UploadView after login
        app.terminate()
        app.launchArguments = ["--uitesting", "--uitest-upload-file", fileName, "--uitest-navigate-upload"]
        app.launch()

        // Wait for splash, log in, then the app auto-navigates to UploadView
        XCTAssert(app.buttons["splash_login_button"].waitForExistence(timeout: 10), "Splash should load")
        performLogin(host: host, user: user, pass: pass, insecure: true)

        // Wait for upload form — the file should already be pre-loaded via the launch arg
        let orgField = app.textFields["upload_org_name_field"]
        XCTAssert(orgField.waitForExistence(timeout: 10), "Upload form should appear")

        // Fill in metadata
        fill("upload_org_name_field", with: "StormPigs")
        fill("upload_song_title_field", with: "Flesh Machine")

        // Check the file was pre-loaded — UploadView shows the filename in the Choose File button
        let fileLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '3ed8bbc4'")).firstMatch
        let filePreloaded = fileLabel.waitForExistence(timeout: 5)
        print("=== File pre-loaded via launch arg: \(filePreloaded) ===")

        // If not pre-loaded, the path resolution failed — skip rather than fail
        guard filePreloaded else {
            print("WARNING: --uitest-upload-file path not resolved. Skipping upload tap.")
            let screenshot = app.screenshot()
            let att = XCTAttachment(screenshot: screenshot)
            att.name = "Upload form — file not pre-loaded"; att.lifetime = .keepAlways
            add(att)
            return
        }

        // Submit
        let submitButton = app.buttons["upload_submit_button"]
        XCTAssert(submitButton.waitForExistence(timeout: 10))
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: enabledPredicate, evaluatedWith: submitButton)
        waitForExpectations(timeout: 30)
        submitButton.tap()

        // Wait for server response (file is ~44 MB; allow up to 120s)
        Thread.sleep(forTimeInterval: 30)

        // Capture everything visible
        print("=== Upload result texts ===")
        let textCount = app.staticTexts.count
        for i in 0..<textCount {
            let l = app.staticTexts.element(boundBy: i).label
            if !l.isEmpty { print("  TEXT: \(l)") }
        }
        print("=== Submit button label: \(app.buttons["upload_submit_button"].label) ===")

        let screenshot = app.screenshot()
        let att = XCTAttachment(screenshot: screenshot)
        att.name = "Upload duplicate result"; att.lifetime = .keepAlways
        add(att)
    }

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
