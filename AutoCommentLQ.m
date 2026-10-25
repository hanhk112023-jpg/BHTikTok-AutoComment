#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==============================================================================
// CONFIGURATION & PERSISTENCE
// ==============================================================================

#define PREF_ENABLED @"lq_auto_comment_enabled"
#define PREF_TEXT @"lq_auto_comment_text"
#define PREF_KEYWORDS @"lq_auto_comment_keywords"
#define PREF_AUTOSCROLL @"lq_auto_comment_autoscroll"
#define DEFAULT_COMMENT_TEXT @"Nhập mã để được nhận 38 vé nhảy: avsqjyM3n7"
#define DEFAULT_KEYWORDS @"#lienquan,#aov,#lienquanmobile,liên quân"

static BOOL getAutoCommentEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_ENABLED] == nil) {
        return YES; // Mặc định BẬT
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_ENABLED];
}

static void setAutoCommentEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:PREF_ENABLED];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSString *getCommentText(void) {
    NSString *t = [[NSUserDefaults standardUserDefaults] stringForKey:PREF_TEXT];
    if (!t || t.length == 0) return DEFAULT_COMMENT_TEXT;
    return t;
}

static void setCommentText(NSString *t) {
    [[NSUserDefaults standardUserDefaults] setObject:t forKey:PREF_TEXT];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSArray<NSString *> *getKeywords(void) {
    NSString *kw = [[NSUserDefaults standardUserDefaults] stringForKey:PREF_KEYWORDS];
    if (!kw || kw.length == 0) kw = DEFAULT_KEYWORDS;
    NSMutableArray *res = [NSMutableArray array];
    for (NSString *k in [kw componentsSeparatedByString:@","]) {
        NSString *trimmed = [k stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
        if (trimmed.length > 0) [res addObject:trimmed];
    }
    return res;
}

static BOOL getAutoScroll(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_AUTOSCROLL] == nil) {
        return YES;
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_AUTOSCROLL];
}

static void setAutoScroll(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_AUTOSCROLL];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Danh sách ID video đã comment
static NSMutableSet<NSString *> *sCommentedAwemeIDs = nil;

// ==============================================================================
// VISUAL TOAST & FLOATING BUTTON (DRAGGABLE)
// ==============================================================================

static void showToastBanner(NSString *message, CGFloat duration) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
                if (window) break;
            }
        }
        if (!window) {
            window = [UIApplication sharedApplication].windows.firstObject;
        }
        if (!window) return;

        UIView *toast = [[UIView alloc] initWithFrame:CGRectMake(20, 60, window.bounds.size.width - 40, 50)];
        toast.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.92];
        toast.layer.cornerRadius = 14.0;
        toast.layer.masksToBounds = YES;
        toast.layer.borderWidth = 1.0;
        toast.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.8].CGColor;
        toast.alpha = 0.0;
        toast.tag = 987654;

        UILabel *label = [[UILabel alloc] initWithFrame:toast.bounds];
        label.text = message;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont boldSystemFontOfSize:13.5];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        [toast addSubview:label];

        [window addSubview:toast];

        [UIView animateWithDuration:0.3 animations:^{
            toast.alpha = 1.0;
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{
                    toast.alpha = 0.0;
                } completion:^(BOOL fin) {
                    [toast removeFromSuperview];
                }];
            });
        }];
    });
}

// Nút điều khiển nổi (Floating HUD Button)
@interface LQFloatingWidget : UIButton
@end

@implementation LQFloatingWidget {
    CGPoint _startPoint;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.65 blue:0.95 alpha:0.88];
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        [self setTitle:@"🎮" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:18.0];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        [self addTarget:self action:@selector(showSettingsMenu) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;

    CGPoint translation = [pan translationInView:superview];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _startPoint = self.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        self.center = CGPointMake(_startPoint.x + translation.x, _startPoint.y + translation.y);
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        // Snap to nearest edge
        CGFloat screenWidth = superview.bounds.size.width;
        CGFloat targetX = (self.center.x < screenWidth / 2.0) ? (self.bounds.size.width / 2.0 + 10) : (screenWidth - self.bounds.size.width / 2.0 - 10);
        CGFloat targetY = MIN(MAX(self.center.y, 80), superview.bounds.size.height - 100);
        [UIView animateWithDuration:0.25 animations:^{
            self.center = CGPointMake(targetX, targetY);
        }];
    }
}

