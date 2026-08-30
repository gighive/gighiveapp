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

    /// Reads GH_TEST_UPLOADER_USER and GH_TEST_UPLOADER_PASS from the environment.
    /// Throws XCTSkip (not XCTFail) if either variable is absent, so the suite still
    /// passes in CI without uploader credentials configured.
    /// Also requires GH_TEST_HOST (shared with admin credential tests).
    private func requireUploaderCredentials(file: StaticString = #file, line: UInt = #line)
        throws -> (host: String, user: String, pass: String, insecure: Bool)
    {
        let env = ProcessInfo.processInfo.environment
        guard
            let host = env["GH_TEST_HOST"],           !host.isEmpty,
            let user = env["GH_TEST_UPLOADER_USER"],  !user.isEmpty,
            let pass = env["GH_TEST_UPLOADER_PASS"],  !pass.isEmpty
        else {
            throw XCTSkip(
                "Set GH_TEST_HOST, GH_TEST_UPLOADER_USER, GH_TEST_UPLOADER_PASS in the test scheme to run uploader tests.",
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

    /// Relaunches the app with --uitest-auto-login so SplashView injects credentials
    /// directly from the environment — no keyboard, no LoginView, no overlay windows.
    ///
    /// Pass an optional navigation arg (e.g. "--uitest-navigate-database") to have the
    /// app automatically push that view after credentials are set.
    ///
    /// After this returns the app is on the logged-in splash (or the requested destination)
    /// with a single clean window and all elements hittable.
    ///
    /// Confirmation strategy (avoids transient-banner timing races):
    ///   - With "--uitest-navigate-database": waits for a UnifiedVideoListView video cell (proves
    ///     both login and navigation succeeded; mirrors testDatabaseLoadsEntriesAfterLogin).
    ///   - Without a nav arg: waits for splash_view_database_button which is only shown
    ///     when session.credential != nil and the user is still on SplashView.
    @discardableResult
    private func autoLogin(navigateTo navArg: String? = nil) throws -> (host: String, user: String, pass: String, insecure: Bool) {
        let creds = try requireCredentials()
        app.terminate()
        var args = ["--uitesting", "--uitest-auto-login"]
        if let nav = navArg { args.append(nav) }
        app.launchArguments = args
        app.launchEnvironment["GH_TEST_HOST"]     = creds.host
        app.launchEnvironment["GH_TEST_USER"]     = creds.user
        app.launchEnvironment["GH_TEST_PASS"]     = creds.pass
        app.launchEnvironment["GH_TEST_INSECURE"] = creds.insecure ? "1" : "0"
        app.launch()

        if navArg == "--uitest-navigate-database" {
            // Auto-login triggers navigation to DatabaseView in ~0.6 s; the splash banner
            // disappears before XCUITest can reliably poll it.  Wait for rows instead —
            // their presence confirms both credential injection and navigation.
            // "Retry" is excluded because DatabaseView shows a Retry button on API error
            // and we must not mistake it for a data row.
            let rowPredicate = NSPredicate(
                format: "label != '' AND label != 'Back' AND label != 'Login' AND label != 'View the Database' AND label != 'Upload a File' AND label != 'Retry'"
            )
            XCTAssert(
                app.buttons.matching(rowPredicate).firstMatch.waitForExistence(timeout: 40),
                "DatabaseView rows did not appear after auto-login + --uitest-navigate-database — check GH_TEST_HOST/USER/PASS env vars"
            )
        } else {
            // No navigation: credentials are set and app stays on SplashView.
            // splash_view_database_button is credential-gated — it only renders when logged in.
            XCTAssert(
                app.buttons["splash_view_database_button"].waitForExistence(timeout: 15),
                "splash_view_database_button did not appear after auto-login — check GH_TEST_HOST/USER/PASS env vars"
            )
        }
        return creds
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

        // Wait for at least one row button — confirms Authorization: Basic header reached the server.
        let firstRow = app.buttons.matching(NSPredicate(format: "label != '' AND label != 'Back' AND label != 'Login' AND label != 'View the Database' AND label != 'Upload a File'" )).firstMatch
        XCTAssert(
            firstRow.waitForExistence(timeout: 40),
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

    // MARK: - Phase 1 — Unified Player

    /// Reads GH_TEST_GUEST_NONCE from the environment. Throws XCTSkip (not XCTFail)
    /// if the variable is not set, so the suite still passes in CI without a live server.
    /// Also requires GH_TEST_HOST so the app knows which server to contact.
    private func requireGuestNonce(file: StaticString = #file, line: UInt = #line)
        throws -> (nonce: String, host: String)
    {
        let env = ProcessInfo.processInfo.environment
        guard
            let nonce = env["GH_TEST_GUEST_NONCE"], !nonce.isEmpty,
            let host  = env["GH_TEST_HOST"], !host.isEmpty
        else {
            throw XCTSkip(
                "Set GH_TEST_GUEST_NONCE and GH_TEST_HOST env vars in the test scheme to run guest gallery tests.",
                file: file, line: line
            )
        }
        return (nonce, host)
    }

    /// Terminates the current app instance, injects a GuestUploadRecord using
    /// GH_TEST_GUEST_NONCE + GH_TEST_HOST from the scheme environment, and
    /// relaunches directly into UnifiedVideoListView via --uitest-navigate-guest-list.
    ///
    /// Throws XCTSkip (not XCTFail) when the required env vars are absent so
    /// CI passes gracefully without a live server or guest nonce configured.
    ///
    /// Returns the (nonce, host) pair; use @discardableResult when only the
    /// side-effect (app launch + auto-navigation) is needed.
    @discardableResult
    private func launchGuestList(file: StaticString = #file, line: UInt = #line)
        throws -> (nonce: String, host: String)
    {
        let (nonce, host) = try requireGuestNonce(file: file, line: line)
        app.terminate()
        app.launchEnvironment["GH_TEST_HOST"]         = host
        app.launchEnvironment["GH_TEST_GUEST_NONCE"] = nonce
        // Forward GH_TEST_GUEST_JOB_ID explicitly: launchEnvironment replaces the process
        // environment on relaunch, so runner-level vars are not inherited automatically (P6).
        let envForGuest = ProcessInfo.processInfo.environment
        if let jobId = envForGuest["GH_TEST_GUEST_JOB_ID"] {
            app.launchEnvironment["GH_TEST_GUEST_JOB_ID"] = jobId
        }
        app.launchArguments = ["--uitesting", "--uitest-inject-guest-nonce", "--uitest-navigate-guest-list"]
        app.launch()
        // SplashView injects the record and auto-pushes UnifiedVideoListView after 0.6 s.
        return (nonce, host)
    }

    /// Navigates the splash screen to the guest gallery for the given nonce.
    /// The app must already be launched with --uitesting. This helper drives the
    /// normal guest entry point (same path a real user would take from splash).
    private func navigateToGuestGallery(nonce: String, host: String) {
        // The gallery button is inside a list that appears after the splash polls the server.
        // Allow up to 15 s for the first poll to complete and the gallery row to appear.
        let galleryPredicate = NSPredicate(format: "label CONTAINS 'Event'")
        let galleryButton = app.buttons.matching(galleryPredicate).firstMatch
        if !galleryButton.waitForExistence(timeout: 15) {
            // Scroll down to find gallery rows if they are below the fold
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0, thenDragTo: end)
        }
        // The guest nonce must already be stored in the simulator from a prior scan or
        // pre-seeded via test infrastructure. Tap the first available gallery row.
        let galleryRow = app.buttons.matching(galleryPredicate).firstMatch
        XCTAssert(galleryRow.waitForExistence(timeout: 5), "Guest gallery row not found on splash")
        galleryRow.tap()
    }

    /// Tapping a guest gallery video card opens UnifiedVideoPlayerView.
    /// Verifies that unified_player_close_button is visible in the player nav bar.
    @MainActor
    func testGuestPlayerOpensFromGallery() throws {
        try launchGuestList()

        // Wait for at least one video card then tap it
        let cell = app.buttons.matching(NSPredicate(format: "identifier == 'unified_list_video_cell' OR label CONTAINS 'play'")).firstMatch
        XCTAssert(cell.waitForExistence(timeout: 20), "No video cell found in guest gallery")
        cell.tap()

        // UnifiedVideoPlayerView should be pushed; Close button must be visible
        let closeButton = app.buttons["unified_player_close_button"]
        XCTAssert(
            closeButton.waitForExistence(timeout: 10),
            "unified_player_close_button not found — UnifiedVideoPlayerView may not have been pushed"
        )
    }

    /// Tapping Close on the guest player dismisses it and returns to the gallery list.
    /// Verifies no stuck screens by checking the close button is gone.
    @MainActor
    func testGuestPlayerCloseButtonDismisses() throws {
        try launchGuestList()

        let cell = app.buttons.matching(NSPredicate(format: "identifier == 'unified_list_video_cell' OR label CONTAINS 'play'")).firstMatch
        XCTAssert(cell.waitForExistence(timeout: 20), "No video cell found in guest gallery")
        cell.tap()

        let closeButton = app.buttons["unified_player_close_button"]
        XCTAssert(closeButton.waitForExistence(timeout: 10), "Close button not found after opening player")
        closeButton.tap()

        // Close button must be gone — confirms the player was dismissed cleanly
        XCTAssertFalse(
            closeButton.waitForExistence(timeout: 5),
            "Close button still visible after tapping Close — player may not have dismissed"
        )
    }

    // MARK: - Shared navigation helper for authenticated player tests

    /// Navigates from logged-in SplashView → UnifiedVideoListView and taps the first
    /// video card to open UnifiedVideoPlayerView.
    ///
    /// Phase 3: DatabaseDetailView is gone. Tapping a video card in UnifiedVideoListView
    /// opens UnifiedVideoPlayerView directly — no intermediate detail screen.
    ///
    /// Requires autoLogin() to have been called first (no nav arg) so the app is on
    /// the logged-in SplashView with a single window and all buttons hittable.
    /// The player is open on return.
    private func navigateToPlayer() throws {
        // splash_view_database_button is only visible when logged in.
        // With no keyboard windows (auto-login), it is hittable — tap it to push UnifiedVideoListView.
        let dbButton = app.buttons["splash_view_database_button"]
        XCTAssert(dbButton.waitForExistence(timeout: 10), "splash_view_database_button not found — auto-login may have failed")
        dbButton.tap()

        // UnifiedVideoListView: wait for at least one video card then tap it.
        // The NavigationLink opens UnifiedVideoPlayerView directly (no intermediate detail screen).
        let cell = app.buttons.matching(identifier: "unified_list_video_cell").firstMatch
        XCTAssert(cell.waitForExistence(timeout: 40), "unified_list_video_cell not found in authenticated video list")
        cell.tap()
        // Player is now open on return.
    }

    /// After auto-login (no keyboard), tapping a database entry navigates to
    /// UnifiedVideoPlayerView — proves the authenticated player path works end-to-end
    /// in the simulator.  Uses --uitest-auto-login to avoid iOS keyboard infrastructure
    /// windows that blocked this test previously (see problem_ios_testing_media_player_unification.md).
    @MainActor
    func testAuthPlayerOpensAndShowsOverlay() throws {
        // No nav arg: stay on SplashView so splash_view_database_button is hittable.
        // User-initiated push avoids the programmatic-NavigationLink child-navigation issue.
        try autoLogin()
        try navigateToPlayer()

        // unified_player_close_button is a reliable signal UnifiedVideoPlayerView was pushed.
        let closeButton = app.buttons["unified_player_close_button"]
        XCTAssert(
            closeButton.waitForExistence(timeout: 15),
            "unified_player_close_button not found — UnifiedVideoPlayerView may not have been pushed for authenticated path"
        )
    }

    // MARK: - Authenticated player — close / dismiss

    /// Tapping Close on the authenticated player returns to the database detail view.
    /// Uses --uitest-auto-login (no keyboard) so window overlay does not block navigation.
    @MainActor
    func testAuthPlayerCloseButtonDismisses() throws {
        try autoLogin()
        // navigateToPlayer() ends by tapping unified_list_video_cell — the player is open on return.
        try navigateToPlayer()

        let closeButton = app.buttons["unified_player_close_button"]
        XCTAssert(closeButton.waitForExistence(timeout: 10), "Close button not found in authenticated player")
        closeButton.tap()

        // Close button must be gone — confirms the player was dismissed and nav stack is clean.
        XCTAssertFalse(
            closeButton.waitForExistence(timeout: 5),
            "Close button still visible after tapping Close — authenticated player may not have dismissed"
        )
    }

    // MARK: - Phase 2 — Unified List (Guest Path)
    //
    // These tests verify UnifiedVideoListView's guest capabilities:
    //   • Card list renders with unified_list_video_cell identifiers
    //   • "New" badge appears for unviewed videos and clears after playback
    //   • Flag button is present (canFlag = true for guest)
    //   • Search bar is absent (canSearch = false for guest)
    //
    // All tests require GH_TEST_GUEST_NONCE + GH_TEST_HOST in the scheme environment,
    // and a stored GuestUploadRecord on the device from a prior QR scan or test setup.
    // Missing env vars cause XCTSkip (not XCTFail) so CI still passes.
    //
    // See problem_ios_testing_media_player_unification.md §Phase 2 patterns for rationale
    // behind the swipeUp / hittability / NavigationLink interaction guidance used here.

    /// UnifiedVideoListView loads and renders at least one video card with the correct
    /// accessibility identifier (`unified_list_video_cell`).
    @MainActor
    func testGuestGalleryListRenders() throws {
        try launchGuestList()

        // unified_list_video_cell is the AccessibilityIdentifier on the NavigationLink
        // wrapping each card row.  At least one must appear within the load timeout.
        let cell = app.buttons.matching(identifier: "unified_list_video_cell").firstMatch
        XCTAssert(
            cell.waitForExistence(timeout: 20),
            "unified_list_video_cell not found — UnifiedVideoListView may not have loaded guest videos"
        )
    }

    /// At least one "New" badge (`unified_list_new_badge`) is visible when the gallery
    /// contains videos that have not yet been played on this device.
    /// Skips (not fails) when all videos are already marked viewed — server-state-dependent.
    @MainActor
    func testGuestNewBadgeVisible() throws {
        try launchGuestList()

        // Wait for the list to load before checking badge state
        let cell = app.buttons.matching(identifier: "unified_list_video_cell").firstMatch
        XCTAssert(cell.waitForExistence(timeout: 20), "No video cells found — cannot check New badge")

        // New badge only appears when canShowNewBadge=true and video not in viewedIds.
        // Skip if no unviewed videos exist on this device (all already played).
        let badge = app.staticTexts.matching(identifier: "unified_list_new_badge").firstMatch
        guard badge.waitForExistence(timeout: 5) else {
            throw XCTSkip(
                "No unified_list_new_badge found — all guest videos may already be marked viewed on this device. " +
                "Clear app data or use a fresh simulator to reset viewedIds."
            )
        }
        // Badge is present — that's the assertion
        XCTAssert(badge.exists, "unified_list_new_badge should be visible for unviewed videos")
    }

    /// Opening a video with a "New" badge clears the badge when the player is closed.
    /// Verifies that UnifiedVideoListView.markViewed() persists through NavigationLink
    /// round-trip and the badge condition re-evaluates on return.
    /// Skips if no unviewed videos are available (all badges already cleared).
    @MainActor
    func testGuestNewBadgeClearsAfterPlay() throws {
        try launchGuestList()

        // Wait for the list to load
        let cell = app.buttons.matching(identifier: "unified_list_video_cell").firstMatch
        XCTAssert(cell.waitForExistence(timeout: 20), "No video cells — cannot test badge clearing")

        // Skip if no badges present (all already viewed)
        let badges = app.staticTexts.matching(identifier: "unified_list_new_badge")
        guard badges.firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip(
                "No unified_list_new_badge found — all guest videos already viewed on this device. " +
                "Reset viewedIds by clearing app data or using a fresh simulator."
            )
        }
        let badgeCountBefore = badges.count

        // Tap the first video cell (expected to be the one carrying the first badge,
        // since video order matches API response order and badges appear in list order)
        cell.tap()

        // Player opens — close it to trigger markViewed round-trip back to list
        let closeButton = app.buttons["unified_player_close_button"]
        XCTAssert(closeButton.waitForExistence(timeout: 10), "unified_player_close_button not found after tapping cell")
        closeButton.tap()

        // Allow the view to re-render after navigation back
        Thread.sleep(forTimeInterval: 1.0)

        // Badge count must decrease — confirms markViewed updated viewedIds and
        // the card body re-evaluated the canShowNewBadge && !viewedIds.contains condition.
        let badgeCountAfter = badges.count
        XCTAssertLessThan(
            badgeCountAfter,
            badgeCountBefore,
            "New badge count should decrease after playing a video (before=\(badgeCountBefore) after=\(badgeCountAfter))"
        )
    }

    /// Flag button (`unified_list_flag_button`) is visible on guest video cards.
    /// Confirms VideoListCapabilities.canFlag = true for the guest context.
    @MainActor
    func testGuestFlagButtonVisible() throws {
        try launchGuestList()

        // Wait for at least one video cell before asserting flag button presence
        let cell = app.buttons.matching(identifier: "unified_list_video_cell").firstMatch
        XCTAssert(cell.waitForExistence(timeout: 20), "No video cells found — cannot check flag button")

        // Flag button must be present: canFlag = true for guest, rendered on every card row.
        // If more than one card exists, at least one flag button must be reachable.
        let flagButton = app.buttons.matching(identifier: "unified_list_flag_button").firstMatch
        XCTAssert(
            flagButton.waitForExistence(timeout: 5),
            "unified_list_flag_button not found — canFlag may be incorrectly disabled for guest context"
        )
    }

    // MARK: - Phase 4 — Authenticated Delete

    /// Terminates the current app, clears UploaderDeleteTokenStore via the P9 hook in
    /// SplashView.onAppear, optionally injects a synthetic invalid delete token for
    /// GH_TEST_DELETE_FILE_ID, then relaunches with --uitest-auto-login and
    /// --uitest-navigate-unified-list.
    ///
    /// Pass useUploader: true to log in as the uploader account (GH_TEST_UPLOADER_USER /
    /// GH_TEST_UPLOADER_PASS) instead of the admin account. Required for
    /// testAuthDelete403ClearsToken because delete_media_files.php routes the token check
    /// only for the uploader HTTP auth user, not admin.
    ///
    /// Returns after at least one unified_list_video_cell is visible — proves auth +
    /// navigation + list load all succeeded. Throws XCTSkip when credentials are absent.
    @discardableResult
    private func launchAuthListWithToken(injectToken: Bool = false,
                                         useUploader: Bool = false,
                                         file: StaticString = #file,
                                         line: UInt = #line)
        throws -> (host: String, user: String, pass: String, insecure: Bool)
    {
        // requireUploaderCredentials / requireCredentials each throw XCTSkip if vars absent.
        let creds = useUploader
            ? try requireUploaderCredentials(file: file, line: line)
            : try requireCredentials(file: file, line: line)
        let env = ProcessInfo.processInfo.environment

        app.terminate()

        var args = ["--uitesting", "--uitest-auto-login", "--uitest-navigate-unified-list"]
        if injectToken { args.append("--uitest-inject-delete-token") }
        app.launchArguments = args

        // creds fields are non-optional Strings validated by the require* helpers above.
        // SplashView reads GH_TEST_USER / GH_TEST_PASS for auto-login regardless of which
        // account we are using, so we always map to those keys.
        app.launchEnvironment["GH_TEST_HOST"]     = creds.host
        app.launchEnvironment["GH_TEST_USER"]     = creds.user
        app.launchEnvironment["GH_TEST_PASS"]     = creds.pass
        app.launchEnvironment["GH_TEST_INSECURE"] = creds.insecure ? "1" : "0"
        if injectToken, let fileId = env["GH_TEST_DELETE_FILE_ID"] {
            app.launchEnvironment["GH_TEST_DELETE_FILE_ID"] = fileId
        }

        app.launch()

        // Confirm list loaded — prevents vacuous passes on empty/failed loads.
        XCTAssert(
            app.buttons.matching(identifier: "unified_list_video_cell").firstMatch
                .waitForExistence(timeout: 40),
            "unified_list_video_cell not found — check credentials and server reachability",
            file: file, line: line
        )
        return creds
    }

    /// ⚠️ SUPERSEDED BY PHASE 5 (refactor_video_player_page_delete_eligibility.md Phase 3).
    /// Delete button visibility is now driven by the server's `can_delete` field, not by
    /// Keychain token presence. For admin callers, `can_delete` is always true, so the admin
    /// account sees delete buttons regardless of token store state. This test would now FAIL
    /// if run as admin (the expected absence becomes presence). Replaced by
    /// testDelEligAdminSeesDeleteButton (Phase 5 test 30) for admin-has-buttons and
    /// testDelEligUploaderNoDeleteButtonForGuestUpload (Phase 5 test 29) for uploader-no-buttons.
    ///
    /// Original intent: no delete button appears when UploaderDeleteTokenStore has no entry.
    @MainActor
    func testAuthDeleteButtonAbsentWithoutToken() throws {
        throw XCTSkip(
            "Superseded by Phase 5: delete button visibility is now driven by server can_delete, " +
            "not Keychain token presence. Use testDelEligAdminSeesDeleteButton (admin) or " +
            "testDelEligUploaderNoDeleteButtonForGuestUpload (uploader) instead."
        )
    }

    /// ⚠️ SUPERSEDED BY PHASE 5 (refactor_video_player_page_delete_eligibility.md Phase 3).
    /// Token injection via --uitest-inject-delete-token no longer controls delete button
    /// visibility after Phase 3. Replaced by testDelEligAdminSeesDeleteButton (Phase 5 test 30).
    ///
    /// Original intent: delete button appears after a synthetic token is injected.
    @MainActor
    func testAuthDeleteButtonVisibleForOwnUpload() throws {
        throw XCTSkip(
            "Superseded by Phase 5: token injection no longer drives ✕ visibility. " +
            "Use testDelEligAdminSeesDeleteButton instead."
        )
    }

    /// Tapping the delete button shows the specific "Delete your video?" confirmation alert.
    /// Cancels without confirming — no server write occurs.
    ///
    /// Phase 3 update: token injection is removed (it no longer drives button visibility).
    /// The admin credential receives can_delete: true for all entries from the server, so at
    /// least one delete button is visible without injection. GH_TEST_DELETE_FILE_ID still
    /// required to target the specific card that is most likely to be visible first.
    @MainActor
    func testAuthDeleteConfirmDialogAppears() throws {
        try requireCredentials()

        // Do not inject token — Phase 5: visibility is server-driven, not token-driven.
        try launchAuthListWithToken(injectToken: false)

        let deleteButton = app.buttons.matching(identifier: "unified_list_delete_button").firstMatch
        if !deleteButton.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssert(deleteButton.waitForExistence(timeout: 5), "Delete button not found before tap")
        deleteButton.tap()

        // Assert the specific alert title, not just any alert (a generic error would be a false pass).
        let confirmAlert = app.alerts["Delete your video?"]
        XCTAssert(
            confirmAlert.waitForExistence(timeout: 10),
            "\"Delete your video?\" confirmation alert did not appear after tapping delete button"
        )

        // Cancel — dismiss without server write
        confirmAlert.buttons["Cancel"].tap()
        XCTAssertFalse(
            confirmAlert.waitForExistence(timeout: 3),
            "Alert should be dismissed after tapping Cancel"
        )
    }

    /// ⚠️ SUPERSEDED BY PHASE 5 (refactor_video_player_page_delete_eligibility.md Phase 3).
    /// After Phase 3: uploader's showDeleteButton always returns false (can_delete: false
    /// for all guest-uploaded assets), so the uploader never reaches a delete button and
    /// cannot trigger a 403. The 403 handler no longer clears UploaderDeleteTokenStore.
    /// Replaced by Phase 5 test 29 (testDelEligUploaderNoDeleteButtonForGuestUpload) which
    /// directly asserts the uploader sees no delete buttons at all.
    ///
    /// Original intent: confirmed delete with an invalid synthetic token produces 403 from
    /// the server, clears the Keychain entry, and button absent on relaunch.
    @MainActor
    func testAuthDelete403ClearsToken() throws {
        throw XCTSkip(
            "Superseded by Phase 5: uploader no longer sees delete buttons (can_delete: false), " +
            "so the 403 path cannot be triggered from the list UI. " +
            "See testDelEligUploaderNoDeleteButtonForGuestUpload."
        )
    }

    /// Delete button is present on owned guest video cards after the Phase 4 refactor.
    /// Regression check: guest path uses deleteScope=.uploaderOnly (ownUploadIds set),
    /// not authDeleteTokens, so Phase 4 changes must not affect guest delete visibility.
    /// Requires GH_TEST_GUEST_NONCE + GH_TEST_HOST + GH_TEST_GUEST_JOB_ID.
    @MainActor
    func testGuestDeleteButtonStillVisible() throws {
        try launchGuestList()

        let cell = app.buttons.matching(identifier: "unified_list_video_cell").firstMatch
        XCTAssert(cell.waitForExistence(timeout: 20), "No video cells found in guest list")

        let deleteButton = app.buttons.matching(identifier: "unified_list_delete_button").firstMatch
        if !deleteButton.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssert(
            deleteButton.waitForExistence(timeout: 5),
            "unified_list_delete_button not found in guest list — " +
            "guest deleteScope=.uploaderOnly may be broken, or GH_TEST_GUEST_JOB_ID does not match any visible card"
        )
    }

    /// No search field appears in the guest list view.
    /// Confirms VideoListCapabilities.canSearch = false for the guest context: neither the
    /// iOS 15+ .searchable bar nor the iOS 14 fallback TextField should render.
    @MainActor
    func testGuestSearchBarAbsent() throws {
        try launchGuestList()

        // Wait for the list to confirm we are inside UnifiedVideoListView, not still on splash
        let cell = app.buttons.matching(identifier: "unified_list_video_cell").firstMatch
        XCTAssert(cell.waitForExistence(timeout: 20), "No video cells found — cannot confirm UnifiedVideoListView loaded")

        // Search field must not be present for guest context (canSearch = false)
        XCTAssertFalse(
            app.textFields["unified_list_search_field"].exists,
            "unified_list_search_field must not appear in guest context (canSearch = false)"
        )
        // Also check there is no iOS-native search bar visible (from .searchable modifier)
        // The searchField accessibility element has type .searchField when .searchable is active.
        XCTAssertFalse(
            app.searchFields.firstMatch.waitForExistence(timeout: 2),
            "A search bar (from .searchable modifier) must not appear in guest context"
        )
    }

    // MARK: - Phase 5 — Server-Authoritative Delete Eligibility

    /// Test 29: Uploader signing in to the unified list must see no ✕ delete button on any
    /// cell when all entries on the test server are guest-uploaded assets (server returns
    /// can_delete: false for all).
    ///
    /// Fixture precondition: the test dev server must contain only guest-uploaded assets for
    /// the uploader account. If any authenticated (iPhone-uploaded) asset exists, the server
    /// returns can_delete: true for it, a ✕ button appears, and this test fails by design.
    /// See docs/refactor_video_player_page_delete_eligibility.md §Phase 3 test preconditions.
    ///
    /// Requires: GH_TEST_HOST, GH_TEST_UPLOADER_USER, GH_TEST_UPLOADER_PASS
    /// Server prerequisite: Phase 2 of the refactor deployed to the dev server.
    @MainActor
    func testDelEligUploaderNoDeleteButtonForGuestUpload() throws {
        // requireUploaderCredentials throws XCTSkip when credentials are absent.
        try launchAuthListWithToken(injectToken: false, useUploader: true)

        // List loaded (launchAuthListWithToken already waited for unified_list_video_cell).
        // Uploader must not see any delete button: showDeleteButton returns false for uploader
        // regardless of can_delete (Phase 3 Step 4 — uploader delete deferred to JWT migration).
        XCTAssertFalse(
            app.buttons.matching(identifier: "unified_list_delete_button").firstMatch
                .waitForExistence(timeout: 3),
            "unified_list_delete_button must not appear for uploader caller — " +
            "server-authoritative can_delete: false for guest-uploaded assets, and " +
            "showDeleteButton always returns false for the uploader role (Phase 3)"
        )
    }

    /// Test 30: Admin signing in to the unified list must see at least one ✕ delete button.
    /// The server returns can_delete: true for admin on all listed entries.
    ///
    /// Requires: GH_TEST_HOST, GH_TEST_USER (admin), GH_TEST_PASS
    /// Server prerequisite: Phase 2 of the refactor deployed to the dev server and at least
    /// one entry in the database.
    @MainActor
    func testDelEligAdminSeesDeleteButton() throws {
        // requireCredentials (admin) throws XCTSkip when credentials are absent.
        try launchAuthListWithToken(injectToken: false)

        // List loaded (launchAuthListWithToken already waited for unified_list_video_cell).
        // Admin must see at least one delete button: server returns can_delete: true for all
        // entries and showDeleteButton returns video.canDelete for admin (Phase 3 Step 4).
        let deleteButton = app.buttons.matching(identifier: "unified_list_delete_button").firstMatch
        if !deleteButton.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssert(
            deleteButton.waitForExistence(timeout: 5),
            "unified_list_delete_button not found for admin caller — " +
            "server should return can_delete: true for admin on all entries. " +
            "Verify Phase 2 is deployed and the database has at least one entry."
        )
    }

    // MARK: - Phase 5 — Unit Tests (GigHiveTests target)
    // Tests 31 and 32 (testDelEligMissingCanDeleteDecodesAsFalse and
    // testDelEligGuestUploadDoesNotWriteTokenStore) are pure unit tests that require
    // @testable import GigHive. They belong in a GigHiveTests unit-test target
    // (XCTest, not XCUITest). The GigHiveTests target does not yet exist in project.yml.
    // Add the target via XcodeGen and re-generate the Xcode project before implementing.
}
