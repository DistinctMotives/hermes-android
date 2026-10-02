# Hermes Android — schéma de l’interface finale

Statut : `[x] navigation validée par Carlos (2026-08-30) — décisions 1, 2, 3, 4, 6, 7 approuvées ; implémentation en cours (Phase A : Workspace unique + Chats)`

## 1. Principe directeur

**Workspace devient l’unique interface principale.** L’ancienne liste de sessions séparée disparaît. Les conversations restent accessibles en un geste depuis Workspace grâce à un onglet **Chats**, tandis que **Accueil** montre seulement les conversations qui demandent de l’attention ou qu’on veut reprendre.

Règles anti-répétition :

1. Une conversation n’apparaît qu’une fois dans une liste donnée.
2. **Accueil** est un résumé priorisé, pas une deuxième liste complète de chats.
3. **Chats** est la source de navigation globale vers toutes les conversations.
4. **Projets** organise les mêmes conversations par contexte ; il ne crée pas une copie locale.
5. La recherche globale utilise le même écran de résultats, quel que soit son point d’entrée.
6. Ouvrir une connexion mène directement à Workspace, jamais à l’ancienne liste de sessions.

---

## 2. Navigation globale

### Téléphone

```text
┌──────────────────────────────────────┐
│ En-tête de la page active            │
│                                      │
│ Contenu                              │
│                                      │
│                              [  +  ] │
├──────────────────────────────────────┤
│ Accueil │ Chats │ Projets │ Activité │ Plus │
└──────────────────────────────────────┘
```

- Barre inférieure permanente : **Accueil · Chats · Projets · Activité · Plus**.
- Le bouton `+` ouvre toujours la même feuille : **Chat rapide** ou **Chat de projet**.
- Un badge n’apparaît que sur **Activité** lorsqu’une action humaine est requise.
- Le tiroir de navigation disparaît pour les fonctions principales.
- Retour Android depuis un chat revient exactement à la liste/carte qui l’a ouvert.

### Tablette / pliable

```text
┌──────────┬──────────────────┬─────────────────────────────┐
│ Rail     │ Liste            │ Détail                      │
│ Accueil  │ chats/projets    │ chat/projet/activité        │
│ Chats    │                  │                             │
│ Projets  │                  │                             │
│ Activité │                  │                             │
│ Plus     │                  │                             │
└──────────┴──────────────────┴─────────────────────────────┘
```

---

## 3. Carte complète des écrans

```text
Connexions
└── Workspace (connexion active)
    ├── Accueil
    │   ├── Action requise
    │   ├── En cours
    │   ├── À reprendre
    │   └── Suggestions d’organisation IA [capability-gated]
    ├── Chats
    │   ├── Tous
    │   ├── Récents
    │   ├── Non classés
    │   ├── Archivés
    │   ├── Recherche / filtres
    │   └── Chat plein écran
    ├── Projets
    │   ├── Liste des projets
    │   └── Détail projet
    │       ├── Aperçu
    │       ├── Chats
    │       ├── Fichiers
    │       ├── Ressources
    │       └── Activité
    ├── Activité
    │   ├── Action requise
    │   ├── En cours
    │   ├── Terminé
    │   └── Échecs
    └── Plus
        ├── Fichiers globaux
        ├── Ressources globales
        ├── Recherche globale
        ├── Cron
        ├── Skills et outils
        ├── Mémoire
        ├── Profils
        ├── MCP et plugins
        ├── Diagnostics
        └── Réglages
```

---

## 4. Écrans proposés

### 4.1 Connexions `[ ]`

But : sélectionner ou administrer un Gateway.

```text
┌──────────────────────────────────────┐
│ Hermes                     Restaurer │
│                                      │
│ Miniserver                    ● Live │
│ 100.x.x.x · Dernière sync maintenant│
│                                      │
│ Serveur secondaire              Hors │
│                                      │
│                         [Ajouter +]  │
└──────────────────────────────────────┘
```

- Toucher une connexion ouvre directement **Workspace / Accueil**.
- Appui long ou menu `⋮` : modifier, tester, exporter, supprimer.
- Aucun accès intermédiaire à une ancienne liste de sessions.

### 4.2 Accueil `[ ]`

But : dire immédiatement **ce qui mérite l’attention**, sans répéter tous les chats.

