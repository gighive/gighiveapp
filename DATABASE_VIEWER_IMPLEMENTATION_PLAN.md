# GigHive Database Viewer Implementation Plan

## Overview
Convert the "View in Database" button from opening external browser to displaying a native iPhone SwiftUI view that consumes the GigHive web server API.

---

## Phase 1: Server-Side Changes (PHP Repository)

### Goal
Add JSON output capability to existing `/db/database.php` endpoint without breaking HTML functionality.

### Changes Required

#### 1.1 Modify `src/Controllers/MediaController.php`

**Add new method after the existing `list()` method:**

```php
/**
 * Return media list as JSON instead of HTML
 */
public function listJson(): Response
{
    $rows = $this->repo->fetchMediaList();

    $counter = 1;
    $entries = [];
    foreach ($rows as $row) {
        $id        = isset($row['id']) ? (int)$row['id'] : 0;
        $date      = (string)($row['date'] ?? '');
        $orgName   = (string)($row['org_name'] ?? '');
        $duration  = self::secondsToHms(isset($row['duration_seconds']) ? (string)$row['duration_seconds'] : '');
        $durationSec = isset($row['duration_seconds']) && $row['duration_seconds'] !== null
            ? (int)$row['duration_seconds']
            : 0;
        $songTitle = (string)($row['song_title'] ?? '');
        $typeRaw   = (string)($row['file_type'] ?? '');
        $file      = (string)($row['file_name'] ?? '');

        $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
        $dir = ($ext === 'mp3') ? '/audio' : (($ext === 'mp4') ? '/video' : '');
        if ($dir === '' && ($typeRaw === 'audio' || $typeRaw === 'video')) {
            $dir = '/' . $typeRaw;
        }
        $url = ($dir && $file) ? $dir . '/' . rawurlencode($file) : '';

        $entries[] = [
            'id'               => $id,
            'index'            => $counter++,
            'date'             => $date,
            'org_name'         => $orgName,
            'duration'         => $duration,
            'duration_seconds' => $durationSec,
            'song_title'       => $songTitle,
            'file_type'        => $typeRaw,
            'file_name'        => $file,
            'url'              => $url,
        ];
    }

    $body = json_encode(['entries' => $entries], JSON_PRETTY_PRINT);
    return new Response(200, ['Content-Type' => 'application/json'], $body);
}
```

#### 1.2 Modify `db/database.php`

**Replace line 19 (`$response = $controller->list();`) with:**

```php
// Check if JSON format is requested via query parameter
$wantsJson = isset($_GET['format']) && $_GET['format'] === 'json';

// Route to appropriate method
$response = $wantsJson ? $controller->listJson() : $controller->list();
```

### Testing Phase 1

After deployment, test:

1. **HTML still works:**
   ```
   https://dev.gighive.app/db/database.php
   → Should return HTML table (existing behavior)
   ```

2. **JSON now available:**
   ```
   https://dev.gighive.app/db/database.php?format=json
   → Should return JSON array
   ```

3. **Authentication:**
   - Both endpoints should require BasicAuth (viewer/secretviewer)

### Expected JSON Response Format

```json
{
  "entries": [
    {
      "id": 123,
      "index": 1,
      "date": "2024-10-20",
      "org_name": "The Jazz Band",
      "duration": "03:45:12",
      "duration_seconds": 13512,
      "song_title": "Blue Moon",
      "file_type": "video",
      "file_name": "jazz_band_2024-10-20.mp4",
      "url": "/video/jazz_band_2024-10-20.mp4"
    }
  ]
}
```

---

## Phase 2: iOS App Changes (GigHive Repository)

### Goal
Create native SwiftUI views to display database contents using the new JSON API.

### Architecture and Navigation (Updated)

