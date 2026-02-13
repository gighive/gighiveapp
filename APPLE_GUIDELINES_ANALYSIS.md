# Apple App Store Review Guidelines Analysis for GigHive

## Executive Summary

GigHive is an iOS app for uploading and viewing audio/video media files (primarily band/wedding event recordings). Based on analysis of Apple's App Store Review Guidelines, **GigHive appears generally compliant** but has **several areas requiring attention** before App Store submission.

---

## App Overview

**GigHive** enables users to:
- Upload audio/video files to a server (with metadata like band name, song title, event date, event type)
- View a database of uploaded media entries
- Play media in-app using AVPlayer
- Share media files
- Authenticate with BasicAuth credentials
- Support for Share Extension (upload from Photos/Files)

---

## Key Apple Guidelines & GigHive Compliance

### ✅ **1. SAFETY (Generally Compliant)**

#### 1.1 Objectionable Content
**Guideline:** Apps should not include offensive, discriminatory, or harmful content.

**GigHive Status:** ✅ **COMPLIANT**
- App facilitates music/event video sharing
- No inherent objectionable content in the app itself
- **ACTION REQUIRED:** Since users upload content, see User-Generated Content below

#### 1.2 User-Generated Content ⚠️
**Guideline:** Apps with user-generated content must include:
- A method for filtering objectionable material
- A mechanism to report offensive content and timely responses
- The ability to block abusive users
- Published contact information

**GigHive Status:** ⚠️ **NEEDS IMPLEMENTATION**

**Current State:**
- Users can upload audio/video files
- No visible content moderation system
- No reporting mechanism
- No user blocking capability
- No published contact information in app

**REQUIRED ACTIONS:**
1. **Add content moderation features:**
   - Implement a "Report Content" button in `DatabaseDetailView`
   - Add server-side endpoint to handle reports
   - Create admin moderation interface (can be web-based)
   - Add ability to block/remove inappropriate content

2. **Add contact information:**
   - Include developer contact email in app settings or about screen
   - Add privacy policy URL
   - Add terms of service URL

3. **Implement user blocking (if multi-user):**
   - If app supports multiple users uploading, add ability to block users
   - If single-user/organization-only, document this in App Review notes

**Code Changes Needed:**
```swift
// In DatabaseDetailView.swift - Add report button
Section {
    Button(action: { showReportSheet = true }) {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text("Report Inappropriate Content")
            Spacer()
        }
    }
    .foregroundColor(.red)
}

// Add new AboutView.swift with contact info
struct AboutView: View {
    var body: some View {
        List {
            Section("Contact") {
                Link("Email Support", destination: URL(string: "mailto:support@gighive.app")!)
                Link("Privacy Policy", destination: URL(string: "https://gighive.app/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://gighive.app/terms")!)
            }
        }
    }
}
```

---

### ✅ **2. PERFORMANCE (Compliant)**

#### 2.1 App Completeness
**Guideline:** Submit final versions with all metadata, functional URLs, and demo account info.

**GigHive Status:** ✅ **COMPLIANT**
- App appears complete and functional
- **ACTION REQUIRED:** Provide demo account credentials in App Review notes

**App Review Notes Template:**
```
Demo Account Credentials:
- Base URL: https://staging.gighive.app (or your demo server)
- Username: demo_reviewer
- Password: [secure password]

The app allows users to:
1. Login with BasicAuth credentials
2. Upload audio/video files with metadata
3. View uploaded media in a database
4. Play media in-app
5. Share media files

Note: The "Disable certificate checking" toggle is for development/testing only 
and will not be promoted to end users in production.
```

#### 2.3 Accurate Metadata
**Guideline:** App description, screenshots, and previews must accurately reflect core experience.

**GigHive Status:** ✅ **COMPLIANT** (assuming accurate App Store listing)
- Ensure App Store description clearly states it's for band/event media management
- Screenshots should show: login, upload, database view, media playback
- Don't oversell features or show features not yet implemented

---

### ⚠️ **3. BUSINESS (Needs Attention)**

#### 3.1.1 In-App Purchase
**Guideline:** If you unlock features or functionality within your app, you must use in-app purchase.

**GigHive Status:** ✅ **CURRENTLY COMPLIANT**
- App does not currently charge for features
- Authentication is for access control, not payment

