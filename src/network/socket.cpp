// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#include "socket.h"

#include <algorithm>
#include <iostream>
#include <cstring>
#include "util/numeric.h"
#include "address.h"
#include "constants.h"
#include "log.h"
#include "networkexceptions.h"

#ifdef __EMSCRIPTEN__

#include "websocket_proxy.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <emscripten.h>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace {

struct QueuedDatagram {
	Address sender;
	std::vector<u8> data;
};

std::atomic<int> next_socket_handle{1};
std::atomic<u16> next_ephemeral_port{20000};
std::mutex sockets_mutex;
std::unordered_map<int, std::shared_ptr<EmscriptenUDPSocketState>> sockets_by_handle;
std::unordered_map<u16, std::shared_ptr<EmscriptenUDPSocketState>> sockets_by_port;
bool sockets_initialized = false;

u16 allocate_ephemeral_port()
{
	for (u32 attempt = 0; attempt < 45535; ++attempt) {
		u16 port = next_ephemeral_port.fetch_add(1, std::memory_order_relaxed);
		if (port < 20000) {
			next_ephemeral_port.store(20001, std::memory_order_relaxed);
			port = 20000;
		}
		if (sockets_by_port.count(port) == 0)
			return port;
	}
	return 0;
}

} // namespace

struct EmscriptenUDPSocketState {
	std::mutex mutex;
	std::condition_variable event;
	std::deque<QueuedDatagram> receive_queue;
	Address bind_address;
	bool closed = false;
};

extern "C" EMSCRIPTEN_KEEPALIVE void luanti_websocket_proxy_receive(
		int handle, const void *data, int size, u32 source_ip, u16 source_port)
{
	if (!data || size < 0)
		return;

	std::shared_ptr<EmscriptenUDPSocketState> state;
	{
		std::lock_guard<std::mutex> lock(sockets_mutex);
		auto found = sockets_by_handle.find(handle);
		if (found != sockets_by_handle.end())
			state = found->second;
	}
	if (!state)
		return;

	QueuedDatagram datagram;
	datagram.sender = Address(source_ip, source_port);
	datagram.data.assign(static_cast<const u8 *>(data),
		static_cast<const u8 *>(data) + size);
	{
		std::lock_guard<std::mutex> lock(state->mutex);
		if (state->closed)
			return;
		if (state->receive_queue.size() >= 1024)
			state->receive_queue.pop_front();
		state->receive_queue.emplace_back(std::move(datagram));
	}
	state->event.notify_one();
}

void websocket_proxy_register_hostname(const char *address, const char *hostname)
{
	MAIN_THREAD_EM_ASM({
		var network = Module["luantiNetwork"];
		if (network && network["_registerHostname"])
			network["_registerHostname"](UTF8ToString($0), UTF8ToString($1));
	}, address, hostname);
}

void sockets_init()
{
	sockets_initialized = true;
}

void sockets_cleanup()
{
	sockets_initialized = false;
}

UDPSocket::UDPSocket(bool ipv6)
{
	init(ipv6, false);
}

bool UDPSocket::init(bool ipv6, bool noExceptions)
{
	if (!sockets_initialized) {
		const char *msg = "Sockets not initialized";
		verbosestream << msg << std::endl;
		if (noExceptions)
			return false;
		throw SocketException(msg);
	}
	if (m_handle >= 0) {
		if (noExceptions)
			return false;
		throw SocketException("Cannot initialize socket twice");
	}
	if (ipv6)
		warningstream << "WebSocket proxy transport is IPv4-only; using IPv4"
			<< std::endl;

	m_handle = next_socket_handle.fetch_add(1, std::memory_order_relaxed);
	m_addr_family = AF_INET;
	m_timeout_ms = 0;
	m_emscripten = std::make_shared<EmscriptenUDPSocketState>();
	{
		std::lock_guard<std::mutex> lock(sockets_mutex);
		sockets_by_handle[m_handle] = m_emscripten;
	}
	return true;
}

UDPSocket::~UDPSocket()
{
	if (!m_emscripten)
		return;
	{
		std::lock_guard<std::mutex> lock(m_emscripten->mutex);
		m_emscripten->closed = true;
	}
	m_emscripten->event.notify_all();
	{
		std::lock_guard<std::mutex> lock(sockets_mutex);
		sockets_by_handle.erase(m_handle);
		if (m_emscripten->bind_address.getPort() != 0)
			sockets_by_port.erase(m_emscripten->bind_address.getPort());
	}
	// JS proxy bookkeeping is best-effort and must not run via
	// MAIN_THREAD_ASYNC_EM_ASM: that import is missing in pthread workers
	// ("function import requires a callable") and crashes instantiate.
}