- **Views:** SplashView, LoginView, View Database, Upload.
- **SplashView:** Reuses the existing title heading format (bee logo + brand font/style) used on the current page. Shows three buttons: View the Database, Upload a File, Login.
- **Auth Flow:** Tapping View/Upload when not authenticated routes to Login first; after successful login, the user is routed to the intended destination.
- **Session:** In-memory session holds `baseURL`, `credentials`, `allowInsecureTLS`, and a derived `role` (viewer/admin). No persistence to disk.
- **Permissions:** Viewer can view database; admin can upload. If a viewer attempts upload, show guidance to re-login as admin.
 - **UI Consistency:** Reuse existing look and feel across all views (bee logo title header, fonts, colors, button styles like `GHButtonStyle`).

### Additional Files to Create

#### 2.0 `GigHive/Sources/App/AuthSession.swift`

```swift
import Foundation
import SwiftUI

final class AuthSession: ObservableObject {
    @Published var baseURL: URL?
    @Published var credentials: (user: String, pass: String)?
    @Published var allowInsecureTLS: Bool = false
    @Published var role: UserRole = .unknown
    @Published var intendedRoute: AppRoute? = nil // .viewDatabase or .upload
}

enum UserRole { case unknown, viewer, admin }
enum AppRoute { case viewDatabase, upload }
```

#### 2.1 `GigHive/Sources/App/SplashView.swift`

```swift
import SwiftUI

struct SplashView: View {
    @EnvironmentObject var session: AuthSession

    var body: some View {
        VStack(spacing: 24) {
            // Reuse existing title header with bee logo and brand font/style
            TitleHeaderView() // existing component used on the current page

            Button("View the Database") {
                session.intendedRoute = .viewDatabase
            }
            .buttonStyle(GHButtonStyle(color: .blue))

            Button("Upload a File") {
                session.intendedRoute = .upload
            }
            .buttonStyle(GHButtonStyle(color: .green))

            Button("Login") { /* present LoginView */ }
            .buttonStyle(GHButtonStyle(color: .orange))
        }
        .padding()
    }
}
```

#### 2.2 `GigHive/Sources/App/LoginView.swift`

```swift
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: AuthSession
    @State private var base: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var disableCertChecking: Bool = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            TitleHeaderView()

            TextField("Base URL (e.g., https://dev.gighive.app)", text: $base)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            TextField("Username", text: $username)
                .textContentType(.username)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            SecureField("Password", text: $password)
                .textContentType(.password)

            Toggle("Disable certificate checking", isOn: $disableCertChecking)

            if let error = errorMessage { Text(error).foregroundColor(.red) }

            Button(isLoading ? "Signing In…" : "Sign In") { Task { await signIn() } }
                .buttonStyle(GHButtonStyle(color: .orange))
                .disabled(isLoading)
        }
        .padding()
    }

    private func signIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: base) else { errorMessage = "Invalid URL"; return }
        session.baseURL = url
        session.credentials = (username, password)
        session.allowInsecureTLS = disableCertChecking
        // Role can be determined lazily by endpoint responses; set unknown initially
        session.role = .unknown
        // Navigation to intended route is handled by parent once credentials are set
    }
}
```

### Files to Create

#### 2.1 `GigHive/Sources/App/DatabaseModels.swift`

```swift
import Foundation

struct MediaEntry: Codable, Identifiable {
    let id: Int
    let index: Int
    let date: String
    let orgName: String
    let duration: String
    let durationSeconds: Int
    let songTitle: String
    let fileType: String
    let fileName: String
    let url: String
    
    enum CodingKeys: String, CodingKey {
        case id, index, date, duration
        case orgName = "org_name"
        case durationSeconds = "duration_seconds"
        case songTitle = "song_title"
        case fileType = "file_type"
        case fileName = "file_name"
        case url
    }
}

struct MediaListResponse: Codable {
    let entries: [MediaEntry]
}
```

#### 2.2 `GigHive/Sources/App/DatabaseAPIClient.swift`

