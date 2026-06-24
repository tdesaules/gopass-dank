# Gopass-Dank

Plugin [DankMaterialShell](https://danklinux.com) de type **Launcher** permettant de rechercher et lister les secrets stockés dans un vault [gopass](https://github.com/gopasspw/gopass) (backend `age`) directement depuis la barre de recherche du launcher.

## Fonctionnalités

- Mot-clé `pass` dans le launcher pour activer la recherche
- **Sync git automatique** (`gopass sync`) à l'activation pour récupérer les entrées ajoutées sur le remote
- Liste et filtrage des secrets du vault gopass en temps réel
- Recherche multi-mots (tous les termes doivent correspondre, insensible à la casse)
- Cache local des chemins de secrets pour un affichage instantané
- Rafraîchissement automatique en arrière-plan (configurable)
- Copie du mot de passe dans le presse-papier via `gopass show -c` (sélection d'un secret)

## Prérequis

- [DankMaterialShell](https://danklinux.com) >= 1.4.0
- [gopass](https://github.com/gopasspw/gopass) installé et configuré avec le backend `age`
- Le vault gopass doit être initialisé (`gopass init`)

## Installation

### Depuis GitHub

```sh
mkdir -p ~/.config/DankMaterialShell/plugins
cd ~/.config/DankMaterialShell/plugins
git clone https://github.com/tdesaules/gopass-dank.git gopassDank
dms restart
```

### Activation

1. Ouvrir **Settings -> Plugins**
2. Cliquer sur **Scan for Plugins**
3. Activer le plugin **Gopass-Dank**
4. Redémarrer le shell : `dms restart`

## Utilisation

1. Ouvrir le launcher (Ctrl+Space ou le bouton launcher)
2. Taper `pass` : le plugin se lance, **sync automatique** avec git puis listage des secrets
3. Affiner avec des mots-clés : `pass github token`
4. Sélectionner un secret et appuyer sur Entrée pour copier le mot de passe dans le presse-papier

Au moment de l'activation (quand on tape `pass`), le plugin exécute automatiquement `gopass sync` (git pull/push) puis `gopass list --flat` pour rafraîchir la liste. Les secrets en cache sont affichés immédiatement pendant que la sync s'effectue en arrière-plan, puis la liste se met à jour automatiquement à la fin de la sync.

Pour éviter des syncs trop fréquentes, un intervalle minimum est respecté (par défaut 60s). Si la sync échoue (ex: pas de réseau), le cache local est utilisé et un toast s'affiche.

Le nom affiché correspond au dernier segment du chemin du secret, et le commentaire affiche le chemin parent.

Exemple pour un secret `websites/github.com/tdesaules` :
- **Nom** : `tdesaules`
- **Commentaire** : `websites / github.com`

## Configuration

Les paramètres sont disponibles dans **Settings -> Plugins -> Gopass-Dank** :

| Paramètre | Description | Valeur par défaut |
|-----------|-------------|-------------------|
| Trigger | Mot-clé d'activation dans le launcher | `pass` |
| Gopass Binary | Chemin vers l'exécutable gopass | `gopass` |
| Max Results | Nombre maximum de secrets affichés | `50` |
| Auto Refresh | Rafraîchissement automatique du cache | activé |
| Refresh Interval | Intervalle du rafraîchissement automatique | `300s` |
| Sync on Activation | Sync git automatique à l'activation du plugin | activé |
| Sync Interval | Intervalle minimum entre deux syncs git | `60s` |

> Note : après avoir modifié le trigger, recharger le plugin avec `dms ipc call plugins reload gopassDank`.

## Architecture

```
gopass-dank/
├── plugin.json          # Manifeste du plugin
├── GopassLauncher.qml   # Composant launcher (recherche + listage)
├── GopassSettings.qml   # Interface de paramètres
├── README.md
└── LICENSE
```

### Fonctionnement

1. Au chargement, le plugin exécute `gopass list --flat` pour récupérer tous les chemins de secrets et alimente le cache
2. Les chemins sont mis en cache en mémoire et persistés dans le state du plugin pour un affichage instantané au prochain chargement
3. À l'activation (taper `pass`), le plugin exécute `gopass sync` (git pull/push) puis `gopass list --flat` pour récupérer les entrées distantes
4. `getItems(query)` filtre le cache de manière synchrone (recherche multi-mots insensible à la casse)
5. `executeItem` lance `gopass show -c <secret>` qui déchiffre et copie le mot de passe dans le presse-papier
6. Un rafraîchissement automatique se déclenche si le cache est vide ou périmé

> `gopass list --flat` ne déchiffre aucun secret, il liste uniquement les chemins stockés en clair sur le disque. Aucune phrase de passe n'est nécessaire pour le listage. La copie (`gopass show -c`) déchiffre le secret et peut déclencher une demande de phrase de passe age via pinentry si elle n'est pas en cache.
>
> `gopass sync` effectue un git pull/push sur le store. Les credentials git doivent être configurés (clé SSH ou credential helper) pour éviter un blocage. En cas d'échec de la sync, le cache local est utilisé.

## Développement

```sh
# Cloner le dépôt DMS pour le support IDE
git clone https://github.com/AvengeMedia/DankMaterialShell.git ~/repos/DankMaterialShell
cd ~/repos/DankMaterialShell/quickshell

# Symlink du plugin pour le développement
ln -sf ~/.config/DankMaterialShell/plugins/gopassDank \
       ~/repos/DankMaterialShell/quickshell/dms-plugins/gopassDank

# Recharger le plugin après modifications
dms ipc call plugins reload gopassDank

# Voir le statut
dms ipc call plugins list
```

## Licence

MIT
