// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

#include "irrlichttypes.h"

#ifdef __EMSCRIPTEN__
#include <memory>
struct EmscriptenUDPSocketState;
#endif

class Address;

void sockets_init();
void sockets_cleanup();

class UDPSocket
{
public:
	UDPSocket() = default;
	UDPSocket(bool ipv6); // calls init()
	~UDPSocket();
	bool init(bool ipv6, bool noExceptions = false);

	void Bind(Address addr);

	void Send(const Address &destination, const void *data, int size);
	// Returns -1 if there is no data
	int Receive(Address &sender, void *data, int size);
	void setTimeoutMs(int timeout_ms);
	// Returns true if there is data, false if timeout occurred
	bool WaitData(int timeout_ms);

	// Debugging purposes only
	int GetHandle() const { return m_handle; };
	u16 getBoundPort() const { return m_bound_port; }

private:
#ifdef __EMSCRIPTEN__
	std::shared_ptr<EmscriptenUDPSocketState> m_emscripten;
#endif
	int m_handle = -1;
	int m_timeout_ms = -1;
	unsigned short m_addr_family = 0;
	u16 m_bound_port = 0;
};
