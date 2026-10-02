# HermesApk development log

This is the public, sanitized engineering record for the Remote Gateway
community edition. Private network topology, credentials, device profiles, and
local operator logs are intentionally excluded.

## Scope

- Base application: Hermes Android 1.0.13.
- Goal: make the Android chat experience useful with Hermes Desktop in Remote
  Gateway mode while preserving the existing REST/dashboard features.
- Validation boundary: synthetic or isolated gateways first, followed by a
  physical-device test over a private network.

## Implemented milestones

### Chat fundamentals

- Made Markdown selectable without removing message actions.
- Added Copy to every message and Read aloud to assistant responses.
- Deferred microphone permission until the user explicitly starts dictation.
- Added Stop for REST streams and Desktop Gateway prompts.

### Desktop Gateway transport

- Added authenticated Dashboard ticket acquisition and JSON-RPC WebSocket
  transport.
- Added session create, resume, reconnect, interrupt, title, branch, and
  per-session configuration.
- Mapped the persistent mobile conversation ID to the runtime session returned
  by Hermes.
- Normalized official Hermes event envelopes and terminal events while keeping
  compatibility with older fixture events.

### Files and composer

- Added Android Storage Access Framework selection for arbitrary file types.
- Added up to 10 attachments per message, 16 MiB each.
- Added per-file ready, uploading, attached, failed, remove, and retry states.
- Ensured text and attachments are sent through the same Desktop Gateway
  session and are not uploaded again after a retry if already attached.
- Added explicit `hermes_mobile` channel and profile metadata for canonical
  server-side document intake. Intake failure is non-blocking for the chat and
  is surfaced as an operator-visible pending status.

### Conversation controls

- Added local search over title, preview, and model.
- Added Rename, Branch, and Delete.
- Added Edit and resend, Regenerate, and Android share/export.
- Fixed a Flutter route-lifecycle assertion when Branch was started from a
  popup menu.
- Reconciled late Branch errors by refreshing history and recognizing a branch
  that the gateway had already created.

### Models and reasoning

- Kept the profile default model in Settings.
- Added a model override scoped to a single chat.
- Added per-chat thinking effort through the official session-scoped
  `config.get/config.set` contract with key `reasoning`.
- Supported `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, and
  `ultra`.
- Persisted and reapplied both model and effort after reconnecting.

### Interactive and asynchronous events

- Added approval prompts with exact request IDs and explicit allow/deny.
- Added masked sudo and secret prompts without logging entered values.
- Added clarification prompts for single choice, multiple choice, and free
  text.
- Added reasoning cards, interim messages, tool activity, notifications,
  background results, review summaries, and subagent status.
- Deduplicated delayed or repeated events and bounded in-memory result storage.

### Build and distribution safety

- Added a separate `.dev` Android application ID so the test build can coexist
  with upstream.
- Prevented Release builds from silently using the Android debug key.
- A production Release requires an explicitly configured private keystore.
- Kept the downloadable community artifact clearly labeled as a debug test
  build.

## Validation

- 113 Flutter tests pass.
- Static analysis passes with `--fatal-infos`.
- The synthetic gateway contract test covers authentication, session lifecycle,
  model/reasoning configuration, files, streaming, interruption, interactive
  prompts, activity, notifications, and subagents.
- ARM64 and x86_64 debug artifacts build successfully.
- The x86_64 artifact installs as an upgrade in the reusable Android emulator.
- The ARM64 artifact was tested successfully on a physical Android phone:
  Remote Gateway chat, Branch, per-chat model, and thinking effort were
  confirmed functional.
- The `.14` ARM64 debug artifact builds successfully and its extended synthetic
  `file.attach` contract returns canonical intake status. Physical-device
  validation of the new intake metadata remains an operator acceptance step.

## Toolchain follow-up

- The current Flutter build warns that several plugins still apply the Kotlin
  Gradle Plugin directly. This is non-blocking today, but the dependencies must
  migrate before a future Flutter release enforces built-in Kotlin.

## Known release boundary

The published `.13` APK is signed with the standard Android Debug certificate.
It is suitable for testing and private sideloading, not store or production
distribution. No release keystore, gateway credential, operator profile, or
private infrastructure data is included in this repository.
