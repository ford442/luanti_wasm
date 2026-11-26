# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors

include_guard(GLOBAL)

option(EMSCRIPTEN_BOOTSTRAP_PORTS
	"Populate the Emscripten SDK cache with Luanti's built-in ports" ON)

if(EMSCRIPTEN_BOOTSTRAP_PORTS)
	get_filename_component(EMSCRIPTEN_COMPILER_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
	set(EMSCRIPTEN_EMBUILDER "${EMSCRIPTEN_COMPILER_DIR}/embuilder")
	if(NOT EXISTS "${EMSCRIPTEN_EMBUILDER}")
		message(FATAL_ERROR "Emscripten embuilder was not found beside ${CMAKE_CXX_COMPILER}")
	endif()

	message(STATUS "Preparing Emscripten ports required by Luanti")
	execute_process(
		COMMAND "${EMSCRIPTEN_EMBUILDER}" build
			zlib libjpeg libpng-mt freetype sqlite3-mt sdl2 ogg vorbis
		RESULT_VARIABLE EMSCRIPTEN_PORTS_RESULT
		COMMAND_ECHO STDOUT
	)
	if(NOT EMSCRIPTEN_PORTS_RESULT EQUAL 0)
		message(FATAL_ERROR
			"Emscripten port preparation failed (${EMSCRIPTEN_PORTS_RESULT})")
	endif()
	execute_process(
		COMMAND "${CMAKE_C_COMPILER}" --print-file-name=libsqlite3-mt.a
		OUTPUT_VARIABLE EMSCRIPTEN_SQLITE3_LIBRARY
		OUTPUT_STRIP_TRAILING_WHITESPACE
		COMMAND_ERROR_IS_FATAL ANY
	)
	set(SQLITE3_LIBRARY "${EMSCRIPTEN_SQLITE3_LIBRARY}" CACHE FILEPATH
		"Path to Emscripten's pthread-enabled SQLite port" FORCE)
	execute_process(
		COMMAND "${CMAKE_C_COMPILER}" --print-file-name=libpng-mt.a
		OUTPUT_VARIABLE EMSCRIPTEN_PNG_LIBRARY
		OUTPUT_STRIP_TRAILING_WHITESPACE
		COMMAND_ERROR_IS_FATAL ANY
	)
	set(PNG_LIBRARY "${EMSCRIPTEN_PNG_LIBRARY}" CACHE FILEPATH
		"Path to Emscripten's pthread-enabled PNG port" FORCE)
	execute_process(
		COMMAND "${CMAKE_C_COMPILER}" --print-file-name=libvorbis.a
		OUTPUT_VARIABLE EMSCRIPTEN_VORBIS_LIBRARY
		OUTPUT_STRIP_TRAILING_WHITESPACE
		COMMAND_ERROR_IS_FATAL ANY
	)
	set(VORBIS_LIBRARY "${EMSCRIPTEN_VORBIS_LIBRARY}" CACHE FILEPATH
		"Path to Emscripten's Vorbis port" FORCE)
	set(VORBISFILE_LIBRARY "${EMSCRIPTEN_VORBIS_LIBRARY}" CACHE FILEPATH
		"Path to Emscripten's VorbisFile port" FORCE)
	execute_process(
		COMMAND "${CMAKE_C_COMPILER}" --print-file-name=libogg.a
		OUTPUT_VARIABLE EMSCRIPTEN_OGG_LIBRARY
		OUTPUT_STRIP_TRAILING_WHITESPACE
		COMMAND_ERROR_IS_FATAL ANY
	)
	set(OGG_LIBRARY "${EMSCRIPTEN_OGG_LIBRARY}" CACHE FILEPATH
		"Path to Emscripten's Ogg port" FORCE)
endif()

# Emscripten 6.0.3 has no zstd port. Fetch an integrity-pinned release and add
# only its static library to the cross build.
include(FetchContent)
set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_CONTRIB OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZSTD_MULTITHREAD_SUPPORT OFF CACHE BOOL "" FORCE)
FetchContent_Declare(luanti_zstd
	URL https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz
	URL_HASH SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
)
FetchContent_GetProperties(luanti_zstd)
if(NOT luanti_zstd_POPULATED)
	FetchContent_Populate(luanti_zstd)
	add_subdirectory("${luanti_zstd_SOURCE_DIR}/build/cmake"
		"${luanti_zstd_BINARY_DIR}" EXCLUDE_FROM_ALL)
endif()
set(ZSTD_INCLUDE_DIR "${luanti_zstd_SOURCE_DIR}/lib" CACHE PATH
	"Path to the Emscripten zstd headers" FORCE)
set(ZSTD_LIBRARY libzstd_static CACHE STRING
	"Emscripten zstd static target" FORCE)
