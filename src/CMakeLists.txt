# We need this as a SOURCES array and not _just_ an OBJECT library because
# these sources will be compiled multiple times (with name-prefix jet-* and
# without (regular distribution)).  The regular distribution does use OBJECT
# library so we don't build the same sources twice for shared and static.
set(JEMALLOC_CMAKE_SOURCES
    arena.c
    base.c
    bitmap.c
    ckh.c
    ctl.c
    extent.c
    extent_dss.c
    extent_mmap.c
    jemalloc.c
    large.c
    mutex.c
    nstime.c
    pages.c
    prof.c
    rtree.c
    stats.c
    tcache.c
    tsd.c
    util.c
    witness.c
    )

if(CMAKE_SYSTEM_NAME MATCHES "Darwin")
    list(APPEND JEMALLOC_CMAKE_SOURCES zone.c)
endif()

# These objects only have code in debug builds (due to macros)
if(CMAKE_BUILD_TYPE MATCHES Debug)
    list(APPEND JEMALLOC_CMAKE_SOURCES
        atomic.c
        hash.c
        prng.c
        spin.c
        ticker.c)
    # No symbols even in debug mode
    # mb.c
endif()

if(enable_valgrind)
    list(APPEND C_SRCS valgrind.c)
endif()

# Bring sources into an object library so we can include elsewhere
# and also so we don't end up compiling the same code twice for no reason.
add_library(${PROJECT_NAME} OBJECT ${JEMALLOC_CMAKE_SOURCES})

# The original library, delivery product
add_library(${PROJECT_NAME}-static STATIC $<TARGET_OBJECTS:${PROJECT_NAME}>)

# Now add shared library. Needed for integration tests
# and a benchmark
add_library(${PROJECT_NAME}-shared SHARED $<TARGET_OBJECTS:${PROJECT_NAME}>)

# Need to export from DLL
target_compile_definitions(${PROJECT_NAME}-shared PRIVATE DLLEXPORT)

if(with-jemalloc-prefix)
    target_compile_definitions(${PROJECT_NAME}-static PRIVATE JEMALLOC_MANGLE)
    target_compile_definitions(${PROJECT_NAME}-shared PRIVATE JEMALLOC_MANGLE)
endif()

if(enable-prefixed-jemalloc-library)
    ############################################################################
    # JET prefixed version of jemalloc library
    # necessary to compliment non-exported symbols
    # Note: we must references the SOURCES here and not the OBJECT library
    #       because we must re-build with different namespace options.
    add_library(${PROJECT_NAME}-jet-static STATIC ${JEMALLOC_CMAKE_SOURCES})
    target_compile_definitions(${PROJECT_NAME}-jet-static PRIVATE "${C_JETLIB_DEFS}")
endif()

