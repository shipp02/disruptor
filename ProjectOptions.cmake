include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(disruptor_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

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

macro(disruptor_setup_options)
  option(disruptor_ENABLE_HARDENING "Enable hardening" ON)
  option(disruptor_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    disruptor_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    disruptor_ENABLE_HARDENING
    OFF)

  disruptor_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR disruptor_PACKAGING_MAINTAINER_MODE)
    option(disruptor_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(disruptor_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(disruptor_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(disruptor_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(disruptor_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(disruptor_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(disruptor_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(disruptor_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(disruptor_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(disruptor_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(disruptor_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(disruptor_ENABLE_PCH "Enable precompiled headers" OFF)
    option(disruptor_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(disruptor_ENABLE_IPO "Enable IPO/LTO" ON)
    option(disruptor_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(disruptor_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(disruptor_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(disruptor_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(disruptor_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(disruptor_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(disruptor_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(disruptor_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(disruptor_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(disruptor_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(disruptor_ENABLE_PCH "Enable precompiled headers" OFF)
    option(disruptor_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      disruptor_ENABLE_IPO
      disruptor_WARNINGS_AS_ERRORS
      disruptor_ENABLE_USER_LINKER
      disruptor_ENABLE_SANITIZER_ADDRESS
      disruptor_ENABLE_SANITIZER_LEAK
      disruptor_ENABLE_SANITIZER_UNDEFINED
      disruptor_ENABLE_SANITIZER_THREAD
      disruptor_ENABLE_SANITIZER_MEMORY
      disruptor_ENABLE_UNITY_BUILD
      disruptor_ENABLE_CLANG_TIDY
      disruptor_ENABLE_CPPCHECK
      disruptor_ENABLE_COVERAGE
      disruptor_ENABLE_PCH
      disruptor_ENABLE_CACHE)
  endif()

  disruptor_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (disruptor_ENABLE_SANITIZER_ADDRESS OR disruptor_ENABLE_SANITIZER_THREAD OR disruptor_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(disruptor_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(disruptor_global_options)
  if(disruptor_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    disruptor_enable_ipo()
  endif()

  disruptor_supports_sanitizers()

  if(disruptor_ENABLE_HARDENING AND disruptor_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR disruptor_ENABLE_SANITIZER_UNDEFINED
       OR disruptor_ENABLE_SANITIZER_ADDRESS
       OR disruptor_ENABLE_SANITIZER_THREAD
       OR disruptor_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${disruptor_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${disruptor_ENABLE_SANITIZER_UNDEFINED}")
    disruptor_enable_hardening(disruptor_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(disruptor_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(disruptor_warnings INTERFACE)
  add_library(disruptor_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  disruptor_set_project_warnings(
    disruptor_warnings
    ${disruptor_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(disruptor_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    disruptor_configure_linker(disruptor_options)
  endif()

  include(cmake/Sanitizers.cmake)
  disruptor_enable_sanitizers(
    disruptor_options
    ${disruptor_ENABLE_SANITIZER_ADDRESS}
    ${disruptor_ENABLE_SANITIZER_LEAK}
    ${disruptor_ENABLE_SANITIZER_UNDEFINED}
    ${disruptor_ENABLE_SANITIZER_THREAD}
    ${disruptor_ENABLE_SANITIZER_MEMORY})

  set_target_properties(disruptor_options PROPERTIES UNITY_BUILD ${disruptor_ENABLE_UNITY_BUILD})

  if(disruptor_ENABLE_PCH)
    target_precompile_headers(
      disruptor_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(disruptor_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    disruptor_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(disruptor_ENABLE_CLANG_TIDY)
    disruptor_enable_clang_tidy(disruptor_options ${disruptor_WARNINGS_AS_ERRORS})
  endif()

  if(disruptor_ENABLE_CPPCHECK)
    disruptor_enable_cppcheck(${disruptor_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(disruptor_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    disruptor_enable_coverage(disruptor_options)
  endif()

  if(disruptor_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(disruptor_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(disruptor_ENABLE_HARDENING AND NOT disruptor_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR disruptor_ENABLE_SANITIZER_UNDEFINED
       OR disruptor_ENABLE_SANITIZER_ADDRESS
       OR disruptor_ENABLE_SANITIZER_THREAD
       OR disruptor_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    disruptor_enable_hardening(disruptor_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