**POTENTIAL FUTURE CONFLICT:**
If you plan to add any of these, you MUST use IAP:
- ❌ Paid subscriptions for storage/uploads
- ❌ Premium features (e.g., "Pro" tier with more storage)
- ❌ One-time purchases to unlock functionality
- ❌ External payment links to bypass App Store

**Exceptions that DON'T require IAP:**
- ✅ Enterprise/B2B sales (if sold directly to organizations, not individuals)
- ✅ Physical goods/services
- ✅ "Reader" app content purchased elsewhere (magazines, books, video streaming)

**RECOMMENDATION:**
- If monetizing, use StoreKit for subscriptions/purchases
- If B2B only, document in App Review notes: "Enterprise app sold directly to organizations"
- If free forever, no action needed

#### 3.1.3(a) Reader Apps
**Guideline:** Apps may allow access to previously purchased content (music, video) without IAP.

**GigHive Status:** ⚠️ **UNCLEAR**
- If GigHive is for viewing user's own uploaded content → ✅ OK
- If GigHive sells access to a media library → ⚠️ May need IAP or Reader app classification

**CLARIFICATION NEEDED:**
Is GigHive:
1. A personal media library (users upload their own content)? → ✅ No IAP needed
2. A content marketplace (users buy access to others' content)? → ⚠️ Needs IAP
3. A subscription service for media access? → ⚠️ Needs IAP

---

### ✅ **4. DESIGN (Compliant)**

#### 4.2 Minimum Functionality
**Guideline:** App should not be just a repackaged website.

**GigHive Status:** ✅ **COMPLIANT**
- Native SwiftUI interface
- In-app media playback with AVPlayer
- Native file picker and upload
- Not a web wrapper

#### 4.2.3 Standalone Functionality
**Guideline:** App should work without requiring another app.

**GigHive Status:** ✅ **COMPLIANT**
- Standalone iOS app
- Share Extension is optional enhancement, not required

---

### ⚠️ **5. LEGAL (Needs Attention)**

#### 5.1.1 Privacy - Data Collection
**Guideline:** Apps must have a privacy policy and clearly disclose data collection.

**GigHive Status:** ⚠️ **NEEDS IMPLEMENTATION**

**REQUIRED ACTIONS:**
1. **Create Privacy Policy:**
   - What data is collected: uploaded files, metadata (band name, date, etc.), user credentials
   - How data is used: stored on server, displayed in app
   - Who has access: authenticated users
   - Data retention: how long files are kept
   - User rights: how to delete data

2. **Add Privacy Policy URL to App Store Connect**

3. **Add Privacy Manifest (PrivacyInfo.xcprivacy):**
   - Required for apps that collect data
   - Declare what data types are collected
   - Declare what APIs are used (e.g., file access, network)

**Sample PrivacyInfo.xcprivacy:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeAudioData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePhotosorVideos</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

#### 5.1.1(v) Account Sign-In
**Guideline:** If app doesn't include significant account-based features, let people use it without login. Must offer account deletion within the app.

**GigHive Status:** ⚠️ **NEEDS CLARIFICATION**

**Current State:**
- App requires login to function
- No account deletion feature visible

**REQUIRED ACTIONS:**
1. **Justify login requirement:**
   - If login is required for core functionality (uploading to private server), document in App Review notes
   - Login appears justified since app manages private media library

2. **Add account deletion (if users can create accounts):**
   - If users create accounts on your server → MUST add "Delete Account" in app
   - If only admin creates accounts → document in App Review notes

**Code to Add (if needed):**
```swift
// In LoginView or SettingsView
Section("Account Management") {
    Button("Delete My Account", role: .destructive) {
        showDeleteConfirmation = true
    }
}
.confirmationDialog("Delete Account?", isPresented: $showDeleteConfirmation) {
    Button("Delete Account and All Data", role: .destructive) {
        Task { await deleteAccount() }
    }
}
```

#### 5.1.2 Data Use and Sharing
**Guideline:** Cannot use/share personal data without permission. Must disclose third-party sharing.

**GigHive Status:** ✅ **APPEARS COMPLIANT**
- No evidence of third-party analytics or ad SDKs
- No data sharing visible in code
- **ACTION REQUIRED:** Confirm no third-party SDKs are used, or disclose them

---

## Critical Issues Summary

### ✅ **ALREADY COMPLETED**

1. **Privacy Policy (5.1.1)** ✅
   - ✅ Privacy policy exists at https://gighive.app/privacy
   - ✅ Contact email provided: contactus@gighive.app
   - ⚠️ **NEEDS:** Privacy Manifest (PrivacyInfo.xcprivacy) in Xcode project
   - ⚠️ **NEEDS:** Add privacy URL to App Store Connect during submission

2. **Content Policy** ✅
   - ✅ Content policy exists at https://gighive.app/gighive_content_policy.html
   - ✅ Copyright email provided: copyright@gighive.app
   - ✅ Prohibited content guidelines documented

3. **Contact Information** ✅
   - ✅ Contact email: contactus@gighive.app (on homepage)
   - ✅ Copyright email: copyright@gighive.app (in content policy)

4. **Software Licenses** ✅
   - ✅ MIT License at https://gighive.app/LICENSE_MIT.html
   - ✅ AGPL v3 License at https://gighive.app/LICENSE_AGPLv3.html
   - ✅ Commercial License at https://gighive.app/LICENSE_COMMERCIAL.html
   - ℹ️ Note: These are software licenses, not app Terms of Service (see below)

### 🔴 **MUST FIX Before Submission**

4. **User-Generated Content Moderation - In-App Features (1.2)**
   - ⚠️ **NEEDS:** Add "Report Content" button in DatabaseDetailView
   - ⚠️ **NEEDS:** Add "About" screen in app linking to policies
   - ⚠️ **NEEDS:** Server endpoint to handle content reports (api/report.php)
   - ✅ Contact info exists (just needs to be linked from app)
   - ✅ Content policy exists (just needs to be linked from app)

5. **Privacy Manifest (5.1.1)**
   - ⚠️ **NEEDS:** Add PrivacyInfo.xcprivacy file to Xcode project
   - ⚠️ **NEEDS:** Declare data collection types (audio, video, photos)
   - ⚠️ **NEEDS:** Declare API usage reasons

6. **Account Deletion (5.1.1(v))**
   - ⚠️ **NEEDS:** Add account deletion feature in app (if users can create accounts)
   - ⚠️ **OR:** Document in App Review notes that only admins create accounts

7. **App Terms of Service**
   - ⚠️ **NEEDS:** Create app-specific terms at https://gighive.app/terms.html
   - ℹ️ Note: You have software licenses (MIT/AGPL/Commercial) but Apple expects app usage terms
   - ℹ️ App ToS covers user behavior, account rules, liability - different from software licensing

### 🟡 **RECOMMENDED Before Submission**

8. **Demo Account for Reviewers (2.1)**
   - ⚠️ **NEEDS:** Provide working demo credentials in App Review notes
   - ⚠️ **NEEDS:** Ensure demo server is accessible during review

9. **App Store Metadata (2.3)**
   - ⚠️ **NEEDS:** Accurate description of app functionality
   - ⚠️ **NEEDS:** Screenshots showing all main features
   - ⚠️ **NEEDS:** Clear explanation this is for band/event media management

10. **TLS Certificate Toggle**
   - ⚠️ **NEEDS:** "Disable certificate checking" should not be visible in production
   - ⚠️ **NEEDS:** Remove or hide behind debug menu
   - Apple may question security implications

### 🟢 **OPTIONAL / FUTURE**

11. **Monetization Strategy**
   - If adding paid features → use StoreKit IAP
   - If B2B only → document in App Review notes
   - If free forever → no action needed

---

## Specific Code Changes Required

### 1. Add Privacy Manifest
**File:** `GigHive/PrivacyInfo.xcprivacy` (create new)
- Declare data collection types
- Declare API usage reasons
- See sample above

### 2. Add Contact/About View
**File:** `GigHive/Sources/App/AboutView.swift` (create new)
```swift
import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section("Support") {
                Link("Email Support", destination: URL(string: "mailto:support@gighive.app")!)
                Link("Privacy Policy", destination: URL(string: "https://gighive.app/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://gighive.app/terms")!)
            }
            
            Section("App Information") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("About")
    }
}
```

### 3. Add Report Content Feature
**File:** `GigHive/Sources/App/DatabaseDetailView.swift` (modify)
```swift
// Add state variable
@State private var showReportSheet = false
@State private var reportReason = ""

// Add to body in a new Section
Section {
    Button(action: { showReportSheet = true }) {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text("Report Inappropriate Content")
            Spacer()
        }
    }
    .foregroundColor(.red)
}
.sheet(isPresented: $showReportSheet) {
    ReportContentView(entry: entry, onSubmit: { reason in
        Task { await submitReport(reason) }
    })
}

// Add report submission function
private func submitReport(_ reason: String) async {
    // Send report to server
    guard let baseURL = session.baseURL else { return }
    let reportURL = baseURL.appendingPathComponent("api/report.php")
    
    var request = URLRequest(url: reportURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let reportData = [
        "entry_id": entry.id,
        "reason": reason,
        "reported_at": ISO8601DateFormatter().string(from: Date())
    ]
    
    request.httpBody = try? JSONEncoder().encode(reportData)
    
    // Add BasicAuth if available
    if let auth = session.credentials {
        let credentials = "\(auth.user):\(auth.pass)"
        let base64 = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
    }
    
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            logWithTimestamp("[Detail] Report submitted successfully")
        }
    } catch {
        logWithTimestamp("[Detail] Report submission failed: \(error)")
    }
}
```

### 4. Add Account Deletion (if applicable)
**File:** `GigHive/Sources/App/LoginView.swift` or create `SettingsView.swift`
```swift
Section("Account Management") {
    Button("Delete My Account", role: .destructive) {
        showDeleteConfirmation = true
    }
}
.confirmationDialog(
    "Delete Account?",
    isPresented: $showDeleteConfirmation,
    titleVisibility: .visible
) {
    Button("Delete Account and All Data", role: .destructive) {
        Task { await deleteAccount() }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This will permanently delete your account and all uploaded media. This action cannot be undone.")
}

private func deleteAccount() async {
    // Implement account deletion API call
    guard let baseURL = session.baseURL,
          let credentials = session.credentials else { return }
    
    let deleteURL = baseURL.appendingPathComponent("api/delete_account.php")
    var request = URLRequest(url: deleteURL)
    request.httpMethod = "DELETE"
    
    let authString = "\(credentials.user):\(credentials.pass)"
    let base64 = Data(authString.utf8).base64EncodedString()
    request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
    
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            // Clear session and return to login
            session.credentials = nil
            session.baseURL = nil
            logWithTimestamp("[Account] Account deleted successfully")
        }
    } catch {
        logWithTimestamp("[Account] Deletion failed: \(error)")
    }
}
```

### 5. Hide/Remove Certificate Bypass Toggle in Production
**File:** `GigHive/Sources/App/LoginView.swift`
```swift
// Option 1: Remove entirely for production
// Comment out or delete the toggle

// Option 2: Hide behind debug flag
#if DEBUG
Toggle("Disable certificate checking", isOn: $disableCertChecking)
    .foregroundColor(.orange)
#endif

// Option 3: Hide behind secret gesture (tap logo 7 times)
@State private var logoTapCount = 0
@State private var showAdvancedSettings = false

// In body:
TitleHeaderView()
    .onTapGesture {
        logoTapCount += 1
        if logoTapCount >= 7 {
            showAdvancedSettings = true
            logoTapCount = 0
        }
    }

if showAdvancedSettings {
    Toggle("⚠️ Disable certificate checking (DEBUG)", isOn: $disableCertChecking)
        .foregroundColor(.orange)
}
```

---

## Server-Side Requirements

To fully comply with guidelines, your backend needs:

### 1. Content Reporting Endpoint
**File:** `api/report.php` (create new)
```php
<?php
// Handle content reports
// Store in database with: entry_id, reason, reporter, timestamp
// Send notification to admin
// Return 200 OK
```

### 2. Account Deletion Endpoint (if applicable)
**File:** `api/delete_account.php` (create new)
```php
<?php
// Verify authentication
// Delete user account and all associated media
// Return 200 OK
```

### 3. Privacy Policy & Terms Pages
**Files:** `privacy.html`, `terms.html` (create new)
- Host at `https://gighive.app/privacy` and `https://gighive.app/terms`
- Or use your actual domain

---

## App Review Notes Template

When submitting to App Store, include these notes:

```
GigHive - Band & Event Media Manager

DEMO ACCOUNT:
- Base URL: https://demo.gighive.app
- Username: app_reviewer
- Password: [secure password]

DESCRIPTION:
GigHive is a media management app for bands and event organizers to upload, 
organize, and share audio/video recordings from performances and events.

FEATURES:
1. Secure login with BasicAuth
2. Upload audio/video files with metadata (band name, song title, event date)
3. Browse uploaded media in searchable database
4. In-app media playback
5. Share media files
6. Share Extension for quick uploads from Photos

USER-GENERATED CONTENT MODERATION:
- Users can report inappropriate content via "Report" button in detail view
- Reports are sent to admin email: moderation@gighive.app
- Admin can remove content via web dashboard at: https://gighive.app/admin
- Contact email for users: support@gighive.app

PRIVACY:
- Privacy Policy: https://gighive.app/privacy
- Terms of Service: https://gighive.app/terms
- No third-party analytics or advertising
- No data sharing with third parties

ACCOUNT MANAGEMENT:
- Users can delete their account via Settings > Delete Account
- [OR if admin-only: "Accounts are created by organization admins only, 
  not by end users. Individual users cannot create accounts."]

BUSINESS MODEL:
- Free app for personal/organizational use
- No in-app purchases
- No subscriptions
- [OR if B2B: "Enterprise app sold directly to organizations"]

NOTES:
- The "Disable certificate checking" toggle is for development/testing only 
  and is hidden in production builds
- App requires network connection to function (uploads to private server)
```

---

## Compliance Checklist

Before submitting to App Store:

- [ ] **Privacy Policy created and published**
- [ ] **Privacy Manifest (PrivacyInfo.xcprivacy) added to Xcode project**
- [ ] **Privacy Policy URL added to App Store Connect**
- [ ] **Terms of Service created and published**
- [ ] **Contact email added to app (About/Settings screen)**
- [ ] **"Report Content" feature implemented**
- [ ] **Server endpoint for handling reports created**
- [ ] **Account deletion feature added (or justified why not needed)**
- [ ] **Demo account credentials prepared for App Review notes**
- [ ] **Demo server is accessible and functional**
- [ ] **Certificate bypass toggle removed or hidden in production**
- [ ] **App Store description accurately describes functionality**
- [ ] **Screenshots show all main features**
- [ ] **No third-party analytics/ads (or disclosed if present)**
- [ ] **App tested on device (not just simulator)**
- [ ] **All features functional and bug-free**
- [ ] **App Review notes prepared with all required information**

---

## Risk Assessment

### Low Risk ✅
- Core app functionality (upload, view, play media)
- Native SwiftUI design
- No monetization conflicts
- No kids/health/gambling content

### Medium Risk ⚠️
- User-generated content (requires moderation features)
- Privacy policy requirement
- Account management requirements

### High Risk 🔴
- **If you add paid features without IAP** → Rejection likely
- **If no content moderation** → May be rejected under 1.2
- **If no privacy policy** → Will be rejected under 5.1.1

---

## Recommendations

### Immediate (Before First Submission)
1. ✅ Add privacy policy and manifest
2. ✅ Add content reporting feature
3. ✅ Add contact information in app
4. ✅ Prepare demo account
5. ✅ Hide/remove cert bypass toggle

### Short-term (Next Update)
6. ✅ Add account deletion feature
7. ✅ Add terms of service
8. ✅ Implement server-side moderation tools
9. ✅ Add app version/about screen

### Long-term (Future Enhancements)
10. ✅ If monetizing, implement StoreKit IAP
11. ✅ Consider adding user profiles/social features (with proper moderation)
12. ✅ Add analytics (with privacy disclosure)

---

---

## UPDATED ACTION PLAN (Based on Existing Documentation)

### ✅ What You've Already Done

**Documentation (https://gighive.app/):**
- ✅ Privacy Policy at `/privacy`
- ✅ Content Policy at `/gighive_content_policy.html`
- ✅ Contact emails: contactus@gighive.app, copyright@gighive.app
- ✅ Prohibited content guidelines
- ✅ Copyright infringement reporting process

**Great work!** This covers ~40% of Apple's requirements. Now here's what's left:

---

### 🔴 CRITICAL: Must Complete Before Submission

#### 1. **Create App Terms of Service Page** (1-2 hours)
**What:** Create https://gighive.app/terms.html

**Why:** Apple requires both Privacy Policy AND Terms of Service for app usage

**Note:** You already have software licenses (MIT/AGPL/Commercial), but Apple wants app-specific terms covering user behavior, not just software licensing.

**Content Template:**
```markdown
# GigHive iOS App - Terms of Service
Last updated: December 2025

## 1. Acceptance of Terms
By downloading and using the GigHive iOS app, you agree to these Terms of Service.

## 2. About GigHive
GigHive is a self-hosted media management platform. The iOS app is a client 
that connects to your own GigHive server instance. Each server is independently 
operated and not controlled by the GigHive project.

## 3. User Responsibilities
When using the GigHive iOS app, you agree to:
- Only upload content you own or have permission to share
- Comply with all applicable copyright and intellectual property laws
- Not upload prohibited content (see our Content Policy)
- Not use the app for illegal purposes
- Maintain the security of your login credentials

## 4. Account Management
- Accounts are created and managed by your server administrator
- You are responsible for keeping your credentials secure
- To delete your account, contact your server administrator
- The GigHive project does not control or manage user accounts

## 5. Content Policy
All uploaded content must comply with our Content Policy:
https://gighive.app/gighive_content_policy.html

Prohibited content includes:
- Copyright-infringing material
- Illegal, defamatory, or explicit material
- Content encouraging violence or harassment
- Private information without consent

## 6. Server Operator Responsibility
The GigHive iOS app connects to independently operated servers. The GigHive 
project is not responsible for:
- Content hosted on third-party servers
- Server availability or performance
- Data loss or security breaches on third-party servers
- Actions taken by server administrators

## 7. Limitation of Liability
THE APP IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND. The GigHive project 
is not liable for any damages arising from use of the app, including but not 
limited to data loss, service interruptions, or content disputes.

## 8. Changes to Terms
We may update these Terms of Service at any time. Continued use of the app 
after changes constitutes acceptance of the updated terms.

## 9. Software License
The GigHive software is open source. For software licensing terms, see:
- MIT License: https://gighive.app/LICENSE_MIT.html
- AGPL v3 License: https://gighive.app/LICENSE_AGPLv3.html
- Commercial License: https://gighive.app/LICENSE_COMMERCIAL.html

## 10. Contact
For questions about these Terms of Service:
- Email: contactus@gighive.app
- Copyright issues: copyright@gighive.app

## 11. Governing Law
These terms are governed by applicable laws in your jurisdiction.
```

**Action:** Create this file and deploy to gighive.app

---

#### 2. **Add Privacy Manifest to iOS App** (30 minutes)
**What:** Create `GigHive/PrivacyInfo.xcprivacy` in Xcode

**Why:** Required by Apple for all apps that access user data

**Action:** Use the code sample from earlier in this document (section "1. Add Privacy Manifest")

**Steps:**
1. In Xcode: File > New > File
2. Search for "App Privacy"
3. Create "PrivacyInfo.xcprivacy"
4. Replace contents with the XML from this document
5. Ensure it's included in the GigHive app target

---

#### 3. **Add About Screen in iOS App** (1-2 hours)
**What:** Create `AboutView.swift` that links to your policies

**Why:** Apple requires in-app access to contact info and policies

**Action:**
```swift
// GigHive/Sources/App/AboutView.swift
import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section("Policies") {
                Link(destination: URL(string: "https://gighive.app/privacy")!) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                
                Link(destination: URL(string: "https://gighive.app/terms.html")!) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                        Text("Terms of Service")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                
                Link(destination: URL(string: "https://gighive.app/gighive_content_policy.html")!) {
                    HStack {
                        Image(systemName: "exclamationmark.shield.fill")
                        Text("Content Policy")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
            
            Section("Contact") {
                Link(destination: URL(string: "mailto:contactus@gighive.app")!) {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Email Support")
                        Spacer()
                        Text("contactus@gighive.app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Link(destination: URL(string: "mailto:copyright@gighive.app")!) {
                    HStack {
                        Image(systemName: "c.circle.fill")
                        Text("Report Copyright Issue")
                        Spacer()
                        Text("copyright@gighive.app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("App Information") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

**Then add to SplashView or LoginView:**
```swift
// In SplashView.swift or create a settings button
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        NavigationLink(destination: AboutView()) {
            Image(systemName: "info.circle")
        }
    }
}
```

---

#### 4. **Add Report Content Feature** (2-3 hours)
**What:** Add "Report Content" button in `DatabaseDetailView.swift`

**Why:** Required for user-generated content apps (Guideline 1.2)

**Action:** Use the code from "3. Add Report Content Feature" section earlier in this document

**Key parts:**
- Add report button in DatabaseDetailView
- Create report submission function
- Send to server endpoint (see #5 below)

---

#### 5. **Create Server Report Endpoint** (1-2 hours)
**What:** Create `api/report.php` on your server

**Why:** Handle content reports from the app

**Sample Code:**
```php
<?php
// api/report.php
header('Content-Type: application/json');

