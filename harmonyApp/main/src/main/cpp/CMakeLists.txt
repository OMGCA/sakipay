# CMake build for the Sakipay NAPI bridge.
#
# The shared business logic is compiled by Kotlin/Native into libsakipay.so
# (see ../../../../../kmp/sakipay/sharedLogic). It is published into
# main/libs/<abi>/ by the Gradle task
#   :sharedLogic:publishDebugBinariesToHarmonyApp
# and linked into libentry.so, which exposes the JSON functions to ArkTS.
cmake_minimum_required(VERSION 3.5.0)
project(sakipay_hmos)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

# Pick the libsakipay.so ABI directory that matches the current build.
if(CMAKE_OHOS_ARCH_ABI STREQUAL "x86_64" OR OHOS_ARCH STREQUAL "x86_64")
    set(SAKIPAY_ABI_DIR "x86_64")
else()
    set(SAKIPAY_ABI_DIR "arm64-v8a")
endif()

add_library(sakipay SHARED IMPORTED)
set_target_properties(sakipay PROPERTIES
    IMPORTED_LOCATION "${NATIVERENDER_ROOT_PATH}/../../../libs/${SAKIPAY_ABI_DIR}/libsakipay.so")

add_library(entry SHARED napi_init.cpp)
target_link_libraries(entry PUBLIC libace_napi.z.so)
target_link_libraries(entry PRIVATE sakipay)
