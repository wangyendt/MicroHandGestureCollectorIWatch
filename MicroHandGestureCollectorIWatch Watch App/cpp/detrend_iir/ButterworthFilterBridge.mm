#import "ButterworthFilterBridge.h"
#import "butterworth_filter.hpp"

@implementation ButterworthFilterBridge {
    ButterworthFilter *filter;
}

- (instancetype)initWithB:(NSArray<NSNumber *> *)b a:(NSArray<NSNumber *> *)a {
    self = [super init];
    if (self) {
        std::vector<double> bVec;
        std::vector<double> aVec;
        
        for (NSNumber *num in b) {
            bVec.push_back(num.doubleValue);
        }
        for (NSNumber *num in a) {
            aVec.push_back(num.doubleValue);
        }
        
        filter = new ButterworthFilter(bVec, aVec);
    }
    return self;
}

- (void)dealloc {
    delete filter;
}

- (NSArray<NSNumber *> *)filterData:(NSArray<NSNumber *> *)data {
    std::vector<double> input;
    for (NSNumber *num in data) {
        input.push_back(num.doubleValue);
    }
    
    std::vector<double> output = filter->filter(input);
    
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:output.size()];
    for (double val : output) {
        [result addObject:@(val)];
    }
    
    return result;
}

@end