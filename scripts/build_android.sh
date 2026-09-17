#!/usr/bin/env bash
# Construit l'APK debug dans build/.
#
# Prérequis : modèles d'export Android de Godot (même version que l'éditeur), JDK 17,
# SDK Android avec build-tools, keystore de debug.
#
# Version : versionCode = nombre de commits (toujours croissant, Android refuse d'installer une
# version plus ancienne par-dessus), versionName = git describe (ex. v0.2.0).
#
# Signature : tous les APK doivent être signés avec le même keystore, sinon une mise à jour
# exige de désinstaller le jeu. Par défaut, le keystore de debug de Godot sur cette machine ;
# la CI reçoit le même via un secret GitHub (voir README, « Publier une version »).
#
# Variables facultatives : GODOT (exécutable), ANDROID_HOME (SDK, utilisé quand le chemin
# n'est pas réglé dans les paramètres de l'éditeur Godot), GODOT_ANDROID_KEYSTORE_DEBUG_PATH,
# GODOT_ANDROID_KEYSTORE_DEBUG_USER, GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD,
# APP_VERSION_CODE, APP_VERSION_NAME.
set -euo pipefail

cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
PRESET="Android Debug"
OUTPUT="build/repa_debug.apk"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
if [ ! -d "$ANDROID_HOME/build-tools" ]; then
	echo "SDK Android introuvable ou sans build-tools : $ANDROID_HOME (définir ANDROID_HOME)" >&2
	exit 1
fi

export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$HOME/.local/share/godot/keystores/debug.keystore}"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"

if [ ! -f "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ]; then
	echo "Keystore de debug introuvable : $GODOT_ANDROID_KEYSTORE_DEBUG_PATH" >&2
	exit 1
fi

# export_presets.cfg est ignoré par git : le modèle versionné sert de point de départ.
if [ ! -f export_presets.cfg ]; then
	cp scripts/export_presets.android.cfg export_presets.cfg
	echo "export_presets.cfg créé depuis scripts/export_presets.android.cfg"
fi

VERSION_CODE="${APP_VERSION_CODE:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
VERSION_NAME="${APP_VERSION_NAME:-$(git describe --tags --always --dirty 2>/dev/null || echo 0.0.0)}"
if ! [[ "$VERSION_CODE" =~ ^[0-9]+$ ]]; then
	echo "APP_VERSION_CODE doit être un entier : $VERSION_CODE" >&2
	exit 1
fi
sed -i -E "s|^version/code=.*|version/code=${VERSION_CODE}|; s|^version/name=.*|version/name=\"${VERSION_NAME}\"|" export_presets.cfg
# La même version dans le jeu : l'écran de diagnostic l'affiche, un testeur peut la lire.
# project.godot est versionné : on le remet en l'état en sortant, sinon le build suivant se
# croirait « dirty » et l'arbre de travail resterait modifié.
PROJECT_BACKUP="$(mktemp)"
cp project.godot "$PROJECT_BACKUP"
trap 'mv -f "$PROJECT_BACKUP" project.godot' EXIT
sed -i -E "s|^config/version=.*|config/version=\"${VERSION_NAME}\"|" project.godot
echo "Version : ${VERSION_NAME} (code ${VERSION_CODE})"

"$GODOT" --headless --path . --import
if ! "$GODOT" --headless --path . --script res://tests/run_tests.gd; then
	echo "Tests en échec : APK non construit." >&2
	exit 1
fi

mkdir -p build
rm -f "$OUTPUT"
# Godot peut terminer avec le code 0 malgré une erreur d'export : on vérifie le fichier.
"$GODOT" --headless --path . --export-debug "$PRESET" "$OUTPUT" || true
if [ ! -s "$OUTPUT" ]; then
	echo "Échec de l'export : $OUTPUT absent (voir les erreurs ci-dessus)." >&2
	exit 1
fi

echo "APK : $OUTPUT"
echo "Installer sur un téléphone branché : adb install -r $OUTPUT"
