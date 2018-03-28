#import "FFFastImageViewManager.h"
#import "FFFastImageView.h"

#import <SDWebImage/SDWebImagePrefetcher.h>

@implementation FFFastImageViewManager

RCT_EXPORT_MODULE(FastImageView)

- (FFFastImageView*)view {
  FFFastImageView* view = [[FFFastImageView alloc] init];
  view.contentMode = (UIViewContentMode) RCTResizeModeContain;
  view.clipsToBounds = YES;
  return view;
}

RCT_EXPORT_VIEW_PROPERTY(source, FFFastImageSource)
RCT_EXPORT_VIEW_PROPERTY(resizeMode, RCTResizeMode)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoadStart, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageProgress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoad, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoadEnd, RCTDirectEventBlock)

RCT_EXPORT_METHOD(preload:(nonnull NSArray<FFFastImageSource *> *)sources)
{
    NSMutableArray *urls = [NSMutableArray arrayWithCapacity:sources.count];

    [sources enumerateObjectsUsingBlock:^(FFFastImageSource * _Nonnull source, NSUInteger idx, BOOL * _Nonnull stop) {
        [source.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString* header, BOOL *stop) {
            [[SDWebImageDownloader sharedDownloader] setValue:header forHTTPHeaderField:key];
        }];
        [urls setObject:source.uri atIndexedSubscript:idx];
    }];

    [[SDWebImagePrefetcher sharedImagePrefetcher] prefetchURLs:urls];
}



- (void)_initializeDownloadOperationQueueList {
    
    if( self.downloadOperationQueueList == nil ){
        self.downloadOperationQueueList = [NSMutableDictionary new];
    }
}

- (void)_initializeDedicatedDownloadManager {
    
    if( self.dedicatedManager == nil ){
        
        SDImageCache * cache = [SDImageCache new];
        
        [[cache config] setMaxCacheAge:NSIntegerMax];
        [[cache config] setMaxCacheSize:0];
        [[cache config] setShouldCacheImagesInMemory:YES];
        [[cache config] setShouldDecompressImages:YES]; //TODO: Try with NO for less memory usage.
        
        SDWebImageDownloader * downloader = [SDWebImageDownloader new];
        
        [downloader setMaxConcurrentDownloads:2];

        self.dedicatedManager = [[SDWebImageManager alloc] initWithCache:cache downloader:downloader];

    }
}

-(SDWebImageOptions)_dedicatedDownloadOptions {
    
    SDWebImageOptions options = 0;
    options |= SDWebImageRetryFailed;
    options |= SDWebImageHighPriority;
    options |= SDWebImageContinueInBackground;
    
    return options;
    
}


RCT_EXPORT_METHOD(setPrimaryDownloadQueue:(NSString *)queueName
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject ) {
    
    if( self.primaryQueueName == queueName ){
        resolve(@YES);
        return;
    }
    
    [self _initializeDownloadOperationQueueList];
    
    if( self.downloadOperationQueueList[queueName] == nil ){
        reject( @"unknown_queue", nil, RCTErrorWithMessage([NSString stringWithFormat:@"Could not find a queue named: %@", queueName]) );
        return;
    }
    
    // change priority of current primary queue
    if( self.downloadOperationQueueList[queueName] != nil ){
        [self.downloadOperationQueueList[queueName] setQualityOfService:NSQualityOfServiceBackground];
    }
    
    [self _pauseAllDownloadOperationQueues];
    
    self.primaryQueueName = queueName;
    
    [self.downloadOperationQueueList[queueName] setSuspended:NO];
    
    resolve(@YES);

}


-(void) _pauseAllDownloadOperationQueues {
    
    [self _initializeDownloadOperationQueueList];
    
    for( NSString * queueName in self.downloadOperationQueueList ){
        
        [self.downloadOperationQueueList[queueName] setSuspended:YES];
        
    }
    
}

static NSString *kQueueOperationsChanged = @"kQueueOperationsChanged";

-(void) _createDownloadOperationQueues:(NSArray *)queueNames {
    
    [self _initializeDownloadOperationQueueList];
    
    for( NSString * queueName in queueNames ){
        
        if( self.downloadOperationQueueList[queueName] == nil ){
            
            NSOperationQueue * queue = [NSOperationQueue new];
            
            [queue setName:queueName];
            [queue setSuspended:YES];
            [queue setQualityOfService:NSQualityOfServiceBackground];
            
            if( self.primaryQueueName == nil ){
                self.primaryQueueName = queueName;
                [queue setQualityOfService:NSQualityOfServiceUserInitiated];
            }
            
        
            [queue addObserver:self forKeyPath:@"operations" options:0 context:&kQueueOperationsChanged];
            
            self.downloadOperationQueueList[queueName] = queue;
            
        }
    }
}


