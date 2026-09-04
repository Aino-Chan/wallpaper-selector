cmake_minimum_required(VERSION 3.21)
project(SteamWorkshopService LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(Qt6 REQUIRED COMPONENTS Core Qml Network DBus)
find_package(Qt6Keychain REQUIRED)

qt_standard_project_setup()

qt_add_plugin(SteamWorkshopServicePlugin
    CLASS_NAME SteamWorkshopPlugin
    plugin.cpp
    plugin.h
    SteamWorkshopService.cpp
    SteamWorkshopService.h
    SteamWorkshopSecrets.cpp
    SteamWorkshopSecrets.h
)

target_link_libraries(SteamWorkshopServicePlugin PRIVATE
    Qt6::Core
    Qt6::Qml
    Qt6::Network
    Qt6::DBus
    Qt6Keychain::Qt6Keychain
)

set_target_properties(SteamWorkshopServicePlugin PROPERTIES
    OUTPUT_NAME SteamWorkshopServicePlugin
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/SteamWorkshopService
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/SteamWorkshopService
)

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/qmldir
    ${CMAKE_BINARY_DIR}/SteamWorkshopService/qmldir
    COPYONLY
)