//
//  WBWebView.h
//  Webby
//
//  A thin, crash-safe wrapper around the WebKit-backed UIWebView class that
//  ships inside tvOS but is not exposed by the public tvOS SDK. Everything is
//  resolved at runtime, so the rest of the app talks to a clean API.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WBNavigationType) {
    WBNavigationTypeLinkClicked = 0,
    WBNavigationTypeFormSubmitted,
    WBNavigationTypeBackForward,
    WBNavigationTypeReload,
    WBNavigationTypeFormResubmitted,
    WBNavigationTypeOther
};

@class WBWebView;

@protocol WBWebViewDelegate <NSObject>
@optional
- (BOOL)webView:(WBWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(WBNavigationType)navigationType
    NS_SWIFT_NAME(webView(_:shouldStartLoad:navigationType:));
- (void)webViewDidStartLoad:(WBWebView *)webView NS_SWIFT_NAME(webViewDidStartLoad(_:));
- (void)webViewDidFinishLoad:(WBWebView *)webView NS_SWIFT_NAME(webViewDidFinishLoad(_:));
- (void)webView:(WBWebView *)webView didFailLoadWithError:(NSError *)error NS_SWIFT_NAME(webView(_:didFailLoad:));
@end

@interface WBWebView : UIView

/// YES when the WebKit engine class exists on this OS build.
@property (class, nonatomic, readonly) BOOL isEngineAvailable;

@property (nonatomic, weak, nullable) id<WBWebViewDelegate> delegate;
@property (nonatomic, readonly, nullable) UIScrollView *scrollView;
@property (nonatomic, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly, getter=isLoading) BOOL loading;

- (void)loadRequest:(NSURLRequest *)request NS_SWIFT_NAME(load(_:));
- (void)loadHTMLString:(NSString *)html baseURL:(nullable NSURL *)baseURL NS_SWIFT_NAME(loadHTML(_:baseURL:));
- (void)reload;
- (void)stopLoading;
- (void)goBack;
- (void)goForward;

/// Synchronously evaluates JavaScript in the main frame and returns the result as a string.
- (nullable NSString *)evaluateJavaScript:(NSString *)script NS_SWIFT_NAME(evaluate(_:));

/// Renders the visible page into an image (used for tab thumbnails).
- (nullable UIImage *)snapshotWithMaxWidth:(CGFloat)maxWidth;

@end

NS_ASSUME_NONNULL_END
