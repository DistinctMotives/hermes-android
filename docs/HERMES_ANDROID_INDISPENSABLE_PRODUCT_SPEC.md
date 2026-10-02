# Hermes Android — produit indispensable

Statut : **vision produit validée, livraison incrémentale**  
Date : 2026-08-30  
Source UI : `docs/ANDROID_FINAL_UI_SPEC_DRAFT.md`

## Vision

Hermes Android n’est pas un simple client de chat. C’est le **poste de pilotage mobile de Hermes** : voir ce qui demande de l’attention, reprendre toutes les conversations, diriger les missions autonomes, approuver les actions, envoyer du contenu depuis Android et récupérer les résultats produits.

Le produit doit être plus pratique que Discord pour piloter Hermes, tout en conservant le Gateway comme source de vérité.

## Principes non négociables

1. **Workspace est l’unique interface principale.** Une connexion ouvre Workspace.
2. La navigation téléphone est **Accueil · Chats · Projets · Activité · Plus**.
3. **Chats remplace l’ancienne liste de sessions** ; aucune seconde interface concurrente.
4. Le serveur reste l’autorité pour sessions, Projects, missions, affectations et capacités.
5. Une action dangereuse reste explicite et vérifiable ; les secrets ne sont jamais affichés dans le transcript.
6. Les tâches longues survivent à la navigation, au passage en arrière-plan et au redémarrage Android.
7. Chaque capacité absente du Gateway est affichée honnêtement, jamais simulée localement.
8. Chaque écran possède des états chargement, vide, hors ligne, erreur, non supporté et permission refusée.
9. Chaque tranche est livrée par TDD, testée sur émulateur et appareil physique lorsqu’ils sont disponibles.

---

## Pilier 1 — Workspace et Chats

### Objectif

Donner accès à toutes les conversations en un geste sans répéter les mêmes listes.

### Surface

- Accueil : digest limité à Action requise, En cours, Suggestions, À reprendre.
- Chats : Tous, Récents, Non classés, Archivés, recherche et filtres.
- Projets : organisation serveur des mêmes chats.
- Activité : événements et travaux, jamais une quatrième liste de chats.
- Plus : capacités secondaires.

### Critères d’acceptation

- Une connexion ouvre `WorkspaceScreen`.
- Le shell expose cinq destinations dans l’ordre validé.
- Chats charge la liste REST existante et ouvre le même `ChatScreen` avec le même `GatewayTurnApplicationController`.
- Non classés/Archivés restent des filtres du composant Chats.
- Le bouton Nouveau est disponible depuis Accueil et Chats.
- Aucun accès normal ne pousse `SessionListScreen`.
- Retour depuis un chat revient au filtre et à la position de défilement précédents.

---

## Pilier 2 — Centre d’actions et notifications

### Objectif

Permettre à Carlos de débloquer Hermes sans rechercher le bon chat.

### Événements

- approbation/refus ;
- clarification ;
- saisie sensible ;
- tâche bloquée ;
- échec ;
- mission terminée ;
- perte/reprise de connexion.

### Expérience

- canaux Android distincts : Action requise, Échecs, Terminé ;
- deep-link vers l’action exacte ;
- actions sûres Approver/Refuser/Réessayer depuis la notification ;
- authentification biométrique pour les actions sensibles configurées ;
- rappel configurable tant que l’action reste pendante ;
- déduplication stricte entre notifications et Activity.

### Dépendance serveur

Le Gateway doit exposer des événements typés, des identifiants stables, un statut courant et des RPC idempotents de résolution. La notification locale de fin de tour existante reste un fallback.

### Critères d’acceptation

- Une action déjà résolue disparaît de l’application et de la notification.
- Une action répétée est idempotente.
- Toucher une notification ouvre le bon Project/chat/tour.
- Aucune valeur secrète ne passe dans le texte de notification.

---

## Pilier 3 — Mission Control

### Objectif

Suivre et diriger les agents, sous-agents, cron jobs et processus longs.

### Surface

- graphe/arbre de mission ;
- état : en attente, en cours, bloqué, terminé, échoué, annulé ;
- dernière action et dernier résultat ;
- durée, progression lorsque disponible ;
- fichiers produits ;
- erreurs et logs repliables ;
- Pause, Reprendre, Arrêter, Réessayer, Donner une instruction.

### Dépendance serveur

Nouveau contrat Gateway de mission : liste/snapshot, flux d’événements, commande de contrôle et liens session/Project/artefacts. L’app ne déduit pas une fausse mission depuis du texte libre.

### Critères d’acceptation

- Une mission continue si l’écran est fermé.
- Reconnexion reconstruit l’état depuis un snapshot serveur puis reprend le flux.
- Une instruction envoyée cible exactement l’agent choisi.
- Les commandes non supportées sont désactivées avec raison visible.

---

## Pilier 4 — Partager vers Hermes

### Objectif

Transformer tout contenu Android en travail Hermes sans copier-coller.

### Entrées

- texte ; URL ; image ; capture ; PDF ; document ; fichier multiple.

### Flux

1. Android Share Sheet → Hermes.
2. Choisir Chat rapide ou Project.
3. Choisir une action favorite ou écrire une instruction.
4. Confirmer pièces jointes, modèle/effort et destination.
5. Créer/assigner la session avant envoi puis ouvrir le chat.

### Actions favorites

Résumer, expliquer, rechercher, extraire les tâches, enregistrer dans la mémoire, ajouter au Project, remplir à partir du document.

### Critères d’acceptation

- Le partage fonctionne à froid et à chaud.
- Les URI Android sont copiées dans un stockage temporaire contrôlé avant expiration de permission.
- La taille/type non supporté produit une erreur actionnable.
- Aucun fichier n’est perdu si le réseau tombe avant l’envoi.

