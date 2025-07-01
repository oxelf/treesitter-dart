# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(treesitter_library VERSION 0.0.1 LANGUAGES C)

add_library(treesitter SHARED
  "treesitter.c"
)

set_target_properties(treesitter PROPERTIES
  PUBLIC_HEADER treesitter.h
  OUTPUT_NAME "treesitter"
)

target_compile_definitions(treesitter PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(treesitter PRIVATE "-Wl,-z,max-page-size=16384")
endif()
