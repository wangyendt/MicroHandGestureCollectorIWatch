cmake_minimum_required(VERSION 3.4)
project(butterworth_filter)

# 设置C++标准为17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置包含目录
include_directories(
    "${CMAKE_CURRENT_SOURCE_DIR}/../../MicroHandGestureCollectorIWatch Watch App/cpp/detrend_iir"
)

# 方案1: 允许通过命令行参数指定Python路径
if(DEFINED PYTHON_EXECUTABLE)
    set(Python_EXECUTABLE "${PYTHON_EXECUTABLE}")
    message(STATUS "Using Python executable from command line: ${Python_EXECUTABLE}")
else()
    # 方案2: 自动检测当前环境的Python
    execute_process(
        COMMAND which python3
        OUTPUT_VARIABLE DETECTED_PYTHON
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    set(Python_EXECUTABLE "${DETECTED_PYTHON}")
    message(STATUS "Detected Python executable: ${Python_EXECUTABLE}")
endif()

# 获取Python相关路径信息
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

# 设置Python路径
set(Python_INCLUDE_DIRS "${Python_ROOT_DIR}/include/python${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}")
set(Python_LIBRARIES "${Python_ROOT_DIR}/lib/libpython${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}.dylib")

# 设置Python开发包搜索路径
set(CMAKE_PREFIX_PATH ${Python_ROOT_DIR} ${CMAKE_PREFIX_PATH})

# 查找Python和pybind11
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

# 打印Python相关信息（用于调试）
message(STATUS "Python_ROOT_DIR: ${Python_ROOT_DIR}")
message(STATUS "Python_EXECUTABLE: ${Python_EXECUTABLE}")
message(STATUS "Python_INCLUDE_DIRS: ${Python_INCLUDE_DIRS}")
message(STATUS "Python_LIBRARIES: ${Python_LIBRARIES}")
message(STATUS "Python version: ${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}")