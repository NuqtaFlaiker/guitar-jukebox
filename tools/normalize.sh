#!/usr/bin/env bash
# normalize.sh — Renombra los MP3 de songs/ a slugs seguros para URL
# (minúsculas, sin espacios ni acentos) y regenera catalog.txt.
#
# Uso:  ./tools/normalize.sh [carpeta-songs]
#       (por defecto usa ./songs relativo a la raíz del proyecto)
#
# El título visible del catálogo se toma del nombre de archivo ORIGINAL
# (sin la extensión), así que nombra tus MP3 como quieras que se lean
# en el menú, p.ej. "Canción del Mariachi.mp3".
#
# Los títulos de canciones que YA estaban en catalog.txt se conservan tal
# cual (puedes editarlos a mano y no se pierden al volver a ejecutar esto).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SONGS_DIR="${1:-$ROOT/songs}"
CATALOG="$ROOT/catalog.txt"

if [ ! -d "$SONGS_DIR" ]; then
    echo "No existe la carpeta: $SONGS_DIR" >&2
    exit 1
fi

# Convierte un nombre a slug URL-safe: translitera acentos a ASCII (si hay
# iconv disponible; Git Bash en Windows no lo trae), pasa a minúsculas,
# reemplaza todo lo que no sea [a-z0-9.] por guiones y colapsa repetidos.
slugify() {
    local s="$1"
    if command -v iconv >/dev/null 2>&1; then
        s="$(printf '%s' "$s" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$s")"
    fi
    printf '%s' "$s" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9.]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//'
}

# Títulos ya presentes en el catálogo actual: se conservan aunque el usuario
# los haya editado a mano. Clave = nombre de archivo, valor = título.
declare -A OLD_TITLES=()
if [ -f "$CATALOG" ]; then
    while IFS='|' read -r t f; do
        t="$(printf '%s' "$t" | tr -d '\r')"
        f="$(printf '%s' "$f" | tr -d '\r')"
        case "$t" in ''|'#'*) continue ;; esac
        [ -n "$f" ] && OLD_TITLES["$f"]="$t"
    done < "$CATALOG"
fi

{
    echo "# Catálogo generado por tools/normalize.sh el $(date +%F)"
    echo "# Formato: Título visible|archivo.mp3"
    echo ""
} > "$CATALOG"

count=0
shopt -s nullglob nocaseglob
for f in "$SONGS_DIR"/*.mp3; do
    base="$(basename "$f")"
    title="${base%.*}"
    slug="$(slugify "$base")"

    if [ "$base" != "$slug" ]; then
        if [ -e "$SONGS_DIR/$slug" ]; then
            echo "AVISO: '$slug' ya existe; se omite '$base'" >&2
            continue
        fi
        mv "$f" "$SONGS_DIR/$slug"
        echo "renombrado: $base -> $slug"
    fi

    # Si la canción ya estaba catalogada, se respeta su título (editable a mano).
    if [ -n "${OLD_TITLES[$slug]+x}" ]; then
        title="${OLD_TITLES[$slug]}"
    fi

    # El separador del catálogo es '|': se elimina del título si apareciera.
    title="${title//|/}"
    echo "$title|$slug" >> "$CATALOG"
    count=$((count + 1))
done

echo ""
echo "catalog.txt regenerado con $count canciones en: $CATALOG"

size=$(wc -c < "$CATALOG")
if [ "$size" -gt 16384 ]; then
    echo "AVISO: el catálogo pesa ${size} bytes (> 16384). El script LSL lo truncará." >&2
fi
