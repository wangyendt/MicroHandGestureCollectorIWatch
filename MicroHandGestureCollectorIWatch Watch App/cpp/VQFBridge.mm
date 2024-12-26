#import "VQFBridge.h"
#import "vqf.hpp"

@implementation VQFBridge {
    VQF *vqf;
}

- (instancetype)initWithGyrTs:(double)gyrTs accTs:(double)accTs {
    self = [super init];
    if (self) {
        vqf = new VQF(gyrTs, accTs);
    }
    return self;
}

- (void)dealloc {
    delete vqf;
}

- (void)updateGyr:(double)dt gyr:(double *)gyr {
    vqf->updateGyr(dt, gyr);
}

- (void)updateAcc:(double)dt acc:(double *)acc {
    vqf->updateAcc(dt, acc);
}

- (void)getQuat6D:(double *)quat {
    vqf->getQuat6D(quat);
}

@end