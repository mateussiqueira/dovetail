cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "dovetail_shortcut_channel")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust dovetail_shortcut_channel "")

set(dovetail_shortcut_channel_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
