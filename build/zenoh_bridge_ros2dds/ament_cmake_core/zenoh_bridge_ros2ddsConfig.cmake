# generated from ament/cmake/core/templates/nameConfig.cmake.in

# prevent multiple inclusion
if(_zenoh_bridge_ros2dds_CONFIG_INCLUDED)
  # ensure to keep the found flag the same
  if(NOT DEFINED zenoh_bridge_ros2dds_FOUND)
    # explicitly set it to FALSE, otherwise CMake will set it to TRUE
    set(zenoh_bridge_ros2dds_FOUND FALSE)
  elseif(NOT zenoh_bridge_ros2dds_FOUND)
    # use separate condition to avoid uninitialized variable warning
    set(zenoh_bridge_ros2dds_FOUND FALSE)
  endif()
  return()
endif()
set(_zenoh_bridge_ros2dds_CONFIG_INCLUDED TRUE)

# output package information
if(NOT zenoh_bridge_ros2dds_FIND_QUIETLY)
  message(STATUS "Found zenoh_bridge_ros2dds: 0.5.0 (${zenoh_bridge_ros2dds_DIR})")
endif()

# warn when using a deprecated package
if(NOT "" STREQUAL "")
  set(_msg "Package 'zenoh_bridge_ros2dds' is deprecated")
  # append custom deprecation text if available
  if(NOT "" STREQUAL "TRUE")
    set(_msg "${_msg} ()")
  endif()
  # optionally quiet the deprecation message
  if(NOT ${zenoh_bridge_ros2dds_DEPRECATED_QUIET})
    message(DEPRECATION "${_msg}")
  endif()
endif()

# flag package as ament-based to distinguish it after being find_package()-ed
set(zenoh_bridge_ros2dds_FOUND_AMENT_PACKAGE TRUE)

# include all config extra files
set(_extras "")
foreach(_extra ${_extras})
  include("${zenoh_bridge_ros2dds_DIR}/${_extra}")
endforeach()