-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    
    if (object && [keyPath isEqualToString:@"operations"] && context == &kQueueOperationsChanged) {
        
        NSOperationQueue * queue = (NSOperationQueue *)object;

        if( [queue.operations count] == 0 ){
            [self _queueDepleted:queue];
        }
        
    }
    
}


-(void)_queueDepleted:(NSOperationQueue *)queue {
    
    NSOperationQueue * primaryQueue = self.downloadOperationQueueList[self.primaryQueueName];
    
    if( primaryQueue == nil ){
        self.primaryQueueName = queue.name;
        self.downloadOperationQueueList[self.primaryQueueName] = queue;
        primaryQueue = queue;
    }
    
    BOOL isPrimary = [queue.name isEqualToString:self.primaryQueueName];
    BOOL primaryHasPendingTasks = [primaryQueue.operations count] > 0;
    
    
    // if a non-primary queue is depleted, pause it
    if( !isPrimary ){
    
        [queue setSuspended:YES];
    
    // If the primary queue is depleted, resume all other queues with pending tasks
    } else {
        
        for( NSString * queueName in self.downloadOperationQueueList ){
            
            if( [self.downloadOperationQueueList[queueName].operations count] > 0 ){
                [self.downloadOperationQueueList[queueName] setSuspended:NO];
            }
            
        }
        
    }

}


RCT_EXPORT_METHOD(preDownload:(nonnull NSArray<FFFastImageSource *> *)sources
                  usingQueueName:(nonnull NSString *)queueName
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject ) {
    
    [self _initializeDedicatedDownloadManager];
    
    [self _initializeDownloadOperationQueueList];
    
    if( self.downloadOperationQueueList[queueName] == nil ){
        reject( @"unknown_queue", nil, RCTErrorWithMessage([NSString stringWithFormat:@"Could not find a queue named: %@", queueName]) );
        return;
    }
    
    NSOperationQueue * queue = self.downloadOperationQueueList[queueName];
    
    if( [queueName isEqualToString:self.primaryQueueName] ){
        [self _pauseAllDownloadOperationQueues];
        [self.downloadOperationQueueList[queueName] setSuspended:NO];
    }
    
    for( FFFastImageSource * source in sources ){
        
        for( NSString * header in source.headers ){
            [self.dedicatedManager.imageDownloader setValue:source.headers[header] forHTTPHeaderField:header];
        }
        
        BOOL queueIsRunning = !queue.suspended;
        NSUInteger pendingTasks = queue.operations.count;
        
        NSURL * url = source.uri;
        
        [self.dedicatedManager cachedImageExistsForURL:url completion:^(BOOL isInCache) {

            if( isInCache ){
                return;
            }
            
            [queue addOperationWithBlock:^{

                dispatch_semaphore_t barrier = dispatch_semaphore_create(0);
                
                @autoreleasepool {
                    [self.dedicatedManager loadImageWithURL:url options:[self _dedicatedDownloadOptions] progress:nil completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                        
                        if (!finished) return;
                        
                        if (!image) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                NSLog(@"Prefetch Download Failed!");
                            });
                        }
                        
                        dispatch_semaphore_signal(barrier);
                        
                    }];
                }
                
                dispatch_semaphore_wait(barrier, DISPATCH_TIME_FOREVER);

            }];
            
        }];

    }
    

    resolve(@YES);
    
    
}






















