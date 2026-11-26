file(GLOB database_HDRS "${CMAKE_CURRENT_SOURCE_DIR}/*.h")

set(database_SRCS
	${database_HDRS}
	${CMAKE_CURRENT_SOURCE_DIR}/database.cpp
	${CMAKE_CURRENT_SOURCE_DIR}/database-dummy.cpp
	${CMAKE_CURRENT_SOURCE_DIR}/database-files.cpp
	${CMAKE_CURRENT_SOURCE_DIR}/database-leveldb.cpp
	${CMAKE_CURRENT_SOURCE_DIR}/database-postgresql.cpp
	${CMAKE_CURRENT_SOURCE_DIR}/database-redis.cpp
	${CMAKE_CURRENT_SOURCE_DIR}/database-sqlite3.cpp
)

if(EMSCRIPTEN)
	# World databases on the Origin Private File System (browser builds only).
	list(APPEND database_SRCS ${CMAKE_CURRENT_SOURCE_DIR}/sqlite3_opfs_vfs.cpp)
endif()

set(database_SRCS ${database_SRCS} PARENT_SCOPE)
