# Dingmark

Client iOS et iPadOS natif pour [linkding](https://github.com/sissbruecker/linkding), le gestionnaire de favoris self-hosted. Éditeur : Letmiko.

Connexion à une instance par son adresse et un jeton d'API, liste avec recherche et filtres rapides, tags, détail, ajout et modification, share extension depuis Safari, widgets (écran d'accueil et écran verrouillé), réglages. Aucun compte, aucun cloud : les favoris ne quittent jamais le serveur de l'utilisateur.

## Prérequis

- Xcode 26 (SDK iOS 26), cible iOS et iPadOS 26.0 minimum.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) : `brew install xcodegen`.
- Une instance linkding joignable (ou le mode démonstration, voir plus bas).

## Commandes

Le projet Xcode n'est pas versionné : il est régénéré depuis `project.yml`.

```sh
# après un clone, après une modification de project.yml, ou quand des
# fichiers Swift sont ajoutés ou supprimés
xcodegen
open Dingmark.xcodeproj

# compilation Debug pour le simulateur
xcodebuild -project Dingmark.xcodeproj -scheme Dingmark \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build

# tests unitaires
xcodebuild -project Dingmark.xcodeproj -scheme Dingmark \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# icône : regénérer les PNG du catalogue depuis la géométrie SVG
swift design/icon/render-icon.swift
```

Mode démonstration : lancer l'app avec l'argument `-demo` (ou la variable d'environnement `DINGMARK_DEMO=1`) pour servir les onze favoris du prototype de design sans serveur. C'est ce que consomment les previews, les captures et les tests d'interface.

## Architecture

```
Dingmark/          app (SwiftUI) : écrans, navigation, SFSafariViewController
DingmarkShare/     share extension (UIHostingController, detents medium et large)
DingmarkWidgets/   WidgetKit : petit, moyen, circulaire, rectangulaire
Shared/            compilé dans les trois cibles
  Models/          Bookmark, DTO de l'API, décodage des dates linkding
  API/             LinkdingAPI (protocole), LinkdingClient (URLSession), confiance TLS
  Storage/         App Group, Keychain (jeton), cache JSON, clés de réglages
  Store/           Session, BookmarkStore (mises à jour optimistes), modèle du formulaire
  UI/              composants : cellule, chips, champ de tags, FlowLayout, icône vectorielle
  Demo/            fixtures du prototype et client en mémoire
DingmarkTests/     tests unitaires (Swift Testing) : client mocké, décodage, filtres, tags
design/icon/       sources SVG de l'icône et script de rendu
```

Choix structurants :

- **Technologies Apple uniquement** : SwiftUI, Observation, WidgetKit, App Groups, Keychain, URLSession, SafariServices. Aucune dépendance tierce.
- **Composants système d'abord** : `List(.plain)`, `.searchable`, `.swipeActions`, `.contextMenu(preview:)`, `ContentUnavailableView`, `.redacted`, `NavigationSplitView`, `Tab`, `.glassProminent`. Trois vues custom, parce qu'aucun contrôle système ne les couvre : la barre de filtres (défilement et compteurs), le champ de tags (chips supprimables et suggestions) et le wrapper `SFSafariViewController`.
- **Mise à jour optimiste partout** : état local d'abord, requête ensuite, retour arrière silencieux et bannière discrète en cas d'échec.
- **Cache dans l'App Group** : lecture hors ligne, données des widgets, mise à jour par la share extension.
- **Jeton dans le Keychain** partagé via l'App Group, jamais dans les préférences ni les journaux.
- **Certificat auto-signé** : refusé par défaut, empreinte SHA-256 épinglée après confirmation explicite sur l'écran de connexion.

## API linkding utilisée

`GET/POST /api/bookmarks/`, `GET /api/bookmarks/archived/`, `PATCH/DELETE /api/bookmarks/<id>/`, `POST /api/bookmarks/<id>/archive/` et `unarchive/`, `GET /api/bookmarks/check/?url=`, `GET /api/tags/`. En-tête `Authorization: Token <jeton>`. La recherche et les filtres s'appliquent en local sur le cache complet, ce qui fonctionne hors ligne.

## Design

Les écrans recréent le handoff Claude Design « Dingmark » (prototype cliquable, planches de spec, icône « Ruban »). Tokens : accent teal `rgb(0,199,190)` clair et `rgb(0,210,224)` sombre, couleurs sémantiques du système, styles de texte Dynamic Type, marges 16 pt, groupes rayon 26, capsules 32 pt pour les filtres, boutons pleins 50 pt.

## Captures

Prises au simulateur (iPhone 17 et iPad Pro 11", iOS 26.5) par `DingmarkUITests/ScreenshotTests.swift` en mode démonstration. Pour les régénérer :

```sh
xcodebuild -project Dingmark.xcodeproj -scheme Dingmark \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:DingmarkUITests -resultBundlePath build/ui.xcresult test
xcrun xcresulttool export attachments --path build/ui.xcresult --output-path build/shots
```

| Connexion | Liste | Détail | Ajout |
|---|---|---|---|
| ![](docs/screenshots/iphone-connexion.png) | ![](docs/screenshots/iphone-liste.png) | ![](docs/screenshots/iphone-detail.png) | ![](docs/screenshots/iphone-ajout.png) |

| Tags | Réglages | Sombre | iPad |
|---|---|---|---|
| ![](docs/screenshots/iphone-tags.png) | ![](docs/screenshots/iphone-reglages.png) | ![](docs/screenshots/iphone-liste-sombre.png) | ![](docs/screenshots/ipad-split-view.png) |
