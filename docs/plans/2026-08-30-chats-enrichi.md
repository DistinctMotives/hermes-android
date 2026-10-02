# Chats enrichi — filtres, regroupement, lignes riches

> **Statut : en cours (2026-08-30).** Suite du schéma UI validé — décision #4 : « Non classés, Récents et Archivés deviennent des filtres de Chats ».

## Objectif

Faire de l'onglet **Chats** le navigateur de conversations complet du schéma : filtres combinables (Tous / Récents / Non classés / Archivés), regroupement par date (Aujourd'hui / Hier / Cette semaine / Plus tôt), lignes qui montrent état (Running/Done), Project (ou Unassigned), épinglé et dernière activité.

## Données disponibles (vérifié API réelle)

- `Session` : `started_at`, `ended_at`, `is_active` (dérivé), `last_active`, `pinned`, `archived`, `preview`, `title`, `model`.
- `ProjectsTreeOverview` : `scopedSessionIds` + `previewSessions` par projet (mapping session→nom projet best-effort).

## Tranches

### Task 1 — Modèle Session enrichi
- Ajouter `lastActive` (fallback startedAt), `pinned`, `archived` à `Session` + `fromJson`.
- Tests : `test/session_model_test.dart`.

### Task 2 — Logique pure filtres + dates
- `WorkspaceChatsFilter { all, recent, unassigned, archived }` + labels.
- `filterChats(...)` : recent = lastActive ≥ now−7j ; unassigned = !claimed ; archived = server-archived ∪ quick-archived.
- `chatDateBucket(now, lastActive)` + `groupChatsByDate(...)` → Aujourd'hui / Hier / Cette semaine / Plus tôt.
- Tri par dernière activité décroissante.
- Tests unitaires dans `test/workspace_sessions_screen_test.dart`.

### Task 3 — UI Chats
- Rangée de chips (Tous / Récents / Non classés / Archivés) en mode embarqué seulement.
- En-têtes de groupes de dates ; lignes enrichies (StatusChip Running/Done, chip projet ou « Unassigned », icône épingle, heure relative).
- États vides par filtre.
- Tests widget.

### Task 4 — Mapping projet best-effort
- `WorkspaceSessionsData.projectLabels` (sessionId → label projet) construit depuis les `previewSessions` de l'overview.
- Câblage dans `_loadWorkspaceSessionsData`.
- Test dans `test/workspace_screen_test.dart`.

### Porte qualité
- `dart format`, `flutter analyze`, `flutter test`, `git diff --check`, `graphify update .`.
- APK release signée, installée téléphone + émulateur, vérification UI.
