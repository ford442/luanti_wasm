// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

#include "irrlichttypes.h"
#include "address.h"

#ifdef __EMSCRIPTEN__
#include <memory>
struct EmscriptenUDPSocketState;
#endif

void sockets_init();
void sockets_cleanup();

class UDPSocket
{
public:
	UDPSocket() = default;
	UDPSocket(UDPSocket &&other):
#ifdef __EMSCRIPTEN__
		m_emscripten(std::move(other.m_emscripten)),
		m_bound_port(other.m_bound_port),
#endif
		m_handle(other.m_handle),
		m_timeout_ms(other.m_timeout_ms),
		m_addr_family(other.m_addr_family)
	{
		other.m_handle = -1;
#ifdef __EMSCRIPTEN__
		other.m_bound_port = 0;
#endif
	}
	~UDPSocket()
	{
		Close();
	}
	UDPSocket &operator=(UDPSocket &&other)
	{
		Close();
#ifdef __EMSCRIPTEN__
		m_emscripten = std::move(other.m_emscripten);
		m_bound_port = other.m_bound_port;
		other.m_bound_port = 0;
#endif
		m_handle = other.m_handle;
		m_timeout_ms = other.m_timeout_ms;
		m_addr_family = other.m_addr_family;
		other.m_handle = -1;
		return *this;
	}

	/// @brief create and bind a socket to an address
	static UDPSocket Create(Address addr)
	{
		UDPSocket socket;
		socket.Bind(addr);
		return socket;
	}

	static UDPSocket CreateEphemeral(bool ipv6)
	{
		if (ipv6)
			return Create(Address(nullptr, 0));
		else
			return Create(Address(u32(0), 0));
	}

	void Init(bool ipv6);
	void Bind(Address addr);
	void Close();

	Address GetLocalAddress();

	void Send(const Address &destination, const void *data, int size);
	// Returns -1 if there is no data
	int Receive(Address &sender, void *data, int size);
	void setTimeoutMs(int timeout_ms);
	// Returns true if there is data, false if timeout occurred
	bool WaitData(int timeout_ms);

	// Debugging purposes only
	int GetHandle() const { return m_handle; };

private:
#ifdef __EMSCRIPTEN__
	std::shared_ptr<EmscriptenUDPSocketState> m_emscripten;
	u16 m_bound_port = 0;
#endif
	int m_handle = -1;
	int m_timeout_ms = -1;
	unsigned short m_addr_family = 0;
};
