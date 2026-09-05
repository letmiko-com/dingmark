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

## Rendu des PNG du catalogue

`Dingmark/Resources/Assets.xcassets/AppIcon.appiconset/` contient trois PNG
1024×1024 (light, dark, tinted) rendus par CoreGraphics depuis la même
géométrie. Ne jamais retoucher les PNG : modifier le script, puis

```sh
swift design/icon/render-icon.swift
```

L'icône light est opaque (App Store Connect refuse un canal alpha sur l'icône
principale). L'icône tinted est un glyphe gris sur transparence : le système
fournit le fond et applique la teinte.

Dans l'app, le même dessin est tracé en SwiftUI (`Shared/UI/RibbonMark.swift`)
pour l'écran de connexion, l'en-tête de la share extension et les widgets :
aucune image bitmap n'est nécessaire hors du catalogue d'icône.
