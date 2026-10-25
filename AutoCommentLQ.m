#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==============================================================================
// CONFIGURATION & PERSISTENCE
// ==============================================================================

#define PREF_ENABLED @"lq_auto_comment_enabled"
#define PREF_TEXT @"lq_auto_comment_text"
#define PREF_KEYWORDS @"lq_auto_comment_keywords"
#define PREF_AUTOSCROLL @"lq_auto_comment_autoscroll"
#define PREF_APPEND_TAG @"lq_auto_comment_append_tag"
#define PREF_DELAY @"lq_auto_comment_delay_sec"

#define DEFAULT_COMMENT_TEXT @"Nhập mã để được nhận 38 vé nhảy: avsqjyM3n7"
#define DEFAULT_KEYWORDS_STR @"#lienquan,#aov,#lienquanmobile,liên quân"

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
    if (!kw || kw.length == 0) kw = DEFAULT_KEYWORDS_STR;
    NSMutableArray *res = [NSMutableArray array];
    for (NSString *k in [kw componentsSeparatedByString:@","]) {
        NSString *trimmed = [k stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
        if (trimmed.length > 0) [res addObject:trimmed];
    }
    return res;
}

static void saveKeywordsList(NSArray<NSString *> *list) {
    NSString *joined = [list componentsJoinedByString:@","];
    [[NSUserDefaults standardUserDefaults] setObject:joined forKey:PREF_KEYWORDS];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static void addCustomKeyword(NSString *tag) {
    if (!tag || tag.length == 0) return;
    NSString *trimmed = [tag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (trimmed.length == 0) return;
    NSMutableArray *current = [NSMutableArray arrayWithArray:getKeywords()];
    if (![current containsObject:trimmed]) {
        [current addObject:trimmed];
        saveKeywordsList(current);
    }
}

static void removeKeyword(NSString *tag) {
    if (!tag) return;
    NSMutableArray *current = [NSMutableArray arrayWithArray:getKeywords()];
    [current removeObject:tag.lowercaseString];
    saveKeywordsList(current);
}

static void resetKeywordsToDefault(void) {
    [[NSUserDefaults standardUserDefaults] setObject:DEFAULT_KEYWORDS_STR forKey:PREF_KEYWORDS];
    [[NSUserDefaults standardUserDefaults] synchronize];
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

static BOOL getAppendMatchedTag(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_APPEND_TAG];
}

static void setAppendMatchedTag(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_APPEND_TAG];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static CGFloat getCommentDelay(void) {
    CGFloat d = [[NSUserDefaults standardUserDefaults] floatForKey:PREF_DELAY];
    if (d < 1.0) return 2.0; // Mặc định 2.0s
    return d;
}

static void setCommentDelay(CGFloat d) {
    [[NSUserDefaults standardUserDefaults] setFloat:d forKey:PREF_DELAY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Danh sách ID video đã comment
static NSMutableSet<NSString *> *sCommentedAwemeIDs = nil;
static NSString *sCurrentlyPendingAwemeID = nil;
static NSString *sCurrentlyPendingMatchedTag = nil;

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
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;

        UIView *old = [window viewWithTag:987654];
        if (old) [old removeFromSuperview];

        UIView *toast = [[UIView alloc] initWithFrame:CGRectMake(20, 55, window.bounds.size.width - 40, 52)];
        toast.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.14 alpha:0.94];
        toast.layer.cornerRadius = 14.0;
        toast.layer.masksToBounds = YES;
        toast.layer.borderWidth = 1.2;
        toast.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.45 alpha:0.9].CGColor;
        toast.alpha = 0.0;
        toast.tag = 987654;

        UILabel *label = [[UILabel alloc] initWithFrame:toast.bounds];
        label.text = message;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont boldSystemFontOfSize:13.0];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        [toast addSubview:label];

        [window addSubview:toast];

        [UIView animateWithDuration:0.25 animations:^{
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
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.62 blue:0.95 alpha:0.90];
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.8;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        [self setTitle:@"🎮" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:19.0];

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

    NSArray *tags = getKeywords();
    NSString *statusStr = getAutoCommentEnabled() ? @"[ĐANG BẬT ✅]" : @"[ĐANG TẮT ❌]";
    NSString *tagPreview = [tags componentsJoinedByString:@", "];
    if (tagPreview.length > 40) tagPreview = [[tagPreview substringToIndex:37] stringByAppendingString:@"..."];

    NSString *msg = [NSString stringWithFormat:@"%@\nĐã comment: %lu video | Delay: %.1fs\nHashtag (%lu): [%@]\nNội dung: %@",
                     statusStr, (unsigned long)sCommentedAwemeIDs.count, getCommentDelay(),
                     (unsigned long)tags.count, tagPreview, getCommentText()];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Auto Comment TikTok (Liên Quân)"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];

    // 1. Bật / Tắt Auto-Comment
    [alert addAction:[UIAlertAction actionWithTitle:getAutoCommentEnabled() ? @"TẮT Auto-Comment" : @"BẬT Auto-Comment"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        setAutoCommentEnabled(!getAutoCommentEnabled());
        showToastBanner(getAutoCommentEnabled() ? @"✅ Đã BẬT Auto Comment!" : @"❌ Đã TẮT Auto Comment!", 2.0);
    }]];

    // 2. Quản lý Hashtag (Tự thêm / Xóa)
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"# Quản lý Hashtag (%lu thẻ)", (unsigned long)tags.count]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self showHashtagManagementMenu:topVC];
    }]];

    // 3. Đổi nội dung bình luận
    [alert addAction:[UIAlertAction actionWithTitle:@"✍️ Đổi nội dung bình luận"
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

    // 4. Chỉnh thời gian Delay xem video
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"⏱️ Chỉnh thời gian Delay (hiện tại: %.1fs)", getCommentDelay()]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UIAlertController *delayAlert = [UIAlertController alertControllerWithTitle:@"Thời gian chờ trước khi comment"
                                                                            message:@"Chọn số giây video phát trước khi gửi comment:"
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *delays = @[@(1.5), @(2.5), @(4.0), @(6.0)];
        for (NSNumber *d in delays) {
            NSString *title = [NSString stringWithFormat:@"%@ giây%@", d, [d floatValue] == getCommentDelay() ? @" (đang chọn)" : @""];
            [delayAlert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
                setCommentDelay([d floatValue]);
                showToastBanner([NSString stringWithFormat:@"✅ Đã đặt delay %.1f giây", [d floatValue]], 2.0);
            }]];
        }
        [delayAlert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:delayAlert animated:YES completion:nil];
    }]];

    // 5. Tự cuộn video (Auto-Scroll)
    [alert addAction:[UIAlertAction actionWithTitle:getAutoScroll() ? @"⏭️ Tắt Tự Cuộn Video (Auto-Scroll)" : @"⏭️ Bật Tự Cuộn Video (Auto-Scroll)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        setAutoScroll(!getAutoScroll());
        showToastBanner(getAutoScroll() ? @"✅ Đã bật Auto-Scroll" : @"❌ Đã tắt Auto-Scroll", 2.0);
    }]];

    // 6. Xóa lịch sử đã comment
    [alert addAction:[UIAlertAction actionWithTitle:@"🧹 Xóa lịch sử video đã comment (để quét lại)"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [sCommentedAwemeIDs removeAllObjects];
        showToastBanner(@"🧹 Đã xóa lịch sử ID đã comment!", 2.0);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

    [topVC presentViewController:alert animated:YES completion:nil];
}

// Bảng menu quản lý Hashtag
- (void)showHashtagManagementMenu:(UIViewController *)topVC {
    NSArray<NSString *> *tags = getKeywords();
    NSMutableString *listMsg = [NSMutableString stringWithString:@"Danh sách các hashtag đang quét:\n\n"];
    int idx = 1;
    for (NSString *t in tags) {
        [listMsg appendFormat:@"%d. %@\n", idx++, t];
    }
    [listMsg appendString:@"\nHễ video có chứa bất kỳ hashtag/từ khóa nào ở trên, hệ thống sẽ tự động comment."];

    UIAlertController *tagAlert = [UIAlertController alertControllerWithTitle:@"# Quản Lý Hashtag"
                                                                      message:listMsg
                                                               preferredStyle:UIAlertControllerStyleAlert];

    // Thêm hashtag mới
    [tagAlert addAction:[UIAlertAction actionWithTitle:@"➕ Thêm Hashtag mới" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *addAlert = [UIAlertController alertControllerWithTitle:@"Thêm Hashtag mới"
                                                                          message:@"Nhập hashtag hoặc từ khóa cần quét (VD: #lienquan, #aov, #freefire):"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [addAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"#hashtag hoặc từ khóa";
        }];
        [addAlert addAction:[UIAlertAction actionWithTitle:@"Thêm" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
            NSString *val = addAlert.textFields.firstObject.text;
            if (val.length > 0) {
                addCustomKeyword(val);
                showToastBanner([NSString stringWithFormat:@"✅ Đã thêm hashtag: %@", val], 2.0);
                [self showHashtagManagementMenu:topVC];
            }
        }]];
        [addAlert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:addAlert animated:YES completion:nil];
    }]];

    // Xóa một hashtag
    if (tags.count > 0) {
        [tagAlert addAction:[UIAlertAction actionWithTitle:@"🗑️ Xóa bớt một Hashtag" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            UIAlertController *delAlert = [UIAlertController alertControllerWithTitle:@"Chọn Hashtag cần xóa"
                                                                              message:nil
                                                                       preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSString *t in tags) {
                [delAlert addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull a) {
                    removeKeyword(t);
                    showToastBanner([NSString stringWithFormat:@"🗑️ Đã xóa hashtag: %@", t], 2.0);
                    [self showHashtagManagementMenu:topVC];
                }]];
            }
            [delAlert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
            [topVC presentViewController:delAlert animated:YES completion:nil];
        }]];
    }

    // Tự động gắn hashtag vào nội dung comment
    NSString *appendTitle = getAppendMatchedTag() ? @"🏷️ Tự gắn hashtag vào comment: [ĐANG BẬT ✅]" : @"🏷️ Tự gắn hashtag vào comment: [ĐANG TẮT ❌]";
    [tagAlert addAction:[UIAlertAction actionWithTitle:appendTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        setAppendMatchedTag(!getAppendMatchedTag());
        showToastBanner(getAppendMatchedTag() ? @"✅ Đã bật tự gắn hashtag vào comment" : @"❌ Đã tắt tự gắn hashtag", 2.0);
        [self showHashtagManagementMenu:topVC];
    }]];

    // Khôi phục mặc định
    [tagAlert addAction:[UIAlertAction actionWithTitle:@"🔄 Khôi phục danh sách mặc định" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        resetKeywordsToDefault();
        showToastBanner(@"🔄 Đã khôi phục hashtag mặc định (#lienquan, #aov, #lienquanmobile)", 2.0);
        [self showHashtagManagementMenu:topVC];
    }]];

    [tagAlert addAction:[UIAlertAction actionWithTitle:@"Quay lại" style:UIAlertActionStyleCancel handler:nil]];

    [topVC presentViewController:tagAlert animated:YES completion:nil];
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
            NSString *matchedWord = nil;
            for (NSString *kw in getKeywords()) {
                if ([lower containsString:kw]) {
                    matchedWord = kw;
                    break;
                }
            }

            if (matchedWord) {
                objc_setAssociatedObject(orig, "lq_matched", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(orig, "lq_matched_tag", matchedWord, OBJC_ASSOCIATION_COPY_NONATOMIC);
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
// NATIVE COMMENT AUTOMATION PIPELINE (BULLETPROOF GEOMETRY & STACK DETECTION)
// ==============================================================================

// Tìm nút Comment ở cạnh phải màn hình dựa theo cấu trúc stack dọc chuẩn của TikTok
static UIButton *findTikTokCommentButton(UIView *cellView, UIWindow *window) {
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;

    NSMutableArray<UIButton *> *candidateButtons = [NSMutableArray array];

    void (^scanViews)(UIView *) = ^(UIView *root) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
        while (queue.count > 0) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];

            if ([v isKindOfClass:[UIButton class]]) {
                UIButton *b = (UIButton *)v;
                CGRect rectInWindow = [b convertRect:b.bounds toView:nil];

                // Nút hành động video TikTok luôn nằm ở dải 25% mép phải màn hình
                if (rectInWindow.origin.x > screenWidth * 0.70 &&
                    rectInWindow.origin.y > 100 &&
                    rectInWindow.origin.y < screenHeight - 100 &&
                    rectInWindow.size.width >= 24 && rectInWindow.size.width <= 90 &&
                    rectInWindow.size.height >= 24 && rectInWindow.size.height <= 90) {
                    [candidateButtons addObject:b];
                }
            }
            [queue addObjectsFromArray:v.subviews];
        }
    };

    if (cellView) scanViews(cellView);
    if (candidateButtons.count == 0 && window) scanViews(window);

    if (candidateButtons.count == 0) return nil;

    // Sắp xếp các nút cạnh phải từ trên xuống dưới theo tọa độ Y
    [candidateButtons sortUsingComparator:^NSComparisonResult(UIButton *b1, UIButton *b2) {
        CGRect r1 = [b1 convertRect:b1.bounds toView:nil];
        CGRect r2 = [b2 convertRect:b2.bounds toView:nil];
        if (r1.origin.y < r2.origin.y) return NSOrderedAscending;
        if (r1.origin.y > r2.origin.y) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    // 1. Kiểm tra ưu tiên: Nút nào có imageNameString hoặc accessibility chứa "comment"
    for (UIButton *b in candidateButtons) {
        SEL imgSel = NSSelectorFromString(@"imageNameString");
        NSString *imgName = @"";
        if ([b respondsToSelector:imgSel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            imgName = [b performSelector:imgSel] ?: @"";
            #pragma clang diagnostic pop
        }
        NSString *acc = b.accessibilityLabel ?: @"";
        if ([imgName localizedCaseInsensitiveContainsString:@"comment"] ||
            [acc localizedCaseInsensitiveContainsString:@"comment"] ||
            [acc localizedCaseInsensitiveContainsString:@"bình luận"]) {
            NSLog(@"[TikTok-LQ] 🎯 Tìm thấy nút comment qua imageName: %@", imgName);
            return b;
        }
    }

    // 2. Cấu trúc chuẩn 100% của TikTok từ trên xuống:
    // candidateButtons[0] = Nút Like (Trái tim)
    // candidateButtons[1] = NÚT COMMENT (Bong bóng bình luận)
    // candidateButtons[2] = Nút Bookmark/Yêu thích
    // candidateButtons[3] = Nút Chia sẻ (Share)
    if (candidateButtons.count >= 2) {
        NSLog(@"[TikTok-LQ] 🎯 Tìm thấy nút Comment theo vị trí stack [1] (Tổng số nút cạnh phải: %lu)", (unsigned long)candidateButtons.count);
        return candidateButtons[1];
    }

    return candidateButtons.firstObject;
}

// Tìm ô nhập text (UITextView hoặc UITextField) trong toàn bộ phân cấp View
static UIView *findAnyInputView(UIView *root) {
    if (!root) return nil;
    if ([root isKindOfClass:[UITextView class]] || [root isKindOfClass:[UITextField class]]) {
        return root;
    }
    for (UIView *sub in root.subviews) {
        UIView *f = findAnyInputView(sub);
        if (f) return f;
    }
    return nil;
}

// Tìm bất kỳ view nào ở thanh đáy (Bottom bar) của bảng comment để kích hoạt bàn phím
static UIView *findBottomInputBarPlaceholder(UIView *root) {
    if (!root) return nil;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];

    void (^scanBottom)(UIView *) = ^(UIView *p) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:p];
        while (queue.count > 0) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];

            CGRect r = [v convertRect:v.bounds toView:nil];
            // Nằm ở đáy màn hình (80pt cuối), có chiều rộng lớn > 150pt
            if (r.origin.y > screenHeight - 140 && r.size.width > 150 && r.size.height >= 28 && r.size.height <= 60) {
                if ([v isKindOfClass:[UIControl class]] || [v isKindOfClass:[UIButton class]] || v.gestureRecognizers.count > 0) {
                    [candidates addObject:v];
                }
            }
            [queue addObjectsFromArray:v.subviews];
        }
    };

    scanBottom(root);
    return candidates.firstObject;
}

