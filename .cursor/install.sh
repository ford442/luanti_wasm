#!/usr/bin/env bash
# Cloud Agent environment bootstrap for luanti_wasm.
# Idempotent: safe to run repeatedly. Prepares the native (Linux) toolchain,
# the Lua lint/test tooling, and the pinned Emscripten SDK for the WASM build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned Emscripten SDK, matching .github/workflows/wasm.yml and doc/compiling/wasm.md.
EMSDK_VERSION="6.0.3"
EMSDK_COMMIT="1b8b2456bf3f54fd6e47d55a82dde7752978a40f"
EMSDK_DIR="${EMSDK_DIR:-$HOME/emsdk}"
EM_CACHE="${EM_CACHE:-$HOME/.emscripten_cache}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. System packages (native client+server build, Lua tooling, headless GL).
# ---------------------------------------------------------------------------
log "Installing system packages"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
	build-essential make libc6-dev cmake ninja-build git ca-certificates \
	python3 python3-pip python3-venv pkg-config \
	libpng-dev libjpeg-dev libgl1-mesa-dev libsqlite3-dev \
	libogg-dev libvorbis-dev libopenal-dev libcurl4-openssl-dev \
	libfreetype-dev zlib1g-dev libgmp-dev libjsoncpp-dev libzstd-dev \
	libluajit-5.1-dev luajit gettext libsdl2-dev libssl-dev \
	xvfb mesa-utils libgl1-mesa-dri \
	lua5.1 luarocks

# ---------------------------------------------------------------------------
# 2. Lua lint/test tooling (luacheck + busted), installed to ~/.luarocks.
# ---------------------------------------------------------------------------
log "Installing Lua tooling (luacheck, busted)"
luarocks install --local luacheck
luarocks install --local busted

# ---------------------------------------------------------------------------
# 3. Pinned Emscripten SDK for the WebAssembly build.
# ---------------------------------------------------------------------------
log "Installing Emscripten SDK ${EMSDK_VERSION}"
if [[ ! -x "$EMSDK_DIR/emsdk" ]]; then
	git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
fi
git -C "$EMSDK_DIR" fetch --depth=1 origin "$EMSDK_COMMIT"
git -C "$EMSDK_DIR" checkout --detach "$EMSDK_COMMIT"
"$EMSDK_DIR/emsdk" install "$EMSDK_VERSION"
"$EMSDK_DIR/emsdk" activate "$EMSDK_VERSION"

mkdir -p "$EM_CACHE"

# ---------------------------------------------------------------------------
# 4. Make emsdk + tooling available in every interactive shell (idempotent).
# ---------------------------------------------------------------------------
MARKER="# >>> luanti_wasm env >>>"
if ! grep -qF "$MARKER" "$HOME/.bashrc" 2>/dev/null; then
	log "Wiring emsdk + luarocks into ~/.bashrc"
	{
		echo ""
		echo "$MARKER"
		echo "export EM_CACHE=\"$EM_CACHE\""
		echo "[ -f \"$EMSDK_DIR/emsdk_env.sh\" ] && source \"$EMSDK_DIR/emsdk_env.sh\" >/dev/null 2>&1 || true"
		echo "command -v luarocks >/dev/null 2>&1 && eval \"\$(luarocks path --bin 2>/dev/null)\" || true"
		echo "# <<< luanti_wasm env <<<"
	} >> "$HOME/.bashrc"
fi

# ---------------------------------------------------------------------------
# 5. Prime Emscripten ports (SDL2, zlib, png, jpeg, freetype, ogg, vorbis,
#    zstd) and the CMake toolchain so the first WASM build is offline-capable.
# ---------------------------------------------------------------------------
log "Priming Emscripten ports via a WASM configure"
export EM_CACHE
# shellcheck disable=SC1091
source "$EMSDK_DIR/emsdk_env.sh"
emcc --version
cd "$REPO_ROOT"
# Configuring the Emscripten preset downloads and builds the emscripten ports
# into EM_CACHE. This is dependency setup, so it belongs in install.
cmake --preset Emscripten

log "Environment bootstrap complete"
