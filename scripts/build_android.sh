#!/usr/bin/env bash
# Construit l'APK debug dans build/.
#
# Prérequis : modèles d'export Android de Godot (même version que l'éditeur), JDK 17,
# SDK Android avec build-tools, keystore de debug.
#
# Variables facultatives : GODOT (exécutable), ANDROID_HOME (SDK, utilisé quand le chemin
# n'est pas réglé dans les paramètres de l'éditeur Godot), GODOT_ANDROID_KEYSTORE_DEBUG_PATH,
# GODOT_ANDROID_KEYSTORE_DEBUG_USER, GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD.
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