```swift
import Foundation

final class DatabaseAPIClient {
    let baseURL: URL
    let basicAuth: (user: String, pass: String)?
    let allowInsecure: Bool
    
    init(baseURL: URL, basicAuth: (String, String)?, allowInsecure: Bool = false) {
        self.baseURL = baseURL
        self.basicAuth = basicAuth
        self.allowInsecure = allowInsecure
    }
    
    func fetchMediaList() async throws -> [MediaEntry] {
        // Use /db/database.php?format=json
        var components = URLComponents(url: baseURL.appendingPathComponent("db/database.php"), 
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "format", value: "json")]
        
        guard let url = components?.url else {
            throw DatabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        
        // Add BasicAuth from user input
        if let auth = basicAuth {
            let credentials = "\(auth.user):\(auth.pass)"
            let base64 = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }
        
        let session: URLSession
        if allowInsecure {
            let config = URLSessionConfiguration.ephemeral
            session = URLSession(configuration: config, 
                               delegate: InsecureTrustDelegate.shared, 
                               delegateQueue: nil)
        } else {
            session = URLSession.shared
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DatabaseError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DatabaseError.httpError(httpResponse.statusCode)
        }
        
        let decoded = try JSONDecoder().decode(MediaListResponse.self, from: data)
        return decoded.entries
    }
}

enum DatabaseError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid database URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP Error \(code)"
        }
    }
}
```

#### 2.3 `GigHive/Sources/App/DatabaseView.swift`

```swift
import SwiftUI

struct DatabaseView: View {
    // Consume session instead of passing creds directly
    @EnvironmentObject var session: AuthSession
    
    @State private var entries: [MediaEntry] = []
    @State private var filteredEntries: [MediaEntry] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading database...")
                        .padding()
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Text("Error")
                            .font(.headline)
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") {
                            Task { await loadData() }
                        }
                        .buttonStyle(GHButtonStyle(color: .blue))
                    }
                    .padding()
                } else if filteredEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No media found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            NavigationLink(destination: DatabaseDetailView(entry: entry,
                                                                          baseURL: session.baseURL ?? URL(string: "https://example.com")!)) {
                                MediaEntryRow(entry: entry)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search by band, song, or date")
                    .refreshable {
                        await loadData()
                    }
                }
            }
            .navigationTitle("Media Database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadData()
            }
            .onChange(of: searchText) { _ in
                filterEntries()
            }
        }
    }
    
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let baseURL = session.baseURL else { errorMessage = "Missing base URL"; isLoading = false; return }
            let client = DatabaseAPIClient(baseURL: baseURL,
                                          basicAuth: session.credentials,
                                          allowInsecure: session.allowInsecureTLS)
            entries = try await client.fetchMediaList()
            filteredEntries = entries
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func filterEntries() {
        if searchText.isEmpty {
            filteredEntries = entries
        } else {
            let query = searchText.lowercased()
            filteredEntries = entries.filter { entry in
                entry.orgName.lowercased().contains(query) ||
                entry.songTitle.lowercased().contains(query) ||
                entry.date.contains(query) ||
                entry.fileType.lowercased().contains(query)
            }
        }
    }
}

struct MediaEntryRow: View {
    let entry: MediaEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.fileType.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.fileType == "video" ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    .cornerRadius(4)
            }
            
            Text(entry.orgName)
                .font(.headline)
            
            HStack {
                Text(entry.songTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

#### 2.4 `GigHive/Sources/App/DatabaseDetailView.swift`

```swift
import SwiftUI

