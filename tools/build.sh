#!/usr/bin/env bash
#
# Sestaví hru do souboru, který jde rovnou otevřít ve Studiu.
#
# Rojo si stáhne sám, když ho nenajde — na otestování hry nemá smysl
# nutit člověka instalovat toolchain.
#
# Použití:
#     tools/build.sh [výstup.rbxlx]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/PowerSmash.rbxlx}"
VERSION="7.4.4"

find_rojo() {
	if command -v rojo >/dev/null 2>&1; then
		command -v rojo
		return
	fi
	if [ -x "$ROOT/tools/rojo" ]; then
		echo "$ROOT/tools/rojo"
		return
	fi

	echo "Stahuju Rojo $VERSION…" >&2
	local os arch
	case "$(uname -s)" in
		Linux) os="linux" ;;
		Darwin) os="macos" ;;
		*) echo "Neznámý systém — nainstaluj Rojo ručně: https://rojo.space" >&2; exit 1 ;;
	esac
	case "$(uname -m)" in
		x86_64|amd64) arch="x86_64" ;;
		arm64|aarch64) arch="aarch64" ;;
		*) echo "Neznámá architektura — nainstaluj Rojo ručně." >&2; exit 1 ;;
	esac

	local url="https://github.com/rojo-rbx/rojo/releases/download/v$VERSION/rojo-$VERSION-$os-$arch.zip"
	local tmp
	tmp="$(mktemp -d)"
	curl -sSL -o "$tmp/rojo.zip" "$url"
	unzip -oq "$tmp/rojo.zip" -d "$tmp"
	mv "$tmp/rojo" "$ROOT/tools/rojo"
	chmod +x "$ROOT/tools/rojo"
	rm -rf "$tmp"
	echo "$ROOT/tools/rojo"
}

ROJO="$(find_rojo)"

# Nejdřív kontroly. Sestavit se dá i rozbitá hra — .rbxlx je jen strom
# souborů, syntaxi ani chybějící remote nikdo cestou neověří.
echo "== Kontroly =="
python3 "$ROOT/tools/lint.py"
python3 "$ROOT/tools/test.py" | tail -1

echo
echo "== Sestavení =="
"$ROJO" build "$ROOT" -o "$OUT"

echo
echo "Hotovo: $OUT"
echo "Otevři to ve Studiu a dej Play."
echo "Postup, co otestovat: docs/TESTOVANI.md"
