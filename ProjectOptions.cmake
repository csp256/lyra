include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(lyra_supports_sanitizers)
  # Emscripten doesn't support sanitizers
  if(EMSCRIPTEN)
    set(SUPPORTS_UBSAN OFF)
    set(SUPPORTS_ASAN OFF)
  elseif((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

    message(STATUS "Sanity checking UndefinedBehaviorSanitizer, it should be supported on this platform")
    set(TEST_PROGRAM "int main() { return 0; }")

    # Check if UndefinedBehaviorSanitizer works at link time
    set(CMAKE_REQUIRED_FLAGS "-fsanitize=undefined")
    set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=undefined")
    check_cxx_source_compiles("${TEST_PROGRAM}" HAS_UBSAN_LINK_SUPPORT)

    if(HAS_UBSAN_LINK_SUPPORT)
      message(STATUS "UndefinedBehaviorSanitizer is supported at both compile and link time.")
      set(SUPPORTS_UBSAN ON)
    else()
      message(WARNING "UndefinedBehaviorSanitizer is NOT supported at link time.")
      set(SUPPORTS_UBSAN OFF)
    endif()
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    if (NOT WIN32)
      message(STATUS "Sanity checking AddressSanitizer, it should be supported on this platform")
      set(TEST_PROGRAM "int main() { return 0; }")

      # Check if AddressSanitizer works at link time
      set(CMAKE_REQUIRED_FLAGS "-fsanitize=address")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=address")
      check_cxx_source_compiles("${TEST_PROGRAM}" HAS_ASAN_LINK_SUPPORT)

      if(HAS_ASAN_LINK_SUPPORT)
        message(STATUS "AddressSanitizer is supported at both compile and link time.")
        set(SUPPORTS_ASAN ON)
      else()
        message(WARNING "AddressSanitizer is NOT supported at link time.")
        set(SUPPORTS_ASAN OFF)
      endif()
    else()
      set(SUPPORTS_ASAN ON)
    endif()
  endif()
endmacro()

macro(lyra_setup_options)
  option(lyra_ENABLE_HARDENING "Enable hardening" ON)
  option(lyra_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    lyra_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    lyra_ENABLE_HARDENING
    OFF)

  lyra_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR lyra_PACKAGING_MAINTAINER_MODE)
    option(lyra_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(lyra_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(lyra_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(lyra_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(lyra_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(lyra_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(lyra_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(lyra_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(lyra_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(lyra_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(lyra_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(lyra_ENABLE_PCH "Enable precompiled headers" OFF)
    option(lyra_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(lyra_ENABLE_IPO "Enable IPO/LTO" ON)
    option(lyra_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(lyra_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(lyra_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(lyra_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(lyra_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(lyra_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(lyra_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(lyra_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(lyra_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(lyra_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(lyra_ENABLE_PCH "Enable precompiled headers" OFF)
    option(lyra_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      lyra_ENABLE_IPO
      lyra_WARNINGS_AS_ERRORS
      lyra_ENABLE_USER_LINKER
      lyra_ENABLE_SANITIZER_ADDRESS
      lyra_ENABLE_SANITIZER_LEAK
      lyra_ENABLE_SANITIZER_UNDEFINED
      lyra_ENABLE_SANITIZER_THREAD
      lyra_ENABLE_SANITIZER_MEMORY
      lyra_ENABLE_UNITY_BUILD
      lyra_ENABLE_CLANG_TIDY
      lyra_ENABLE_CPPCHECK
      lyra_ENABLE_COVERAGE
      lyra_ENABLE_PCH
      lyra_ENABLE_CACHE)
  endif()

  lyra_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (lyra_ENABLE_SANITIZER_ADDRESS OR lyra_ENABLE_SANITIZER_THREAD OR lyra_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(lyra_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(lyra_global_options)
  if(lyra_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    lyra_enable_ipo()
  endif()

  lyra_supports_sanitizers()

  if(lyra_ENABLE_HARDENING AND lyra_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR lyra_ENABLE_SANITIZER_UNDEFINED
       OR lyra_ENABLE_SANITIZER_ADDRESS
       OR lyra_ENABLE_SANITIZER_THREAD
       OR lyra_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${lyra_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${lyra_ENABLE_SANITIZER_UNDEFINED}")
    lyra_enable_hardening(lyra_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(lyra_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(lyra_warnings INTERFACE)
  add_library(lyra_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  lyra_set_project_warnings(
    lyra_warnings
    ${lyra_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  # Linker and sanitizers not supported in Emscripten
  if(NOT EMSCRIPTEN)
    if(lyra_ENABLE_USER_LINKER)
      include(cmake/Linker.cmake)
      lyra_configure_linker(lyra_options)
    endif()

    include(cmake/Sanitizers.cmake)
    lyra_enable_sanitizers(
      lyra_options
      ${lyra_ENABLE_SANITIZER_ADDRESS}
      ${lyra_ENABLE_SANITIZER_LEAK}
      ${lyra_ENABLE_SANITIZER_UNDEFINED}
      ${lyra_ENABLE_SANITIZER_THREAD}
      ${lyra_ENABLE_SANITIZER_MEMORY})
  endif()

  set_target_properties(lyra_options PROPERTIES UNITY_BUILD ${lyra_ENABLE_UNITY_BUILD})

  if(lyra_ENABLE_PCH)
    target_precompile_headers(
      lyra_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(lyra_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    lyra_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(lyra_ENABLE_CLANG_TIDY)
    lyra_enable_clang_tidy(lyra_options ${lyra_WARNINGS_AS_ERRORS})
  endif()

  if(lyra_ENABLE_CPPCHECK)
    lyra_enable_cppcheck(${lyra_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(lyra_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    lyra_enable_coverage(lyra_options)
  endif()

  if(lyra_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(lyra_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(lyra_ENABLE_HARDENING AND NOT lyra_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR lyra_ENABLE_SANITIZER_UNDEFINED
       OR lyra_ENABLE_SANITIZER_ADDRESS
       OR lyra_ENABLE_SANITIZER_THREAD
       OR lyra_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    lyra_enable_hardening(lyra_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