// Verify authentication
if (!isset($_SERVER['PHP_AUTH_USER'])) {
    http_response_code(401);
    echo json_encode(['error' => 'Authentication required']);
    exit;
}

// Get report data
$input = json_decode(file_get_contents('php://input'), true);

if (!isset($input['entry_id']) || !isset($input['reason'])) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing required fields']);
    exit;
}

// Log the report (you can also email yourself)
$logFile = '/var/log/gighive/content_reports.log';
$logEntry = sprintf(
    "[%s] User: %s | Entry ID: %d | Reason: %s\n",
    date('Y-m-d H:i:s'),
    $_SERVER['PHP_AUTH_USER'],
    $input['entry_id'],
    $input['reason']
);
file_put_contents($logFile, $logEntry, FILE_APPEND);

// Optional: Send email notification
mail(
    'copyright@gighive.app',
    'Content Report - Entry #' . $input['entry_id'],
    "User {$_SERVER['PHP_AUTH_USER']} reported:\n\n{$input['reason']}\n\nEntry ID: {$input['entry_id']}",
    'From: noreply@gighive.app'
);

http_response_code(200);
echo json_encode(['success' => true, 'message' => 'Report submitted']);
?>
```

---

#### 6. **Account Deletion Feature OR Documentation** (1-2 hours)

**Option A: If users can create their own accounts**
- Add "Delete Account" button in app (use code from earlier section)
- Create server endpoint `api/delete_account.php`

**Option B: If only admins create accounts (RECOMMENDED)**
- Document in App Review notes:
  ```
  ACCOUNT MANAGEMENT:
  GigHive is a self-hosted platform where accounts are created and managed 
  by server administrators only. End users cannot create accounts themselves. 
  Users who wish to delete their account should contact their server 
  administrator at the contact email provided in the app.
  ```

**Which to choose?** If your current setup is admin-only account creation, choose Option B (just documentation).

---

#### 7. **Hide Certificate Bypass Toggle** (15 minutes)
**What:** Hide "Disable certificate checking" in production builds

**Why:** Apple may reject apps with visible security bypasses

**Action in LoginView.swift:**
```swift
// Replace the toggle with:
#if DEBUG
Toggle("⚠️ Disable certificate checking (DEBUG)", isOn: $disableCertChecking)
    .foregroundColor(.orange)
