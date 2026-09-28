#import "PlayniteReadinessMonitor.h"

#import <CommonCrypto/CommonHMAC.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

#include <stdlib.h>
#include <string.h>

#import "Logger.h"
#import "ReadinessFrameMatcher.h"
#import "StreamView.h"
#import "Utils.h"

static const NSUInteger PlayniteReadinessPort = 48591;
static const NSUInteger PlayniteMaximumResponseBytes = 65536;
static const NSUInteger PlayniteRequiredFrameMatches = 2;
static const NSTimeInterval PlaynitePollInterval = 0.7;
static const NSTimeInterval PlayniteRequestTimeout = 1.2;

static NSString *PlayniteHexString(const uint8_t *bytes, NSUInteger length) {
    static const char digits[] = "0123456789abcdef";
    char output[128];
    if (length * 2 >= sizeof(output)) {
        return nil;
    }
    for (NSUInteger i = 0; i < length; i++) {
        output[i * 2] = digits[(bytes[i] >> 4) & 0x0f];
        output[i * 2 + 1] = digits[bytes[i] & 0x0f];
    }
    output[length * 2] = '\0';
    return [NSString stringWithUTF8String:output];
}

static NSData *PlayniteDataFromHex(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length != CC_SHA256_DIGEST_LENGTH * 2) {
        return nil;
    }
    uint8_t bytes[CC_SHA256_DIGEST_LENGTH];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        unichar high = [value characterAtIndex:i * 2];
        unichar low = [value characterAtIndex:i * 2 + 1];
        int highValue = high >= '0' && high <= '9' ? high - '0' :
                        high >= 'a' && high <= 'f' ? high - 'a' + 10 : -1;
        int lowValue = low >= '0' && low <= '9' ? low - '0' :
                       low >= 'a' && low <= 'f' ? low - 'a' + 10 : -1;
        if (highValue < 0 || lowValue < 0) {
            return nil;
        }
        bytes[i] = (uint8_t)((highValue << 4) | lowValue);
    }
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

static BOOL PlayniteConstantTimeEqual(NSData *left, NSData *right) {
    if (left.length != right.length) {
        return NO;
    }
    const uint8_t *a = left.bytes;
    const uint8_t *b = right.bytes;
    uint8_t difference = 0;
    for (NSUInteger i = 0; i < left.length; i++) {
        difference |= a[i] ^ b[i];
    }
    return difference == 0;
}

static NSData *PlayniteRGBAFromCGImage(CGImageRef image) {
    if (image == NULL || CGImageGetWidth(image) != READINESS_FRAME_WIDTH ||
        CGImageGetHeight(image) != READINESS_FRAME_HEIGHT) {
        return nil;
    }

    NSMutableData *pixels = [NSMutableData dataWithLength:
        READINESS_FRAME_WIDTH * READINESS_FRAME_HEIGHT * READINESS_FRAME_BYTES_PER_PIXEL];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes,
                                                 READINESS_FRAME_WIDTH,
                                                 READINESS_FRAME_HEIGHT,
                                                 8,
                                                 READINESS_FRAME_WIDTH * READINESS_FRAME_BYTES_PER_PIXEL,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        return nil;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextDrawImage(context, CGRectMake(0, 0, READINESS_FRAME_WIDTH, READINESS_FRAME_HEIGHT), image);
    CGContextRelease(context);
    return pixels;
}

@interface PlayniteReadinessMonitor ()
@property(atomic, getter=isStopped) BOOL stopped;
@property(nonatomic, copy) dispatch_block_t readinessConfirmed;
@end

@implementation PlayniteReadinessMonitor {
    NSString *_hostAddress;
    NSString *_sharedKey;
    NSData *_sharedKeyData;
    NSString *_sessionId;
    StreamView *_streamView;
    dispatch_queue_t _stateQueue;
    NSURLSession *_session;
    NSUInteger _consecutiveMatches;
    NSUInteger _requestCount;
    NSTimeInterval _requestStartedAt;
    NSString *_lastError;
    BOOL _started;
}