void UDPSocket::Bind(Address addr)
{
	if (!m_emscripten) {
		if (!init(addr.getFamily() == AF_INET6, true))
			throw SocketException("Socket is not initialized");
	}
	if (addr.getFamily() == 0)
		addr.setAddress(static_cast<u32>(0));
	if (addr.getFamily() != AF_INET)
		throw SocketException("WebSocket proxy transport supports IPv4 only");

	u16 port;
	{
		std::lock_guard<std::mutex> lock(sockets_mutex);
		if (m_emscripten->bind_address.getPort() != 0)
			throw SocketException("Socket is already bound");
		port = addr.getPort();
		if (port == 0)
			port = allocate_ephemeral_port();
		if (port == 0 || sockets_by_port.count(port) != 0)
			throw SocketException("Failed to bind browser UDP socket");
		addr.setPort(port);
		m_emscripten->bind_address = addr;
		sockets_by_port[port] = m_emscripten;
		m_bound_port = port;
	}
	// In-process singleplayer only needs the C++ port map. The WSS proxy
	// link is created lazily in JS on the first remote _send.
}

void UDPSocket::Send(const Address &destination, const void *data, int size)
{
	if (!m_emscripten || size < 0 || (size > 0 && !data))
		throw SendFailedException("Invalid browser UDP send");
	if (destination.getFamily() != AF_INET)
		throw SendFailedException("WebSocket proxy transport supports IPv4 only");
	if (m_emscripten->bind_address.getPort() == 0)
		Bind(Address(0, 0, 0, 0, 0));

	// Singleplayer / in-process loopback: deliver datagram directly to matching port queue
	{
		std::shared_ptr<EmscriptenUDPSocketState> target;
		bool in_process = destination.isLocalhost() || destination.isAny();
		{
			std::lock_guard<std::mutex> lock(sockets_mutex);
			auto found = sockets_by_port.find(destination.getPort());
			if (found != sockets_by_port.end()) {
				target = found->second;
				in_process = true;
			}
		}
		if (in_process) {
			if (!target) {
				warningstream << "Loopback UDP send to port "
					<< destination.getPort()
					<< " dropped (no socket bound yet)" << std::endl;
				return;
			}
			QueuedDatagram datagram;
			// Always stamp loopback as 127.0.0.1 + the real bound port.
			// Using bind_address.getPort() can disagree with 0.0.0.0 binds and
			// makes the receiver drop the packet as "different address".
			datagram.sender = Address(127, 0, 0, 1, m_bound_port);
			datagram.data.assign(static_cast<const u8 *>(data),
				static_cast<const u8 *>(data) + size);
			{
				std::lock_guard<std::mutex> lock(target->mutex);
				if (target->closed)
					return;
				// Mapblock traffic needs headroom; 1024 was too small and
				// silently dropped reliable fragments under load.
				constexpr size_t kMaxQueue = 16384;
				if (target->receive_queue.size() >= kMaxQueue) {
					target->receive_queue.pop_front();
					static std::atomic<int> drops{0};
					if (drops.fetch_add(1) < 8)
						warningstream << "Loopback UDP receive queue full; dropping oldest"
							<< std::endl;
				}
				target->receive_queue.emplace_back(std::move(datagram));
			}
			target->event.notify_one();
			static std::atomic<int> loopback_sends{0};
			int n = loopback_sends.fetch_add(1, std::memory_order_relaxed);
			if (n < 16) {
				actionstream << "Loopback UDP " << m_bound_port
					<< " -> " << destination.getPort()
					<< " (" << size << " bytes)" << std::endl;
			}
			return;
		}
	}

	// Remote multiplayer destination: route packet through the WebSocket proxy bridge
	const std::string address = destination.serializeString();
	int accepted = MAIN_THREAD_EM_ASM_INT({
		var network = Module["luantiNetwork"];
		return network && network["_send"] ?
			network["_send"]($0, $1, $2, UTF8ToString($3), $4) : 0;
	}, m_handle, data, size, address.c_str(), destination.getPort());
	if (!accepted)
		throw SendFailedException("Multiplayer proxy is unavailable");
}

int UDPSocket::Receive(Address &sender, void *data, int size)
{
	if (!m_emscripten || !data || size < 0)
		return -1;
	std::unique_lock<std::mutex> lock(m_emscripten->mutex);
	auto ready = [this]() {
		return m_emscripten->closed || !m_emscripten->receive_queue.empty();
	};
	if (m_timeout_ms < 0) {
		m_emscripten->event.wait(lock, ready);
	} else if (m_timeout_ms > 0) {
		if (!m_emscripten->event.wait_for(lock,
				std::chrono::milliseconds(m_timeout_ms), ready)) {
			return -1;
		}
	}
	if (m_emscripten->closed || m_emscripten->receive_queue.empty())
		return -1;

	QueuedDatagram datagram = std::move(m_emscripten->receive_queue.front());
	m_emscripten->receive_queue.pop_front();
	int received = std::min<int>(size, datagram.data.size());
	memcpy(data, datagram.data.data(), received);
	sender = datagram.sender;
	return received;
}

