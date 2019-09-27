#import "QueueITWKViewController.h"
#import "QueueITEngine.h"

@interface QueueITWKViewController ()<WKNavigationDelegate>
@property (nonatomic) WKWebView* webView;
@property (nonatomic, strong) UIViewController* host;
@property (nonatomic, strong) QueueITEngine* engine;
@property (nonatomic, strong)NSString* queueUrl;
@property (nonatomic, strong)NSString* eventTargetUrl;
@property (nonatomic, strong)UIActivityIndicatorView* spinner;
@property (nonatomic, strong)NSString* customerId;
@property (nonatomic, strong)NSString* eventId;
@property BOOL isQueuePassed;
@end

static NSString * const JAVASCRIPT_GET_BODY_CLASSES = @"document.getElementsByTagName('body')[0].className";

@implementation QueueITWKViewController

-(instancetype)initWithHost:(UIViewController *)host
                queueEngine:(QueueITEngine*) engine
                   queueUrl:(NSString*)queueUrl
             eventTargetUrl:(NSString*)eventTargetUrl
                 customerId:(NSString*)customerId
                    eventId:(NSString*)eventId
{
    self = [super init];
    if(self) {
        self.host = host;
        self.engine = engine;
        self.queueUrl = queueUrl;
        self.eventTargetUrl = eventTargetUrl;
        self.customerId = customerId;
        self.eventId = eventId;
        self.isQueuePassed = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    WKPreferences* preferences = [[WKPreferences alloc]init];
    preferences.javaScriptEnabled = YES;
    WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc]init];
    config.preferences = preferences;
    WKWebView* view = [[WKWebView alloc]initWithFrame:CGRectMake(0, 84, self.view.bounds.size.width, self.view.bounds.size.height - 84) configuration:config];
    view.navigationDelegate = self;
    self.webView = view;
}

- (void)viewWillAppear:(BOOL)animated{
    self.spinner = [[UIActivityIndicatorView alloc]initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
    [self.spinner setColor:[UIColor grayColor]];
    [self.spinner startAnimating];
    
    [self.view addSubview:self.webView];
    [self.webView addSubview:self.spinner];
    
    
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    NSBundle *bundle = [NSBundle bundleWithURL: [[NSBundle bundleForClass:QueueITWKViewController.class] URLForResource:@"Queue-It" withExtension:@"bundle"]];
    UIImage *closeButtonImage = [UIImage imageNamed:@"icClose" inBundle:bundle compatibleWithTraitCollection:nil];
    [closeButton setFrame:CGRectMake(24, 44, 24, 24)];
    [closeButton setBackgroundImage:closeButtonImage forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(buttonPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
    
    NSURL *urlAddress = [NSURL URLWithString:self.queueUrl];
    NSURLRequest *request = [NSURLRequest requestWithURL:urlAddress];
    [self.webView loadRequest:request];
}

- (void)buttonPressed {
    [self.engine raiseUserExited];
    [self dismissViewControllerAnimated:true completion:nil];
}

#pragma mark - WKNavigationDelegate
- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(nonnull WKNavigationAction *)navigationAction decisionHandler:(nonnull void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURLRequest* request = navigationAction.request;
    NSString* urlString = [[request URL] absoluteString];
    NSString* targetUrlString = self.eventTargetUrl;
    NSLog(@"request Url: %@", urlString);
    
    if (!self.isQueuePassed) {
        if (urlString != nil) {
            NSURL* url = [NSURL URLWithString:urlString];
            NSURL* targetUrl = [NSURL URLWithString:targetUrlString];
            if(urlString != nil && ![urlString isEqualToString:@"about:blank"]) {
                BOOL isQueueUrl = [self.queueUrl containsString:url.host];
                BOOL isNotFrame = [[[request URL] absoluteString] isEqualToString:[[request mainDocumentURL] absoluteString]];
                if (isNotFrame) {
                    if (isQueueUrl) {
                        [self.engine updateQueuePageUrl:urlString];
                    }
                    if ([targetUrl.host containsString:url.host]) {
                        self.isQueuePassed = YES;
                        NSString* queueitToken = [self extractQueueToken:url.absoluteString];
                        [self.engine raiseQueuePassed:queueitToken];
                        [self.host dismissViewControllerAnimated:YES completion:^{
                            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                        }];
                    }
                }
                if (navigationAction.navigationType == WKNavigationTypeLinkActivated && !isQueueUrl) {
                    if (@available(iOS 10.0, *)) {
                        [[UIApplication sharedApplication] openURL:[request URL] options:@{} completionHandler:nil];
                    }
                    else {
                        [[UIApplication sharedApplication] openURL:[request URL]];
                    }
                    decisionHandler(WKNavigationActionPolicyCancel);
                    return;
                }
            }
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (NSString*)extractQueueToken:(NSString*) url {
    NSString* tokenKey = @"queueittoken=";
    if ([url containsString:tokenKey]) {
        NSString* token = [url substringFromIndex:NSMaxRange([url rangeOfString:tokenKey])];
        if([token containsString:@"&"]) {
            token = [token substringToIndex:NSMaxRange([token rangeOfString:@"&"]) - 1];
        }
        return token;
    }
    return nil;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(nonnull NSError *)error {
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(nonnull NSError *)error {
    [self.engine.queueITUnavailableDelegate notifyQueueITUnavailable: [NSString stringWithFormat:@"%d",error.code]];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    NSURL* url = webView.URL;
    NSString* urlString = url.absoluteString;
    NSLog(@"finished url = %@", urlString); 
    
    [self.spinner stopAnimating];
    if (![self.webView isLoading])
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    }
    
    // Check if user exitted through the default exit link and notify the engine
    [self.webView evaluateJavaScript:JAVASCRIPT_GET_BODY_CLASSES completionHandler:^(id result, NSError* error){
        if (error != nil) {
            NSLog(@"evaluateJavaScript error : %@", error.localizedDescription);
        }
        else {
            NSString* resultString = [NSString stringWithFormat:@"%@", result];
            NSArray<NSString *> *htmlBodyClasses = [resultString componentsSeparatedByString:@" "];
            BOOL isExitClassPresent = [htmlBodyClasses containsObject:@"exit"];
            if (isExitClassPresent) {
                [self.engine raiseUserExited];
            }
        }
    }];
}

-(void)appWillResignActive:(NSNotification*)note
{
}

@end
