//
//  WBWebView.m
//  Webby
//

#import "WBWebView.h"

/// The subset of the legacy UIWebView API that Webby uses. Declared here
/// because the tvOS SDK marks the real class unavailable.
@protocol WBLegacyWebViewSurface <NSObject>
@property (nonatomic, assign, nullable) id delegate;
@property (nonatomic, readonly, strong) UIScrollView *scrollView;
@property (nonatomic, readonly, strong, nullable) NSURLRequest *request;
@property (nonatomic, readonly, getter=canGoBack) BOOL canGoBack;
@property (nonatomic, readonly, getter=canGoForward) BOOL canGoForward;
@property (nonatomic, readonly, getter=isLoading) BOOL loading;
@property (nonatomic) BOOL scalesPageToFit;
@property (nonatomic) BOOL allowsInlineMediaPlayback;
@property (nonatomic) BOOL mediaPlaybackRequiresUserAction;
@property (nonatomic) BOOL keyboardDisplayRequiresUserAction;
- (void)loadRequest:(NSURLRequest *)request;
- (void)loadHTMLString:(NSString *)string baseURL:(nullable NSURL *)baseURL;
- (void)reload;
- (void)stopLoading;
- (void)goBack;
- (void)goForward;
- (nullable NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script;
@end

static NSString *const WBEngineClassName = @"UIWebView";

@interface WBWebView ()
@property (nonatomic, strong, nullable) UIView<WBLegacyWebViewSurface> *engine;
@end

@implementation WBWebView

+ (BOOL)isEngineAvailable {
    return NSClassFromString(WBEngineClassName) != nil;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setUpEngine];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self setUpEngine];
    }
    return self;
}

- (void)dealloc {
    if ([_engine respondsToSelector:@selector(setDelegate:)]) {
        _engine.delegate = nil;
    }
    [_engine stopLoading];
}

- (void)setUpEngine {
    self.backgroundColor = UIColor.blackColor;
    self.clipsToBounds = YES;

    Class engineClass = NSClassFromString(WBEngineClassName);
    if (!engineClass) { return; }

    UIView<WBLegacyWebViewSurface> *engine = (UIView<WBLegacyWebViewSurface> *)[[engineClass alloc] initWithFrame:self.bounds];
    engine.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    engine.backgroundColor = UIColor.whiteColor;
    engine.opaque = YES;

    if ([engine respondsToSelector:@selector(setScalesPageToFit:)]) { engine.scalesPageToFit = YES; }
    if ([engine respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) { engine.allowsInlineMediaPlayback = YES; }
    if ([engine respondsToSelector:@selector(setMediaPlaybackRequiresUserAction:)]) { engine.mediaPlaybackRequiresUserAction = NO; }
    if ([engine respondsToSelector:@selector(setKeyboardDisplayRequiresUserAction:)]) { engine.keyboardDisplayRequiresUserAction = NO; }
    if ([engine respondsToSelector:@selector(setDelegate:)]) { engine.delegate = self; }

    UIScrollView *scrollView = [engine respondsToSelector:@selector(scrollView)] ? engine.scrollView : nil;
    scrollView.bounces = YES;
    scrollView.showsVerticalScrollIndicator = YES;
    scrollView.indicatorStyle = UIScrollViewIndicatorStyleDefault;
    // Webby drives scrolling itself from the Siri Remote, so the engine never takes input directly.
    engine.userInteractionEnabled = NO;

    [self addSubview:engine];
    self.engine = engine;
}

#pragma mark - Properties

- (UIScrollView *)scrollView {
    return [self.engine respondsToSelector:@selector(scrollView)] ? self.engine.scrollView : nil;
}

- (NSURL *)currentURL {
    if (![self.engine respondsToSelector:@selector(request)]) { return nil; }
    return self.engine.request.URL;
}

- (BOOL)canGoBack { return [self.engine respondsToSelector:@selector(canGoBack)] && self.engine.canGoBack; }
- (BOOL)canGoForward { return [self.engine respondsToSelector:@selector(canGoForward)] && self.engine.canGoForward; }
- (BOOL)isLoading { return [self.engine respondsToSelector:@selector(isLoading)] && self.engine.isLoading; }

#pragma mark - Navigation

- (void)loadRequest:(NSURLRequest *)request { [self.engine loadRequest:request]; }
- (void)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL { [self.engine loadHTMLString:html baseURL:baseURL]; }
- (void)reload { [self.engine reload]; }
- (void)stopLoading { [self.engine stopLoading]; }
- (void)goBack { [self.engine goBack]; }
- (void)goForward { [self.engine goForward]; }

- (NSString *)evaluateJavaScript:(NSString *)script {
    if (![self.engine respondsToSelector:@selector(stringByEvaluatingJavaScriptFromString:)]) { return nil; }
    return [self.engine stringByEvaluatingJavaScriptFromString:script];
}

- (UIImage *)snapshotWithMaxWidth:(CGFloat)maxWidth {
    CGSize size = self.bounds.size;
    if (size.width <= 0 || size.height <= 0) { return nil; }
    CGFloat scale = MIN(1.0, maxWidth / size.width);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [self.layer renderInContext:ctx.CGContext];
    }];
}

#pragma mark - Engine delegate (UIWebViewDelegate selectors)

- (BOOL)webView:(UIView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(NSInteger)navigationType {
    id<WBWebViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
        return [delegate webView:self shouldStartLoadWithRequest:request navigationType:(WBNavigationType)navigationType];
    }
    return YES;
}

- (void)webViewDidStartLoad:(UIView *)webView {
    id<WBWebViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [delegate webViewDidStartLoad:self];
    }
}

- (void)webViewDidFinishLoad:(UIView *)webView {
    id<WBWebViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [delegate webViewDidFinishLoad:self];
    }
}

- (void)webView:(UIView *)webView didFailLoadWithError:(NSError *)error {
    id<WBWebViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [delegate webView:self didFailLoadWithError:error];
    }
}

@end