- (void)showSettingsMenu {
    UIWindow *window = self.window;
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    NSString *statusStr = getAutoCommentEnabled() ? @"[ĐANG BẬT ✅]" : @"[ĐANG TẮT ❌]";
    NSString *msg = [NSString stringWithFormat:@"%@\nĐã comment: %lu video\nMã: %@\nTừ khóa: Liên Quân, #lienquan, #aov",
                     statusStr, (unsigned long)sCommentedAwemeIDs.count, getCommentText()];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Auto Comment TikTok (Liên Quân)"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:getAutoCommentEnabled() ? @"TẮT Auto-Comment" : @"BẬT Auto-Comment"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        setAutoCommentEnabled(!getAutoCommentEnabled());
        showToastBanner(getAutoCommentEnabled() ? @"✅ Đã BẬT Auto Comment Liên Quân!" : @"❌ Đã TẮT Auto Comment!", 2.0);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đổi nội dung bình luận"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"Nội dung bình luận"
                                                                            message:@"Nhập nội dung muốn auto comment:"
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = getCommentText();
        }];
        [inputAlert addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            NSString *newText = inputAlert.textFields.firstObject.text;
            if (newText.length > 0) {
                setCommentText(newText);
                showToastBanner(@"✅ Đã cập nhật nội dung bình luận!", 2.0);
            }
        }]];
        [inputAlert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:inputAlert animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:getAutoScroll() ? @"Tắt Tự Cuộn Video (Auto-Scroll)" : @"Bật Tự Cuộn Video (Auto-Scroll)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        setAutoScroll(!getAutoScroll());
        showToastBanner(getAutoScroll() ? @"✅ Đã bật Auto-Scroll" : @"❌ Đã tắt Auto-Scroll", 2.0);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Xóa lịch sử đã comment (để quét lại)"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [sCommentedAwemeIDs removeAllObjects];
        showToastBanner(@"🧹 Đã xóa lịch sử ID đã comment!", 2.0);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

    [topVC presentViewController:alert animated:YES completion:nil];
}

@end

static void attachFloatingWidgetIfNeeded(void) {
    static BOOL sWidgetAttached = NO;
    if (sWidgetAttached) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
                if (window) break;
            }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;

        if ([window viewWithTag:11223344]) return;

        LQFloatingWidget *btn = [[LQFloatingWidget alloc] initWithFrame:CGRectMake(window.bounds.size.width - 52, 110, 42, 42)];
        btn.tag = 11223344;
        [window addSubview:btn];
        sWidgetAttached = YES;
        NSLog(@"[TikTok-LQ] 🎮 Floating Widget attached to window!");
    });
}

// ==============================================================================
// RUNTIME METHOD SWIZZLING HELPERS
// ==============================================================================

