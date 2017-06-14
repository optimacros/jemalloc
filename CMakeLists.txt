# This CMake file was originally created to only support building on Windows,
# but it's more useful to remove most of the Windows-isms and just make it a
# clean CMake infrastructure for Unix platforms.

cmake_minimum_required(VERSION 2.8 FATAL_ERROR)
project(jemalloc C)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(CheckFunctionExists)
include(CheckSymbolExists)
include(CheckCCompilerFlag)
include(CheckCSourceCompiles)
include(CheckCSourceRuns)
include(CheckIncludeFiles)
include(TestBigEndian)
include(CTest)

include(${PROJECT_SOURCE_DIR}/Utilities.cmake)
include(${PROJECT_SOURCE_DIR}/GetSystemSizes.cmake)
include(${PROJECT_SOURCE_DIR}/GetSystemAddrBits.cmake)

include_directories(${PROJECT_SOURCE_DIR}/include)

if(POLICY CMP0042)
    cmake_policy(SET CMP0042 NEW)
endif()

option(enable-prefixed-jemalloc-library "Build prefixed namespace library" OFF)
# The following config switches that mimic the original autoconf behavior are supported
# use -D to define cmd arguments, options may have values of ON/OFF
option(disable-munmap "Disables unmapping for later reuse (default - enabled)" OFF )
#  with-mangling=k:v,k:v... comma separated list of key:value pairs overrides specific function mangling
#  with-jemalloc-prefix=<prefix> override default je_ prefix
option(without-export "Disable export of public APIs" OFF)
#  with-private-namespace=<additional_prefix>
#  with-install-suffix=<suffix> added to public headers and the library
#  with-malloc-conf=lg_chunk:18 Embed <malloc_conf> as a run-time options string that is processed prior to
#       the malloc_conf global variable
option(disable-cc-silence "Disable compiler silencing code" OFF)
option(enable-debug "Enable debugging code" OFF)
option(enable-ivsalloc "Validate pub API pointers" OFF)
option(disable-stats "Disable stats calculation (on by default)" OFF)
option(disable-tcache "Disable thread-specific caching (on by default)" OFF)
option(disable-fill  "Disabling filling memory with junk on by default" OFF)
option(enable-xmalloc "Support xmalloc option" OFF)
option(disable-cache-oblivious "Disable uniform distribution of large allocations" OFF)
#  with-lg-tiny-min=<lg2 value> override default value of 3 of lg2 minimum tiny clas size
#  with-lg-quantum=<lg2 of the min allocation alignment>
#  with-lg-page=<lg2 of the page size> override system page size
#  with-lg-page-sizes=<comma separated list of lg2 pages sizes> Base 2 logs of system page sizes to support
#  with-lg_size-class-group=<Base 2 log of size classes per doubling> default 2
option(enable-lazy-lock "Enable lazy locking (only lock when multi-threaded" OFF)
option(force_lazy_lock "Forcing lazy-lock to avoid allocator/threading bootstrap issues" OFF)
# install_prefix - installation directory prefix
# with-xslroot=<path>  XSL stylesheet root path

# Installation
# Munge install path variables.
# All of these can simply we be passed as
# Cmake arguments
if(NOT install_prefix)
    set(install_prefix "/usr/local")
endif()

if(NOT exec_prefix)
    set(exec_prefix $install_prefix)
endif()

set(PREFIX $install_prefix)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu11")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wsign-compare")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -pipe -g3")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D_GNU_SOURCE")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fvisibility=hidden -O3 -funroll-loops")

if(CMAKE_C_COMPILER_ID MATCHES "Clang")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-tautological-pointer-compare")
endif()

check_c_compiler_flag("-Wshorten-64-to-32" FLAG_SHORTEN)

if(FLAG_SHORTEN)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wshorten-64-to-32")
endif()

##############################################################################
# Versioning from GIT
# Defaults
set(jemalloc_version "0.0.0-0-g0000000000000000000000000000000000000000")
set(jemalloc_version_major 0)
set(jemalloc_version_minor 0)
set(jemalloc_version_bugfix 0)
set(jemalloc_version_nrev 0)
set(jemalloc_version_gid "0")

find_package(Git)
GetAndParseVersion()

# We do not support exec_prefix until we find it is necessary