void UDPSocket::setTimeoutMs(int timeout_ms)
{
	m_timeout_ms = timeout_ms;
}

bool UDPSocket::WaitData(int timeout_ms)
{
	if (!m_emscripten)
		return false;
	std::unique_lock<std::mutex> lock(m_emscripten->mutex);
	if (!m_emscripten->receive_queue.empty())
		return true;
	if (timeout_ms <= 0)
		return false;
	auto ready = [this]() {
		return m_emscripten->closed || !m_emscripten->receive_queue.empty();
	};
	return m_emscripten->event.wait_for(lock,
		std::chrono::milliseconds(timeout_ms), ready) &&
		!m_emscripten->closed && !m_emscripten->receive_queue.empty();
}

#else // !__EMSCRIPTEN__

#ifdef _WIN32
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include "util/string.h"
#define LAST_SOCKET_ERR() WSAGetLastError()
#define SOCKET_ERR_STR(e) itos(e)
typedef int socklen_t;
#else
#include <cerrno>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <arpa/inet.h>
#define LAST_SOCKET_ERR() (errno)
#define SOCKET_ERR_STR(e) strerror(e)
#endif

static bool g_sockets_initialized = false;

// Initialize sockets
void sockets_init()
{
#ifdef _WIN32
	// Windows needs sockets to be initialized before use
	WSADATA WsaData;
	if (WSAStartup(MAKEWORD(2, 2), &WsaData) != NO_ERROR)
		throw SocketException("WSAStartup failed");
#endif
	g_sockets_initialized = true;
}

void sockets_cleanup()
{
#ifdef _WIN32
	// On Windows, cleanup sockets after use
	WSACleanup();
#endif
	g_sockets_initialized = false;
}

/*
	UDPSocket
*/

UDPSocket::UDPSocket(bool ipv6)
{
	init(ipv6, false);
}

bool UDPSocket::init(bool ipv6, bool noExceptions)
{
	if (!g_sockets_initialized) {
		verbosestream << "Sockets not initialized" << std::endl;
		return false;
	}

	if (m_handle >= 0) {
		auto msg = "Cannot initialize socket twice";
		verbosestream << msg << std::endl;
		if (noExceptions)
			return false;
		throw SocketException(msg);
	}

	// Use IPv6 if specified
	m_addr_family = ipv6 ? AF_INET6 : AF_INET;
	m_handle = socket(m_addr_family, SOCK_DGRAM, IPPROTO_UDP);

	if (m_handle < 0) {
		auto msg = std::string("Failed to create socket: ") +
			SOCKET_ERR_STR(LAST_SOCKET_ERR());
		verbosestream << msg << std::endl;
		if (noExceptions)
			return false;
		throw SocketException(msg);
	}

	setTimeoutMs(0);

	return true;
}

UDPSocket::~UDPSocket()
{
	if (m_handle >= 0) {
#ifdef _WIN32
		closesocket(m_handle);
#else
		close(m_handle);
#endif
	}
}

void UDPSocket::Bind(Address addr)
{
	if (addr.getFamily() != m_addr_family) {
		const char *errmsg =
				"Socket and bind address families do not match";
		errorstream << "Bind failed: " << errmsg << std::endl;
		throw SocketException(errmsg);
	}

	if (m_addr_family == AF_INET6) {
		// Allow our socket to accept both IPv4 and IPv6 connections
		// required on Windows:
		// <https://msdn.microsoft.com/en-us/library/windows/desktop/bb513665(v=vs.85).aspx>
		int value = 0;
		if (setsockopt(m_handle, IPPROTO_IPV6, IPV6_V6ONLY,
				reinterpret_cast<char *>(&value), sizeof(value)) != 0) {
			auto errmsg = SOCKET_ERR_STR(LAST_SOCKET_ERR());
			errorstream << "Failed to disable V6ONLY: " << errmsg
				<< "\nTry disabling ipv6_server to fix this." << std::endl;
			throw SocketException(errmsg);
		}
	}

	int ret = 0;

	if (m_addr_family == AF_INET6) {
		struct sockaddr_in6 address;
		memset(&address, 0, sizeof(address));

		address.sin6_family = AF_INET6;
		address.sin6_addr = addr.getAddress6();
		address.sin6_port = htons(addr.getPort());

		ret = bind(m_handle, (const struct sockaddr *) &address,
				sizeof(struct sockaddr_in6));
	} else {
		struct sockaddr_in address;
		memset(&address, 0, sizeof(address));

		address.sin_family = AF_INET;
		address.sin_addr = addr.getAddress();
		address.sin_port = htons(addr.getPort());

		ret = bind(m_handle, (const struct sockaddr *) &address,
			sizeof(struct sockaddr_in));
	}

	if (ret < 0) {
		tracestream << (int)m_handle << ": Bind failed: "
			<< SOCKET_ERR_STR(LAST_SOCKET_ERR()) << std::endl;
		throw SocketException("Failed to bind socket");
	}
	m_bound_port = addr.getPort();
}