static void SwizzleMethod(Class cls, SEL origSEL, SEL newSEL) {
    Method origMethod = class_getInstanceMethod(cls, origSEL);
    Method newMethod = class_getInstanceMethod(cls, newSEL);
    if (!origMethod || !newMethod) return;

    BOOL didAdd = class_addMethod(cls, origSEL, method_getImplementation(newMethod), method_getTypeEncoding(newMethod));
    if (didAdd) {
        class_replaceMethod(cls, newSEL, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

// ==============================================================================
// HOOK 1: AWEAwemeModel (Bắt JSON trực tiếp từ TikTok API)
// ==============================================================================

@interface NSObject (LQAwemeHook)
- (id)lq_initWithDictionary:(id)arg1 error:(id *)arg2;
@end

@implementation NSObject (LQAwemeHook)

- (id)lq_initWithDictionary:(id)arg1 error:(id *)arg2 {
    id orig = [self lq_initWithDictionary:arg1 error:arg2];
    if (orig && [arg1 isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)arg1;
        NSString *rawDesc = dict[@"desc"];
        NSString *rawAid = dict[@"aweme_id"];
        if (!rawAid && dict[@"aid"]) rawAid = [NSString stringWithFormat:@"%@", dict[@"aid"]];

        if (rawDesc && [rawDesc isKindOfClass:[NSString class]]) {
            objc_setAssociatedObject(orig, "lq_caption", rawDesc, OBJC_ASSOCIATION_COPY_NONATOMIC);
            
            NSString *lower = [rawDesc lowercaseString];
            BOOL isMatch = NO;
            for (NSString *kw in getKeywords()) {
                if ([lower containsString:kw]) {
                    isMatch = YES;
                    break;
                }
            }

            if (isMatch) {
                objc_setAssociatedObject(orig, "lq_matched", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        if (rawAid) {
            objc_setAssociatedObject(orig, "lq_aweme_id", [NSString stringWithFormat:@"%@", rawAid], OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    }
    return orig;
}

@end

// ==============================================================================
// NATIVE COMMENT AUTOMATION PIPELINE
// ==============================================================================

static UIButton *findButtonMatching(UIView *root, NSArray<NSString *> *keywords) {
    if (!root) return nil;
    if ([root isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)root;
        NSString *acc = b.accessibilityLabel ?: @"";
        NSString *cls = NSStringFromClass([b class]);
        for (NSString *kw in keywords) {
            if ([acc localizedCaseInsensitiveContainsString:kw] || [cls localizedCaseInsensitiveContainsString:kw]) {
                return b;
            }
        }
    }
    for (UIView *sub in root.subviews) {
        UIButton *found = findButtonMatching(sub, keywords);
        if (found) return found;
    }
    return nil;
}

static UITextView *findTextViewInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITextView class]]) return (UITextView *)view;
    for (UIView *sub in view.subviews) {
        UITextView *tv = findTextViewInView(sub);
        if (tv) return tv;
    }
    return nil;
}

static void triggerCommentSequence(UIView *cellView, NSString *awemeId, NSString *caption) {
    if (!getAutoCommentEnabled()) return;
    if (!awemeId || [sCommentedAwemeIDs containsObject:awemeId]) return;

    [sCommentedAwemeIDs addObject:awemeId];
    NSLog(@"[TikTok-LQ] 🎯 Bắt đầu quy trình comment cho AwemeID=%@: %@", awemeId, caption);

    showToastBanner([NSString stringWithFormat:@"🎯 Phát hiện video Liên Quân!\n⏳ Đang chuẩn bị comment sau 2s..."], 2.5);

    // Đợi 2s để video hiển thị ổn định
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = cellView.window;
        if (!window) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) { if (w.isKeyWindow) { window = w; break; } }
                    if (window) break;
                }
            }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;

        // 1. Tìm nút Comment trong Cell hoặc trên màn hình
        UIButton *commentBtn = findButtonMatching(cellView, @[@"Comment", @"Bình luận", @"comment"]);
        if (!commentBtn && window) {
            commentBtn = findButtonMatching(window, @[@"Comment", @"Bình luận", @"comment"]);
        }

        if (commentBtn) {
            NSLog(@"[TikTok-LQ] 👉 Bấm nút mở bảng comment...");
            [commentBtn sendActionsForControlEvents:UIControlEventTouchUpInside];

            // 2. Chờ 1.2s để bảng bình luận trượt lên
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Tìm input textView trong toàn bộ window
                UITextView *inputView = findTextViewInView(window);
                if (inputView) {
                    NSString *msg = getCommentText();
                    inputView.text = msg;
                    // Bắn notification để TikTok nhận diện text thay đổi
                    [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:inputView];

                    NSLog(@"[TikTok-LQ] ✍️ Đã nhập text comment: %@", msg);

                    // 3. Chờ 0.8s tìm nút Gửi (Send)
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        UIButton *sendBtn = findButtonMatching(window, @[@"Send", @"Gửi", @"publish", @"Post"]);
                        if (sendBtn) {
                            [sendBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
                            NSLog(@"[TikTok-LQ] 🚀 Đã bấm nút GỬI comment!");
                            showToastBanner(@"✅ Đã gửi bình luận mã 38 vé nhảy!", 2.5);
                        } else {
                            // Thử submit qua textview delegate hoặc resign
                            if ([inputView.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
                                [inputView.delegate textView:inputView shouldChangeTextInRange:NSMakeRange(inputView.text.length, 0) replacementText:@"\n"];
                            }
                            showToastBanner(@"✅ Đã nhập comment thành công!", 2.0);
                        }

                        // 4. Đóng bảng comment và lướt tiếp sau 2.5s nếu bật AutoScroll
                        if (getAutoScroll()) {
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                // Giả lập lướt lên trên UITableView của feed
                                UIView *v = cellView;
                                while (v && ![v isKindOfClass:[UIScrollView class]]) {
                                    v = v.superview;
                                }
                                if ([v isKindOfClass:[UIScrollView class]]) {
                                    UIScrollView *scrollView = (UIScrollView *)v;
                                    CGPoint currentOffset = scrollView.contentOffset;
                                    CGFloat pageHeight = scrollView.bounds.size.height;
                                    [scrollView setContentOffset:CGPointMake(currentOffset.x, currentOffset.y + pageHeight) animated:YES];
                                    NSLog(@"[TikTok-LQ] ⏭️ Đã tự động cuộn sang video tiếp theo!");
                                }
                            });
                        }
                    });
                } else {
                    NSLog(@"[TikTok-LQ] ⚠️ Không tìm thấy ô nhập comment trong window!");
                }
            });
        } else {
            NSLog(@"[TikTok-LQ] ⚠️ Không tìm thấy nút Comment trên giao diện!");
        }
    });
}