// Tìm nút Gửi (Send Button) trong thanh nhập comment
static UIButton *findSendCommentButton(UIView *root, UIView *inputView) {
    if (!root) return nil;
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];

    void (^scanBtns)(UIView *) = ^(UIView *p) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:p];
        while (queue.count > 0) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];

            if ([v isKindOfClass:[UIButton class]]) {
                UIButton *b = (UIButton *)v;
                NSString *acc = b.accessibilityLabel ?: @"";
                NSString *title = [b titleForState:UIControlStateNormal] ?: @"";
                if ([acc localizedCaseInsensitiveContainsString:@"send"] ||
                    [acc localizedCaseInsensitiveContainsString:@"gửi"] ||
                    [acc localizedCaseInsensitiveContainsString:@"post"] ||
                    [title localizedCaseInsensitiveContainsString:@"gửi"] ||
                    [title localizedCaseInsensitiveContainsString:@"send"] ||
                    [title localizedCaseInsensitiveContainsString:@"đăng"]) {
                    [buttons insertObject:b atIndex:0]; // Ưu tiên hàng đầu
                } else {
                    [buttons addObject:b];
                }
            }
            [queue addObjectsFromArray:v.subviews];
        }
    };

    scanBtns(root);

    // Ưu tiên nút có chữ Send / Gửi
    if (buttons.count > 0) {
        return buttons.firstObject;
    }

    // Nếu không có title rõ ràng, nút Gửi thường là nút nằm bên phải cùng của ô nhập inputView
    if (inputView) {
        CGRect inputRect = [inputView convertRect:inputView.bounds toView:nil];
        for (UIButton *b in buttons) {
            CGRect bRect = [b convertRect:b.bounds toView:nil];
            if (bRect.origin.x > inputRect.origin.x + inputRect.size.width - 50 &&
                fabs(bRect.origin.y - inputRect.origin.y) < 30) {
                return b;
            }
        }
    }

    return nil;
}