- (instancetype)initWithHostAddress:(NSString *)hostAddress
                         sharedKey:(NSString *)sharedKey
                         streamView:(StreamView *)streamView
             readinessConfirmed:(dispatch_block_t)readinessConfirmed {
    self = [super init];
    if (self) {
        _hostAddress = [hostAddress copy];
        _sharedKey = [sharedKey copy];
        _sharedKeyData = [_sharedKey dataUsingEncoding:NSUTF8StringEncoding];
        _streamView = streamView;
        self.readinessConfirmed = readinessConfirmed;
        _stateQueue = dispatch_queue_create("org.moonlight.playnite-readiness", DISPATCH_QUEUE_SERIAL);

        uint8_t nonce[16];
        arc4random_buf(nonce, sizeof(nonce));
        _sessionId = PlayniteHexString(nonce, sizeof(nonce));
    }
    return self;
}

- (NSURL *)readinessURL {
    NSString *address = [Utils addressPortStringToAddress:_hostAddress];
    if (address.length == 0) {
        return nil;
    }

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"http";
    components.host = address;
    components.port = @(PlayniteReadinessPort);
    components.path = @"/moonlight/ready";
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"session" value:_sessionId]];
    return components.URL;
}

- (NSData *)signatureForUTF8String:(NSString *)string {
    NSData *message = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (_sharedKeyData.length == 0 || message == nil) {
        return nil;
    }
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256,
           _sharedKeyData.bytes,
           _sharedKeyData.length,
           message.bytes,
           message.length,
           digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

- (void)start {
    if (self.isStopped) {
        return;
    }
    dispatch_async(_stateQueue, ^{
        if (self.isStopped || self->_started) {
            return;
        }
        self->_started = YES;
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.URLCache = nil;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.timeoutIntervalForRequest = PlayniteRequestTimeout;
        configuration.timeoutIntervalForResource = PlayniteRequestTimeout;
        self->_session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        Log(LOG_I, @"Playnite Ready Bridge monitor started for this launch session");
#if DEBUG
        NSLog(@"[PlayniteDiag] Ready Bridge monitor active: sharedKeyPresent=%@ sharedKeyLength=%lu uptime=%.3f",
              self->_sharedKey.length >= 16 ? @"yes" : @"no",
              (unsigned long)self->_sharedKey.length,
              [NSProcessInfo processInfo].systemUptime);
#endif
        [self poll];
    });
}

- (void)poll {
    if (self.isStopped) {
        return;
    }
    if (_hostAddress.length == 0 || _sharedKey.length < 16 || _sessionId.length != 32) {
        [self recordError:@"Monitor needs a host address and a shared key of at least 16 characters"];
        [self scheduleNextPoll];
        return;
    }

    NSURL *url = [self readinessURL];
    if (url == nil) {
        [self recordError:@"Could not create the Playnite readiness URL"];
        [self scheduleNextPoll];
        return;
    }

    NSString *requestText = [NSString stringWithFormat:@"GET\n/moonlight/ready\n%@", _sessionId];
    NSData *requestSignature = [self signatureForUTF8String:requestText];
    NSString *requestSignatureHex = PlayniteHexString(requestSignature.bytes, requestSignature.length);
    if (requestSignatureHex == nil) {
        [self recordError:@"Could not sign the Playnite readiness request"];
        [self scheduleNextPoll];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:PlayniteRequestTimeout];
    request.HTTPMethod = @"GET";
    request.HTTPShouldHandleCookies = NO;
    [request setValue:requestSignatureHex forHTTPHeaderField:@"X-Moonlight-Auth"];

    _requestCount++;
    _requestStartedAt = [NSProcessInfo processInfo].systemUptime;
#if DEBUG
    NSLog(@"[PlayniteDiag] HMAC request generated: request=%lu keyLength=%lu uptime=%.3f",
          (unsigned long)_requestCount,
          (unsigned long)_sharedKey.length,
          _requestStartedAt);
#endif

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        PlayniteReadinessMonitor *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        dispatch_async(strongSelf->_stateQueue, ^{
            [strongSelf processResponseData:data response:response error:error];
        });
    }];
    [task resume];
}