// ==============================================================================
// HOOK 2: AWEFeedViewTemplateCell & Detail Cells (Hiển thị video trên màn hình)
// ==============================================================================

@interface UIView (LQCellHook)
- (void)lq_configWithModel:(id)model;
- (void)lq_configureWithModel:(id)model;
@end

@implementation UIView (LQCellHook)

- (void)lq_handleVideoDisplay:(id)model {
    attachFloatingWidgetIfNeeded();

    if (!model) return;

    NSNumber *matched = objc_getAssociatedObject(model, "lq_matched");
    NSString *awemeId = objc_getAssociatedObject(model, "lq_aweme_id");
    NSString *caption = objc_getAssociatedObject(model, "lq_caption");

    // Fallback nếu model chưa có associated object (lấy qua KVC)
    if (!awemeId) {
        @try {
            awemeId = [model valueForKey:@"itemID"] ?: [model valueForKey:@"awemeId"] ?: [model valueForKey:@"aid"];
        } @catch (NSException *e) {}
    }

    if (!caption) {
        @try {
            caption = [model valueForKey:@"descriptionString"] ?: [model valueForKey:@"desc"] ?: [model valueForKey:@"title"];
        } @catch (NSException *e) {}
    }

    if (!matched && caption) {
        NSString *lower = [caption lowercaseString];
        for (NSString *kw in getKeywords()) {
            if ([lower containsString:kw]) {
                matched = @YES;
                break;
            }
        }
    }

    if ([matched boolValue] && awemeId) {
        triggerCommentSequence(self, [NSString stringWithFormat:@"%@", awemeId], caption ?: @"");
    }
}

- (void)lq_configWithModel:(id)model {
    [self lq_configWithModel:model];
    [self lq_handleVideoDisplay:model];
}

- (void)lq_configureWithModel:(id)model {
    [self lq_configureWithModel:model];
    [self lq_handleVideoDisplay:model];
}

@end

// ==============================================================================
// INITIALIZER (Được gọi tự động khi dylib được nạp vào TikTok process)
// ==============================================================================

__attribute__((constructor))
static void initTikTokAutoCommentLienQuan(void) {
    @autoreleasepool {
        sCommentedAwemeIDs = [[NSMutableSet alloc] init];
        NSLog(@"=================================================================");
        NSLog(@"[TikTok-LQ] 🚀 Standalone AutoComment LQ Loaded into TikTok!");
        NSLog(@"[TikTok-LQ] 🔑 Mã nhận vé: %@", getCommentText());
        NSLog(@"=================================================================");

        // 1. Swizzle AWEAwemeModel
        Class awemeCls = NSClassFromString(@"AWEAwemeModel");
        if (awemeCls) {
            SwizzleMethod(awemeCls, @selector(initWithDictionary:error:), @selector(lq_initWithDictionary:error:));
            NSLog(@"[TikTok-LQ] ✅ Swizzled AWEAwemeModel initWithDictionary:error:");
        }

        // 2. Swizzle Video Feed Cells
        NSArray *cellClassNames = @[
            @"AWEFeedViewTemplateCell",
            @"AWEAwemeDetailTableViewCell",
            @"TTKFeedViewCell",
            @"AWEFeedCell"
        ];

        for (NSString *clsName in cellClassNames) {
            Class cls = NSClassFromString(clsName);
            if (cls) {
                if (class_getInstanceMethod(cls, @selector(configWithModel:))) {
                    SwizzleMethod(cls, @selector(configWithModel:), @selector(lq_configWithModel:));
                }
                if (class_getInstanceMethod(cls, @selector(configureWithModel:))) {
                    SwizzleMethod(cls, @selector(configureWithModel:), @selector(lq_configureWithModel:));
                }
                NSLog(@"[TikTok-LQ] ✅ Swizzled Cell Class: %@", clsName);
            }
        }

        // 3. Hiển thị thông báo khi app mở và đính kèm widget
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            attachFloatingWidgetIfNeeded();
            showToastBanner(@"🟢 Auto Comment Liên Quân v1.0 đã kích hoạt!\nBấm nút 🎮 góc màn hình để tùy chỉnh.", 4.0);
        });
    }
}
