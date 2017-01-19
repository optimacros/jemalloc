# Utilities.cmake
# Supporting functions to build Jemalloc

include(CheckTypeSize)
include(CheckCCompilerFlag)
include(CheckCSourceCompiles)

##############################################################################
# CheckTypeSize
function(UtilCheckTypeSize type OUTPUT_VAR_NAME)
    CHECK_TYPE_SIZE(${type} ${OUTPUT_VAR_NAME} LANGUAGE C)

    if(${${OUTPUT_VAR_NAME}})
        set(${OUTPUT_VAR_NAME} ${${OUTPUT_VAR_NAME}} PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Can not determine ${type} size")
    endif()
endfunction(UtilCheckTypeSize)

##############################################################################
# Power of two
# returns result in a VAR whose name is in RESULT_NAME
function(pow2 e RESULT_NAME)
    set(pow2_result 1)
    while(${e} GREATER 0)
        math(EXPR pow2_result "${pow2_result} + ${pow2_result}")
        math(EXPR e "${e} - 1")
    endwhile(${e} GREATER 0)
    set(${RESULT_NAME} ${pow2_result} PARENT_SCOPE)
endfunction(pow2)

##############################################################################
# Logarithm base 2
# returns result in a VAR whose name is in RESULT_NAME
function(lg x RESULT_NAME)
    set(lg_result 0)
    while (${x} GREATER 1)
        math(EXPR lg_result "${lg_result} + 1")
        math(EXPR x "${x} / 2")
    endwhile (${x} GREATER 1)
    set(${RESULT_NAME} ${lg_result} PARENT_SCOPE)
endfunction(lg)

##############################################################################
# Read one file and append it to another
function(AppendFileContents input output)
    file(READ ${input} buffer)
    file(APPEND ${output} "${buffer}")
endfunction(AppendFileContents)

##############################################################################
# Generate public symbols list
function(GeneratePublicSymbolsList public_sym_list mangling_map symbol_prefix output_file)
    # Note: this doesn't do proper change checking.  If you update
    # 'symbol_prefix' or 'mangling_map' you'll need to manually rebuild.
    # Those are uncommon operations at present.
    file(REMOVE "${output_file}")

    # First remove from public symbols those that appear in the mangling map
    if(mangling_map)
        foreach(map_entry ${mangling_map})
            # Extract the symbol
            string(REGEX REPLACE "([^ \t]*):[^ \t]*" "\\1" sym ${map_entry})
            list(REMOVE_ITEM  public_sym_list ${sym})
            file(APPEND "${output_file}" "${map_entry}\n")
        endforeach(map_entry)
    endif()  

    foreach(pub_sym ${public_sym_list})
        file(APPEND "${output_file}" "${pub_sym}:${symbol_prefix}${pub_sym}\n")
    endforeach(pub_sym)

    # Generate files depending on symbols list
    set(JEMALLOC_RENAME_HDR "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_rename.h")
    GenerateJemallocRename("${PUBLIC_SYM_FILE}" ${JEMALLOC_RENAME_HDR})

    set(JEMALLOC_MANGLE_HDR "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_mangle.h")
    GenerateJemallocMangle("${PUBLIC_SYM_FILE}" ${je_} ${JEMALLOC_MANGLE_HDR})

    # Needed for tests
    set(JEMALLOC_MANGLE_JET_HDR "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_mangle_jet.h")
    GenerateJemallocMangle("${PUBLIC_SYM_FILE}" ${JEMALLOC_PREFIX_JET} ${JEMALLOC_MANGLE_JET_HDR})

endfunction(GeneratePublicSymbolsList)

##############################################################################
# Decorate symbols with a prefix
#
# This is per jemalloc_mangle.sh script.
#
# IMHO, the script has a bug that is currently reflected here
# If the public symbol as alternatively named in a mangling map it is not
# reflected here. Instead, all symbols are #defined using the passed symbol_prefix
function(GenerateJemallocMangle public_sym_list symbol_prefix output_file)
    # Header
    file(WRITE "${output_file}"
        "/*\n * By default application code must explicitly refer to mangled symbol names,\n"
        " * so that it is possible to use jemalloc in conjunction with another allocator\n"
        " * in the same application.  Define JEMALLOC_MANGLE in order to cause automatic\n"
        " * name mangling that matches the API prefixing that happened as a result of\n"
        " * --with-mangling and/or --with-jemalloc-prefix configuration settings.\n"
        " */\n"
        "#ifdef JEMALLOC_MANGLE\n"
        "#  ifndef JEMALLOC_NO_DEMANGLE\n"
        "#    define JEMALLOC_NO_DEMANGLE\n"
        "#  endif\n"
        )

    file(STRINGS "${public_sym_list}" INPUT_STRINGS)

    foreach(line ${INPUT_STRINGS})
        string(REGEX REPLACE "([^ \t]*):[^ \t]*" "#  define \\1 ${symbol_prefix}\\1" output ${line})      
        file(APPEND "${output_file}" "${output}\n")
    endforeach(line)

    file(APPEND "${output_file}"
        "#endif\n\n"
        "/*\n"
        " * The ${symbol_prefix}* macros can be used as stable alternative names for the\n"
        " * public jemalloc API if JEMALLOC_NO_DEMANGLE is defined.  This is primarily\n"
        " * meant for use in jemalloc itself, but it can be used by application code to\n"
        " * provide isolation from the name mangling specified via --with-mangling\n"
        " * and/or --with-jemalloc-prefix.\n"
        " */\n"
        "#ifndef JEMALLOC_NO_DEMANGLE\n"
        )

    foreach(line ${INPUT_STRINGS})
        string(REGEX REPLACE "([^ \t]*):[^ \t]*" "#  undef ${symbol_prefix}\\1" output ${line})      
        file(APPEND "${output_file}" "${output}\n")
    endforeach(line)

    # Footer
    file(APPEND "${output_file}" "#endif\n")
endfunction(GenerateJemallocMangle)

##############################################################################
# Generate jemalloc_rename.h per jemalloc_rename.sh
function(GenerateJemallocRename public_sym_list_file file_path)
    # Header
    file(WRITE "${file_path}"
        "/*\n * Name mangling for public symbols is controlled by --with-mangling and\n"
        " * --with-jemalloc-prefix.  With" "default settings the je_" "prefix is stripped by\n"
        " * these macro definitions.\n"
        " */\n#ifndef JEMALLOC_NO_RENAME\n\n"
        )

    file(STRINGS "${public_sym_list_file}" INPUT_STRINGS)
    foreach(line ${INPUT_STRINGS})
        string(REGEX REPLACE "([^ \t]*):([^ \t]*)" "#define je_\\1 \\2" output ${line})
        file(APPEND "${file_path}" "${output}\n")
    endforeach(line)

    # Footer
    file(APPEND "${file_path}"
        "#endif\n"
        )
endfunction(GenerateJemallocRename)

##############################################################################
# Create a jemalloc.h header by concatenating the following headers
# Mimic processing from jemalloc.sh
# This is a Windows specific function
function(CreateJemallocHeader pubsyms header_list output_file)
    file(REMOVE ${output_file})

    message(STATUS "Generating API header ${output_file}")

    file(TO_NATIVE_PATH "${output_file}" ntv_output_file)

    # File Header
    file(WRITE "${ntv_output_file}"
        "#ifndef JEMALLOC_H_\n"
        "#define    JEMALLOC_H_\n"
        "#ifdef __cplusplus\n"
        "extern \"C\" {\n"
        "#endif\n\n"
        )

    foreach(pub_hdr ${header_list} )
        if(False)
            message(STATUS "Copying ${pub_hdr} into public header")
        endif()
        set(HDR_PATH "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/${pub_hdr}")
        file(TO_NATIVE_PATH "${HDR_PATH}" ntv_pub_hdr)
        AppendFileContents(${ntv_pub_hdr} ${ntv_output_file})
    endforeach(pub_hdr)

    # Footer
    file(APPEND "${ntv_output_file}"
        "#ifdef __cplusplus\n"
        "}\n"
        "#endif\n"
        "#endif /* JEMALLOC_H_ */\n"
        )
endfunction(CreateJemallocHeader)

##############################################################################
# Redefines public symbols prefxied with je_ via a macro
# Based on public_namespace.sh which echoes the result to a stdout
function(PublicNamespace public_sym_list_file output_file)
    file(REMOVE ${output_file})
    file(STRINGS "${public_sym_list_file}" INPUT_STRINGS)
    foreach(line ${INPUT_STRINGS})
        string(REGEX REPLACE "([^ \t]*):[^ \t]*" "#define    je_\\1 JEMALLOC_N(\\1)" output ${line})
        file(APPEND ${output_file} "${output}\n")
    endforeach(line)
endfunction(PublicNamespace)

##############################################################################
# #undefs public je_prefixed symbols
# Based on public_unnamespace.sh which echoes the result to a stdout
function(PublicUnnamespace public_sym_list_file output_file)
    file(REMOVE ${output_file})
    file(STRINGS "${public_sym_list_file}" INPUT_STRINGS)
    foreach(line ${INPUT_STRINGS})
        string(REGEX REPLACE "([^ \t]*):[^ \t]*" "#undef    je_\\1" output ${line})
        file(APPEND ${output_file} "${output}\n")
    endforeach(line)
endfunction(PublicUnnamespace)


##############################################################################
# Redefines a private symbol via a macro
# Based on private_namespace.sh
function(PrivateNamespace private_sym_list_file output_file)
    file(REMOVE ${output_file})
    file(STRINGS ${private_sym_list_file} INPUT_STRINGS)
    foreach(line ${INPUT_STRINGS})
        file(APPEND ${output_file} "#define    ${line} JEMALLOC_N(${line})\n")
    endforeach(line)
endfunction(PrivateNamespace)

##############################################################################
# Redefines a private symbol via a macro
# Based on private_namespace.sh
function(PrivateUnnamespace private_sym_list_file output_file)
    file(REMOVE ${output_file})
    file(STRINGS ${private_sym_list_file} INPUT_STRINGS)
    foreach(line ${INPUT_STRINGS})
        file(APPEND ${output_file} "#undef ${line}\n")
    endforeach(line)
endfunction(PrivateUnnamespace)


##############################################################################
# A function(that configures a file_path and outputs
# end result into output_path
# ExpandDefine True/False if we want to process the file and expand
# lines that start with #undef DEFINE into what is defined in CMAKE
function(ConfigureFile file_path output_path ExpandDefine)
    # Convert autoconf .in files to .cmake files to generate proper .h files
    file(TO_NATIVE_PATH "${file_path}" ntv_file_path)

    if(EXISTS ${file_path})
        get_filename_component(fname ${file_path} NAME)
        get_filename_component(oname ${output_path} NAME)
        if(NOT ${ExpandDefine})
            message(STATUS "Configuring ${fname} -> ${oname}")
            configure_file(${file_path} ${output_path} @ONLY)
        else()
            message(STATUS
                "Translating ${fname} -> ${fname}.cmake => ${oname}")

            # Quotes around the variables below are _necessary_ or CMake
            # will remove semicolons from files, which is very bad for us.
            file(READ ${file_path} CONFIG_TRANSLATE)
            string(REGEX REPLACE
                "#undef[ \t]*([^ \t\r\n]+)" "#cmakedefine \\1 @\\1@"
                CONFIG_TRANSLATED "${CONFIG_TRANSLATE}")
            file(WRITE ${file_path}.cmake "${CONFIG_TRANSLATED}")

            configure_file(${file_path}.cmake ${output_path} @ONLY)
        endif()
    else()
        message(FATAL_ERROR "${file_path} not found")
    endif()
endfunction(ConfigureFile)

##############################################################################
## Run Git and parse the output to populate version settings above
function(GetAndParseVersion)
    if (GIT_FOUND AND EXISTS "${PROJECT_SOURCE_DIR}/.git")
        execute_process(COMMAND ${GIT_EXECUTABLE}
            describe --long --abbrev=40
            HEAD
            WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
            OUTPUT_VARIABLE jemalloc_version)

        # Figure out version components    
        string (REPLACE "\n" "" jemalloc_version  ${jemalloc_version})
        set(jemalloc_version ${jemalloc_version} PARENT_SCOPE)
        message(STATUS "Version is ${jemalloc_version}")

        # replace in this order to get a valid cmake list
        string (REPLACE "-g" "-" T_VERSION ${jemalloc_version})
        string (REPLACE "-" "." T_VERSION  ${T_VERSION})
        string (REPLACE "." ";" T_VERSION  ${T_VERSION})

        list(LENGTH T_VERSION L_LEN)

        if(${L_LEN} GREATER 0)
            list(GET T_VERSION 0 jemalloc_version_major)
            set(jemalloc_version_major ${jemalloc_version_major} PARENT_SCOPE)
            message(STATUS "jemalloc_version_major: ${jemalloc_version_major}")
        endif()

        if(${L_LEN} GREATER 1)
            list(GET T_VERSION 1 jemalloc_version_minor)
            set(jemalloc_version_minor ${jemalloc_version_minor} PARENT_SCOPE)
            message(STATUS "jemalloc_version_minor: ${jemalloc_version_minor}")
        endif()

        if(${L_LEN} GREATER 2)
            list(GET T_VERSION 2 jemalloc_version_bugfix)
            set(jemalloc_version_bugfix ${jemalloc_version_bugfix} PARENT_SCOPE)
            message(STATUS "jemalloc_version_bugfix: ${jemalloc_version_bugfix}")
        endif()

        if(${L_LEN} GREATER 3)
            list(GET T_VERSION 3 jemalloc_version_nrev)
            set(jemalloc_version_nrev ${jemalloc_version_nrev} PARENT_SCOPE)
            message(STATUS "jemalloc_version_nrev: ${jemalloc_version_nrev}")
        endif()

        if(${L_LEN} GREATER 4)
            list(GET T_VERSION 4 jemalloc_version_gid)
            set(jemalloc_version_gid ${jemalloc_version_gid} PARENT_SCOPE)
            message(STATUS "jemalloc_version_gid: ${jemalloc_version_gid}")
        endif()
    endif()
endfunction(GetAndParseVersion)

##############################################################################
## This function(attemps to compile a one liner
# with compiler flags to append. If the compiler flags
# are supported they are appended to the variable which names
# is supplied in the APPEND_TO_VAR and the RESULT_VAR is set to
# True, otherwise to False
function(JeCflagsAppend cflags APPEND_TO_VAR RESULT_VAR)
    # Combine the result to try
    set(TFLAGS "${${APPEND_TO_VAR}} ${cflags}")
    CHECK_C_COMPILER_FLAG(${TFLAGS} status)

    if(status)
        set(${APPEND_TO_VAR} "${TFLAGS}" PARENT_SCOPE)
        set(${RESULT_VAR} True PARENT_SCOPE)
        message(STATUS "Checking whether compiler supports ${cflags} ... yes")
    else()
        set(${RESULT_VAR} False PARENT_SCOPE)
        message(STATUS "Checking whether compiler supports ${cflags} ... no")
    endif()
endfunction(JeCflagsAppend)

##############################################################################
# JeCompilable checks if the code supplied in the hcode
# is compilable 
# label - part of the message
# hcode - code prolog such as definitions
# mcode - body of the main() function
#
# It sets rvar to yes or now depending on the result
#
# TODO: Make sure that it does expose linking problems
function(JeCompilable label hcode mcode rvar)
    set(SRC "${hcode}
int main() {
    ${mcode}
    return 0;
}")

    # We may want a stronger check here
    CHECK_C_SOURCE_COMPILES("${SRC}" status)

    if(status)
        set(${rvar} True PARENT_SCOPE)
    else()
        set(${rvar} False PARENT_SCOPE)
    endif()
endfunction(JeCompilable)
