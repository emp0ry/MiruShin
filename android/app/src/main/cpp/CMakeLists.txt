cmake_minimum_required(VERSION 3.22.1)
project(mirushin_seek_thumbnail LANGUAGES CXX)

get_filename_component(MIRUSHIN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)

add_library(mirushin_seek_thumbnail SHARED
  "${MIRUSHIN_ROOT}/native/seek_thumbnail_decoder/seek_thumbnail_decoder.cpp")
target_compile_features(mirushin_seek_thumbnail PUBLIC cxx_std_17)
target_compile_options(mirushin_seek_thumbnail PRIVATE
  -Wall -Werror -fvisibility=hidden)
target_include_directories(mirushin_seek_thumbnail PRIVATE
  "${MIRUSHIN_ROOT}/native/seek_thumbnail_decoder"
  "${MIRUSHIN_ROOT}/third_party/ffmpeg_headers")
target_link_libraries(mirushin_seek_thumbnail PRIVATE dl log)

if(ANDROID_ABI MATCHES "64")
  target_link_options(mirushin_seek_thumbnail PRIVATE -Wl,-z,max-page-size=16384)
endif()
