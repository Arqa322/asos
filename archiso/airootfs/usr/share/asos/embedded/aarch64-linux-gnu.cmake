# ASOS: CMake toolchain for NanoPi / any aarch64 Linux board
#   cmake -B build -DCMAKE_TOOLCHAIN_FILE=/usr/share/asos/embedded/aarch64-linux-gnu.cmake
# With the board's libraries (asos-nanopi sysroot pi@board):
#   ASOS_SYSROOT=~/sysroots/nanopi cmake -B build -DCMAKE_TOOLCHAIN_FILE=...
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_ASM_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_AR           aarch64-linux-gnu-ar CACHE FILEPATH "")
set(CMAKE_STRIP        aarch64-linux-gnu-strip CACHE FILEPATH "")

if(DEFINED ENV{ASOS_SYSROOT} AND NOT "$ENV{ASOS_SYSROOT}" STREQUAL "")
  set(CMAKE_SYSROOT "$ENV{ASOS_SYSROOT}")
  set(CMAKE_FIND_ROOT_PATH "$ENV{ASOS_SYSROOT}")
  set(ENV{PKG_CONFIG_SYSROOT_DIR} "$ENV{ASOS_SYSROOT}")
  set(ENV{PKG_CONFIG_LIBDIR} "$ENV{ASOS_SYSROOT}/usr/lib/aarch64-linux-gnu/pkgconfig:$ENV{ASOS_SYSROOT}/usr/lib/pkgconfig:$ENV{ASOS_SYSROOT}/usr/share/pkgconfig")
else()
  set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu)
endif()

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# run test binaries / try_run() through qemu
set(CMAKE_CROSSCOMPILING_EMULATOR qemu-aarch64-static;-L;/usr/aarch64-linux-gnu)
