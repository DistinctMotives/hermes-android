# Android Spaces — validated prototype specification

Status: `[superseded as target architecture; retained as prototype record]`

Validated by Carlos on 2026-08-24 after requesting Android-only organization comparable to Discord channels. On 2026-08-25, Carlos expanded the goal to an AI-organized Android daily driver with native Projects, smart views, files, assets, settings parity, and actionable notifications. The new draft source of truth is [`ANDROID_DAILY_DRIVER_ROADMAP.md`](ANDROID_DAILY_DRIVER_ROADMAP.md).

## Goal

Replace the flat Android session experience with named Spaces that separate related conversations while remaining compatible with a stock Hermes Gateway.

## Spaces home

- Show a persistent **All chats** entry.
- Show an **Unassigned** entry containing sessions that do not belong to a Space.
- Show user-created Spaces with their session counts and most recent activity.
- A Space can be created and renamed.
- Spaces are scoped to the saved Hermes connection; sessions from different gateways never mix.

## Space sessions

- Opening a Space shows only sessions assigned to it.
- Opening **All chats** shows every session.
- Opening **Unassigned** shows sessions with no assignment.
- Existing full-text and AI-assisted search operate inside the currently selected scope.
- Starting a chat while a Space is selected assigns the new session to that Space.
- Starting a chat from All chats or Unassigned leaves it unassigned.

## Session actions

- A session can be moved to another Space.
- A session can be moved back to Unassigned.
- Rename, branch, and delete continue to work.
- Deleting a session removes its local Space assignment.

## States

- Loading: retain the existing connection/loading feedback.
- Empty Spaces home: All chats and Unassigned remain visible; offer creation of the first Space.
- Empty Space: explain that it has no chats and expose the new-chat action.
- Gateway error: retain the current retry behavior.

## Storage and compatibility

- Space definitions and session assignments are persisted locally per saved connection using SharedPreferences.
- The feature requires no ATLAS service and no non-standard Gateway RPC.
- Unknown/deleted session assignments are pruned after a successful session refresh.
- Existing sessions initially appear under Unassigned.

## Deferred

- Cross-device synchronization of Spaces.
- Icons, colors, drag-and-drop ordering, favorites, archives, and nested Spaces.
- Server-side project/session binding if Hermes later exposes a stable generic contract for it.
