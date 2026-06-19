cmake_minimum_required(VERSION 3.14)
project(LogosAgentTests LANGUAGES CXX)

include(LogosTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
add_compile_definitions(LOGOS_AGENT_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/..")

find_package(OpenSSL REQUIRED)

logos_test(
    NAME logos_agent_tests
    MODULE_SOURCES
        ../src/json_utils.cpp
        ../src/amount_utils.cpp
        ../src/crypto_utils.cpp
        ../src/owner_message_utils.cpp
        ../src/agent_state.cpp
        ../src/policy_engine.cpp
        ../src/skill_registry.cpp
    TEST_SOURCES
        main.cpp
        test_amount_policy.cpp
        test_crypto_utils.cpp
        test_owner_message_utils.cpp
        test_state_skills.cpp
        test_skill_contract.cpp
)

target_link_libraries(logos_agent_tests PRIVATE OpenSSL::Crypto)
