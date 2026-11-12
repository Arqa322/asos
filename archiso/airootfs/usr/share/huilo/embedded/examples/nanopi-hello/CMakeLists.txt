cmake_minimum_required(VERSION 3.16)
project(nanopi_hello C)

# Arch's cross glibc is newer than the one on most board images
# (Ubuntu/Debian), so link statically unless a board sysroot is used.
if(CMAKE_SYSROOT)
  option(STATIC "Link statically" OFF)
else()
  option(STATIC "Link statically" ON)
endif()

add_executable(hello main.c)
target_compile_options(hello PRIVATE -O2 -Wall -Wextra)
if(STATIC)
  target_link_options(hello PRIVATE -static)
endif()
