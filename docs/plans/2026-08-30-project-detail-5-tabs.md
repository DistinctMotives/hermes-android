# Project detail à 5 onglets — décision #5 du schéma UI

> **Statut : en cours (2026-08-30).** Suite du schéma validé : « Détail Project à cinq onglets : Aperçu, Chats, Fichiers, Ressources, Activité ».

## Objectif

Transformer le détail Project (2 onglets aujourd'hui) en cockpit à 5 onglets, chaque onglet honnête sur ses données :

- **Overview** : existant (compteurs serveur, repos, localisation) — conservé.
- **Chats** : existant (recherche, déplacement, gestion) — conservé.
- **Files** : chemins de dossiers du Project **fournis par le serveur** (`tree.path` + repos/lanes paths, dédupliqués). Aucun scan local inventé.
- **Assets** : capacité-gated — même raison que More : « Needs a server-authoritative Assets index in the Hermes Gateway. »
- **Activity** : activité dérivée des sessions du Project (statut Running/Done, temps relatif, tri par dernière activité) — honnête car ce sont les événements du Project.

## Tranches

### Task 1 — RED : tests widget 5 onglets
- 5 onglets déclarés ; Files liste les chemins serveur ; Assets explique l'index manquant ; Activity montre les statuts.

### Task 2 — GREEN : implémentation
- `TabController(length: 5)`, onglets Overview/Chats/Files/Assets/Activity (ordre du schéma).
- `_buildFiles` (chemins dédupliqués + EmptyState), `_buildAssets` (raison), `_buildActivity` (statuts + temps relatif).

### Task 3 — Porte qualité + appareil
- format/analyze/test/diff-check/graphify, APK debug + release, vérif émulateur.
