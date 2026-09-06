# Icône « Ruban »

Sources SVG issues du handoff Claude Design (projet « Design requirements
clarification », dossier `icon/final/`), métadonnées C2PA retirées :

| Fichier | Rôle |
|---|---|
| `light.svg` | Apparence par défaut : fond teal `#00C7BE`, bande blanche, pli `#007F7A` |
| `dark.svg` | Apparence sombre : fond `#0A2E2C`, bande teal |
| `mono.svg` | Glyphe monochrome (Tinted et Clear) |
| `widget-light.svg` | Glyphe seul à 72 %, pour les widgets et les endroits où le fond est fourni |

Géométrie (grille 1024) : bande 220 de large, pli à 45°, échancrure 90, marges
150 en haut et 234 en bas. Les fichiers sont carrés pleins : iOS applique
lui-même le masque squircle.

## Icône de l'app : le paquet en couches

`Dingmark/Resources/AppIcon.icon/` est la seule source de l'icône de l'app
(format Icon Composer, Xcode 26). Il contient `icon.json` et deux couches
vectorielles dans `Assets/` :

| Couche | Contenu |
|---|---|
| `band.svg` | la bande, blanche par défaut, teal `#00C7BE` en apparence sombre |
| `fold.svg` | le pli, `#007F7A` dans toutes les apparences |

Le fond n'est pas une image mais le `fill` de l'icône : teal `#00C7BE` par
défaut, `#0A2E2C` en apparence sombre. Le système fabrique lui-même les
rendus sombre, teinté et Clear à partir de ces couches, et applique le relief
Liquid Glass (ombre et reflet spéculaire) : aucun PNG d'apparence à fournir.
`ASSETCATALOG_COMPILER_APPICON_NAME` vaut `AppIcon`, le nom du paquet.

Modifier l'icône = modifier `icon.json` ou les deux SVG de `Assets/`, puis
rebuilder. Le paquet s'ouvre aussi dans Icon Composer (Xcode > Open Developer
Tool). Vérifier après coup que les trois apparences sont bien compilées :

```sh
xcrun assetutil --info <build>/Dingmark.app/Assets.car | grep -A1 "Icon Image"
# attendu : une rendition par défaut, une UIAppearanceDark, une ISAppearanceTintable
```

Piège constaté le 2026-09-06 : le SpringBoard du simulateur garde les icônes
en cache et n'affiche pas le variant sombre même après désinstallation et
réinstallation (il a même affiché un mélange de deux icônes). La preuve du
rendu par apparence se lit dans le `.car`, pas sur l'écran d'accueil du
simulateur.

## Rendu des PNG hors app

`design/icon/render-icon.swift` produit trois PNG 1024 dans `design/icon/out/`
(ignoré par git) pour les usages hors app : site web, fiche de store, aperçu
social. Ils ne sont plus l'icône de l'app.

```sh
swift design/icon/render-icon.swift
```

Dans l'app, le même dessin est tracé en SwiftUI (`Shared/UI/RibbonMark.swift`)
pour l'écran de connexion, l'en-tête de la share extension et les widgets :
aucune image bitmap n'est nécessaire hors du catalogue d'icône.
