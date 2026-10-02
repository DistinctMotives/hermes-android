# Workspace Unique + Chats Implementation Plan

> **Status 2026-08-30 : COMPLETED.** All six tasks done, 879 tests green, analyze clean, signed APKs installed on phone (SM-S948B) and emulator (hermes-test).

## Bugs discovered and fixed during on-device verification

1. **`ApiClient` had no request timeout** — a stale keep-alive socket (server closed an idle connection) hung `getSessions()` forever, leaving Chats on an infinite skeleton. Fixed: fresh TCP connection per request (`HttpClient.idleTimeout = Duration.zero`) + `getSessions(timeout: requestTimeout)` (20s default). Regression test: `test/api_client_timeout_test.dart`.
2. **Connection form pre-filled a hardcoded example** — `_desktopGatewayUrl` defaulted to `http://192.168.1.193/desktop` for new connections. Saving silently pointed the app at a dead Desktop Gateway → `ProjectsRepository` created → `overview()` hung ~75s (Connection refused) → every session load blocked. Fixed: default empty (advanced override only). Regression test: "a new connection never pre-fills a Desktop Gateway URL".
3. **Projects overview blocked the session list** — `_loadWorkspaceSessionsData` awaited `repository.overview()` unbounded; a wedged Desktop Gateway hid every conversation. Fixed: `.timeout(Duration(seconds: 8))`, best-effort additive metadata only. Regression test: "Chats still shows sessions when the Projects overview hangs".

## Live verification (emulator, restored real config)

- Restored `hermes-config-2026-08-30T11-36-32.json` (passphrase provided by Carlos) via the app's Restore flow on the emulator.
- Miniserver connection restored: `carlos-miniserver.taild544f6.ts.net:8642 • Key: ✓`.
- Workspace opens with 5 tabs (Home 1/5 … More 5/5).
- Chats loads the real session list (Connexion ADB, roadmap sessions, compression tests) with no Loading hang.

---

### Task 1: Lock the five-destination shell contract

**Objective:** Add the validated Chats destination between Home and Projects.

**Files:**
- Modify: `test/hermes_shell_test.dart`
- Modify: `lib/core/widgets/hermes_shell.dart`

**Step 1 — RED:** Change the destination contract test to expect Home, Chats, Projects, Activity, More and assert Chats renders a chat-bubble icon/label.

**Step 2 — Verify RED:**

```bash
flutter test test/hermes_shell_test.dart
```

Expected: failure because `HermesDestination.chats` does not exist.

**Step 3 — GREEN:** Add `chats` to the enum and label/icon switches.

**Step 4 — Verify GREEN:** Run the same test; expected all tests pass.

---

### Task 2: Embed the conversation browser in Workspace

**Objective:** Render all conversations directly inside the Chats destination without a nested Scaffold/AppBar.

**Files:**
- Modify: `test/workspace_sessions_screen_test.dart`
- Modify: `lib/core/screens/workspace_sessions_screen.dart`

**Step 1 — RED:** Add a widget test for an embedded/pane mode that shows search and sessions but no nested `Scaffold`/`AppBar`, and preserves refresh/error/empty behavior.

**Step 2 — Verify RED:**

```bash
flutter test test/workspace_sessions_screen_test.dart
```

Expected: failure because pane mode is unavailable.

**Step 3 — GREEN:** Extract the existing body into a reusable builder and add an explicit presentation mode or named pane constructor. Keep route mode backward-compatible during migration.

**Step 4 — Verify GREEN:** Run the targeted tests.

---

### Task 3: Wire Chats to real Workspace data

**Objective:** Chats loads the complete server session list and opens the existing durable chat flow.

**Files:**
- Modify: `test/workspace_screen_test.dart`
- Modify: `lib/core/screens/workspace_screen.dart`

**Step 1 — RED:** Add tests that:

- tap Chats and see supplied sessions;
- open a session through `onOpenSession`;
- show loading/error/empty states;
- expose the global New button on Home and Chats;
- keep More free of duplicate All chats/Search/Inbox entries once Chats owns them.

**Step 2 — Verify RED:**

```bash
flutter test test/workspace_screen_test.dart
```

Expected: failures because `_pane` has no Chats branch and the FAB is Home-only.

**Step 3 — GREEN:** Add a Chats branch using embedded `WorkspaceSessionsScreen`, `_loadWorkspaceSessionsData`, and `_openSession`. Show FAB for Home and Chats. Remove duplicate navigation entries from More only after tests pin their new location.

**Step 4 — Verify GREEN:** Run workspace, sessions and More tests.

---

### Task 4: Make Workspace the connection launch surface

**Objective:** Selecting or auto-resuming a saved connection opens Workspace, never the legacy session list.

**Files:**
- Modify: `test/home_config_restore_test.dart`
- Modify: any dedicated Home navigation tests found during implementation
- Modify: `lib/main.dart`

**Step 1 — RED:** Change the saved-connection test to expect `WorkspaceScreen` and the five destination labels, and assert `SessionListScreen` is absent.

**Step 2 — Verify RED:**

```bash
flutter test test/home_config_restore_test.dart
```

Expected: failure because `_navigateToSessions` still constructs `SessionListScreen`.

**Step 3 — GREEN:** Import `workspace_screen.dart`, rename the method to `_navigateToWorkspace`, construct `WorkspaceScreen(connection:, turnApplicationController:)`, and update manual/automatic call sites.

**Step 4 — Verify GREEN:** Run targeted Home and Workspace tests.

---

### Task 5: Remove normal legacy navigation and stale claims

**Objective:** Ensure no user-visible path or documentation claims the old session list remains primary.

**Files:**
- Modify: `docs/ANDROID_PHASE1_COHERENCE_GOAL.md`
- Modify: `docs/ANDROID_FINAL_UI_SPEC_DRAFT.md` status
- Modify tests/source only where searches reveal normal navigation to `SessionListScreen`

**Verification:**

```bash
rg "SessionListScreen\(" lib test
rg "session list as the primary|four-destination|Home / Projects / Activity / More" docs test lib
```

Expected: `SessionListScreen` may remain as compatibility code/tests but no production navigation from Home uses it; current docs describe Workspace + Chats.

---

### Task 6: Full quality and device gate

**Objective:** Prove the slice is shippable.

**Commands:**

```bash
dart format lib test
flutter analyze
flutter test
git diff --check
graphify update .
flutter build apk --release --target-platform android-arm64 --split-per-abi
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

**Live acceptance:**

1. Open Miniserver connection.
2. Confirm Workspace opens.
3. Confirm bottom bar order Home, Chats, Projects, Activity, More.
4. Open Chats, search, open a real conversation, return to Chats.
5. Create a quick chat and a Project chat.
6. Confirm Project assignment server-side.
7. Confirm configuration remains intact after upgrade.
