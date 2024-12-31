#ifndef BUTTERWORTH_FILTER_HPP
#define BUTTERWORTH_FILTER_HPP

#include <vector>
#include <cmath>
#include <algorithm>

class ButterworthFilter {
public:
    ButterworthFilter(const std::vector<double>& b, const std::vector<double>& a);
    std::vector<double> filter(const std::vector<double>& x);
    std::vector<double> detrend(const std::vector<double>& x);

private:
    std::vector<double> b;
    std::vector<double> a;
    
    std::pair<int, std::vector<double>> validatePad(const std::vector<double>& x);
    std::vector<double> lfilterZi();
    std::pair<std::vector<double>, std::vector<double>> lfilter(
        const std::vector<double>& x, 
        const std::vector<double>& zi
    );
};

#endif 