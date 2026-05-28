cmake_minimum_required(VERSION 3.20)
project(pqcap-cli CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(DUCKDB_BUILD_DIR "" CACHE PATH "Path to duckdb_pqcap_reader/build/release")
set(DUCKDB_SOURCE_DIR "" CACHE PATH "Path to duckdb source tree")
set(PQCAP_EXTENSION_DIR "" CACHE PATH "Path to duckdb_pqcap_reader")

if(NOT EXISTS "${DUCKDB_BUILD_DIR}/src/libduckdb_static.a")
  message(FATAL_ERROR "DuckDB build not found at ${DUCKDB_BUILD_DIR}. Run: make -C duckdb_pqcap_reader release")
endif()

find_package(Threads REQUIRED)

set(SHELL_DIR "${DUCKDB_SOURCE_DIR}/tools/shell")
set(LINENOISE_DIR "${SHELL_DIR}/linenoise")

set(LINENOISE_SOURCES
    ${LINENOISE_DIR}/highlighting.cpp
    ${LINENOISE_DIR}/history.cpp
    ${LINENOISE_DIR}/linenoise.cpp
    ${LINENOISE_DIR}/linenoise-c.cpp
    ${LINENOISE_DIR}/rendering.cpp
    ${LINENOISE_DIR}/terminal.cpp
)

set(SHELL_SOURCES
    ${SHELL_DIR}/shell_command_line_option.cpp
    ${SHELL_DIR}/shell_extension.cpp
    ${SHELL_DIR}/shell.cpp
    ${SHELL_DIR}/shell_helpers.cpp
    ${SHELL_DIR}/shell_metadata_command.cpp
    ${SHELL_DIR}/shell_prompt.cpp
    ${SHELL_DIR}/shell_renderer.cpp
    ${SHELL_DIR}/shell_highlight.cpp
    ${SHELL_DIR}/shell_progress_bar.cpp
    ${SHELL_DIR}/shell_render_table_metadata.cpp
    ${SHELL_DIR}/shell_windows.cpp
)

add_executable(pqcap pqcap_main.cpp ${SHELL_SOURCES} ${LINENOISE_SOURCES})

set_source_files_properties(${SHELL_DIR}/shell.cpp PROPERTIES COMPILE_DEFINITIONS "main=duckdb_shell_main")

target_compile_definitions(pqcap PRIVATE
    DUCKDB_BUILD_LIBRARY
    GENERATED_EXTENSION_HEADERS=1
    DUCKDB_EXTENSION_PQCAP_READER_LINKED=1
    DUCKDB_EXTENSION_PARQUET_LINKED=1
    DUCKDB_EXTENSION_CORE_FUNCTIONS_LINKED=1
    HAVE_LINENOISE=1
    USE_DUCKDB_SHELL_WRAPPER
)

target_include_directories(pqcap PRIVATE
    ${DUCKDB_SOURCE_DIR}/src/include
    ${DUCKDB_SOURCE_DIR}/third_party/fmt/include
    ${DUCKDB_SOURCE_DIR}/third_party/fsst
    ${DUCKDB_SOURCE_DIR}/third_party/hyperloglog
    ${DUCKDB_SOURCE_DIR}/third_party/fastpforlib
    ${DUCKDB_SOURCE_DIR}/third_party/skiplist
    ${DUCKDB_SOURCE_DIR}/third_party/ska_sort
    ${DUCKDB_SOURCE_DIR}/third_party/fast_float
    ${DUCKDB_SOURCE_DIR}/third_party/re2
    ${DUCKDB_SOURCE_DIR}/third_party/miniz
    ${DUCKDB_SOURCE_DIR}/third_party/utf8proc/include
    ${DUCKDB_SOURCE_DIR}/third_party/concurrentqueue
    ${DUCKDB_SOURCE_DIR}/third_party/pcg
    ${DUCKDB_SOURCE_DIR}/third_party/pdqsort
    ${DUCKDB_SOURCE_DIR}/third_party/tdigest
    ${DUCKDB_SOURCE_DIR}/third_party/mbedtls/include
    ${DUCKDB_SOURCE_DIR}/third_party/httplib
    ${DUCKDB_SOURCE_DIR}/third_party/jaro_winkler
    ${DUCKDB_SOURCE_DIR}/third_party/vergesort
    ${DUCKDB_SOURCE_DIR}/third_party/yyjson/include
    ${DUCKDB_SOURCE_DIR}/third_party/zstd/include
    ${DUCKDB_BUILD_DIR}/codegen/include
    ${DUCKDB_SOURCE_DIR}/extension
    ${PQCAP_EXTENSION_DIR}/src/include
    ${DUCKDB_SOURCE_DIR}/extension/core_functions/include
    ${DUCKDB_SOURCE_DIR}/extension/parquet/include
    ${SHELL_DIR}/include
    ${LINENOISE_DIR}/include
)

target_link_libraries(pqcap PRIVATE
    ${DUCKDB_BUILD_DIR}/extension/libduckdb_generated_extension_loader.a
    ${DUCKDB_BUILD_DIR}/extension/pqcap_reader/libpqcap_reader_extension.a
    ${DUCKDB_BUILD_DIR}/extension/core_functions/libcore_functions_extension.a
    ${DUCKDB_BUILD_DIR}/extension/parquet/libparquet_extension.a
    ${DUCKDB_BUILD_DIR}/third_party/utf8proc/libduckdb_utf8proc.a
    ${DUCKDB_BUILD_DIR}/src/libduckdb_static.a
    Threads::Threads
)

if(APPLE)
  target_link_libraries(pqcap PRIVATE "-framework CoreFoundation")
endif()

install(TARGETS pqcap RUNTIME DESTINATION bin)
