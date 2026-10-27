#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Generando paquete de recursos PCK..."
mkdir -p build
godot --headless --export-pack "Linux" "build/SwiftPiano.pck"

echo "==> Configurando binario ejecutable independiente..."
GODOT_BIN="$(command -v godot)"
if [ -z "$GODOT_BIN" ]; then
    echo "Error: No se encontro el binario de Godot en el sistema." >&2
    exit 1
fi
cp "$GODOT_BIN" "build/SwiftPiano"
chmod +x "build/SwiftPiano"
chmod +x "bin/swiftpiano"
chmod +x "SwiftPiano"

echo "==> Instalando lanzador de escritorio..."
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$APPS_DIR"
cp "assets/swiftpiano.desktop" "$APPS_DIR/swiftpiano.desktop"
chmod +x "$APPS_DIR/swiftpiano.desktop"

DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Escritorio}"
if [ -d "$DESKTOP_DIR" ]; then
    cp "assets/swiftpiano.desktop" "$DESKTOP_DIR/swiftpiano.desktop"
    chmod +x "$DESKTOP_DIR/swiftpiano.desktop"
    echo "==> Acceso directo creado en: $DESKTOP_DIR/swiftpiano.desktop"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi

echo "==> SwiftPiano compilado e instalado con exito."
echo "    - Ejecutable directo: $ROOT_DIR/SwiftPiano"
echo "    - Paquete binario:    $ROOT_DIR/build/SwiftPiano"
echo "    - Lanzador aplicacion: $APPS_DIR/swiftpiano.desktop"