check_include_files(alloca.h JEMALLOC_HAS_ALLOCA_H)

if(APPLE)
    set(abi "macho")
else()
    set(abi "elf")
endif()

# Whether malloc_usable_size definition can use const argument
check_include_files(malloc.h HAVE_MALLOC_H)
if(HAVE_MALLOC_H)
    set(JEMALLOC_USABLE_SIZE_CONST const)
else()
    set(JEMALLOC_USABLE_SIZE_CONST const)
endif()    

check_include_files(inttypes.h HAVE_INTTYPES_H)
check_include_files(sys/time.h HAVE_SYSTIME_H)

test_big_endian(JEMALLOC_BIG_ENDIAN)

UtilCheckTypeSizeValid("void *" LG_SIZEOF_PTR 8 4)
UtilCheckTypeSizeValid("int" LG_SIZEOF_INT 8 4)
UtilCheckTypeSizeValid("long" LG_SIZEOF_LONG 8 4)
UtilCheckTypeSizeValid("long long" LG_SIZEOF_LONG_LONG 8 4)
UtilCheckTypeSizeValid("intmax_t" LG_SIZEOF_INTMAX_T 16 8 4)

if(MSVC)
    JeCompilable("pause instruction MSVC" "" "_mm_pause();" je_cv_pause_msvc)
    if(je_cv_pause_msvc)
        set(CPU_SPINWAIT "_mm_pause()")
    else()
        JeCompilable("YieldProcessor() MSVC" "#include <Windows.h>" "YieldProcessor();" je_cv_pause_msvc)
        if(je_cv_pause_msvc)
            set(CPU_SPINWAIT "YieldProcessor()")
        endif()
    endif()
elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "i686" OR
        CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "x86_64")
    JeCompilable("pause instruction" "" "__asm__ volatile(\"pause\");" je_cv_pause)
    if(je_cv_pause)
        set( CPU_SPINWAIT "__asm__ volatile(\"pause\")")
    endif()
endif()

if(CMAKE_SYSTEM_NAME MATCHES "powerpc")
    set(HAVE_ALTIVEC 1)
endif()


# If defined, use munmap() to unmap freed chunks, rather than storing them for
# later reuse.  This is disabled by default on Linux because common sequences
# of mmap()/munmap() calls will cause virtual memory map holes.
# But it is enabled by default on Windows
if(NOT UNIX)
    set(JEMALLOC_MUNMAP 1)
endif()

if(disable-munmap)
    set(JEMALLOC_MUNMAP 0)
endif()

# If defined, adjacent virtual memory mappings with identical attributes
# automatically coalesce, and they fragment when changes are made to subranges.
# This is the normal order of things for mmap()/munmap(), but on Windows
# VirtualAlloc()/VirtualFree() operations must be precisely matched, i.e.
# mappings do *not* coalesce/fragment.
set(JEMALLOC_MAPS_COALESCE 1)

##############################################################################
# Below is everything under HAVE_ATTR