RCT_EXPORT_METHOD(prefetch:(nonnull NSArray<FFFastImageSource *> *)sources
                  downloadOnly:(BOOL)downloadOnly
                  immediate:(BOOL)immediate )
{

    SDImageCache * cache = nil;
    SDWebImageDownloader * downloader = nil;
    SDWebImageManager * manager = nil;
    SDWebImagePrefetcher * prefetcher = nil;
    
    dispatch_queue_t dispatchQueue = nil;
    
    if( immediate ){
        
        if( _prefetchImmediateQueue == nil ){
            _prefetchImmediateQueue = dispatch_queue_create("fffastImageImmediatePrefetcherQueue", DISPATCH_QUEUE_CONCURRENT);
        }
        
        dispatchQueue = _prefetchImmediateQueue;
        
        cache = [SDImageCache new];
        downloader = [SDWebImageDownloader new];
        manager = [[SDWebImageManager alloc] initWithCache:cache downloader:downloader];
        prefetcher = [[SDWebImagePrefetcher alloc] initWithImageManager:manager];
        
    } else {
        
        if( _prefetchQueue == nil ){
            _prefetchQueue = dispatch_queue_create("fffastImagePrefetcherQueue", DISPATCH_QUEUE_SERIAL);
        }
        
        dispatchQueue = _prefetchQueue;
        
        cache = [SDImageCache sharedImageCache];
        downloader = [SDWebImageDownloader sharedDownloader];
        manager = [SDWebImageManager sharedManager];
        prefetcher = [SDWebImagePrefetcher sharedImagePrefetcher];
        
    }

    
    dispatch_async(dispatchQueue, ^{
        
        dispatch_semaphore_t barrier = dispatch_semaphore_create(0);
        
        NSMutableArray *urls = [NSMutableArray arrayWithCapacity:sources.count];
        
        @autoreleasepool {
            
            // skip pre-loading sources to memory. Just download them.
            if( downloadOnly ){
                [[cache config] setShouldCacheImagesInMemory:NO];
            }
            
            [sources enumerateObjectsUsingBlock:^(FFFastImageSource * _Nonnull source, NSUInteger idx, BOOL * _Nonnull stop) {
                [source.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString* header, BOOL *stop) {
                    [downloader setValue:header forHTTPHeaderField:key];
                }];
                [urls setObject:source.uri atIndexedSubscript:idx];
            }];
            
            [prefetcher prefetchURLs:urls
                progress:^(NSUInteger noOfFinishedUrls, NSUInteger noOfTotalUrls) {
                    NSLog( @"Progress: %tu/%tu", noOfFinishedUrls, noOfTotalUrls );
                }
                completed:^(NSUInteger noOfFinishedUrls, NSUInteger noOfSkippedUrls) {
                    if( !immediate ){
                        dispatch_semaphore_signal(barrier);
                    }
                }
            ];
            
            if( !immediate ){
                dispatch_semaphore_wait(barrier, DISPATCH_TIME_FOREVER);
            }
        }
        
        
    });
    

}


RCT_EXPORT_METHOD(clearMemoryCache)
{
    [[SDImageCache sharedImageCache] clearMemory];
}




RCT_EXPORT_METHOD(configure:(nonnull NSDictionary *)settings){

    for( NSString * key in settings ){

        NSString * value = settings[key];
        
        if( [key isEqualToString:@"maxCacheAge"] ){
            
            if( [value isEqualToString:@"0"] ){
                [[[SDImageCache sharedImageCache] config] setMaxCacheAge:NSIntegerMax];
            } else {
                [[[SDImageCache sharedImageCache] config] setMaxCacheAge:[value integerValue]];
            }
            
        } else if( [key isEqualToString:@"shouldDecompressImages"] ) {
            
            [[[SDImageCache sharedImageCache] config] setShouldDecompressImages:[value boolValue]];
            
        } else if( [key isEqualToString:@"shouldDisableiCloud"] ) {
            
            [[[SDImageCache sharedImageCache] config] setShouldDisableiCloud:[value boolValue]];
            
        } else if( [key isEqualToString:@"shouldCacheImagesInMemory"] ) {
            
            [[[SDImageCache sharedImageCache] config] setShouldCacheImagesInMemory:[value boolValue]];
            
        } else if( [key isEqualToString:@"maxCacheSize"] ) {
            
            [[[SDImageCache sharedImageCache] config] setMaxCacheSize:[value integerValue]];
            
        } else if( [key isEqualToString:@"prefetcherMaxConcurrentDownloads"] ) {
            
            [[SDWebImagePrefetcher sharedImagePrefetcher] setMaxConcurrentDownloads:[value integerValue]];
            
        } else if( [key isEqualToString:@"maxMemoryCost"] ) {
            
            [[SDImageCache sharedImageCache] setMaxMemoryCost:[value integerValue]];
            
        } else if( [key isEqualToString:@"maxMemoryCountLimit"] ) {
            
            [[SDImageCache sharedImageCache] setMaxMemoryCountLimit:[value integerValue]];
            
        } else if( [key isEqualToString:@"downloadQueues"] ) {
            
            NSArray * queues = [value componentsSeparatedByString:@","];
            
            [self _createDownloadOperationQueues: queues];
            
        }

    }
    
}


@end

