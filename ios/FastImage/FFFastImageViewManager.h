#import <React/RCTViewManager.h>

@interface FFFastImageViewManager : RCTViewManager
    @property (nonatomic, strong) dispatch_queue_t prefetchQueue;
@end
