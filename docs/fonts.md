# Polices auto-hébergées

Les fichiers sont dans `app/assets/fonts`, servis par l'application et jamais
par Google Fonts : aucun appel sortant depuis le navigateur du visiteur
(exigence RGPD du cahier des charges).

| Fichier                     | Famille          | Graisse   | Usage                   |
| --------------------------- | ---------------- | --------- | ----------------------- |
| `BarlowCondensed-600.woff2` | Barlow Condensed | 600       | Titres                  |
| `BarlowCondensed-700.woff2` | Barlow Condensed | 700       | Titres forts, chiffres  |
| `Figtree.woff2`             | Figtree          | 400 → 700 | Corps et interface      |

**Figtree est une police variable** : un seul fichier couvre tout l'axe de
graisse utilisé par l'interface. L'API Google Fonts sert le même fichier quelle
que soit la graisse demandée — télécharger `400`, `500`, `600` et `700`
donnerait quatre copies identiques. La règle `@font-face` déclare donc
`font-weight: 400 700`.

Barlow Condensed, elle, est une famille statique : deux fichiers distincts.

Sous-ensemble **latin** uniquement (`U+0000-00FF`, `U+0152-0153`, `U+20AC`…),
ce qui couvre les accents français, la ligature œ et le symbole €.

## Chemin des assets

`app/assets/fonts` est ajouté comme racine d'assets dans
`config/initializers/assets.rb`. Les chemins logiques sont donc plats, et les
`url("Figtree.woff2")` de `app/assets/tailwind/application.css` se résolvent
depuis `app/assets/builds/tailwind.css`, qui est lui aussi à plat. Propshaft
réécrit ces URL avec leur empreinte au moment de servir la feuille.

## Licences

Les deux familles sont publiées sous **SIL Open Font License 1.1**, qui
autorise l'auto-hébergement et la redistribution.

- Barlow Condensed — © Jeremy Tribby, <https://github.com/jpt/barlow>
- Figtree — © Erik Kennedy, <https://github.com/erikdkennedy/figtree>

Texte de la licence : <https://openfontlicense.org/open-font-license-official-text/>

## Mise à jour

Les fichiers sont téléchargés depuis l'API Google Fonts puis versionnés ici.
Ne pas les remplacer par un `<link>` vers `fonts.googleapis.com`.