// Điền text chuẩn cho TikTok (Gọi delegate để state machine của TikTok nhận text và bật sáng nút gửi)
static void injectTextIntoInputView(UIView *inputView, NSString *text) {
    if ([inputView isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)inputView;
        id<UITextViewDelegate> del = tv.delegate;

        if ([del respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
            [del textView:tv shouldChangeTextInRange:NSMakeRange(0, tv.text.length) replacementText:text];
        }
        tv.text = text;
        if ([del respondsToSelector:@selector(textViewDidChange:)]) {
            [del textViewDidChange:tv];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
        NSLog(@"[TikTok-LQ] ✍️ Đã điền text vào UITextView và kích hoạt delegate!");

    } else if ([inputView isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)inputView;
        id<UITextFieldDelegate> del = tf.delegate;

        if ([del respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)]) {
            [del textField:tf shouldChangeCharactersInRange:NSMakeRange(0, tf.text.length) replacementString:text];
        }
        tf.text = text;
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:tf];
        [tf sendActionsForControlEvents:UIControlEventEditingChanged];
        NSLog(@"[TikTok-LQ] ✍️ Đã điền text vào UITextField và kích hoạt delegate!");
    }
}

// Thực hiện toàn bộ chuỗi gửi comment
static void executeCommentPostingFlow(UIWindow *window, NSString *finalMsg, UIView *cellView) {
    NSLog(@"[TikTok-LQ] 🚀 Bắt đầu flow nhập và gửi comment...");

    // 1. Quét tìm ô nhập text trong toàn bộ Window
    UIView *inputView = findAnyInputView(window);

    // Nếu chưa thấy ô nhập text (do thanh input đang ở dạng placeholder thu nhỏ), bấm vào thanh đáy để mở bàn phím
    if (!inputView) {
        UIView *bottomPlaceholder = findBottomInputBarPlaceholder(window);
        if (bottomPlaceholder) {
            NSLog(@"[TikTok-LQ] 👉 Bấm vào placeholder input đáy để mở bàn phím...");
            if ([bottomPlaceholder respondsToSelector:@selector(sendActionsForControlEvents:)]) {
                [((UIControl *)bottomPlaceholder) sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
            for (UIGestureRecognizer *g in bottomPlaceholder.gestureRecognizers) {
                if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
                    UITapGestureRecognizer *tap = (UITapGestureRecognizer *)g;
                    for (id target in [tap valueForKey:@"_targets"]) {
                        id actTarget = [target valueForKey:@"_target"];
                        SEL actSel = NSSelectorFromString([target valueForKey:@"_action"]);
                        if (actTarget && [actTarget respondsToSelector:actSel]) {
                            #pragma clang diagnostic push
                            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                            [actTarget performSelector:actSel withObject:tap];
                            #pragma clang diagnostic pop
                        }
                    }
                }
            }
        }
    }

    // Đợi 0.6s để ô nhập text và bàn phím sẵn sàng
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *activeInput = findAnyInputView(window);
        if (activeInput) {
            // Đưa focus vào ô nhập
            [activeInput becomeFirstResponder];

            // Ghi nội dung bình luận
            injectTextIntoInputView(activeInput, finalMsg);

            // Đợi 0.6s để TikTok kích hoạt nút Send
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIButton *sendBtn = findSendCommentButton(window, activeInput);
                if (sendBtn) {
                    NSLog(@"[TikTok-LQ] 🚀 ĐÃ BẤM NÚT GỬI BÌNH LUẬN!");
                    [sendBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
                    showToastBanner(@"✅ ĐÃ GỬI BÌNH LUẬN THÀNH CÔNG!", 2.5);
                } else {
                    // Fallback gửi qua phím Return (\n)
                    if ([activeInput isKindOfClass:[UITextView class]]) {
                        UITextView *tv = (UITextView *)activeInput;
                        if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
                            [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(tv.text.length, 0) replacementText:@"\n"];
                        }
                    }
                    showToastBanner(@"✅ Đã nhập comment xong!", 2.0);
                }

                // Đóng bảng comment và lướt tiếp sau 2.0s
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [activeInput resignFirstResponder];

                    // Tự động cuộn sang video kế tiếp nếu bật Auto-Scroll
                    if (getAutoScroll()) {
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
                    }
                });
            });
        } else {
            NSLog(@"[TikTok-LQ] ⚠️ Không tìm thấy ô nhập sau khi mở bảng comment!");
        }
    });
}

