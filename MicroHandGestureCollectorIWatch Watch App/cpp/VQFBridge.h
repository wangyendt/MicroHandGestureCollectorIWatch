#import <Foundation/Foundation.h>

@interface VQFBridge : NSObject

- (instancetype)initWithGyrTs:(double)gyrTs accTs:(double)accTs;
- (void)updateGyr:(double)dt gyr:(double *)gyr;
- (void)updateAcc:(double)dt acc:(double *)acc;
- (void)getQuat6D:(double *)quat;

@end