#endif
```

**Or use secret gesture (tap logo 7 times):**
```swift
@State private var logoTapCount = 0
@State private var showDebugSettings = false

TitleHeaderView()
    .onTapGesture {
        logoTapCount += 1
        if logoTapCount >= 7 {
            showDebugSettings = true
            logoTapCount = 0
        }
    }

if showDebugSettings {
    Toggle("⚠️ Disable certificate checking (DEBUG)", isOn: $disableCertChecking)
        .foregroundColor(.orange)
}
```

---

### 🟡 RECOMMENDED: Complete Before Submission

#### 8. **Prepare Demo Account** (15 minutes)
**What:** Create test credentials for Apple reviewers

**Action:**
1. Set up demo server (staging.gighive.app or similar)
2. Create account: `app_reviewer` / `[secure password]`
3. Pre-populate with sample media (3-5 videos/audio files)
4. Document in App Review notes (template below)

---

#### 9. **App Store Metadata** (1-2 hours)
**What:** Prepare App Store listing

**Required:**
- App name: "GigHive - Band Media Manager" (or similar)
- Subtitle: "Upload and organize band recordings"
- Description: Clear explanation of features
- Keywords: band, music, video, audio, recording, gig, performance
- Screenshots: Login, Upload, Database, Detail, Playback (5-10 screenshots)
- Privacy URL: https://gighive.app/privacy

---

### 📋 COMPLETE CHECKLIST

**Documentation (Website):**
- [x] Privacy Policy at https://gighive.app/privacy
- [x] Content Policy at https://gighive.app/gighive_content_policy.html
- [x] Contact emails (contactus@, copyright@)
- [ ] **Terms of Service at https://gighive.app/terms.html** ← CREATE THIS

**iOS App Code:**
- [ ] **Add PrivacyInfo.xcprivacy to Xcode project** ← CREATE THIS
- [ ] **Add AboutView.swift with policy links** ← CREATE THIS
- [ ] **Add Report button in DatabaseDetailView** ← CREATE THIS
- [ ] **Hide certificate bypass toggle** ← MODIFY LoginView.swift
- [ ] Add account deletion OR document admin-only accounts

**Server Code:**
- [ ] **Create api/report.php endpoint** ← CREATE THIS
- [ ] Create api/delete_account.php (if needed)

**App Store Submission:**
- [ ] Prepare demo account credentials
- [ ] Write App Store description
- [ ] Take screenshots (5-10)
- [ ] Add privacy URL in App Store Connect
- [ ] Write App Review notes (template below)

---

### 📝 APP REVIEW NOTES TEMPLATE

```
GigHive - Self-Hosted Band Media Manager

