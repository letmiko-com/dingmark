# CLAUDE.md

Dingmark : client iOS/iPadOS 26+ pour linkding (SwiftUI, technologies Apple uniquement). Éditeur Letmiko. Le README décrit l'architecture et les commandes ; ce fichier ne garde que ce qui n'en découle pas.

## Commandes

`Dingmark.xcodeproj` n'est pas versionné : `xcodegen` le régénère depuis `project.yml`. À relancer après tout ajout ou suppression de fichier Swift, sinon Xcode ne voit pas le fichier.

```sh
xcodegen
xcodebuild -project Dingmark.xcodeproj -scheme Dingmark -destination 'generic/platform=iOS Simulator' -configuration Debug build
xcodebuild -project Dingmark.xcodeproj -scheme Dingmark -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Sans serveur : lancer avec `-demo` (données du prototype servies par `DemoLinkdingClient`).

Tests contre un linkding réel (`RealServerTests`) : serveur Docker jetable, jeton `ApiToken`, seed par `scripts/seed-linkding.py`, variables `TEST_RUNNER_DINGMARK_TEST_SERVER` et `TEST_RUNNER_DINGMARK_TEST_TOKEN` (voir README). Le jeton ne s'écrit nulle part dans le dépôt.

## Règles du projet

- Un composant système existe ? L'utiliser. Les seules vues custom acceptées sont la barre de filtres, le champ de tags et le wrapper `SFSafariViewController` (voir README).
- Pas d'`Alert` pour les erreurs de connexion ou d'enregistrement : carte sous le formulaire ou pied de section.
- Toute mutation est optimiste (`BookmarkStore`) : état local, requête, rollback silencieux. Ne pas introduire de spinner bloquant.
- Le jeton d'API ne passe que par `KeychainStore`. Jamais dans `UserDefaults`, les logs, les tests ou les fixtures.
- Les chaînes visibles sont en français dans le code (clé) avec leur traduction anglaise dans `Shared/Resources/Localizable.xcstrings`. Une nouvelle chaîne = une entrée ajoutée au fichier.
- `Shared/` est compilé dans l'app, la share extension et les widgets : pas de `SafariServices` ni de code spécifique à l'app dedans.
- Un bug corrigé dans la logique (client, filtres, tags, dates) se prouve par un test dans `DingmarkTests/`.
- Tokens visuels dans `Shared/UI/Theme.swift` (`Metrics`, `Color.dingmarkAccent`) : ne pas coder de valeurs en dur dans les vues.
- Icône : modifier les SVG ou `design/icon/render-icon.swift`, jamais les PNG.
