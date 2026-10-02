# Hermes Android — functional and interface audit

Audit date: 2026-08-29  
Evidence: live SM-S948B UI hierarchy, Flutter source, widget tests, and `ANDROID_DAILY_DRIVER_ROADMAP.md`.

## Product-level verdict

The application has a strong technical foundation: durable turn recovery, server-owned Projects, Home attention ranking, Activity, Quick Chat retention, project chat creation/movement/search, files access, voice, attachments, and explicit offline/error states. The main weakness is no longer transport reliability; it is **product coherence and feature discoverability**.

The current APK exposes two competing information architectures:

1. launch opens the legacy **All chats** screen;
2. the drawer opens **Workspace — Projects, Activity — new navigation**;
3. Workspace then appears as a child route with a Back button, despite containing the intended primary navigation Home / Projects / Activity / More.

This makes the new daily-driver experience look optional and unfinished. Workspace should become the launch surface; All chats should remain available as a secondary Smart View.

## Screen and capability matrix

| Surface | Working now | Important gaps |
|---|---|---|
| Legacy All chats | Local/full-text/AI search modes, profiles, chat actions, new chat | Competes with Workspace as the app home; visually belongs to an older navigation system |
| Home | Needs you, Running, Continue, Recently completed; badges; New flow | No Inbox/Unassigned, Pinned, or explicit Archived views; many idle/done chips add noise |
| Projects list | Server source of truth, cache/offline states, create, migration entry | No counts/current-focus summary on cards; no archived section; no reorder/pin/color/icon controls |
| Project detail | Chats/Overview, create chat, move chat, per-project search, repositories/location | Rename and archive absent; deletion added in this audit slice; Files/Assets/Activity tabs absent |
| Activity | Durable per-turn timeline with grouped states and elapsed time | Local journal only; no unified approvals/clarifications/cron/platform events or action controls |
| More | Files, Cron, Skills, Memory, Settings/Dashboard fallback | Assets and global Search remain placeholders; long flat list lacks stronger grouping/navigation hierarchy |
| Chat | Durable recovery, model/effort controls, attachments, voice, approvals/clarifications, reasoning/tool cards, code copy/wrap, long-press actions | Phase 1.5 remains partial: sticky context header, richer diff rendering, scroll/process restoration audit, haptic polish |
| Project administration | Create and server-backed assignment | Rename/archive/restore not surfaced; archived Projects are invisible; destructive management was missing until this slice |
| Quick Chat | 72-hour local archive lifecycle, never deletes sessions | No visible Archived destination and no Promote action, so the lifecycle is technically present but hard to manage |
| Global organization | Manual Project creation/move and Project search | No global Workspace search, batch selection, undo, Inbox/Unassigned triage, pinned chats, or AI organizer |

## Interface coherence findings

### P0 — information architecture

- **Two homes:** launch goes to legacy All chats; Workspace is hidden in the drawer and has a Back button. Make Workspace the launch route and place All chats under Home/More as a Smart View.
- **Incomplete Project management:** create and move exist, while rename/archive/restore were implemented below the UI but unavailable. Complete one consistent Project actions menu.
- **No organization recovery surface:** Unassigned exists as a move destination but there is no browsable Inbox/Unassigned screen. Users cannot easily find chats that were never filed or became unassigned after Project deletion.

### P1 — visible consistency and density

- Project cards show name/description/path and Active, but not the server counts/current-focus data expected by the roadmap; the list is visually sparse while Home cards are operationally dense.
- Home and Activity expose duplicated accessibility/status strings such as `Idle · Idle` and `Done · Done`. The chip and parent semantics should be merged; idle chips should usually be omitted.
- More rows expose repeated labels (`Files · Files`, `Cron · Cron`) in the accessibility tree because title and semantic label overlap.
- Project detail uses Chats/Overview only, whereas the validated model promises Overview/Chats/Files/Assets/Activity. Missing tabs should be capability-gated rather than silently absent once implemented.
- Destructive and management actions should use the same pattern everywhere: overflow menu, explicit confirmation, honest consequence text, progress state, rollback/retry.

### P2 — completeness

- Global server-backed search and an Archived surface.
- Pin, batch select, undo, and Quick Chat Promote.
- Project Files/Assets/Activity tabs and richer cards.
- Unified actionable Activity Center.
- AI-assisted filing only after manual organization is complete and reversible.
- Tablet/foldable layout, full accessibility audit, and localization.

## Ordered implementation backlog

1. **Project delete** — confirmed destructive action; chats survive and return to Unassigned; optimistic repository rollback. Implemented in this audit slice.
2. **Project rename + archive/restore + Archived section** — reuse existing RPC/repository methods and one consistent actions menu.
3. **Inbox / Unassigned Smart View** — essential recovery path after deletion or failed classification.
4. **Make Workspace the default launch surface** — retain All chats as a Smart View; eliminate the competing-root navigation.
5. **Quick Chat Archived + Promote** — expose the lifecycle already implemented.
6. **Project card counts/current focus** — consume the existing `projects.tree` overview.
7. **Pin/batch/undo** — complete manual organization before AI filing.
8. **Global Workspace search** — unify the existing search capabilities under the new information architecture.
9. **Semantics/density cleanup** — deduplicate labels and remove non-actionable idle chips.
10. Continue Phase 1.5 chat polish, then the AI organizer and expanded Activity Center.

## Project deletion interaction contract

- Entry: Project detail app-bar overflow → **Delete project**.
- Confirmation title names the Project.
- Copy explicitly states that Project deletion is permanent but chat sessions are not deleted and return to **Unassigned**.
- Cancel performs no write.
- Confirm calls the server-authoritative `projects.delete` RPC through `ProjectsRepository`.
- The repository removes the Project optimistically, clears the active selection when necessary, updates the connection-scoped cache, and restores the exact prior state on failure.
- Success returns to the refreshed Projects list.
- Failure keeps the detail open and offers Retry.
