#import <Foundation/Foundation.h>

@interface ButterworthFilterBridge : NSObject

- (instancetype)initWithB:(NSArray<NSNumber *> *)b a:(NSArray<NSNumber *> *)a;
- (NSArray<NSNumber *> *)filterData:(NSArray<NSNumber *> *)data;

@end