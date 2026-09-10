cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "dovetail_privileged_helper")
project(${PROJECT_NAME} LANGUAGES CXX)

add_library(${PROJECT_NAME} SHARED
  "dovetail_windows_service.cpp"
)

apply_standard_settings(${PROJECT_NAME})

target_compile_definitions(${PROJECT_NAME} PRIVATE DOVETAIL_BUILDING_DLL)
# The ABI header lives at the package root, not under windows/, so that a
# second platform reaching for it reads the same file rather than a copy.
target_include_directories(${PROJECT_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../include/dovetail_privileged_helper")
# advapi32 carries the service control manager: OpenSCManagerW and everything
# below it.
target_link_libraries(${PROJECT_NAME} PRIVATE advapi32)

set(dovetail_privileged_helper_bundled_libraries
  $<TARGET_FILE:${PROJECT_NAME}>
  PARENT_SCOPE
)
