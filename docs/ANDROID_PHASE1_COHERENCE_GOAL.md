# Goal — Hermes Android: sessions first, organization that helps

Status: `[revised after device feedback — sessions-first, Workspace secondary]`

Approved: 2026-08-30 · Revised: 2026-08-30 (Carlos: “on ne retrouve pas vraiment les sessions… le but est que cette application rende l’utilisation de Hermes le plus pratique possible”)

## Outcome

Opening a connection lands directly on the **Workspace shell** — Home, **Chats**, Projects, Activity, More — with every conversation immediately visible and findable in the **Chats** destination, exactly one tap away. Workspace is the sole main interface; there is no separate session-list launch surface. The long-term north star is **automatic organization**: an AI (e.g. an open model like GPT-OSS) proposes and creates Projects/groups by itself. Nothing in this goal fakes that on-device; it stays honest about what the Gateway can do.

## Product rules

1. The session list is the primary surface. Sessions must never be buried behind another screen.
2. The Hermes Gateway remains the source of truth for Projects and Project membership.
3. Existing chat sessions are never deleted by organization actions.
4. Workspace is a secondary Smart Workspace (drawer), not the launch surface.
5. Every destructive action names its consequence, exposes progress, and offers rollback or Retry where technically possible.
6. Missing Gateway capabilities are shown honestly and capability-gated; Android must not invent a competing server authority.
7. AI-assisted auto-organization belongs to the server (agent) side; the Android app consumes it once a contract exists.

## In-scope changes (kept)

### Project lifecycle
- One consistent Project actions menu exposes Rename, Archive, Restore, and Delete when valid.
- Archived Projects have a visible section and can be restored.
- System/auto-discovered Projects do not expose mutations unsupported by the server.
- Project cards display authoritative conversation counts when supplied by `projects.tree`.

### Workspace Smart Views (secondary, behind the drawer)
- **Inbox / Unassigned** is browsable and opens its conversations.
- Global Workspace search finds all reachable sessions, including archived Quick Chats.
- **Archived quick chats** are reviewable and can be promoted into a Project (`projects.assign_session` + terminal lifecycle marker).

### Interface coherence and accessibility
- Remove duplicate screen-reader labels such as `Idle · Idle`, `Done · Done`.
- Maintain 48 dp touch targets, useful tooltips/semantics, text-scale safety, explicit loading/empty/offline/error states, and Material 3 design tokens.

## Reverted after device feedback

- ~~Workspace as default launch surface~~ — reverted: tapping a connection opens the session list again (test pins this).
- ~~All chats as a secondary Smart View~~ — the session list is the primary surface again; Workspace returns to the drawer.

## Superseded 2026-08-30 (Workspace unique, validated by Carlos)

- ~~Session list as primary surface~~ — replaced: tapping a connection opens **Workspace**; the shell owns Home / Chats / Projects / Activity / More.
- ~~Workspace in the drawer~~ — replaced: Workspace **is** the interface; **Chats** is its second destination and shows every conversation.
- ~~All chats / Search as More entries~~ — removed from More; Chats owns the full conversation browser and its search.

## Contract-gated follow-ons (north star — server work required)

These must not be faked with Android-only authority. This goal ships an honest disabled/capability-gated entry and records the exact server work required:

- **AI auto-organization**: a Gateway RPC (e.g. `projects.suggest` / agent-driven) that analyzes sessions and proposes/creates Projects and groups automatically, with user approval.
- cross-client pin ordering, batch mutation history, and universal undo;
- server-authoritative Assets index;
- unified actionable Activity events beyond the durable local turn journal;
- Project color/icon/reorder metadata if absent from `projects.*`.

## Acceptance criteria

- [x] Tapping a connection opens Workspace; Chats shows every session in one tap.
- [x] Workspace remains reachable from the drawer and returns normally.
- [x] Rename, archive, restore, and delete work against a real Gateway and preserve chats.
- [x] Archived Projects are visible and restorable.
- [x] Inbox/Unassigned lists the server’s unscoped sessions and opens them.
- [x] Quick Chats can be browsed after 72-hour archival and promoted into a Project.
- [x] Global search finds active, unassigned, Project, and archived Quick Chat conversations without duplicates.
- [x] Project cards show authoritative counts when available and degrade honestly on older Gateways.
- [x] Accessibility hierarchy contains no duplicated status/row labels in the reworked surfaces.
- [x] Every new behavior was introduced through a failing automated test.
- [x] `dart format`, `flutter analyze`, `flutter test`, and `git diff --check` pass.
- [x] `graphify update .` completes.
- [x] Signed arm64 release APK installs over the existing app without clearing data.
- [x] Physical-device smoke test verifies launch into sessions, drawer → Workspace, Project actions, Inbox, search, Quick Chat management, and preserved configuration.

## Shipping rule

Do not push remotely. Commit locally in coherent tested slices, build with the existing Hermes release key, verify the APK signature, install with `adb install -r`, and read back the installed package/version before declaring success.