void UDPSocket::Send(const Address &destination, const void *data, int size)
{
	bool dumping_packet = false; // for INTERNET_SIMULATOR

	if (INTERNET_SIMULATOR)
		dumping_packet = myrand() % INTERNET_SIMULATOR_PACKET_LOSS == 0;

	if (dumping_packet) {
		// Lol let's forget it
		tracestream << "UDPSocket::Send(): INTERNET_SIMULATOR: dumping packet."
			<< std::endl;
		return;
	}

	if (destination.getFamily() != m_addr_family)
		throw SendFailedException("Address family mismatch");

	int sent;
	if (m_addr_family == AF_INET6) {
		struct sockaddr_in6 address = {};
		address.sin6_family = AF_INET6;
		address.sin6_addr = destination.getAddress6();
		address.sin6_port = htons(destination.getPort());

		sent = sendto(m_handle, (const char *)data, size, 0,
				(struct sockaddr *)&address, sizeof(struct sockaddr_in6));
	} else {
		struct sockaddr_in address = {};
		address.sin_family = AF_INET;
		address.sin_addr = destination.getAddress();
		address.sin_port = htons(destination.getPort());

		sent = sendto(m_handle, (const char *)data, size, 0,
				(struct sockaddr *)&address, sizeof(struct sockaddr_in));
	}

	if (sent != size)
		throw SendFailedException("Failed to send packet");
}

int UDPSocket::Receive(Address &sender, void *data, int size)
{
	// Return on timeout
	assert(m_timeout_ms >= 0);
	if (!WaitData(m_timeout_ms))
		return -1;

	size = MYMAX(size, 0);

	int received;
	if (m_addr_family == AF_INET6) {
		struct sockaddr_in6 address;
		memset(&address, 0, sizeof(address));
		socklen_t address_len = sizeof(address);

		received = recvfrom(m_handle, (char *)data, size, 0,
				(struct sockaddr *)&address, &address_len);

		if (received < 0)
			return -1;

		u16 address_port = ntohs(address.sin6_port);
		IPv6AddressBytes bytes;
		memcpy(bytes.bytes, address.sin6_addr.s6_addr, sizeof(address.sin6_addr.s6_addr));
		sender = Address(&bytes, address_port);
	} else {
		struct sockaddr_in address;
		memset(&address, 0, sizeof(address));

		socklen_t address_len = sizeof(address);

		received = recvfrom(m_handle, (char *)data, size, 0,
				(struct sockaddr *)&address, &address_len);

		if (received < 0)
			return -1;

		u32 address_ip = ntohl(address.sin_addr.s_addr);
		u16 address_port = ntohs(address.sin_port);

		sender = Address(address_ip, address_port);
	}

	return received;
}

void UDPSocket::setTimeoutMs(int timeout_ms)
{
	m_timeout_ms = timeout_ms;
}

bool UDPSocket::WaitData(int timeout_ms)
{
	timeout_ms = MYMAX(timeout_ms, 0);

#ifdef _WIN32
	WSAPOLLFD pfd;
	pfd.fd = m_handle;
	pfd.events = POLLRDNORM;

	int result = WSAPoll(&pfd, 1, timeout_ms);
#else
	struct pollfd pfd;
	pfd.fd = m_handle;
	pfd.events = POLLIN;

	int result = poll(&pfd, 1, timeout_ms);
#endif

	if (result == 0) {
		return false; // No data
	} else if (result > 0) {
		// There might be data
		return pfd.revents != 0;
	}

	// Error case
	int e = LAST_SOCKET_ERR();

#ifdef _WIN32
	if (e == WSAEINTR || e == WSAEBADF) {
#else
	if (e == EINTR || e == EBADF) {
#endif
		// N.B. poll() fails when sockets are destroyed on Connection's dtor
		// with EBADF. Instead of doing tricky synchronization, allow this
		// thread to exit but don't throw an exception.
		return false;
	}

	tracestream << (int)m_handle << ": poll failed: "
		<< SOCKET_ERR_STR(e) << std::endl;

	throw SocketException("poll failed");
}

#endif // !__EMSCRIPTEN__
