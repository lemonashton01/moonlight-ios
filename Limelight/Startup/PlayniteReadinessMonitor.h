#import <Foundation/Foundation.h>

@class StreamView;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PlayniteBridgeConnectionTestResult) {
    PlayniteBridgeConnectionTestSuccess,
    PlayniteBridgeConnectionTestMissingKey,
    PlayniteBridgeConnectionTestUnreachable,
    PlayniteBridgeConnectionTestAuthenticationFailed,
    PlayniteBridgeConnectionTestInvalidResponse,
};

// Implements the existing Playnite Ready Bridge v1 protocol and requires two
// successive matches against the rendered Moonlight stream before confirming readiness.
@interface PlayniteReadinessMonitor : NSObject <NSURLSessionTaskDelegate>

- (instancetype)initWithHostAddress:(NSString *)hostAddress
                         sharedKey:(NSString *)sharedKey
                         streamView:(nullable StreamView *)streamView
             readinessConfirmed:(nullable dispatch_block_t)readinessConfirmed;
+ (void)testHostAddress:(NSString *)hostAddress
              sharedKey:(NSString *)sharedKey
             completion:(void (^)(PlayniteBridgeConnectionTestResult result))completion;
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
