cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "accent_acrylic_handler.cpp"
  "desktop_lyrics_window.cpp"
  "flutter_window.cpp"
  "main.cpp"
  "smtc_handler.cpp"
  "taskbar_player_handler.cpp"
  "taskbar_player_window.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "workerw_handler.cpp"
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
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# === SMTC（SystemMediaTransportControls）原生桥 ===
# C++/WinRT 投影要求启用 STL 异常（apply_standard_settings 默认关掉了
# _HAS_EXCEPTIONS）。仅影响本应用 target，Flutter 引擎库本身不受影响。
target_compile_definitions(${BINARY_NAME} PRIVATE "_HAS_EXCEPTIONS=1")

# 源码含中文注释：显式 UTF-8，避免 MSVC 按本机代码页（如 936）解析告警
# （C4819 会被 /WX 升级为错误）。
target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")

# C++/WinRT 头文件位于 Windows SDK 的 cppwinrt 目录，不在默认 include 路径。
# SDK 版本优先取 vcvars 环境变量，否则取 VS generator 探测到的版本。
if(DEFINED ENV{WindowsSDKVersion})
  string(REGEX REPLACE "/$" "" SMTC_SDK_VER "$ENV{WindowsSDKVersion}")
elseif(DEFINED CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION)
  set(SMTC_SDK_VER "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")
endif()
if(DEFINED SMTC_SDK_VER)
  set(SMTC_CPPWINRT_CANDIDATES
    "$ENV{WindowsSdkDir}Include/${SMTC_SDK_VER}/cppwinrt"
    "C:/Program Files (x86)/Windows Kits/10/Include/${SMTC_SDK_VER}/cppwinrt"
    "C:/Program Files/Windows Kits/10/Include/${SMTC_SDK_VER}/cppwinrt")
  foreach(SMTC_CANDIDATE IN LISTS SMTC_CPPWINRT_CANDIDATES)
    if(EXISTS "${SMTC_CANDIDATE}")
      target_include_directories(${BINARY_NAME} PRIVATE "${SMTC_CANDIDATE}")
      break()
    endif()
  endforeach()
endif()

# WinRT 激活与投影需要 windowsapp.lib；SDK 的 Lib 目录不在默认链接路径，
# 显式补上（架构由 CMAKE_SIZEOF_VOID_P 决定）。
if(DEFINED SMTC_SDK_VER)
  if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(SMTC_SDK_ARCH "x64")
  else()
    set(SMTC_SDK_ARCH "x86")
  endif()
  set(SMTC_SDK_LIB_CANDIDATES
    "$ENV{WindowsSdkDir}Lib/${SMTC_SDK_VER}/um/${SMTC_SDK_ARCH}"
    "C:/Program Files (x86)/Windows Kits/10/Lib/${SMTC_SDK_VER}/um/${SMTC_SDK_ARCH}"
    "C:/Program Files/Windows Kits/10/Lib/${SMTC_SDK_VER}/um/${SMTC_SDK_ARCH}")
  foreach(SMTC_CANDIDATE IN LISTS SMTC_SDK_LIB_CANDIDATES)
    if(EXISTS "${SMTC_CANDIDATE}")
      target_link_directories(${BINARY_NAME} PRIVATE "${SMTC_CANDIDATE}")
      break()
    endif()
  endforeach()
endif()
target_link_libraries(${BINARY_NAME} PRIVATE "windowsapp.lib")

# smtc_handler.cpp 使用 C++/WinRT 协程（fire_and_forget），需 /await。
set_source_files_properties("smtc_handler.cpp" PROPERTIES COMPILE_OPTIONS "/await")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
