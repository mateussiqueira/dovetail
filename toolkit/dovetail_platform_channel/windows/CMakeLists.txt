cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "dovetail_platform_channel")
project(${PROJECT_NAME} LANGUAGES CXX)

add_library(${PROJECT_NAME} SHARED
  "single_instance_guard.cpp"
  "guard_window.cpp"
  "launch_payload.cpp"
)

apply_standard_settings(${PROJECT_NAME})

target_compile_definitions(${PROJECT_NAME} PRIVATE DOVETAIL_BUILDING_DLL)
target_include_directories(${PROJECT_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PROJECT_NAME} PRIVATE ole32 user32)

set(dovetail_platform_channel_bundled_libraries
  $<TARGET_FILE:${PROJECT_NAME}>
  PARENT_SCOPE
)