```text
┌──────────────────────────────────────┐
│ Bonjour Carlos       Miniserver ●  🔍│
│                                      │
│ ACTION REQUISE                    (2)│
│ ┌ Approbation nécessaire ─────────┐ │
│ │ Projet X · depuis 8 min [Ouvrir]│ │
│ └─────────────────────────────────┘ │
│                                      │
│ EN COURS                          (1)│
│ ┌ Analyse APK  63% · 04:12 ──────┐ │
│ │ Projet Hermes Android  [Ouvrir]│ │
│ └─────────────────────────────────┘ │
│                                      │
│ À REPRENDRE                       → │
│ • Titre du chat · Projet · hier     │
│ • Titre du chat · Non classé · 3 j  │
│                                      │
│ Rien à signaler = état calme conçu  │
└──────────────────────────────────────┘
```

Ordre fixe : **Action requise → En cours → Suggestions IA → À reprendre**.

- Maximum proposé : 3 éléments par section, puis **Voir tout**.
- Une conversation terminée sans intérêt récent n’est pas affichée ici.
- Toucher une carte ouvre directement le chat ou l’action exacte.
- `🔍` ouvre la recherche globale dans **Chats**.

### 4.3 Chats `[ ]` — remplacement complet de l’ancienne interface

But : rendre **toutes les sessions** accessibles, lisibles et organisables depuis Workspace.

```text
┌──────────────────────────────────────┐
│ Chats                         🔍  ⋮  │
│ [Tous] [Récents] [Non classés] [Arc]│
│ Trier : Dernière activité       ≡/▦ │
│                                      │
│ AUJOURD’HUI                          │
│ ┌ ● Migration Android ────────────┐ │
│ │ Hermes Android · En cours       │ │
│ │ “Je vérifie le build…” · 2 min  │ │
│ └─────────────────────────────────┘ │
│ ┌   Question comptabilité ────────┐ │
│ │ Non classé · Terminé            │ │
│ │ “Le cash-flow…” · 1 h           │ │
│ └─────────────────────────────────┘ │
│                                      │
│ HIER                                 │
│ ...                                  │
│                              [  +  ] │
└──────────────────────────────────────┘
```

Chaque ligne/carte affiche une seule fois :

- titre ;
- aperçu d’une ligne ;
- Project ou **Non classé** ;
- état : action requise / en cours / échec / terminé ;
- dernière activité ;
- indicateur non lu si disponible.

Interactions :

- toucher : ouvrir le chat ;
- glisser : archiver ou marquer lu, avec Annuler ;
- appui long : déplacer vers un Project, renommer, épingler, archiver, supprimer ;
- recherche : titre, aperçu, Project, modèle et identifiant ;
- filtres combinables : état, Project, date, modèle, profil ;
- changement liste/grille mémorisé localement.

**Non classés** et **Archivés** sont des filtres du même écran, pas des écrans/listes dupliqués.

### 4.4 Recherche globale `[ ]`

```text
┌──────────────────────────────────────┐
│ ← Rechercher dans Hermes             │
│ [ migration android____________ ]  × │
│ [Chats 12] [Projets 2] [Fichiers 4] │
│                                      │
│ Résultats groupés, sans doublons     │
│ • Chat — Migration Android           │
│ • Projet — Hermes Android            │
│ • Fichier — docs/migration.md         │
└──────────────────────────────────────┘
```

- Même composant depuis Accueil, Chats ou Plus.
- Onglets de type de résultat, pas plusieurs recherches indépendantes.
- Un résultat ouvre directement sa destination.

### 4.5 Projets `[ ]`

```text
┌──────────────────────────────────────┐
│ Projets                       🔍  +  │
│ [Actifs] [Archivés]                  │
│                                      │
│ ┌ ⚙ Hermes Android ───────────────┐ │
│ │ Phase 1 · 1 en cours · 2 bloqués│ │
│ │ 14 chats · activité il y a 2 min│ │
│ └─────────────────────────────────┘ │
│ ┌ 🚗 C-MAY ───────────────────────┐ │
│ │ Documentation et suivi          │ │
│ │ 8 chats · activité hier         │ │
│ └─────────────────────────────────┘ │
└──────────────────────────────────────┘
```

- Les cartes montrent l’état utile, pas seulement un nombre de chats.
- Menu unique : renommer, couleur/icône, archiver/restaurer, supprimer.
- Supprimer un Project ne supprime jamais ses chats ; ils deviennent **Non classés**.

### 4.6 Détail d’un Project `[ ]`

```text
┌──────────────────────────────────────┐
│ ← Hermes Android               ⋮    │
│ Phase 1 · 1 en cours · 2 bloqués    │
│ [Aperçu][Chats][Fichiers][Ress.][Act]│
├──────────────────────────────────────┤
│ Contenu de l’onglet actif            │
│                                      │
│ Chats : même composant que Chats,    │
│ automatiquement filtré par Project.  │
│                              [  +  ] │
└──────────────────────────────────────┘
```

