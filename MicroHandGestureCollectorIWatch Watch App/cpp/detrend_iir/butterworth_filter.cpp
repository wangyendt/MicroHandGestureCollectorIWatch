#include "butterworth_filter.hpp"

ButterworthFilter::ButterworthFilter(const std::vector<double>& b, const std::vector<double>& a) 
    : b(b), a(a) {}

std::vector<double> ButterworthFilter::detrend(const std::vector<double>& x) {
    int n = x.size();
    if (n <= 1) return x;

    // 计算x的索引
    std::vector<double> x_idx(n);
    for (int i = 0; i < n; i++) {
        x_idx[i] = static_cast<double>(i);
    }

    // 计算均值
    double mean_x = 0.0, mean_y = 0.0;
    for (int i = 0; i < n; i++) {
        mean_x += x_idx[i];
        mean_y += x[i];
    }
    mean_x /= n;
    mean_y /= n;

    // 计算斜率
    double numerator = 0.0, denominator = 0.0;
    for (int i = 0; i < n; i++) {
        double dx = x_idx[i] - mean_x;
        double dy = x[i] - mean_y;
        numerator += dx * dy;
        denominator += dx * dx;
    }

    double slope = (denominator != 0.0) ? numerator / denominator : 0.0;

    // 移除趋势
    std::vector<double> detrended(n);
    for (int i = 0; i < n; i++) {
        detrended[i] = x[i] - (slope * x_idx[i] + (mean_y - slope * mean_x));
    }

    return detrended;
}

std::pair<int, std::vector<double>> ButterworthFilter::validatePad(const std::vector<double>& x) {
    int ntaps = std::max(a.size(), b.size());
    int edge = ntaps * 3;

    std::vector<double> ext(x.size() + 2 * edge, 0.0);
    
    // 复制主信号
    for (size_t i = 0; i < x.size(); i++) {
        ext[i + edge] = x[i];
    }

    // 奇对称扩展边界
    for (int i = 0; i < edge; i++) {
        ext[i] = 2 * x[0] - x[edge - i - 1];
        ext[ext.size() - 1 - i] = 2 * x[x.size() - 1] - x[x.size() - 2 - i];
    }

    return {edge, ext};
}

std::vector<double> ButterworthFilter::lfilterZi() {
    int n = std::max(a.size(), b.size()) - 1;
    std::vector<double> zi(n, 0.0);

    double sum_b = 0.0, sum_a = 0.0;
    for (const auto& val : b) sum_b += val;
    for (const auto& val : a) sum_a += val;

    if (std::abs(sum_a) > 1e-6) {
        double gain = sum_b / sum_a;
        std::fill(zi.begin(), zi.end(), gain);
    }

    return zi;
}

std::pair<std::vector<double>, std::vector<double>> ButterworthFilter::lfilter(
    const std::vector<double>& x, 
    const std::vector<double>& zi
) {
    int n = x.size();
    std::vector<double> y(n, 0.0);
    std::vector<double> z = zi;

    for (int i = 0; i < n; i++) {
        y[i] = b[0] * x[i] + z[0];
        
        for (size_t j = 1; j < a.size(); j++) {
            z[j-1] = b[j] * x[i] - a[j] * y[i] + (j < z.size() ? z[j] : 0.0);
        }
    }

    return {y, z};
}

std::vector<double> ButterworthFilter::filter(const std::vector<double>& x) {
    // 去除信号趋势
    auto detrended = detrend(x);

    // 计算边界扩展
    auto [edge, ext] = validatePad(detrended);

    // 计算初始状态
    auto zi = lfilterZi();

    // 正向滤波
    double x0 = ext[0];
    auto [y, _] = lfilter(ext, std::vector<double>(zi.begin(), zi.end()));
    for (auto& val : zi) val *= x0;

    // 反向滤波
    double y0 = y[y.size() - 1];
    std::reverse(y.begin(), y.end());
    auto [y_rev, __] = lfilter(y, std::vector<double>(zi.begin(), zi.end()));
    for (auto& val : zi) val *= y0;
    std::reverse(y_rev.begin(), y_rev.end());

    // 提取有效部分
    std::vector<double> result(y_rev.begin() + edge, y_rev.end() - edge);
    return result;
}