- (void)processResponseData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    if (self.isStopped) {
        return;
    }
#if DEBUG
    NSInteger httpStatus = [response isKindOfClass:NSHTTPURLResponse.class] ?
        ((NSHTTPURLResponse *)response).statusCode : 0;
    NSLog(@"[PlayniteDiag] Ready Bridge response: elapsed=%.3fs http=%ld bytes=%lu errorCode=%ld uptime=%.3f",
          _requestStartedAt > 0 ? [NSProcessInfo processInfo].systemUptime - _requestStartedAt : -1.0,
          (long)httpStatus,
          (unsigned long)data.length,
          (long)error.code,
          [NSProcessInfo processInfo].systemUptime);
#endif
    if (error != nil) {
        _consecutiveMatches = 0;
        [self recordError:error.localizedDescription ?: @"Playnite readiness request failed"];
        [self scheduleNextPoll];
        return;
    }
    if (![response isKindOfClass:NSHTTPURLResponse.class] ||
        ((NSHTTPURLResponse *)response).statusCode != 200 || data.length == 0 ||
        data.length > PlayniteMaximumResponseBytes) {
        _consecutiveMatches = 0;
        [self recordError:@"Playnite readiness server returned an invalid HTTP response"];
        [self scheduleNextPoll];
        return;
    }

    NSError *jsonError = nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![decoded isKindOfClass:NSDictionary.class]) {
        _consecutiveMatches = 0;
        [self recordError:jsonError.localizedDescription ?: @"Playnite readiness response was not JSON"];
        [self scheduleNextPoll];
        return;
    }

    NSDictionary *json = (NSDictionary *)decoded;
    NSString *responseSession = json[@"session"];
    NSString *state = json[@"state"];
    NSString *frameBase64 = json[@"framePngBase64"];
    NSString *signatureHex = json[@"hmacSha256"];
    if (![responseSession isKindOfClass:NSString.class] ||
        ![state isKindOfClass:NSString.class] ||
        ![frameBase64 isKindOfClass:NSString.class] ||
        ![signatureHex isKindOfClass:NSString.class] ||
        ![_sessionId isEqualToString:responseSession] ||
        !([state isEqualToString:@"waiting"] || [state isEqualToString:@"ready"])) {
        _consecutiveMatches = 0;
        [self recordError:@"Playnite readiness response had invalid fields or session ID"];
        [self scheduleNextPoll];
        return;
    }

    NSString *responseText = [NSString stringWithFormat:@"%@\n%@\n%@", responseSession, state, frameBase64];
    NSData *expectedSignature = [self signatureForUTF8String:responseText];
    NSData *receivedSignature = PlayniteDataFromHex(signatureHex);
    if (expectedSignature == nil || receivedSignature == nil ||
        !PlayniteConstantTimeEqual(expectedSignature, receivedSignature)) {
        _consecutiveMatches = 0;
        [self recordError:@"Playnite readiness response authentication failed"];
        [self scheduleNextPoll];
        return;
    }

    _lastError = nil;
#if DEBUG
    NSLog(@"[PlayniteDiag] Ready Bridge response authenticated: state=%@ frameBase64Length=%lu",
          state,
          (unsigned long)frameBase64.length);