struct DatabaseDetailView: View {
    let entry: MediaEntry
    let baseURL: URL
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        List {
            Section("Media Info") {
                DetailRow(label: "Date", value: entry.date)
                DetailRow(label: "Band/Event", value: entry.orgName)
                DetailRow(label: "Song Title", value: entry.songTitle)
                DetailRow(label: "Duration", value: entry.duration)
                DetailRow(label: "File Type", value: entry.fileType)
                DetailRow(label: "File Name", value: entry.fileName)
            }
            
            Section {
                Button(action: {
                    if let url = URL(string: entry.url, relativeTo: baseURL) {
                        openURL(url)
                    }
                }) {
                    HStack {
                        Image(systemName: entry.fileType == "video" ? "play.circle.fill" : "music.note")
                        Text(entry.fileType == "video" ? "Play Video" : "Play Audio")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                
                if let url = URL(string: entry.url, relativeTo: baseURL) {
                    ShareLink(item: url) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                    }
                }
            }
        }
        .navigationTitle("Media Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
```

### Files to Modify

#### 2.5 Refactor `GigHive/Sources/App/UploadView.swift`

- Remove embedded authentication UI; rely on `AuthSession` for `baseURL`, `credentials`, and `allowInsecureTLS`.
- If `session.credentials == nil`, route user to `LoginView` first.
- On upload attempt with viewer credentials, show clear message: "Upload requires admin credentials. Please re-login as admin." Provide a button to open `LoginView` with intent `.upload`.
- Keep existing look and feel (including header/title styles and `GHButtonStyle`).

---

## Testing Phase 2

### Test Checklist:

1. **Splash & Navigation:**
   - [ ] Splash header matches existing title/bee logo/branding
   - [ ] Three buttons visible: View Database, Upload a File, Login
   - [ ] Tapping View/Upload when not logged in routes to Login, then returns to intended destination after successful login
2. **Login:**
   - [ ] Base URL, Username, Password fields work
   - [ ] Disable certificate checking toggle affects all network calls
   - [ ] Bad URL or creds produce clear errors
3. **View Database:**
   - [ ] Loads using session baseURL/credentials (Phase 1 JSON)
   - [ ] Loading indicator appears while fetching data
   - [ ] List displays all media entries

4. **Search & Filter:**
   - [ ] Search bar filters by band name
   - [ ] Search bar filters by song title
   - [ ] Search bar filters by date
   - [ ] Search bar filters by file type

5. **Detail View:**
   - [ ] Tapping entry opens detail view
   - [ ] All metadata displays correctly
   - [ ] "Play Video/Audio" button opens media in browser
   - [ ] Share button works

6. **Error Handling:**
   - [ ] 401/403 show appropriate messages and guidance
   - [ ] Network failure shows error with retry button
   - [ ] Empty database shows "No media found"
7. **UI/UX:**
   - [ ] Pull-to-refresh works (View Database)
   - [ ] Works on different iPhone sizes
   - [ ] Dark mode displays correctly
   - [ ] Insecure TLS setting is respected globally
8. **Permissions:**
   - [ ] Viewer creds allow viewing but block upload with re-login messaging
   - [ ] Admin creds allow both viewing and uploading

---

## Rollback Plan

If issues arise:

### Server-Side Rollback:
Revert `db/database.php` line 19 to:
```php
$response = $controller->list();
```

### iOS Rollback:
Revert `UploadView.swift` lines 331-340 to original code that uses `successURL` and `openURL()`.

---

## Notes

- **Authentication:** Database viewer prompts for read-only credentials at runtime (do not store credentials in the app or source).
- **Upload credentials:** Remain admin/secretadmin (unchanged; not stored in code).
- **Backward Compatibility:** HTML view continues to work at `/db/database.php`
- **No Breaking Changes:** All existing functionality preserved

---

## Implementation Order

1. ✅ Phase 1: Server-side JSON API (PHP repository)
2. ✅ Test Phase 1 endpoints
3. ✅ Phase 2: iOS native views (GigHive repository)
4. ✅ Test Phase 2 functionality
5. ✅ Deploy to production

---

## Questions or Issues?

If you encounter any issues during implementation, check:

1. JSON endpoint returns valid JSON (test with curl or browser)
2. Authentication credentials are correct
3. URL construction in `DatabaseAPIClient` is correct
4. All new files are added to Xcode project
5. Import statements are correct