DEMO ACCOUNT:
Base URL: https://staging.gighive.app
Username: app_reviewer
Password: [your secure password]

DESCRIPTION:
GigHive is a self-hosted media management app for musicians and event 
organizers. Users connect to their own server to upload, organize, and 
share audio/video recordings from performances.

KEY FEATURES:
1. Secure authentication (BasicAuth)
2. Upload audio/video with metadata (band, song, date)
3. Browse searchable media database
4. In-app playback (AVPlayer)
5. Share media files
6. Share Extension for Photos integration

USER-GENERATED CONTENT MODERATION:
- Users can report inappropriate content via "Report" button
- Reports sent to: copyright@gighive.app
- Content Policy: https://gighive.app/gighive_content_policy.html
- Server admins can remove content via admin interface

PRIVACY & POLICIES:
- Privacy Policy: https://gighive.app/privacy
- Terms of Service: https://gighive.app/terms.html
- Content Policy: https://gighive.app/gighive_content_policy.html
- Contact: contactus@gighive.app

ACCOUNT MANAGEMENT:
Accounts are created by server administrators only. End users cannot 
create accounts themselves. Users can request account deletion by 
contacting their server administrator via the contact email in the app.

BUSINESS MODEL:
Free, open-source app. No in-app purchases. No subscriptions.
Self-hosted infrastructure (user provides their own server).

