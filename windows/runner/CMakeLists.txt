cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# --- Copy required runtime binaries into the generated runner folder ---------
# The Clash Meta runtime (mihomo.exe) and the Windows TUN driver (wintun.dll)
# must live next to the built executable so the desktop app can launch the
# tunnel. Users typically place these files in the repo root; we mirror them
# into the build output after every successful build.

get_filename_component(VLF_PROJECT_ROOT "${CMAKE_SOURCE_DIR}/.." ABSOLUTE)
set(VLF_DEP_NAMES "mihomo.exe" "wintun.dll")
set(VLF_DEP_SOURCE_DIRS
  "${VLF_PROJECT_ROOT}"
  "${VLF_PROJECT_ROOT}/.."  # repo sibling fallbacks (legacy Python client)
  "${VLF_PROJECT_ROOT}/../client"
  "${VLF_PROJECT_ROOT}/../client/_internal"
  "${VLF_PROJECT_ROOT}/../client/_internal/pyzbar"
)

foreach(DEP_NAME IN LISTS VLF_DEP_NAMES)
  set(DEP_SOURCE "")
  foreach(DEP_DIR IN LISTS VLF_DEP_SOURCE_DIRS)
    if(EXISTS "${DEP_DIR}/${DEP_NAME}")
      set(DEP_SOURCE "${DEP_DIR}/${DEP_NAME}")
      break()
    endif()
  endforeach()

  if(DEP_SOURCE STREQUAL "")
    message(WARNING "${DEP_NAME} не найден — поместите файл в корень проекта, чтобы он копировался в сборку.")
  else()
    add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
              "${DEP_SOURCE}"
              "$<TARGET_FILE_DIR:${BINARY_NAME}>/${DEP_NAME}"
      COMMENT "Копирую ${DEP_NAME} в папку сборки из ${DEP_SOURCE}"
    )
  endif()
endforeach()