- **Aperçu** : but, état actuel, éléments épinglés, prochaine action.
- **Chats** : composant partagé avec l’écran Chats, filtré par ce Project.
- **Fichiers** : dossiers serveur du Project.
- **Ressources** : pièces jointes et artefacts générés.
- **Activité** : événements de ce Project seulement.
- `+` crée un chat déjà assigné au Project avant son ouverture.

### 4.7 Activité `[ ]`

```text
┌──────────────────────────────────────┐
│ Activité                 [Filtres]   │
│ [Action requise] [Cours] [Finis] [⚠]│
│                                      │
│ MAINTENANT                            │
│ ⚠ Clarification · Projet X [Répondre]│
│ ● Build APK · 63%          [Ouvrir]  │
│                                      │
│ AUJOURD’HUI                           │
│ ✓ Analyse terminée · 09:42           │
└──────────────────────────────────────┘
```

- Les éléments bloqués restent en tête.
- Actions sûres directement dans la carte ; sinon ouverture de l’écran exact.
- Filtre par Project, profil, état et période.
- Activité n’est pas une autre liste de chats : elle liste des événements/tâches.

### 4.8 Plus `[ ]`

```text
┌──────────────────────────────────────┐
│ Plus                                 │
│ CONTENU                              │
│ Fichiers · Ressources · Recherche    │
│ AUTOMATISATION                       │
│ Cron · Skills et outils · MCP        │
│ HERMES                               │
│ Mémoire · Profils · Plugins          │
│ SYSTÈME                              │
│ Diagnostics · Réglages               │
└──────────────────────────────────────┘
```

- Sections courtes et stables.
- Pas de raccourcis qui répètent Accueil, Chats, Projets ou Activité.

### 4.9 Chat plein écran `[ ]`

```text
┌──────────────────────────────────────┐
│ ← Titre du chat                  ⋮   │
│ Projet · Modèle · Connecté ●         │
├──────────────────────────────────────┤
│ Carlos                               │
│ Message                              │
│                                      │
│ Hermes                               │
│ Réponse                              │
│ ┌ Outil · terminal · 4,2 s · ✓ ───┐ │
│ │ Résumé replié             [Voir] │ │
│ └──────────────────────────────────┘ │
│                                      │
├──────────────────────────────────────┤
│ [＋] Écrire un message… [🎙] [Envoyer]│
└──────────────────────────────────────┘
```

- En-tête collant : Project, modèle, effort, connexion.
- Texte utilisateur, réponse, raisonnement, appels d’outils et erreurs visuellement distincts.
- Outils repliés par défaut avec statut, durée et résumé.
- Composer multiligne avec pièces jointes, voix, choix modèle/effort, envoyer/arrêter.
- Actions de message par appui long, pas une rangée d’icônes répétée.

### 4.10 Création d’un chat `[ ]`

```text
┌──────────────────────────────────────┐
│ Nouveau chat                         │
│                                      │
│ ⚡ Chat rapide                       │
│    Commencer sans choisir de Project │
│                                      │
│ 📁 Chat de projet                    │
│    [Choisir ou rechercher un Project]│
│                                      │
│ Modèle et effort       [Par défaut >]│
└──────────────────────────────────────┘
```

- Chat rapide : apparaît dans **Chats / Non classés**.
- Chat de projet : assignation serveur effectuée avant l’ouverture.
- Aucun second formulaire de création ailleurs dans l’app.

---

## 5. États obligatoires pour chaque écran `[ ]`

Chaque surface définit explicitement :

- chargement par skeleton ;
- vide utile avec action suivante ;
- hors ligne avec contenu en cache clairement marqué ;
- erreur avec Réessayer ;
- Gateway trop ancien / capacité indisponible ;
- permission refusée ;
- rafraîchissement ;
- texte agrandi et lecteur d’écran ;
- clair, sombre, téléphone étroit et tablette.

---

## 6. Décisions validées avec Carlos (2026-08-30)

- [x] Navigation finale à **5 onglets**, avec **Chats** toujours visible.
- [x] **Accueil** reste un digest priorisé et ne montre jamais la liste complète.
- [x] L’ancienne liste de sessions est supprimée ; **Chats** la remplace dans Workspace.
- [x] Non classés, Récents et Archivés deviennent des filtres de Chats, pas des pages séparées.
- [x] Détail Project à cinq onglets : Aperçu, Chats, Fichiers, Ressources, Activité (livré 2026-08-30, ordre Chats/Overview/Files/Assets/Activity pour rester sessions-first).
- [x] Le bouton `+` global propose uniquement Chat rapide ou Chat de projet.
- [x] La recherche est globale et partagée, sans implémentations concurrentes.