#endif
    if ([state isEqualToString:@"waiting"] || frameBase64.length == 0) {
        _consecutiveMatches = 0;
        [self scheduleNextPoll];
        return;
    }

    NSData *pngData = [[NSData alloc] initWithBase64EncodedString:frameBase64 options:0];
    static const uint8_t pngSignature[] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    if (pngData.length < sizeof(pngSignature) || memcmp(pngData.bytes, pngSignature, sizeof(pngSignature)) != 0) {
        _consecutiveMatches = 0;
        [self recordError:@"Playnite readiness frame was not a PNG"];
        [self scheduleNextPoll];
        return;
    }

    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)pngData, NULL);
    CGImageRef referenceImage = imageSource == NULL ? NULL : CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    if (referenceImage == NULL || CGImageGetWidth(referenceImage) != READINESS_FRAME_WIDTH ||
        CGImageGetHeight(referenceImage) != READINESS_FRAME_HEIGHT) {
        if (referenceImage != NULL) {
            CGImageRelease(referenceImage);
        }
        if (imageSource != NULL) {
            CFRelease(imageSource);
        }
        _consecutiveMatches = 0;
        [self recordError:@"Playnite readiness PNG must be exactly 64 by 36 pixels"];
        [self scheduleNextPoll];
        return;
    }

    NSData *referenceRGBA = PlayniteRGBAFromCGImage(referenceImage);
    CGImageRelease(referenceImage);
    CFRelease(imageSource);
    if (referenceRGBA == nil) {
        _consecutiveMatches = 0;
        [self recordError:@"Could not read Playnite readiness frame pixels"];
        [self scheduleNextPoll];
        return;
    }

    NSTimeInterval captureQueuedAt = [NSProcessInfo processInfo].systemUptime;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isStopped) {
            return;
        }
        NSTimeInterval captureStartedAt = [NSProcessInfo processInfo].systemUptime;
        NSMutableData *streamRGBA = [NSMutableData dataWithLength:
            READINESS_FRAME_WIDTH * READINESS_FRAME_HEIGHT * READINESS_FRAME_BYTES_PER_PIXEL];
        BOOL captured = [self->_streamView copyReadinessFrameToRGBA:streamRGBA.mutableBytes
                                                            byteLength:streamRGBA.length];
        NSTimeInterval captureFinishedAt = [NSProcessInfo processInfo].systemUptime;
        BOOL matched = captured && ReadinessFrameMatcherMatches(referenceRGBA.bytes,
                                                                 streamRGBA.bytes,
                                                                 READINESS_FRAME_WIDTH,
                                                                 READINESS_FRAME_HEIGHT);
#if DEBUG
        NSLog(@"[PlayniteDiag] readiness compare: mainQueueDelay=%.3fs captureAndMatch=%.3fs captured=%@ matched=%@ uptime=%.3f",
              captureStartedAt - captureQueuedAt,
              captureFinishedAt - captureStartedAt,
              captured ? @"yes" : @"no",
              matched ? @"yes" : @"no",
              captureFinishedAt);
#endif
        dispatch_async(self->_stateQueue, ^{
            if (self.isStopped) {
                return;
            }
            if (matched) {
                self->_consecutiveMatches++;
                Log(LOG_D, @"Playnite readiness image match %lu/%lu",
                    (unsigned long)self->_consecutiveMatches,
                    (unsigned long)PlayniteRequiredFrameMatches);
                if (self->_consecutiveMatches >= PlayniteRequiredFrameMatches) {
                    self.stopped = YES;
                    [self->_session invalidateAndCancel];
                    self->_session = nil;
                    Log(LOG_I, @"Playnite Ready Bridge authenticated and stream image matched twice");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.readinessConfirmed != nil) {
                            self.readinessConfirmed();
                        }
                    });
                    return;
                }
            }
            else {
                self->_consecutiveMatches = 0;
            }
            [self scheduleNextPoll];
        });
    });
}

- (void)scheduleNextPoll {
    if (self.isStopped) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PlaynitePollInterval * NSEC_PER_SEC)),
                   _stateQueue, ^{
        if (!self.isStopped) {
            [self poll];
        }
    });
}

- (void)recordError:(NSString *)message {
    if (![message isEqualToString:_lastError]) {
        Log(LOG_W, @"Playnite readiness unavailable: %@", message);
        _lastError = [message copy];
    }
}

- (void)stop {
    if (self.isStopped) {
        return;
    }
    self.stopped = YES;
    dispatch_async(_stateQueue, ^{
        [self->_session invalidateAndCancel];
        self->_session = nil;
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    // Do not forward the per-session authenticator to a redirected origin.
    completionHandler(nil);
}

- (void)dealloc {
    [_session invalidateAndCancel];
}

@end
