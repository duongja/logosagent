cmake_minimum_required(VERSION 3.14)
project(LogosAgentPlugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(OpenSSL REQUIRED)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../logos-module-builder/cmake/LogosModule.cmake")
    include("${CMAKE_CURRENT_SOURCE_DIR}/../logos-module-builder/cmake/LogosModule.cmake")
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" METADATA_JSON)
string(JSON MODULE_NAME GET ${METADATA_JSON} name)
string(JSON MODULE_VERSION GET ${METADATA_JSON} version)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/module_config.h"
    "#pragma once\n"
    "#define MODULE_NAME \"${MODULE_NAME}\"\n"
    "#define MODULE_VERSION \"${MODULE_VERSION}\"\n"
)
include_directories("${CMAKE_CURRENT_BINARY_DIR}")

set(EXTRA_SDK_SOURCES)
if(DEFINED LOGOS_CPP_SDK_ROOT)
    foreach(extra_sdk_source
        logos_registry_factory.cpp
        logos_transport_factory.cpp
        logos_types.cpp
        implementations/mock/mock_transport.cpp
        implementations/qt_local/local_transport.cpp
        implementations/qt_remote/qt_remote_registry.cpp
        implementations/qt_remote/remote_transport.cpp
    )
        if(EXISTS "${LOGOS_CPP_SDK_ROOT}/cpp/${extra_sdk_source}")
            list(APPEND EXTRA_SDK_SOURCES "${LOGOS_CPP_SDK_ROOT}/cpp/${extra_sdk_source}")
        endif()
    endforeach()
endif()

logos_module(
    NAME ${MODULE_NAME}
    SOURCES
        src/logos_agent_interface.h
        src/logos_agent_plugin.h
        src/logos_agent_plugin.cpp
        src/agent_runtime.h
        src/agent_runtime.cpp
        src/agent_state.h
        src/agent_state.cpp
        src/json_utils.h
        src/json_utils.cpp
        src/owner_message_utils.h
        src/owner_message_utils.cpp
        src/amount_utils.h
        src/amount_utils.cpp
        src/crypto_utils.h
        src/crypto_utils.cpp
        src/skill_registry.h
        src/skill_registry.cpp
        src/policy_engine.h
        src/policy_engine.cpp
        src/wallet_adapter.h
        src/wallet_adapter.cpp
        src/storage_adapter.h
        src/storage_adapter.cpp
        src/messaging_adapter.h
        src/messaging_adapter.cpp
        src/a2a_adapter.h
        src/a2a_adapter.cpp
        src/program_adapter.h
        src/program_adapter.cpp
        ${EXTRA_SDK_SOURCES}
)

target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE OpenSSL::Crypto)
