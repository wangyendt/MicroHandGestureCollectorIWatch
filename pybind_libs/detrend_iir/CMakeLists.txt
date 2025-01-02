cmake_minimum_required(VERSION 3.4)
project(butterworth_filter)

if(WIN32)
   # Python 配置
   set(PYTHON_ENV_PATH "D:/ProgramData/Anaconda3/envs/wayne")
   set(Python_EXECUTABLE "${PYTHON_ENV_PATH}/python.exe")
   set(Python_ROOT "${PYTHON_ENV_PATH}")
   set(Python_INCLUDE_DIR "${PYTHON_ENV_PATH}/include")
   set(Python_LIBRARY "${PYTHON_ENV_PATH}/libs/python39.lib")
   set(Python_LIBRARIES "${PYTHON_ENV_PATH}/libs/python39.lib")
   set(Python_Development_FOUND TRUE)
   set(Python_Development.Module_FOUND TRUE)
   set(Python_Development.Embed_FOUND TRUE)
   
   # VCPKG 配置
   set(VCPKG_PATH "$ENV{VCPKG_ROOT}")
   set(pybind11_DIR "${VCPKG_PATH}/installed/x64-windows/share/pybind11")
else()
   # Mac/Linux Python 检测
   execute_process(
       COMMAND which python3
       OUTPUT_VARIABLE DETECTED_PYTHON
       OUTPUT_STRIP_TRAILING_WHITESPACE
   )
   set(Python_EXECUTABLE "${DETECTED_PYTHON}")
   
   # 获取Python信息
   execute_process(
       COMMAND ${Python_EXECUTABLE} -c "import sys; print(sys.prefix)"
       OUTPUT_VARIABLE Python_ROOT_DIR
       OUTPUT_STRIP_TRAILING_WHITESPACE
   )
   
   execute_process(
       COMMAND ${Python_EXECUTABLE} -c "import sys; print(sys.version_info[0]); print(sys.version_info[1])"
       OUTPUT_VARIABLE PYTHON_VERSION_INFO
       OUTPUT_STRIP_TRAILING_WHITESPACE
   )
   string(REPLACE "\n" ";" PYTHON_VERSION_LIST ${PYTHON_VERSION_INFO})
   list(GET PYTHON_VERSION_LIST 0 PYTHON_VERSION_MAJOR)
   list(GET PYTHON_VERSION_LIST 1 PYTHON_VERSION_MINOR)
   
   # 设置Mac/Linux的Python路径
   set(Python_INCLUDE_DIRS "${Python_ROOT_DIR}/include/python${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}")
   set(Python_LIBRARIES "${Python_ROOT_DIR}/lib/libpython${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}.dylib")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置包含目录
include_directories("${CMAKE_CURRENT_SOURCE_DIR}/../../MicroHandGestureCollectorIWatch Watch App/cpp/detrend_iir")

# 设置Python搜索路径
if(WIN32)
   set(CMAKE_PREFIX_PATH ${Python_ROOT} ${CMAKE_PREFIX_PATH})
else() 
   set(CMAKE_PREFIX_PATH ${Python_ROOT_DIR} ${CMAKE_PREFIX_PATH})
endif()

# 查找依赖包
find_package(Python COMPONENTS Interpreter Development REQUIRED)
find_package(pybind11 CONFIG REQUIRED)

# 添加源文件
set(SOURCES
   "${CMAKE_CURRENT_SOURCE_DIR}/../../MicroHandGestureCollectorIWatch Watch App/cpp/detrend_iir/butterworth_filter.cpp"
   "${CMAKE_CURRENT_SOURCE_DIR}/butterworth_filter_bind.cpp"
)

# 创建Python模块
pybind11_add_module(butterworth_filter ${SOURCES})

# 设置输出目录
set_target_properties(butterworth_filter PROPERTIES
   LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

# 打印调试信息
if(WIN32)
   message(STATUS "Python Root: ${Python_ROOT}")
else()
   message(STATUS "Python Root: ${Python_ROOT_DIR}")
endif()
message(STATUS "Python Executable: ${Python_EXECUTABLE}")
message(STATUS "Python Include Dirs: ${Python_INCLUDE_DIRS}")
message(STATUS "Python Libraries: ${Python_LIBRARIES}")
if(NOT WIN32)
   message(STATUS "Python version: ${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}")
endif()