set(CMAKE_REQUIRED_FLAGS "-Werror -Wall -Wextra -std=gnu11")
check_c_source_runs("__attribute__((unused)) void foo(void){}
int main() {
    foo();
    return 0;
}" JEMALLOC_HAVE_ATTR)
check_c_source_runs("#include <stdlib.h>
void *foo(size_t size) __attribute__((alloc_size(1))) {
    return NULL;
}
int main() {
    (void)foo(100);
    return 0;
}" JEMALLOC_HAVE_ATTR_ALLOC_SIZE)
check_c_source_runs("#include <stdlib.h>
void *foo(const char *format, ...) __attribute__((format(printf, 1, 2)));
__attribute__((format(printf, 1, 2))) void *foo(const char *format, ...) {
    return (void *)format;
}
int main() {
    (void)foo(NULL);
    return 0;
}" JEMALLOC_HAVE_ATTR_FORMAT_PRINTF)
check_c_source_runs("#include <stdlib.h>
int main() {
    void *restrict abc = NULL;
    (void)abc;
    return 0;
}" JEMALLOC_HAS_RESTRICT)
check_c_source_runs("#include <stdlib.h>
#include <stdio.h>
#include <strings.h>
#include <string.h>
int main() {
    int rv = __builtin_ffsl(0x08);
    printf(\"%d\", rv);
    return !(rv == 4);
}" HAS_BUILTIN_FFSL)

if(HAS_BUILTIN_FFSL)
    set(JEMALLOC_INTERNAL_FFSLL "__builtin_ffsll")
    set(JEMALLOC_INTERNAL_FFSL "__builtin_ffsl")
    set(JEMALLOC_INTERNAL_FFS "__builtin_ffs")
else()
    check_c_source_runs("#include <stdlib.h>
    #include <stdio.h>
    #include <strings.h>
    #include <string.h>
    int main() {
        int rv = ffsl(0x08);
        printf(\"%d\", rv);
        return !(rv == 4);
    }" HAS_FFSL)

    if(HAS_FFSL)
        set(JEMALLOC_INTERNAL_FFSLL "ffsll")
        set(JEMALLOC_INTERNAL_FFSL "ffsl")
        set(JEMALLOC_INTERNAL_FFS "ffs")
    else()
        message(FATAL_ERROR "Neither __builtin_ffs() or ffs() found!")
    endif()
endif()

check_function_exists(memalign JEMALLOC_OVERRIDE_MEMALIGN)
check_function_exists(valloc JEMALLOC_OVERRIDE_VALLOC)
check_function_exists(secure_getenv JEMALLOC_HAVE_SECURE_GETENV)

set(CMAKE_REQUIRED_FLAGS) # reset arguments back to defaults


if(with-mangling)
    # We are expecting entries separated by a comma
    # with individual entries split by a ':' as in n:m
    # Convert that into a CMake list of ';' separated pairs
    string(REPLACE "," ";" MANGLING_MAP  ${with-mangling})
endif()

# Set the default API prefix for public
set(JEMALLOC_PREFIX "\"je_\"")
set(je_ je_) # in-header prefix for je_blahblah

if(with-jemalloc-prefix)
    set(JEMALLOC_PREFIX "\"${with-jemalloc-prefix}\"")
endif()

# Uppercase copy of the JEMALLOC_PREFIX
# Need  quotes so the preprocessor concats two strings
if(JEMALLOC_PREFIX)
    string(TOUPPER ${JEMALLOC_PREFIX} JEMALLOC_CPREFIX)
endif()

# Disable exporting jemalloc public APIs
# We need to define the var to whitespace string
# as empty strings will not be defined in CMake
# Non-empty definition is necessary so
if(without-export)
    set(JEMALLOC_EXPORT " ")
endif()

# Prefix to prepend to all library-private APIs
# default is on
set(JEMALLOC_PRIVATE_NAMESPACE je_)
if(with-private-namespace)
    set(JEMALLOC_PRIVATE_NAMESPACE "${with_private_namespace}je_")
endif()

set(private_namespace ${JEMALLOC_PRIVATE_NAMESPACE})

# Default empty
# Specify default malloc_conf
set(JEMALLOC_CONFIG_MALLOC_CONF "\"\"")
if(with-malloc-conf)
    set(JEMALLOC_CONFIG_MALLOC_CONF "\"${with-malloc-conf}\"")
endif()

if(with-install-suffix)
    set(INSTALL_SUFFIX ${with-install-suffix})
    set(install_suffix ${with-install-suffix})
endif()

# Do not silence irrelevant compiler warnings
set(JEMALLOC_CC_SILENCE 1)
if(disable-cc-silence)
    set(JEMALLOC_CC_SILENCE 0)
endif()

# Build debugging code (implies --enable-ivsalloc)
if(enable-debug OR (CMAKE_BUILD_TYPE MATCHES Debug))
    set(JEMALLOC_DEBUG 1)
    set(JEMALLOC_IVSALLOC 1)
endif()

# Validate pointers passed through the public API
if(enable-ivsalloc)
    set(JEMALLOC_IVSALLOC 1)
endif()

# Enable stats by default
set(JEMALLOC_STATS 1)
# Disable statistics calculation/reporting
if(disable-stats)
    set(JEMALLOC_STATS 0)
endif()

# Enable thread-specific caching by default.
set(JEMALLOC_TCACHE 1)
if(disable-tcache)
    set(JEMALLOC_TCACHE 0)
endif()

set(JEMALLOC_PREFIX_JET jet_)

# Disabling dss allocation because sbrk is deprecated
set(JEMALLOC_DSS 0)

# Support the junk/zero filling option by default.
set(JEMALLOC_FILL 1)
# Disable support for junk/zero filling, quarantine, and redzones
if(disable-fill)
    set(JEMALLOC_FILL 0)
endif()

# Windows does not have it
set(JEMALLOC_UTRACE 0)
set(JEMALLOC_VALGRIND 0)

# Support xmalloc option
set(JEMALLOC_XMALLOC 0)
if(enable-xmalloc)
    set(JEMALLOC_XMALLOC 1)
endif()

# Support cache-oblivious allocation alignment by default.
# If defined, explicitly attempt to more uniformly distribute large allocation
# pointer alignments across all cache indices.
set(JEMALLOC_CACHE_OBLIVIOUS 1)
if(disable-cache-oblivious)
    set(JEMALLOC_CACHE_OBLIVIOUS 0)
endif()

set(JEMALLOC_INTERNAL_UNREACHABLE abort)

# Base 2 log of minimum tiny size class to support
set(LG_TINY_MIN 3)
if(with-lg-tiny-min)
    set(LG_TINY_MIN ${with-lg-tiny-min})
endif()

# Base 2 log of minimum allocation alignment
set(LG_QUANTA "3 4")

#if(with-lg-quantum)
# Convert to a CMake list
#string(REPLACE "," ";" LG_QUANTA  ${with-lg-quantum})
#  set(LG_QUANTA ${with-lg-quantum})
#set(LG_QUANTUM ${LG_QUANTA})
#endif()

# Base 2 log of system page size

if(with-lg-page)
    set(LG_PAGE ${with-lg-page})
endif()

if(NOT LG_VADDR)
    if(${CMAKE_SYSTEM_PROCESSOR} MATCHES "aarch64") # maybe "arm64"?
        set(LG_VADDR 48)
    elseif(${CMAKE_SYSTEM_PROCESSOR} MATCHES "x86_64")
        GetSystemAddrBits(LG_VADDR)
    else()
        message(FATAL_ERROR "Undecided number of VADDR bits")
    endif()
endif()

if((NOT LG_PAGE) OR (NOT CACHELINE) OR ("${LG_PAGE}" STREQUAL "detect"))
    if(NOT SYSTEM_JE_PAGE_SIZE)
        GetSystemSizes(SYSTEM_PAGE_SIZE SYSTEM_CACHE_SIZE)
        set(SYSTEM_PAGE_SIZE ${SYSTEM_PAGE_SIZE} CACHE STRING "Page Size")
        set(SYSTEM_CACHE_SIZE ${SYSTEM_CACHE_SIZE} CACHE STRING "Cache Line Size")
    endif()
    lg(${SYSTEM_PAGE_SIZE} LG_PAGE)
    set(CACHELINE ${SYSTEM_CACHE_SIZE})
    lg(${SYSTEM_CACHE_SIZE} LG_CACHELINE)
endif()

# Base 2 logs of system page sizes to support
set(LG_PAGE_SIZES ${LG_PAGE})
if(with-lg-page-sizes)
    string(REPLACE "," ";" LG_PAGE_SIZES  ${with-lg-page-sizes})
endif()

# Base 2 log of size classes per doubling
set(LG_SIZE_CLASS_GROUP 2)
if(with-lg-size-class-group)
    set(LG_SIZE_CLASS_GROUP ${with-lg-size-class-group})
endif()

if(NOT WIN32)
    # Check if syscall(2) is usable.
    # Treat warnings as errors, so that e.g. OS X 10.12's warning prevents use.
    set(CMAKE_REQUIRED_FLAGS  "${CMAKE_C_FLAGS} -Werror")
    CHECK_C_SOURCE_COMPILES("
    #include <sys/syscall.h>
    #include <unistd.h>
    syscall(SYS_write, 2, \"hello\", 5);
    " HAVE_SYSCALL)

    if(HAVE_SYSCALL)
        set(JEMALLOC_HAVE_SYSCALL 1)
    endif()
endif()

set(JEMALLOC_HAVE_ISSETUGID 0)
set(JEMALLOC_MALLOC_THREAD_CLEANUP 0)

set(JEMALLOC_MUTEX_INIT_CB 0)

##############################################################################
# enable-lazy-lock
set(JEMALLOC_LAZY_LOCK 0)
if(NOT enable-lazy-lock)
    if(force_lazy_lock)
        message(STATUS "Forcing lazy-lock to avoid allocator/threading bootstrap issues")
        set(enable-lazy-lock ON)
    endif()
endif()

if(enable-lazy-lock)
    if(${abi} STREQUAL "pecoff")
        message(STATUS "Forcing no lazy-lock because thread creation monitoring is unimplemented")
        set(enable-lazy-lock OFF)
    endif()
endif()

if(enable-lazy-lock)
    check_include_files(dlfcn.h HAVE_DLFCN_H)
    if(NOT HAVE_DLFCN_H)
        message(FATAL_ERROR "dlfcn.h is missing")
    endif()

    set(CMAKE_REQUIRED_LIBRARIES "dl")
    CHECK_FUNCTION_EXISTS(dlsym HAVE_DLSYM)
    if(NOT HAVE_DLSYM)
        message(FATAL_ERROR "libdl is missing]")
    endif()
endif()

##############################################################################

# Thread-local storage
set(JEMALLOC_TLS 0)

if(${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
    # Relevant for FreeBSD only
    set(JEMALLOC_ATOMIC9 1)
endif()

# On linux, can detect by parsing :
# hpsk=`cat /proc/meminfo 2>/dev/null | \
#          grep -e '^Hugepagesize:[[:space:]]\+[0-9]\+[[:space:]]kB$' | \
#          awk '{print $2}'`
# then adding 1 to the result
set(LG_HUGEPAGE 21)

# OS X / iOS / Darwin settings
if(APPLE)
    set(LG_HUGEPAGE 21)
    set(JEMALLOC_OSATOMIC 1)

    # Sierra has a new locking mechanism
    CHECK_INCLUDE_FILE(os/lock.h APPLE_LOCK)
    if(APPLE_LOCK)
        set(JEMALLOC_OS_UNFAIR_LOCK 1)
    else()
        set(JEMALLOC_OSSPIN 1)
    endif()

    set(JEMALLOC_ZONE 1)
endif()

if(WIN32)
    # Only for GNU
    set(JE_FORCE_SYNC_COMPARE_AND_SWAP_4 0)
    set(JE_FORCE_SYNC_COMPARE_AND_SWAP_8 0)
    set(JEMALLOC_HAVE_BUILTIN_CLZ 0)
    set(JEMALLOC_HAVE_MADVISE 0)
    set(JEMALLOC_THREADED_INIT 0)

    set(JEMALLOC_TLS_MODEL 0)
    set(JEMALLOC_CODE_COVERAGE 0)
    set(JEMALLOC_PROF 0)
    set(JEMALLOC_PROF_LIBUNWIND 0)
    set(JEMALLOC_PROF_LIBGCC 0)
    set(JEMALLOC_PROF_GCC 0)
else()
    # jemalloc uses GCC macros to detect if 4/8 byte swaps are available.
    # If headers are bad, you can force using even if your compiler doesn't
    # advertise the behavior.
    set(JE_FORCE_SYNC_COMPARE_AND_SWAP_4 0)
    set(JE_FORCE_SYNC_COMPARE_AND_SWAP_8 0)

    # We assume good compilers with clz and clzl available (no testing required)
    set(JEMALLOC_HAVE_BUILTIN_CLZ 1)

    set(JEMALLOC_HAVE_MADVISE 1)
    set(JEMALLOC_THREADED_INIT 1)

    set(JEMALLOC_TLS_MODEL "__attribute__((tls_model(\"initial-exec\")))")

    # Debugging / Profiling / Testing
    set(JEMALLOC_CODE_COVERAGE 0)
    set(JEMALLOC_PROF 0)
    set(JEMALLOC_PROF_LIBUNWIND 0) # Allow manual option() here
    set(JEMALLOC_PROF_LIBGCC 0)
    set(JEMALLOC_PROF_GCC 0)
endif()



set(CMAKE_REQUIRED_FLAGS "-Werror -Wall -Wextra -std=c11")
check_c_source_runs("
#include <stdint.h>
#if(__STDC_VERSION__ >= 201112L) && !defined(__STDC_NO_ATOMICS__)
#include <stdatomic.h>
#else
#error Atomics not available
#endif
int main() {
    uint64_t q = 0;
    uint64_t *p = &q;
    uint64_t x = 1;
    volatile atomic_uint_least64_t *a = (volatile atomic_uint_least64_t *)p;
    uint64_t r = atomic_fetch_add(a, x) + x;
    return (r == 0);
}
" JEMALLOC_C11_ATOMICS)

set(CMAKE_REQUIRED_FLAGS)

# Platform overrides (taken from configure.ac)
if(CMAKE_SYSTEM_NAME MATCHES "Darwin")
    set(JEMALLOC_TLS 0)
    set(JEMALLOC_THREADED_INIT 0)
    set(JEMALLOC_PROF_LIBUNWIND 0)
elseif(CMAKE_SYSTEM_NAME MATCHES "FreeBSD")
    set(JEMALLOC_SYSCTL_VM_OVERCOMMIT 1)
elseif(CMAKE_SYSTEM_NAME MATCHES "Linux")
    set(JEMALLOC_PROC_SYS_VM_OVERCOMMIT_MEMORY 1)
    set(JEMALLOC_THREADED_INIT 1)
    set(JEMALLOC_USE_CXX_THROW 1)
endif()

##############################################################################
# Generate configured public headers for concatenation
# Public Headers in for configuring
set(PUBLIC_SYM
    aligned_alloc
    calloc
    dallocx
    free
    mallctl
    mallctlbymib
    mallctlnametomib
    malloc
    malloc_conf
    malloc_message
    malloc_stats_print
    malloc_usable_size
    mallocx
    nallocx
    posix_memalign
    rallocx
    realloc
    sallocx
    sdallocx
    xallocx
    valloc
)

set(PUBLIC_SYM_FILE "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/public_symbols.txt")
GeneratePublicSymbolsList("${PUBLIC_SYM}" "${MANGLING_MAP}" ${je_} "${PUBLIC_SYM_FILE}")

foreach(public_in jemalloc_macros.h jemalloc_defs.h jemalloc_protos.h jemalloc_typedefs.h)
    ConfigureFile("${PROJECT_SOURCE_DIR}/include/jemalloc/${public_in}.in"
        "${PROJECT_SOURCE_DIR}/include/jemalloc/${public_in}" True)
endforeach(public_in)  

# Generate main public header
set(JEMALLOC_HDR "${PROJECT_SOURCE_DIR}/include/jemalloc/jemalloc${install_suffix}.h")

set(JEMALLOC_HDR_LIST
    jemalloc_defs.h
    jemalloc_rename.h
    jemalloc_macros.h
    jemalloc_protos.h
    jemalloc_typedefs.h
    jemalloc_mangle.h
    )

CreateJemallocHeader(${PUBLIC_SYM_FILE} "${JEMALLOC_HDR_LIST}" "${JEMALLOC_HDR}")

##############################################################################
## Internal headers generation
set(PUBLIC_NAMESPACE_FILE "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/public_namespace.h")
PublicNamespace(${PUBLIC_SYM_FILE} "${PUBLIC_NAMESPACE_FILE}")

set(PUBLIC_UNNAMESPACE_FILE "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/public_unnamespace.h")
PublicUnnamespace(${PUBLIC_SYM_FILE} "${PUBLIC_UNNAMESPACE_FILE}")

# This file comes with repo
set(PRIVATE_SYM_FILE "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/private_symbols.txt")

set(PRIVATE_NAMESPACE_FILE "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/private_namespace.h")
PrivateNamespace("${PRIVATE_SYM_FILE}" "${PRIVATE_NAMESPACE_FILE}")

# Configure internal headers

# Main internal header does not require #define expansion otherwise it affects real #undefs
ConfigureFile("${PROJECT_SOURCE_DIR}/include/jemalloc/internal/jemalloc_preamble.h.in"
    "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/jemalloc_preamble.h" True)

foreach(internal_in jemalloc_internal_defs.h)
    ConfigureFile("${PROJECT_SOURCE_DIR}/include/jemalloc/internal/${internal_in}.in"
        "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/${internal_in}" True)
endforeach(internal_in)  

# Test related headers
ConfigureFile("${PROJECT_SOURCE_DIR}/test/include/test/jemalloc_test_defs.h.in"
    "${PROJECT_SOURCE_DIR}/test/include/test/jemalloc_test_defs.h" True)

ConfigureFile("${PROJECT_SOURCE_DIR}/test/include/test/jemalloc_test.h.in"
    "${PROJECT_SOURCE_DIR}/test/include/test/jemalloc_test.h" False)

# Only build size_classes.h if it doesn't exist.  No dependency/update checking.
if("${PROJECT_SOURCE_DIR}/include/jemalloc/internal/size_classes.sh"
        IS_NEWER_THAN
        "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/size_classes.h")
    message(STATUS
        "RUNNING ${PROJECT_SOURCE_DIR}/include/jemalloc/internal/size_classes.sh "
        "\"${LG_QUANTA}\" \"${LG_TINY_MIN}\" \"${LG_PAGE_SIZES}\" \"${LG_SIZE_CLASS_GROUP}\"")

    execute_process(COMMAND
        "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/size_classes.sh"
        "${LG_QUANTA}" "${LG_TINY_MIN}" "${LG_PAGE_SIZES}" "${LG_SIZE_CLASS_GROUP}"
        OUTPUT_FILE "${PROJECT_SOURCE_DIR}/include/jemalloc/internal/size_classes.h")
endif()

# To generate protos_jet
set(je_ jet_)

# replace prefix only
ConfigureFile("${PROJECT_SOURCE_DIR}/include/jemalloc/jemalloc_protos.h.in"
    "${PROJECT_SOURCE_DIR}/include/jemalloc/jemalloc_protos_jet.h" True)

# revert
set(je_ je_)

if(CMAKE_BUILD_TYPE MATCHES Debug)
    set(enable-prefixed-jemalloc-library ON)
endif()

if(enable-prefixed-jemalloc-library)
    set(C_JETLIB_DEFS "JEMALLOC_JET")

    set(C_UTIL_INTEGRATION_DEFS "")
    set(C_TESTLIB_INTEGRATION_DEFS "JEMALLOC_INTEGRATION_TEST")
    set(C_TESTLIB_INTEGRATION ${PROJECT_NAME}IntegrationTest${install_suffix})

    set(C_TESTLIB_UNIT_DEFS "JEMALLOC_UNIT_TEST")
    set(C_TESTLIB_STRESS_DEF "JEMALLOC_STRESS_TEST;JEMALLOC_STRESS_TESTLIB")
    set(C_TESTLIB_STRESS ${PROJECT_NAME}TestStress${install_suffix})

    set(C_UNITETEST_DEFS "JEMALLOC_UNIT_TEST")

    if(with-jemalloc-prefix)
        set(C_JETLIB_DEFS  "${C_JETLIB_DEFS};JEMALLOC_MANGLE")
        set(C_UTIL_INTEGRATION_DEFS "${C_UTIL_INTEGRATION_DEFS};JEMALLOC_MANGLE")
    endif()

    # Add empty definition of JEMALLOC_EXPORT as we use them in
    # static form on other platforms it is empty defined by default but
    # not on windows
    if(MSVC)
        set(C_JETLIB_DEFS  "${C_JETLIB_DEFS};JEMALLOC_EXPORT=")
        set(C_TESTLIB_INTEGRATION_DEFS "${C_TESTLIB_INTEGRATION_DEFS};JEMALLOC_EXPORT=")
        set(C_TESTLIB_UNIT_DEFS "${C_TESTLIB_UNIT_DEFS};JEMALLOC_EXPORT=")
        set(C_TESTLIB_STRESS_DEF "${C_TESTLIB_STRESS_DEF};JEMALLOC_EXPORT=")
        set(C_UNITETEST_DEFS "${C_UNITETEST_DEFS};JEMALLOC_EXPORT=")

        # C4018 signed/unsigned mismatch in timer.c
        set(COMMON_TESTLIB_CC_FLAGS /wd4018)
    endif()
endif()

if(CMAKE_BUILD_TYPE MATCHES Debug)
    enable_testing()
    add_custom_target(check COMMAND ${CMAKE_CTEST_COMMAND})

    add_subdirectory(test)
endif()

add_subdirectory(src)
