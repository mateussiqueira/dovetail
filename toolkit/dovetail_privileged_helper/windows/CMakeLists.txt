cmake_minimum_required(VERSION 3.14)
project(dovetail_privileged_helper LANGUAGES CXX)
find_program(DOVETAIL_CARGO NAMES cargo.exe cargo)
if(NOT DOVETAIL_CARGO)
  message(FATAL_ERROR "Rust/Cargo is required for dovetail_privileged_helper")
endif()
set(RUST_TARGET x86_64-pc-windows-msvc)
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64" OR CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64")
  set(RUST_TARGET aarch64-pc-windows-msvc)
endif()
set(RUST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../rust")
set(RUST_BUILD "${CMAKE_CURRENT_BINARY_DIR}/rust")
set(SERVICE_DLL "${CMAKE_CURRENT_BINARY_DIR}/dovetail_privileged_helper.dll")
file(GLOB_RECURSE RUST_SOURCES CONFIGURE_DEPENDS "${RUST_DIR}/src/*.rs")
add_custom_command(OUTPUT "${SERVICE_DLL}"
  COMMAND "${DOVETAIL_CARGO}" build --release --locked --manifest-path "${RUST_DIR}/Cargo.toml" --target "${RUST_TARGET}" --target-dir "${RUST_BUILD}"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${RUST_BUILD}/${RUST_TARGET}/release/dovetail_windows_service.dll" "${SERVICE_DLL}"
  DEPENDS ${RUST_SOURCES} "${RUST_DIR}/Cargo.toml" "${RUST_DIR}/Cargo.lock"
  VERBATIM)
add_custom_target(dovetail_privileged_helper ALL DEPENDS "${SERVICE_DLL}")
set(dovetail_privileged_helper_bundled_libraries "${SERVICE_DLL}" PARENT_SCOPE)
