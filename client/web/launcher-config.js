// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Deployment owners may add regional WSS proxy entries without rebuilding the
// engine. Never put credentials in this public file.
window.LUANTI_WEB_CONFIG = {
	serverListUrl: "https://servers.luanti.org/list.json",
	defaultProxy: "",
	proxies: [
		// { id: "eu", label: "Europe", url: "wss://proxy.example.org/" }
	]
};
