// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// The hosted multiplayer proxy regions of a deployment. Never put credentials
// in this public file. The repository default stays empty: no proxy hostname is
// committed here. A deployment ships its own by building with
// -DLUANTI_WEB_LAUNCHER_CONFIG=<file> (write the file with
// util/wasm/write_launcher_config.py; CI does it from the WASM_PUBLIC_PROXY_*
// repository variables), so it is hashed into the release like every other
// shell file. See doc/compiling/wasm-embedding.md, "Hosted proxy regions".
//
//   id, label, url   a region of the launcher's proxy picker; url must be wss://
//   expires          optional ISO date or timestamp. From then on the launcher no
//                    longer offers the region (a date that does not parse counts
//                    as passed), instead of letting a join hang against a proxy
//                    nobody maintains
//   defaultProxy     the url of the region preselected for the player
//
// With no usable region the launcher says so and disables the server fields;
// the player can still enter a self-hosted proxy, or play singleplayer.
// A proxy that is not on the player's own machine can read their gameplay and
// chat; the launcher says so.
window.LUANTI_WEB_CONFIG = {
	serverListUrl: "https://servers.luanti.org/list.json",
	defaultProxy: "",
	proxies: [
		// { id: "eu", label: "Europe", url: "wss://proxy.example.org/", expires: "2027-01-01" }
	]
};
