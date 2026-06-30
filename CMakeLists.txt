cmake_minimum_required(VERSION 3.20)
project(EmojiDescription VERSION 1.0.0 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Host plugin interface + Scintilla (read-only; NO host changes)
set(NPP_MACOS_DIR      "${CMAKE_SOURCE_DIR}/../../notepad-plus-plus-macos")
set(NPP_PLUGIN_INCLUDE "${NPP_MACOS_DIR}/src")
set(SCINTILLA_INCLUDE  "${NPP_MACOS_DIR}/scintilla/include")

add_library(EmojiDescription SHARED src/EmojiDescription.mm)
target_include_directories(EmojiDescription PRIVATE ${NPP_PLUGIN_INCLUDE} ${SCINTILLA_INCLUDE})
target_link_libraries(EmojiDescription PRIVATE "-framework Cocoa")
target_compile_options(EmojiDescription PRIVATE
    -Wall -Wno-unused-parameter -fvisibility=hidden
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
set_target_properties(EmojiDescription PROPERTIES PREFIX "" SUFFIX ".dylib")
target_link_options(EmojiDescription PRIVATE "-Wl,-current_version,${PROJECT_VERSION}")

# Install (real plugins dir). Menu-only plugin: no toolbar icons, no runtime
# resources — just the dylib.
set(PLUGIN_INSTALL_DIR "$ENV{HOME}/Library/Application Support/Nextpad++/plugins/EmojiDescription")
install(TARGETS EmojiDescription DESTINATION "${PLUGIN_INSTALL_DIR}")
