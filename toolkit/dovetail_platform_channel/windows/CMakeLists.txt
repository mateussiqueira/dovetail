cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "dovetail_platform_channel")
project(${PROJECT_NAME} LANGUAGES CXX)

add_library(${PROJECT_NAME} SHARED
  "single_instance_guard.cpp"
  "guard_window.cpp"
  "launch_payload.cpp"
  "dovetail_system_appearance.cpp"
)

apply_standard_settings(${PROJECT_NAME})

target_compile_definitions(${PROJECT_NAME} PRIVATE DOVETAIL_BUILDING_DLL)
target_include_directories(${PROJECT_NAME}
  INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include"
  # O header da sonda e compartilhado com macOS e Linux, entao mora na raiz do
  # pacote e nao em windows/include: um `.h` por plataforma para um ABI so e
  # como os tres saem de sincronia.
  PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../include/dovetail_platform_channel")
target_link_libraries(${PROJECT_NAME} PRIVATE ole32 user32)

set(dovetail_platform_channel_bundled_libraries
  $<TARGET_FILE:${PROJECT_NAME}>
  PARENT_SCOPE
)
