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





RCT_EXPORT_METHOD(prefetch:(nonnull NSArray<FFFastImageSource *> *)sources downloadOnly:(BOOL)downloadOnly)
{

    if( _prefetchQueue == nil ){
        _prefetchQueue = dispatch_queue_create("fffastImagePrefetcherQueue", 0);
    }
    
    dispatch_async(_prefetchQueue, ^{
        
        dispatch_semaphore_t barrier = dispatch_semaphore_create(0);
        
        NSMutableArray *urls = [NSMutableArray arrayWithCapacity:sources.count];
        
        @autoreleasepool {
            
            // skip pre-loading sources to memory. Just download them.
            if( downloadOnly ){
                [[[SDImageCache sharedImageCache] config] setShouldCacheImagesInMemory:NO];
            }
            
            
            [sources enumerateObjectsUsingBlock:^(FFFastImageSource * _Nonnull source, NSUInteger idx, BOOL * _Nonnull stop) {
                [source.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString* header, BOOL *stop) {
                    [[SDWebImageDownloader sharedDownloader] setValue:header forHTTPHeaderField:key];
                }];
                [urls setObject:source.uri atIndexedSubscript:idx];
            }];
            
            [[SDWebImagePrefetcher sharedImagePrefetcher] prefetchURLs:urls
                progress:^(NSUInteger noOfFinishedUrls, NSUInteger noOfTotalUrls) {
                    NSLog( @"Progress: %tu/%tu", noOfFinishedUrls, noOfTotalUrls );
                }
                completed:^(NSUInteger noOfFinishedUrls, NSUInteger noOfSkippedUrls) {
                    dispatch_semaphore_signal(barrier);
                }
            ];
            
            dispatch_semaphore_wait(barrier, DISPATCH_TIME_FOREVER);
        }
        
        
    });
    

}


RCT_EXPORT_METHOD(clearMemoryCache)
{
    [[SDImageCache sharedImageCache] clearMemory];
}




RCT_EXPORT_METHOD(configure:(nonnull NSDictionary *)settings)
{

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
            
        }

    }
    
}


@end