// Bắt đầu chuỗi kích hoạt comment cho một video
static void triggerCommentSequence(UIView *cellView, NSString *awemeId, NSString *caption, NSString *matchedTag) {
    if (!getAutoCommentEnabled()) return;
    if (!awemeId || [sCommentedAwemeIDs containsObject:awemeId]) return;

    [sCommentedAwemeIDs addObject:awemeId];
    sCurrentlyPendingAwemeID = awemeId;
    sCurrentlyPendingMatchedTag = matchedTag;

    NSString *tagLabel = matchedTag ?: @"Liên Quân";
    NSLog(@"[TikTok-LQ] 🎯 Phát hiện video khớp [%@]: ID=%@", tagLabel, awemeId);

    CGFloat delaySec = getCommentDelay();
    showToastBanner([NSString stringWithFormat:@"🎯 Khớp [%@]!\n⏳ Tự động comment sau %.1fs...", tagLabel, delaySec], delaySec + 0.5);

    // Ghép nội dung comment
    NSString *baseText = getCommentText();
    NSMutableString *fullComment = [NSMutableString stringWithString:baseText];
    if (getAppendMatchedTag() && matchedTag.length > 0) {
        if (![matchedTag hasPrefix:@"#"]) {
            [fullComment appendFormat:@" #%@", matchedTag];
        } else {
            [fullComment appendFormat:@" %@", matchedTag];
        }
    }

    // Đợi theo delay đã cài đặt
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySec * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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

        // 1. Tìm nút Comment ở cạnh phải màn hình
        UIButton *commentBtn = findTikTokCommentButton(cellView, window);

        if (commentBtn) {
            NSLog(@"[TikTok-LQ] 👉 Bấm nút mở bảng bình luận TikTok...");
            [commentBtn sendActionsForControlEvents:UIControlEventTouchUpInside];

            SEL touchUpSel = NSSelectorFromString(@"_onTouchUpInside");
            if ([commentBtn respondsToSelector:touchUpSel]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [commentBtn performSelector:touchUpSel];
                #pragma clang diagnostic pop
            }

            // 2. Chờ 0.8s để bảng comment mở ra và bắt đầu điền text
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                executeCommentPostingFlow(window, fullComment, cellView);
            });
        } else {
            NSLog(@"[TikTok-LQ] ⚠️ Không tìm thấy nút Comment ở cạnh phải!");
            // Vẫn thử quét xem bảng comment có đang mở sẵn không
            executeCommentPostingFlow(window, fullComment, cellView);
        }
    });
}

