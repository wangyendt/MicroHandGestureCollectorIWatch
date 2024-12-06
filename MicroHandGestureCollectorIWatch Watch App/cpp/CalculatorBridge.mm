#import "CalculatorBridge.h"
#import "Calculator.hpp"

@implementation CalculatorBridge

- (int)sum:(int)a with:(int)b {
    Calculator calc;
    return calc.sum(a, b);
}

@end 