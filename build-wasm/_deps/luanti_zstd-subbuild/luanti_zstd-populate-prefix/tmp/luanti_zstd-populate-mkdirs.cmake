# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION 3.5)

file(MAKE_DIRECTORY
  "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-src"
  "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-build"
  "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-subbuild/luanti_zstd-populate-prefix"
  "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-subbuild/luanti_zstd-populate-prefix/tmp"
  "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-subbuild/luanti_zstd-populate-prefix/src/luanti_zstd-populate-stamp"
  "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-subbuild/luanti_zstd-populate-prefix/src"
  "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-subbuild/luanti_zstd-populate-prefix/src/luanti_zstd-populate-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-subbuild/luanti_zstd-populate-prefix/src/luanti_zstd-populate-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "/root/luanti_wasm/build-wasm/_deps/luanti_zstd-subbuild/luanti_zstd-populate-prefix/src/luanti_zstd-populate-stamp${cfgdir}") # cfgdir has leading slash
endif()