// ==============================================================================
// HOOK 2: Comment Panel ViewControllers (Phát hiện mở panel bình luận)
// ==============================================================================

@interface UIViewController (LQCommentPanelHook)
- (void)lq_commentPanel_viewDidAppear:(BOOL)animated;
@end

@implementation UIViewController (LQCommentPanelHook)

- (void)lq_commentPanel_viewDidAppear:(BOOL)animated {
    [self lq_commentPanel_viewDidAppear:animated];

    // Nếu đang có một video chờ comment
    if (sCurrentlyPendingAwemeID && [sCommentedAwemeIDs containsObject:sCurrentlyPendingAwemeID]) {
        NSString *pendingTag = sCurrentlyPendingMatchedTag;
        NSString *baseText = getCommentText();
        NSMutableString *fullComment = [NSMutableString stringWithString:baseText];
        if (getAppendMatchedTag() && pendingTag.length > 0) {
            [fullComment appendFormat:@" %@", pendingTag];
        }

        NSLog(@"[TikTok-LQ] 🔔 Comment panel viewDidAppear kích hoạt! Bắt đầu nhập ngay...");
        sCurrentlyPendingAwemeID = nil; // Reset trạng thái chờ
        sCurrentlyPendingMatchedTag = nil;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            executeCommentPostingFlow(self.view.window ?: [UIApplication sharedApplication].windows.firstObject, fullComment, nil);
        });
    }
}