TECHNICAL NOTES:
- App requires network connection to user's server
- No third-party analytics or advertising
- No data collected by GigHive project (all data on user's server)
- Certificate bypass toggle is hidden in production (DEBUG builds only)
```

---

## UPDATED TIME ESTIMATES

**Critical (Must Do):**
1. Terms of Service page: 1-2 hours
2. Privacy Manifest: 30 minutes
3. About screen in app: 1-2 hours
4. Report content feature: 2-3 hours
5. Server report endpoint: 1-2 hours
6. Account deletion docs: 30 minutes
7. Hide cert toggle: 15 minutes

**Subtotal: 6.5-10.5 hours**

**Recommended:**
8. Demo account setup: 15 minutes
9. App Store metadata: 1-2 hours

**Subtotal: 1.25-2.25 hours**

**TOTAL: 8-13 hours of work**

---

## Conclusion

**GigHive is fundamentally App Store compliant** and you've already done great work on documentation!

**What's Done:**
- ✅ Privacy policy
- ✅ Content policy  
- ✅ Contact emails
- ✅ Core app functionality

**What's Left:**
- 🔴 Terms of Service (1-2 hours)
- 🔴 Privacy Manifest in Xcode (30 min)
- 🔴 About screen in app (1-2 hours)
- 🔴 Report content feature (2-3 hours)
- 🔴 Server report endpoint (1-2 hours)
- 🔴 Hide cert toggle (15 min)

**Total remaining: ~8-13 hours**

Once these are complete, GigHive should pass App Review without issues.

---

## Questions or Next Steps?

I can help you with:
1. Creating the Terms of Service page content
2. Implementing any of the iOS code changes
3. Writing the server-side report endpoint
4. Preparing App Store screenshots and description
5. Reviewing your App Review notes before submission

What would you like to tackle first?
