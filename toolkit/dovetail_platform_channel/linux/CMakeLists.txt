cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "dovetail_platform_channel")
project(${PROJECT_NAME} LANGUAGES CXX)

# GIO, e nao GTK. A sonda le o portal XDG por D-Bus e o GSettings, e as duas
# coisas moram em gio-2.0 — que o embedder GTK do Flutter ja carrega. Pedir
# gtk+-3.0 aqui acrescentaria uma dependencia de compilacao para nada.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)

add_library(${PROJECT_NAME} SHARED
  "dovetail_system_appearance.cc"
)

apply_standard_settings(${PROJECT_NAME})

set_target_properties(${PROJECT_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_definitions(${PROJECT_NAME} PRIVATE DOVETAIL_BUILDING_DLL)
target_include_directories(${PROJECT_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../include/dovetail_platform_channel")
target_link_libraries(${PROJECT_NAME} PRIVATE PkgConfig::GIO)

set(dovetail_platform_channel_bundled_libraries
  $<TARGET_FILE:${PROJECT_NAME}>
  PARENT_SCOPE
)
