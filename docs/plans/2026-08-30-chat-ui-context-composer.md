# Chat UI — en-tête contextuel et composer unifié

> **Statut : en cours (2026-08-30).** Implémente la section 4.9 du schéma UI sans réécrire les transports/streaming déjà fiables.

## État actuel confirmé

- AppBar : titre + connexion ; modèle/effort cachés dans le composer.
- Tool activity : déjà repliable, statut/durée/détail, auto-ouvert pendant l’exécution puis repliable.
- Composer : pièces jointes, modèle, voix, TTS, multiligne, send/stop — fonctionnel mais fragmenté visuellement.
- Streaming/recovery : fortement testé ; aucune modification de contrat.

## Tranche 1 — En-tête contextuel collant

Créer `ChatContextHeader` réutilisable avec :
- Project (ou Unassigned) ;
- modèle effectif ;
- effort de raisonnement ;
- connexion + état coloré.

Le header est le `AppBar.bottom`, donc reste visible pendant le scroll. `ChatScreen.projectName` est optionnel ; Workspace le fournit quand le chat vient d’un Project.

## Tranche 2 — Composer unifié

- Garder toutes les actions existantes, mais transformer le sélecteur modèle en chip compact et regrouper attachment / champ / voix / TTS / send dans une surface arrondie unique.
- Conserver les clés, semantics et dimensions 48dp existantes.
- Champ multiligne 1–5 lignes ; placeholder « Message Hermes… ».

## Tranche 3 — Cartes d’outils

- Migrer `GatewayActivityCard` vers `HermesCard`/tokens ; titre « Tool activity » ; résumé statut compact.
- Conserver ExpansionTile, durée, détail et comportement verbose.

## Tests

- `test/chat_context_header_test.dart` : labels, état connecté/offline, grand texte/largeur étroite.
- `test/gateway_activity_card_test.dart` : replié une fois terminé, ouvert pendant running, durée/échec.
- Tests Chat existants pour composer/voice/attachments/recovery.
- Porte : analyze + suite complète + build + émulateur réel.