@end

// ==============================================================================
// HOOK 3: Video Feed Cells & Detail Cells (Hiển thị video trên màn hình)
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
    NSString *matchedTag = objc_getAssociatedObject(model, "lq_matched_tag");

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
                matchedTag = kw;
                break;
            }
        }
    }

    if ([matched boolValue] && awemeId) {
        triggerCommentSequence(self, [NSString stringWithFormat:@"%@", awemeId], caption ?: @"", matchedTag ?: @"#lienquan");
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
        NSLog(@"[TikTok-LQ] 🚀 Standalone AutoComment LQ v2.1.0 Loaded into TikTok!");
        NSLog(@"[TikTok-LQ] 🔑 Mã nhận vé: %@", getCommentText());
        NSLog(@"[TikTok-LQ] 🏷️ Danh sách hashtag: %@", [getKeywords() componentsJoinedByString:@", "]);
        NSLog(@"=================================================================");

        // 1. Swizzle AWEAwemeModel (Bắt JSON trực tiếp từ server TikTok)
        Class awemeCls = NSClassFromString(@"AWEAwemeModel");
        if (awemeCls) {
            SwizzleMethod(awemeCls, @selector(initWithDictionary:error:), @selector(lq_initWithDictionary:error:));
            NSLog(@"[TikTok-LQ] ✅ Swizzled AWEAwemeModel initWithDictionary:error:");
        }

        // 2. Swizzle Comment Panel ViewControllers
        NSArray *panelClassNames = @[
            @"TTKCommentPanelViewController",
            @"AWECommentPanelViewController",
            @"AWECommentListViewController"
        ];
        for (NSString *clsName in panelClassNames) {
            Class cls = NSClassFromString(clsName);
            if (cls) {
                SwizzleMethod(cls, @selector(viewDidAppear:), @selector(lq_commentPanel_viewDidAppear:));
                NSLog(@"[TikTok-LQ] ✅ Swizzled Comment Panel: %@", clsName);
            }
        }

        // 3. Swizzle Video Feed Cells
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

        // 4. Hiển thị thông báo khi app mở và đính kèm widget
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            attachFloatingWidgetIfNeeded();
            showToastBanner(@"🟢 Auto Comment TikTok v2.1 Đã Sẵn Sàng!\nBấm nút 🎮 để thêm Hashtag & chỉnh nội dung.", 4.0);
        });
    }
}
