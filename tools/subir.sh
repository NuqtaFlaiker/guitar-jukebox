#!/usr/bin/env bash
# subir.sh — Sube a GitHub Pages las canciones nuevas de songs/ en un paso.
#
# Uso: ./tools/subir.sh          (o doble clic en "Subir canciones.cmd")
#
# Hace todo el flujo:
#   1. Normaliza los MP3 nuevos y regenera catalog.txt (los títulos que ya
#      estaban en el catálogo se conservan tal cual, aunque estén editados).
#   2. git add + commit + push (usa las credenciales de gh, cuenta NuqtaFlaiker).
#   3. Espera a que GitHub Pages publique el catálogo nuevo y lo verifica.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="https://nuqtaflaiker.github.io/guitar-jukebox"
cd "$ROOT"

echo "== 1/3 Normalizando canciones y regenerando catálogo =="
"$ROOT/tools/normalize.sh"
echo ""

if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "No hay cambios que subir: la carpeta songs/ y el catálogo ya están publicados."
    exit 0
fi

echo "== 2/3 Subiendo a GitHub =="
git add -A
git commit -m "Añade canciones nuevas ($(date +%F))"
# El credential helper de gh evita el prompt gráfico de credenciales.
git -c 'credential.helper=!gh auth git-credential' push origin main
echo ""

echo "== 3/3 Esperando a que GitHub Pages publique (1-2 min) =="
for i in $(seq 1 30); do
    if curl -fsS "$BASE_URL/catalog.txt" 2>/dev/null | cmp -s - "$ROOT/catalog.txt"; then
        echo ""
        echo "✔ Publicado y verificado. Catálogo en producción:"
        echo ""
        grep -v '^\s*#' "$ROOT/catalog.txt" | grep -v '^\s*$' | sed 's/|.*//' | sed 's/^/   ♪ /'
        echo ""
        echo "Toca la guitarra en Second Life y las canciones nuevas ya salen en el menú."
        exit 0
    fi
    printf '.'
    sleep 10
done

echo ""
echo "AVISO: el push se hizo bien, pero tras 5 minutos GitHub Pages aún no sirve" >&2
echo "el catálogo nuevo. Suele ser cuestión de esperar un poco más; compruébalo en:" >&2
echo "  $BASE_URL/catalog.txt" >&2
exit 1
