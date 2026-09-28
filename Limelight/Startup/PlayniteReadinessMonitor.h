#import <Foundation/Foundation.h>

@class StreamView;

NS_ASSUME_NONNULL_BEGIN

// Implements the existing Playnite Ready Bridge v1 protocol and requires two
// successive matches against the rendered Moonlight stream before confirming readiness.
@interface PlayniteReadinessMonitor : NSObject <NSURLSessionTaskDelegate>

- (instancetype)initWithHostAddress:(NSString *)hostAddress
                         sharedKey:(NSString *)sharedKey
                         streamView:(StreamView *)streamView
             readinessConfirmed:(dispatch_block_t)readinessConfirmed;
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
