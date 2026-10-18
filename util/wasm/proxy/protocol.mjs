// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import {isIPv4} from "node:net";

export const MAGIC = 0x778B4CF3;
export const HEADER_SIZE = 12;
export const MAX_DATAGRAM = 65507;

export function decodeFrame(data) {
	const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
	if (buffer.length < HEADER_SIZE)
		throw new Error("truncated UDP frame");
	if (buffer.readUInt32BE(0) !== MAGIC)
		throw new Error("invalid UDP frame magic");
	const length = buffer.readUInt16BE(10);
	if (buffer.length !== HEADER_SIZE + length)
		throw new Error("invalid UDP frame length");
	return {
		address: [buffer[4], buffer[5], buffer[6], buffer[7]].join("."),
		port: buffer.readUInt16BE(8),
		payload: buffer.subarray(HEADER_SIZE),
	};
}

export function encodeFrame(address, port, payload) {
	if (!isIPv4(address))
		throw new Error("IPv4 address required");
	if (!Number.isInteger(port) || port < 1 || port > 65535)
		throw new Error("invalid UDP port");
	const bytes = Buffer.from(payload);
	if (bytes.length > MAX_DATAGRAM)
		throw new Error("UDP datagram exceeds proxy limit");
	const frame = Buffer.allocUnsafe(HEADER_SIZE + bytes.length);
	frame.writeUInt32BE(MAGIC, 0);
	address.split(".").forEach((part, index) => {
		frame[4 + index] = Number(part);
	});
	frame.writeUInt16BE(port, 8);
	frame.writeUInt16BE(bytes.length, 10);
	bytes.copy(frame, HEADER_SIZE);
	return frame;
}

export function parseHandshake(text) {
	const tokens = String(text).trim().split(/\s+/);
	if (tokens.length === 4 && tokens[0] === "PROXY" &&
			tokens[1] === "IPV4" && tokens[2] === "UDP" && tokens[3] === "1")
		return {mode: "encapsulated", version: 1};
	if (tokens.length === 5 && tokens[0] === "PROXY" &&
			tokens[1] === "IPV4" && tokens[2] === "UDP" &&
			isIPv4(tokens[3])) {
		const port = Number(tokens[4]);
		if (Number.isInteger(port) && port >= 1 && port <= 65535)
			return {mode: "legacy", address: tokens[3], port};
	}
	throw new Error("unsupported proxy handshake");
}

export function parseResolve(text) {
	const tokens = String(text).trim().split(/\s+/);
	if (tokens.length !== 3 || tokens[0] !== "RESOLVE" ||
			!isIPv4(tokens[1]) || !isHostname(tokens[2]))
		throw new Error("invalid RESOLVE command");
	return {virtualAddress: tokens[1], hostname: tokens[2]};
}

export function isHostname(value) {
	return value.length > 0 && value.length <= 253 &&
		/^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(value);
}
