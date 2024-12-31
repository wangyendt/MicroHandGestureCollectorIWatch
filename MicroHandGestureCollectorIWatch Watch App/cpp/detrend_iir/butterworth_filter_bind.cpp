#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include "butterworth_filter.hpp"

namespace py = pybind11;

PYBIND11_MODULE(butterworth_filter, m) {
    m.doc() = "Butterworth filter implementation"; // 可选的模块文档字符串

    py::class_<ButterworthFilter>(m, "ButterworthFilter")
        .def(py::init<const std::vector<double>&, const std::vector<double>&>())
        .def("filter", &ButterworthFilter::filter)
        .def("detrend", &ButterworthFilter::detrend);
} 