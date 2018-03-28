#import <React/RCTViewManager.h>
#import <SDWebImage/SDWebImagePrefetcher.h>


@interface FFFastImageViewManager : RCTViewManager
    @property (nonatomic, strong) dispatch_queue_t prefetchQueue;
    @property (nonatomic, strong) dispatch_queue_t prefetchImmediateQueue;

    @property (atomic, strong) NSMutableDictionary<NSString *, NSOperationQueue *> * downloadOperationQueueList;
    @property (atomic, strong) NSString * primaryQueueName;
    @property (atomic, strong) SDWebImageManager * dedicatedManager;
@end