---

## Pilier 5 — Voix

### Objectif

Piloter Hermes mains libres.

### Fonctions

- maintien pour parler et dictée ;
- conversation voix-à-voix ;
- TTS interrompable ;
- commandes courtes depuis notification/écran verrouillé ;
- sélection langue/voix/vitesse ;
- état clair d’écoute, transcription, envoi et lecture.

### Dépendances

Réutiliser STT/TTS Hermes configurés lorsque le Gateway les expose ; fallback Android explicitement identifié. Android Auto et contrôle écran verrouillé sont des tranches séparées soumises aux politiques Android.

---

## Pilier 6 — Intelligence des Projects

### Politique validée

- affecter automatiquement à un **Project existant** seulement à haute confiance ;
- proposer, ne pas créer silencieusement, un **nouveau Project** ;
- ne jamais déplacer automatiquement un chat épinglé ou récemment corrigé ;
- les corrections manuelles deviennent des règles prioritaires.

### Aperçu intelligent

- but du Project ;
- situation actuelle ;
- décisions ;
- blocages ;
- prochaine action ;
- éléments épinglés ;
- dernière synthèse et date.

### Dépendance serveur

RPC de suggestion/organisation et journal d’annulation serveur. Hindsight peut fournir du contexte, mais Projects reste l’autorité d’affectation.

---

## Pilier 7 — Fichiers, artefacts et résultats

### Objectif

Ne plus perdre les résultats utiles dans le transcript.

### Fonctions

- index global et par Project ;
- aperçu images, PDF, texte, diff, tableau et APK ;
- états créé, modifié, testé, signé, installé, publié ;
- lien vers mission/chat source ;
- téléchargement, partage, installation et historique de versions ;
- action « Ouvrir le dernier résultat ».

### Dépendance serveur

Index d’artefacts serveur avec identifiants stables, métadonnées, téléchargement authentifié et permissions. Aucun scan local opportuniste présenté comme index universel.

---

## Pilier 8 — Continuité et mode dégradé

- reprise durable des tours ;
- brouillons et pièces jointes en attente ;
- cache chiffré des écrans récemment lus ;
- lecture hors ligne clairement marquée ;
- file d’envoi avec Retry/Annuler ;
- reconnexion Wi-Fi/Tailscale ;
- handoff téléphone/Desktop/Discord ;
- backup/restore chiffré de la configuration ;
- état de santé Gateway visible.

Critère principal : tuer l’application pendant un tour ou un brouillon ne doit perdre ni le travail serveur ni le brouillon local.

---

## Pilier 9 — Accès instantané Android

- widget : actions requises, missions en cours, Nouveau chat, Parler ;
- raccourcis d’application ;
- tuile Réglages rapides ;
- actions favorites configurables ;
- deep links internes stables.

Aucun widget ne révèle de contenu sensible sur écran verrouillé sans opt-in.

---

## Pilier 10 — Modèles, coûts et profils

### Surface simple

- modes Automatique, Rapide, Qualité, Économique ;
- provider/modèle effectif et fallback visibles ;
- choix modèle/effort dans le composer ;
- consommation et quota lorsque le Gateway les connaît ;
- avertissement avant mission lourde ;
- favoris par Project/type de tâche.

### Principe

Android choisit une intention utilisateur ; le Gateway conserve la logique d’autorité et de fallback. L’app ne promet pas un coût que le provider ne fournit pas.

---

## Pilier 11 — Sécurité

- verrouillage biométrique optionnel ;
- stockage Android Keystore ;
- confirmation biométrique par catégorie dangereuse ;
- saisie secrète hors transcript ;
- appareils/connexions révocables ;
- historique d’approbation ;
- masquage du contenu sensible dans notifications et écran récent.

---

## Pilier 12 — Automatisations

- liste, détail, prochaine exécution et historique des cron jobs ;
- créer depuis une conversation ;
- Exécuter maintenant, Pause, Reprendre, Modifier, Supprimer ;
- résultat lié à un Project et à Activity ;
- modèles d’automatisation ;
- notifications uniquement sur changement, action ou échec lorsque configuré.

---

## Plan de livraison

### Phase A — Fondation indispensable

1. Workspace unique et onglet Chats.
2. Nettoyage des doublons All chats/Inbox/Search dans Plus.
3. Création globale de chat depuis Accueil et Chats.
4. Navigation et état de liste préservés.
5. Tests, thèmes, accessibilité, appareil physique.

### Phase B — Action mobile

1. Notifications typées et deep links.
2. Activity comme centre d’actions.
3. Partager vers Hermes.
4. File d’attente/reprise fiable.
5. Widget minimal.

### Phase C — Pilotage autonome

1. Contrat Mission Control Gateway.
2. Vue mission et commandes de contrôle.
3. Artefacts liés aux missions.
4. Notifications mission.

### Phase D — Assistant personnel

1. Organisation IA des Projects.
2. Aperçus intelligents.
3. Voix complète.
4. Handoff multi-client.
5. Modèles/coûts/profils.

### Phase E — Plateforme sécurisée

1. Biométrie et secrets.
2. Automatisations avancées.
3. tablette/pliable deux panneaux.
4. durcissement offline, performance et observabilité.

---

## Définition de terminé pour chaque tranche

- spécification et contrat validés ;
- tests écrits avant le code et RED observé ;
- tests unitaires/widget/intégration verts ;
- `dart format`, `flutter analyze`, `flutter test`, `git diff --check` verts ;
- Graphify mis à jour ;
- états clair/sombre, petit écran et grand texte vérifiés ;
- APK signée et signature vérifiée ;
- installation et lecture version/package sur appareil réel ;
- capture ou dump UI de la surface livrée ;
- aucune capacité simulée si le Gateway ne l’expose pas.
