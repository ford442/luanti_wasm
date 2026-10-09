#!/usr/bin/env bash
# Cloud Agent environment bootstrap for luanti_wasm.
# Idempotent: safe to run repeatedly. Prepares the native (Linux) toolchain,
# the Lua lint/test tooling, Node dependencies, and the pinned Emscripten SDK
# for the WASM build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned Emscripten SDK, matching .github/workflows/wasm.yml and doc/compiling/wasm.md.
EMSDK_VERSION="6.0.3"
EMSDK_COMMIT="1b8b2456bf3f54fd6e47d55a82dde7752978a40f"
EMSDK_DIR="${EMSDK_DIR:-$HOME/emsdk}"
# Use the emsdk's own (writable) ports/system-library cache. A custom EM_CACHE
# is only needed when the SDK is installed read-only; overriding it here would
# leave the Emscripten ports (png/jpeg/freetype/...) out of the sysroot the
# build actually compiles against.
PROFILE_SNIPPET="/etc/profile.d/luanti-wasm.sh"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. System packages (native client+server build, Lua tooling, headless GL).
#    Optional map backends match the CMake defaults (Postgres client, LevelDB,
#    Redis, SpatialIndex) so a stock configure does not silently drop them.
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
	libpq-dev libleveldb-dev libhiredis-dev libspatialindex-dev libncurses-dev \
	xvfb mesa-utils libgl1-mesa-dri \
	lua5.1 luarocks

# ---------------------------------------------------------------------------
# 2. Lua lint/test tooling (luacheck + busted) on the default PATH.
#    System luarocks targets Lua 5.1, which is what builtin/ and devtest use.
# ---------------------------------------------------------------------------
log "Installing Lua tooling (luacheck, busted)"
sudo luarocks --lua-version=5.1 install luacheck
sudo luarocks --lua-version=5.1 install busted

# Playwright drives the WASM browser smoke tests (util/wasm/test_*.py). It uses
# the system Google Chrome, so no extra browser download is required. Ubuntu's
# Python is externally managed (PEP 668), hence --break-system-packages.
log "Installing Playwright for the WASM browser smoke tests"
python3 -m pip install --user --break-system-packages "playwright==1.59.0"

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

# ---------------------------------------------------------------------------
# 4. Publish EMSDK for every login shell and for this image's session startup.
#    Cloud Agent install/start run as non-interactive login shells, which read
#    /etc/profile.d but do not execute the interactive half of ~/.bashrc.
#    Appending to the bottom of ~/.bashrc is not enough: Ubuntu's stock bashrc
#    returns before that point when the shell is not interactive. Wrappers in
#    /usr/local/bin cover emcc when a process never sources a profile.
# ---------------------------------------------------------------------------
log "Publishing emsdk for login shells and /usr/local/bin"
sudo tee "$PROFILE_SNIPPET" >/dev/null <<EOF
# Installed by .cursor/install.sh. Sourced from /etc/profile and ~/.bashrc.
if [ -z "\${LUANTI_WASM_ENV:-}" ]; then
	export LUANTI_WASM_ENV=1
	export EMSDK_DIR="$EMSDK_DIR"
	if [ -f "$EMSDK_DIR/emsdk_env.sh" ]; then
		. "$EMSDK_DIR/emsdk_env.sh" >/dev/null
	fi
fi
EOF
sudo chmod 644 "$PROFILE_SNIPPET"

MARKER="# >>> luanti_wasm env >>>"
if ! grep -qF "$MARKER" "$HOME/.bashrc" 2>/dev/null; then
	tmp="$(mktemp)"
	{
		echo "$MARKER"
		echo "[ -f \"$PROFILE_SNIPPET\" ] && . \"$PROFILE_SNIPPET\""
		echo "# <<< luanti_wasm env <<<"
		echo
		cat "$HOME/.bashrc"
	} > "$tmp"
	mv "$tmp" "$HOME/.bashrc"
fi

install_em_wrapper() {
	local name="$1"
	local target="$EMSDK_DIR/upstream/emscripten/$name"
	sudo tee "/usr/local/bin/$name" >/dev/null <<EOF
#!/bin/sh
if [ -z "\${EMSDK:-}" ] && [ -f "$PROFILE_SNIPPET" ]; then
	. "$PROFILE_SNIPPET"
fi
exec "$target" "\$@"
EOF
	sudo chmod 755 "/usr/local/bin/$name"
}
for tool in emcc em++ emcmake emmake emar emranlib emconfigure emsize; do
	if [[ -e "$EMSDK_DIR/upstream/emscripten/$tool" ]]; then
		install_em_wrapper "$tool"
	fi
done

# ---------------------------------------------------------------------------
# 5. Prime Emscripten ports (SDL2, zlib, png, jpeg, freetype, ogg, vorbis,
#    zstd) and the CMake toolchain so the first WASM build is offline-capable.
# ---------------------------------------------------------------------------
log "Priming Emscripten ports via a WASM configure"
# shellcheck disable=SC1091
set +u
source "$EMSDK_DIR/emsdk_env.sh"
set -u
emcc --version
cd "$REPO_ROOT"
# Configuring the Emscripten preset downloads and builds the emscripten ports
# into the SDK cache. This is dependency setup, so it belongs in install.
cmake --preset Emscripten

# ---------------------------------------------------------------------------
# 6. Node dependencies for the root smoke harness and the WebSocket proxy.
#    Done after the toolchain so a registry hiccup cannot skip Emscripten.
# ---------------------------------------------------------------------------
log "Installing Node dependencies"
if [[ -f "$REPO_ROOT/package-lock.json" ]]; then
	npm ci --prefix "$REPO_ROOT"
fi
if [[ -f "$REPO_ROOT/util/wasm/proxy/package-lock.json" ]]; then
	npm ci --prefix "$REPO_ROOT/util/wasm/proxy"
fi

log "Checking login-shell visibility of emcc"
# install/start are non-interactive login shells. Prove they see EMSDK
# without relying on the caller's exported environment.
env -u EMSDK -u LUANTI_WASM_ENV bash -lc 'command -v emcc && emcc --version && test -n "$EMSDK"'

log "Environment bootstrap complete"
