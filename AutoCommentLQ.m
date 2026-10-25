#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Photos/Photos.h>

// ==============================================================================
// CONFIGURATION & PERSISTENCE
// ==============================================================================

#define PREF_ENABLED @"lq_auto_comment_enabled"
#define PREF_TEXT @"lq_auto_comment_text"
#define PREF_KEYWORDS @"lq_auto_comment_keywords"
#define PREF_AUTOSCROLL @"lq_auto_comment_autoscroll"
#define PREF_APPEND_TAG @"lq_auto_comment_append_tag"
#define PREF_DELAY @"lq_auto_comment_delay_sec"
#define PREF_HIDE_ADS @"lq_hide_ads_enabled"
#define PREF_SHOW_WIDGET @"lq_show_floating_widget"
#define PREF_REMOVE_WATERMARK @"lq_remove_watermark"
#define PREF_PROGRESS_BAR @"lq_progress_bar"
#define PREF_EXTENDED_COMMENT @"lq_extended_comment"

#define DEFAULT_COMMENT_TEXT @"Nhập mã để được nhận 38 vé nhảy: avsqjyM3n7"
#define DEFAULT_KEYWORDS_STR @"#lienquan,#aov,#lienquanmobile,liên quân"

static BOOL getAutoCommentEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_ENABLED] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_ENABLED];
}
static void setAutoCommentEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_ENABLED];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getHideAdsEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_HIDE_ADS] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_HIDE_ADS];
}
static void setHideAdsEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_HIDE_ADS];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getShowFloatingWidget(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_SHOW_WIDGET]; // Mặc định TẮT (Ẩn nút nổi)
}
static void setShowFloatingWidget(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_SHOW_WIDGET];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getRemoveWatermarkEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_REMOVE_WATERMARK] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_REMOVE_WATERMARK];
}
static void setRemoveWatermarkEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_REMOVE_WATERMARK];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getProgressBarEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_PROGRESS_BAR] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_PROGRESS_BAR];
}
static void setProgressBarEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_PROGRESS_BAR];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getExtendedCommentEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_EXTENDED_COMMENT] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_EXTENDED_COMMENT];
}
static void setExtendedCommentEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_EXTENDED_COMMENT];
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
    [[NSUserDefaults standardUserDefaults] setObject:[list componentsJoinedByString:@","] forKey:PREF_KEYWORDS];
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
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_AUTOSCROLL] == nil) return YES;
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
    if (d < 1.0) return 2.0;
    return d;
}
static void setCommentDelay(CGFloat d) {
    [[NSUserDefaults standardUserDefaults] setFloat:d forKey:PREF_DELAY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Runtime tracking
static NSMutableSet<NSString *> *sCommentedAwemeIDs = nil;
static NSString *sCurrentlyPendingAwemeID = nil;
static NSString *sCurrentlyPendingMatchedTag = nil;

// Forward declaration
static void showSettingsMenu(void);

// ==============================================================================
// VISUAL TOAST & HUD
// ==============================================================================

static void showToastBanner(NSString *message, CGFloat duration) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) { if (w.isKeyWindow) { window = w; break; } }
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

// ==============================================================================
// CACHE CLEANING ENGINE (DỌN DẸP BỘ NHỚ ĐỆM TOÀN DIỆN)
// ==============================================================================

static uint64_t cleanDirectoryWithExtensions(NSString *dirPath, NSArray<NSString *> *targetExts) {
    if (!dirPath) return 0;
    uint64_t freedBytes = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:dirPath error:nil];
    for (NSString *file in files) {
        NSString *fullPath = [dirPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir]) {
            if (isDir) {
                // Đệ quy dọn thư mục con
                freedBytes += cleanDirectoryWithExtensions(fullPath, targetExts);
                // Xóa thư mục rỗng
                NSArray *sub = [fm contentsOfDirectoryAtPath:fullPath error:nil];
                if (sub.count == 0) [fm removeItemAtPath:fullPath error:nil];
            } else {
                BOOL shouldDelete = NO;
                if (!targetExts || targetExts.count == 0) {
                    shouldDelete = YES;
                } else {
                    NSString *ext = [file pathExtension].lowercaseString;
                    if ([targetExts containsObject:ext]) shouldDelete = YES;
                }
                if (shouldDelete) {
                    NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                    freedBytes += [attrs fileSize];
                    [fm removeItemAtPath:fullPath error:nil];
                }
            }
        }
    }
    return freedBytes;
}

static void performCleanCache(void) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint64_t totalFreed = 0;

        // 1. Dọn dẹp Library/Caches (Image cache, HTTP network cache, WebKit cache)
        NSString *cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        totalFreed += cleanDirectoryWithExtensions(cachesPath, nil);

        // 2. Dọn dẹp NSTemporaryDirectory() (Video temp, chunks, download temp)
        NSString *tmpPath = NSTemporaryDirectory();
        totalFreed += cleanDirectoryWithExtensions(tmpPath, nil);

        // 3. Dọn dẹp các video rác & ảnh tạm trong Documents/
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSArray *mediaExts = @[@"mp4", @"mov", @"tmp", @"m4a", @"mp3", @"jpeg", @"jpg", @"png"];
        totalFreed += cleanDirectoryWithExtensions(docPath, mediaExts);

        // 4. Xóa bộ nhớ đệm NSURLCache
        [[NSURLCache sharedURLCache] removeAllCachedResponses];

        double mbFreed = (double)totalFreed / (1024.0 * 1024.0);
        NSLog(@"[TikTok-LQ] 🧹 Đã dọn dẹp bộ nhớ đệm: Giải phóng %.2f MB", mbFreed);

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *resText = [NSString stringWithFormat:@"🧹 Dọn dẹp thành công!\nGiải phóng %.1f MB bộ nhớ đệm.", mbFreed];
            showToastBanner(resText, 3.5);
        });
    });
}

// ==============================================================================
// GESTURE MANAGER: LONG-PRESS & DOUBLE-TAP ON "TRANG CHỦ" (HOME TAB)
// ==============================================================================

@interface LQGestureDelegateHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end

@implementation LQGestureDelegateHandler
+ (instancetype)shared {
    static LQGestureDelegateHandler *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[LQGestureDelegateHandler alloc] init]; });
    return inst;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES; // Cho phép cử chỉ nhận diện song song, không làm kẹt nút bấm gốc của TikTok
}
@end

static void handleHomeTabLongPress(UILongPressGestureRecognizer *rec) {
    if (rec.state == UIGestureRecognizerStateBegan) {
        UIView *view = rec.view;
        CGPoint pt = [rec locationInView:view];
        CGFloat h = view.bounds.size.height;
        CGFloat w = view.bounds.size.width;

        // Vùng nút "Trang chủ" (Góc dưới cùng bên trái: y > h - 110, x < w * 0.28)
        if (pt.y >= h - 110 && pt.x <= w * 0.28) {
            NSLog(@"[TikTok-LQ] 🎯 Phát hiện NHẤN GIỮ (Long-Press) vào nút Trang chủ!");
            UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [fb impactOccurred];
            showSettingsMenu();
        }
    }
}

static void handleHomeTabDoubleTap(UITapGestureRecognizer *rec) {
    if (rec.state == UIGestureRecognizerStateEnded) {
        UIView *view = rec.view;
        CGPoint pt = [rec locationInView:view];
        CGFloat h = view.bounds.size.height;
        CGFloat w = view.bounds.size.width;

        // Vùng nút "Trang chủ" (Góc dưới cùng bên trái: y > h - 110, x < w * 0.28)
        if (pt.y >= h - 110 && pt.x <= w * 0.28) {
            NSLog(@"[TikTok-LQ] 🎯 Phát hiện CHẠM 2 LẦN (Double-Tap) vào nút Trang chủ!");
            UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [fb impactOccurred];
            showSettingsMenu();
        }
    }
}

static void setupHomeTabGesturesOnWindow(UIWindow *window) {
    if (!window) return;
    if (objc_getAssociatedObject(window, "lq_gestures_installed")) return;

    // 1. Nhấn giữ (Long-Press >= 0.55s) vào nút Trang chủ
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[LQGestureDelegateHandler class] action:@selector(handleLongPressHelper:)];
    lp.minimumPressDuration = 0.55;
    lp.delegate = [LQGestureDelegateHandler shared];
    [window addGestureRecognizer:lp];

    // 2. Chạm 2 lần (Double-Tap) vào nút Trang chủ
    UITapGestureRecognizer *dt = [[UITapGestureRecognizer alloc] initWithTarget:[LQGestureDelegateHandler class] action:@selector(handleDoubleTapHelper:)];
    dt.numberOfTapsRequired = 2;
    dt.delegate = [LQGestureDelegateHandler shared];
    [window addGestureRecognizer:dt];

    objc_setAssociatedObject(window, "lq_gestures_installed", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[TikTok-LQ] ✅ Đã cài đặt bộ nhận diện cử chỉ Long-Press & Double-Tap vào nút Trang chủ!");
}

@implementation LQGestureDelegateHandler (ActionHelpers)
+ (void)handleLongPressHelper:(UILongPressGestureRecognizer *)rec { handleHomeTabLongPress(rec); }
+ (void)handleDoubleTapHelper:(UITapGestureRecognizer *)rec { handleHomeTabDoubleTap(rec); }
@end

// ==============================================================================
// FLOATING WIDGET (TUỲ CHỌN HIỆN HOẶC ẨN)
// ==============================================================================

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
        [self addTarget:self action:@selector(widgetTapped) forControlEvents:UIControlEventTouchUpInside];
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
        [UIView animateWithDuration:0.25 animations:^{ self.center = CGPointMake(targetX, targetY); }];
    }
}
- (void)widgetTapped { showSettingsMenu(); }
@end

static void updateFloatingWidgetVisibility(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) { if (w.isKeyWindow) { window = w; break; } }
                if (window) break;
            }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;

        setupHomeTabGesturesOnWindow(window);

        UIView *existing = [window viewWithTag:11223344];
        if (getShowFloatingWidget()) {
            if (!existing) {
                LQFloatingWidget *btn = [[LQFloatingWidget alloc] initWithFrame:CGRectMake(window.bounds.size.width - 52, 110, 42, 42)];
                btn.tag = 11223344;
                [window addSubview:btn];
            }
            existing.hidden = NO;
        } else {
            if (existing) existing.hidden = YES;
        }
    });
}

// ==============================================================================
// MAIN CONTROL MENU (BẢNG ĐIỀU KHIỂN CHÍNH)
// ==============================================================================

static void showHashtagManagementMenu(UIViewController *topVC);

static void showSettingsMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) { if (w.isKeyWindow) { window = w; break; } }
                if (window) break;
            }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;

        UIViewController *topVC = window.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }

        NSArray *tags = getKeywords();
        NSString *tagPreview = [tags componentsJoinedByString:@", "];
        if (tagPreview.length > 36) tagPreview = [[tagPreview substringToIndex:33] stringByAppendingString:@"..."];

        NSString *statusStr = getAutoCommentEnabled() ? @"[Auto-Comment: BẬT ✅]" : @"[Auto-Comment: TẮT ❌]";
        NSString *adsStr = getHideAdsEnabled() ? @"[Chặn Ads: BẬT 🛡️]" : @"[Chặn Ads: TẮT ⚠️]";

        NSString *msg = [NSString stringWithFormat:@"%@ | %@\nĐã comment: %lu video | Delay: %.1fs\nHashtag (%lu): [%@]\nNội dung: %@",
                         statusStr, adsStr, (unsigned long)sCommentedAwemeIDs.count, getCommentDelay(),
                         (unsigned long)tags.count, tagPreview, getCommentText()];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TikTok Mod & Auto-Comment"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];

        // 1. DỌN DẸP BỘ NHỚ ĐỆM (CLEAN CACHE)
        [alert addAction:[UIAlertAction actionWithTitle:@"🧹 Dọn dẹp bộ nhớ đệm (Clean Cache)"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            performCleanCache();
        }]];

        // 2. Bật / Tắt Auto-Comment
        [alert addAction:[UIAlertAction actionWithTitle:getAutoCommentEnabled() ? @"⚡ TẮT Auto-Comment" : @"⚡ BẬT Auto-Comment"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            setAutoCommentEnabled(!getAutoCommentEnabled());
            showToastBanner(getAutoCommentEnabled() ? @"✅ Đã BẬT Auto Comment!" : @"❌ Đã TẮT Auto Comment!", 2.0);
        }]];

        // 3. Quản lý Hashtag (Tự do thêm / Xóa)
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"#️⃣ Quản lý Hashtag (%lu thẻ)", (unsigned long)tags.count]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            showHashtagManagementMenu(topVC);
        }]];

        // 4. Đổi nội dung comment
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

        // 5. Chặn quảng cáo (Ad Block)
        NSString *adTitle = getHideAdsEnabled() ? @"🛡️ Chặn quảng cáo (Ad Block): [BẬT ✅]" : @"🛡️ Chặn quảng cáo (Ad Block): [TẮT ❌]";
        [alert addAction:[UIAlertAction actionWithTitle:adTitle
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            setHideAdsEnabled(!getHideAdsEnabled());
            showToastBanner(getHideAdsEnabled() ? @"🛡️ Đã BẬT Chặn quảng cáo TikTok!" : @"⚠️ Đã TẮT Chặn quảng cáo!", 2.0);
        }]];

        // 6. Tải không Watermark
        NSString *wmTitle = getRemoveWatermarkEnabled() ? @"💧 Tải video không Watermark: [BẬT ✅]" : @"💧 Tải video không Watermark: [TẮT ❌]";
        [alert addAction:[UIAlertAction actionWithTitle:wmTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            setRemoveWatermarkEnabled(!getRemoveWatermarkEnabled());
            showToastBanner(getRemoveWatermarkEnabled() ? @"✅ Đã BẬT Không Watermark" : @"❌ Đã TẮT", 2.0);
        }]];

        // 7. Bật thanh tua video
        NSString *pbTitle = getProgressBarEnabled() ? @"⏩ Thanh tua video cho mọi video: [BẬT ✅]" : @"⏩ Thanh tua video cho mọi video: [TẮT ❌]";
        [alert addAction:[UIAlertAction actionWithTitle:pbTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            setProgressBarEnabled(!getProgressBarEnabled());
            showToastBanner(getProgressBarEnabled() ? @"✅ Đã BẬT Thanh tua video" : @"❌ Đã TẮT", 2.0);
        }]];

        // 8. Chỉnh delay & Tự cuộn (Auto-Scroll)
        NSString *scrollTitle = getAutoScroll() ? @"⏭️ Tự động lướt video: [BẬT ✅]" : @"⏭️ Tự động lướt video: [TẮT ❌]";
        [alert addAction:[UIAlertAction actionWithTitle:scrollTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            setAutoScroll(!getAutoScroll());
            showToastBanner(getAutoScroll() ? @"✅ Đã bật Auto-Scroll" : @"❌ Đã tắt Auto-Scroll", 2.0);
        }]];

        // 9. Nút nổi 🎮 (Tùy chọn hiện/ẩn)
        NSString *widgetTitle = getShowFloatingWidget() ? @"🎮 Hiện nút nổi góc màn hình: [BẬT ✅]" : @"🎮 Hiện nút nổi góc màn hình: [TẮT (Dùng nhấn giữ Trang chủ)]";
        [alert addAction:[UIAlertAction actionWithTitle:widgetTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            setShowFloatingWidget(!getShowFloatingWidget());
            updateFloatingWidgetVisibility();
            showToastBanner(getShowFloatingWidget() ? @"✅ Đã hiện nút nổi 🎮" : @"✅ Đã ẩn nút nổi. Bạn có thể nhấn giữ hoặc chạm 2 lần vào 'Trang chủ' để mở menu!", 3.0);
        }]];

        // 10. Xóa lịch sử video đã comment
        [alert addAction:[UIAlertAction actionWithTitle:@"🗑️ Xóa danh sách video đã comment (để quét lại)"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [sCommentedAwemeIDs removeAllObjects];
            showToastBanner(@"🧹 Đã xóa lịch sử ID đã comment!", 2.0);
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

static void showHashtagManagementMenu(UIViewController *topVC) {
    NSArray<NSString *> *tags = getKeywords();
    NSMutableString *listMsg = [NSMutableString stringWithString:@"Danh sách các hashtag đang quét:\n\n"];
    int idx = 1;
    for (NSString *t in tags) {
        [listMsg appendFormat:@"%d. %@\n", idx++, t];
    }
    [listMsg appendString:@"\nHễ video có chứa bất kỳ hashtag/từ khóa nào ở trên, hệ thống sẽ tự động comment."];

    UIAlertController *tagAlert = [UIAlertController alertControllerWithTitle:@"#️⃣ Quản Lý Hashtag"
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
                showHashtagManagementMenu(topVC);
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
                    showHashtagManagementMenu(topVC);
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
        showHashtagManagementMenu(topVC);
    }]];

    // Khôi phục mặc định
    [tagAlert addAction:[UIAlertAction actionWithTitle:@"🔄 Khôi phục danh sách mặc định" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        resetKeywordsToDefault();
        showToastBanner(@"🔄 Đã khôi phục hashtag mặc định (#lienquan, #aov, #lienquanmobile)", 2.0);
        showHashtagManagementMenu(topVC);
    }]];

    [tagAlert addAction:[UIAlertAction actionWithTitle:@"Quay lại" style:UIAlertActionStyleCancel handler:nil]];

    [topVC presentViewController:tagAlert animated:YES completion:nil];
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
// HOOK 1: AWEAwemeModel (JSON Filter, Ad-Block, Progress Bar)
// ==============================================================================

@interface NSObject (LQAwemeHook)
- (id)lq_initWithDictionary:(id)arg1 error:(id *)arg2;
- (BOOL)lq_isAds;
- (BOOL)lq_isUserRecommendBigCard;
- (BOOL)lq_progressBarDraggable;
- (BOOL)lq_progressBarVisible;
@end

@implementation NSObject (LQAwemeHook)

- (BOOL)lq_isAds {
    if (getHideAdsEnabled()) return NO;
    return [self lq_isAds];
}

- (BOOL)lq_isUserRecommendBigCard {
    if (getHideAdsEnabled()) return NO;
    return [self lq_isUserRecommendBigCard];
}

- (BOOL)lq_progressBarDraggable {
    if (getProgressBarEnabled()) return YES;
    return [self lq_progressBarDraggable];
}

- (BOOL)lq_progressBarVisible {
    if (getProgressBarEnabled()) return YES;
    return [self lq_progressBarVisible];
}

- (id)lq_initWithDictionary:(id)arg1 error:(id *)arg2 {
    id orig = [self lq_initWithDictionary:arg1 error:arg2];

    // CHẶN QUẢNG CÁO BHTIKTOK (AD-BLOCK)
    if (getHideAdsEnabled() && orig) {
        @try {
            if ([orig respondsToSelector:@selector(isAds)]) {
                BOOL isAdsVal = [[orig valueForKey:@"isAds"] boolValue];
                if (isAdsVal) {
                    NSLog(@"[TikTok-AdBlock] 🛡️ Bỏ qua video Quảng Cáo (isAds = YES)");
                    return nil;
                }
            }
        } @catch (NSException *e) {}

        if ([arg1 isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)arg1;
            BOOL isServerAd = [dict[@"is_ads"] boolValue] ||
                              [dict[@"is_ad"] boolValue] ||
                              (dict[@"ad_info"] != nil && [dict[@"ad_info"] count] > 0) ||
                              (dict[@"raw_ad_data"] != nil) ||
                              [dict[@"commercial_type"] integerValue] > 0;
            if (isServerAd) {
                NSLog(@"[TikTok-AdBlock] 🛡️ Bỏ qua video Quảng Cáo từ Server JSON!");
                return nil;
            }
        }
    }

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
// HOOK 2: BHTikTok Extra Features (Remove Watermark, Extended Comment)
// ==============================================================================

@interface NSObject (LQExtraFeaturesHook)
- (NSUInteger)lq_watermarkType;
- (void)lq_setWatermarkType:(NSUInteger)type;
- (NSUInteger)lq_maxLength;
@end

@implementation NSObject (LQExtraFeaturesHook)

- (NSUInteger)lq_watermarkType {
    if (getRemoveWatermarkEnabled()) return 1; // 1 = No watermark
    return [self lq_watermarkType];
}

- (void)lq_setWatermarkType:(NSUInteger)type {
    if (getRemoveWatermarkEnabled()) {
        [self lq_setWatermarkType:1];
    } else {
        [self lq_setWatermarkType:type];
    }
}

- (NSUInteger)lq_maxLength {
    if (getExtendedCommentEnabled()) return 1000;
    return [self lq_maxLength];
}

@end

// ==============================================================================
// NATIVE COMMENT AUTOMATION PIPELINE (GEOMETRY & DELEGATE DRIVEN)
// ==============================================================================

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
                CGRect r = [b convertRect:b.bounds toView:nil];
                if (r.origin.x > screenWidth * 0.70 &&
                    r.origin.y > 100 && r.origin.y < screenHeight - 100 &&
                    r.size.width >= 24 && r.size.width <= 90 &&
                    r.size.height >= 24 && r.size.height <= 90) {
                    [candidateButtons addObject:b];
                }
            }
            [queue addObjectsFromArray:v.subviews];
        }
    };

    if (cellView) scanViews(cellView);
    if (candidateButtons.count == 0 && window) scanViews(window);
    if (candidateButtons.count == 0) return nil;

    [candidateButtons sortUsingComparator:^NSComparisonResult(UIButton *b1, UIButton *b2) {
        CGRect r1 = [b1 convertRect:b1.bounds toView:nil];
        CGRect r2 = [b2 convertRect:b2.bounds toView:nil];
        if (r1.origin.y < r2.origin.y) return NSOrderedAscending;
        if (r1.origin.y > r2.origin.y) return NSOrderedDescending;
        return NSOrderedSame;
    }];

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
            return b;
        }
    }

    if (candidateButtons.count >= 2) {
        return candidateButtons[1]; // Vị trí thứ 2 luôn là Comment Button trên TikTok
    }
    return candidateButtons.firstObject;
}

static UIView *findAnyInputView(UIView *root) {
    if (!root) return nil;
    if ([root isKindOfClass:[UITextView class]] || [root isKindOfClass:[UITextField class]]) return root;
    for (UIView *sub in root.subviews) {
        UIView *f = findAnyInputView(sub);
        if (f) return f;
    }
    return nil;
}

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
                    [buttons insertObject:b atIndex:0];
                } else {
                    [buttons addObject:b];
                }
            }
            [queue addObjectsFromArray:v.subviews];
        }
    };
    scanBtns(root);

    if (buttons.count > 0) return buttons.firstObject;

    if (inputView) {
        CGRect inputRect = [inputView convertRect:inputView.bounds toView:nil];
        for (UIButton *b in buttons) {
            CGRect bRect = [b convertRect:b.bounds toView:nil];
            if (bRect.origin.x > inputRect.origin.x + inputRect.size.width - 50 && fabs(bRect.origin.y - inputRect.origin.y) < 30) {
                return b;
            }
        }
    }
    return nil;
}

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
    } else if ([inputView isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)inputView;
        id<UITextFieldDelegate> del = tf.delegate;
        if ([del respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)]) {
            [del textField:tf shouldChangeCharactersInRange:NSMakeRange(0, tf.text.length) replacementString:text];
        }
        tf.text = text;
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:tf];
        [tf sendActionsForControlEvents:UIControlEventEditingChanged];
    }
}

static void executeCommentPostingFlow(UIWindow *window, NSString *finalMsg, UIView *cellView) {
    NSLog(@"[TikTok-LQ] 🚀 Bắt đầu flow nhập và gửi comment...");
    UIView *inputView = findAnyInputView(window);

    if (!inputView) {
        UIView *bottomPlaceholder = findBottomInputBarPlaceholder(window);
        if (bottomPlaceholder) {
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *activeInput = findAnyInputView(window);
        if (activeInput) {
            [activeInput becomeFirstResponder];
            injectTextIntoInputView(activeInput, finalMsg);

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIButton *sendBtn = findSendCommentButton(window, activeInput);
                if (sendBtn) {
                    [sendBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
                    showToastBanner(@"✅ ĐÃ GỬI BÌNH LUẬN THÀNH CÔNG!", 2.5);
                } else {
                    if ([activeInput isKindOfClass:[UITextView class]]) {
                        UITextView *tv = (UITextView *)activeInput;
                        if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
                            [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(tv.text.length, 0) replacementText:@"\n"];
                        }
                    }
                    showToastBanner(@"✅ Đã nhập bình luận thành công!", 2.0);
                }

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [activeInput resignFirstResponder];

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
        }
    });
}

static void triggerCommentSequence(UIView *cellView, NSString *awemeId, NSString *caption, NSString *matchedTag) {
    if (!getAutoCommentEnabled()) return;
    if (!awemeId || [sCommentedAwemeIDs containsObject:awemeId]) return;

    [sCommentedAwemeIDs addObject:awemeId];
    sCurrentlyPendingAwemeID = awemeId;
    sCurrentlyPendingMatchedTag = matchedTag;

    NSString *tagLabel = matchedTag ?: @"Liên Quân";
    CGFloat delaySec = getCommentDelay();
    showToastBanner([NSString stringWithFormat:@"🎯 Khớp [%@]!\n⏳ Tự động comment sau %.1fs...", tagLabel, delaySec], delaySec + 0.5);

    NSString *baseText = getCommentText();
    NSMutableString *fullComment = [NSMutableString stringWithString:baseText];
    if (getAppendMatchedTag() && matchedTag.length > 0) {
        if (![matchedTag hasPrefix:@"#"]) {
            [fullComment appendFormat:@" #%@", matchedTag];
        } else {
            [fullComment appendFormat:@" %@", matchedTag];
        }
    }

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

        UIButton *commentBtn = findTikTokCommentButton(cellView, window);
        if (commentBtn) {
            [commentBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
            SEL touchUpSel = NSSelectorFromString(@"_onTouchUpInside");
            if ([commentBtn respondsToSelector:touchUpSel]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [commentBtn performSelector:touchUpSel];
                #pragma clang diagnostic pop
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                executeCommentPostingFlow(window, fullComment, cellView);
            });
        } else {
            executeCommentPostingFlow(window, fullComment, cellView);
        }
    });
}

// ==============================================================================
// HOOK 3: Comment Panel ViewControllers (viewDidAppear Hook)
// ==============================================================================

@interface UIViewController (LQCommentPanelHook)
- (void)lq_commentPanel_viewDidAppear:(BOOL)animated;
@end

@implementation UIViewController (LQCommentPanelHook)
- (void)lq_commentPanel_viewDidAppear:(BOOL)animated {
    [self lq_commentPanel_viewDidAppear:animated];

    if (sCurrentlyPendingAwemeID && [sCommentedAwemeIDs containsObject:sCurrentlyPendingAwemeID]) {
        NSString *pendingTag = sCurrentlyPendingMatchedTag;
        NSString *baseText = getCommentText();
        NSMutableString *fullComment = [NSMutableString stringWithString:baseText];
        if (getAppendMatchedTag() && pendingTag.length > 0) {
            [fullComment appendFormat:@" %@", pendingTag];
        }
        sCurrentlyPendingAwemeID = nil;
        sCurrentlyPendingMatchedTag = nil;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            executeCommentPostingFlow(self.view.window ?: [UIApplication sharedApplication].windows.firstObject, fullComment, nil);
        });
    }
}
@end

// ==============================================================================
// HOOK 4: Video Feed Cells (Feed Display)
// ==============================================================================

@interface UIView (LQCellHook)
- (void)lq_configWithModel:(id)model;
- (void)lq_configureWithModel:(id)model;
@end

@implementation UIView (LQCellHook)

- (void)lq_handleVideoDisplay:(id)model {
    updateFloatingWidgetVisibility();

    if (!model) return;

    NSNumber *matched = objc_getAssociatedObject(model, "lq_matched");
    NSString *awemeId = objc_getAssociatedObject(model, "lq_aweme_id");
    NSString *caption = objc_getAssociatedObject(model, "lq_caption");
    NSString *matchedTag = objc_getAssociatedObject(model, "lq_matched_tag");

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
// INITIALIZER (CONSTRUCTOR)
// ==============================================================================

__attribute__((constructor))
static void initTikTokAutoCommentLienQuan(void) {
    @autoreleasepool {
        sCommentedAwemeIDs = [[NSMutableSet alloc] init];
        NSLog(@"=================================================================");
        NSLog(@"[TikTok-LQ] 🚀 Standalone AutoComment LQ v3.0.0 Loaded into TikTok!");
        NSLog(@"[TikTok-LQ] 🔑 Mã nhận vé: %@", getCommentText());
        NSLog(@"[TikTok-LQ] 🏷️ Danh sách hashtag: %@", [getKeywords() componentsJoinedByString:@", "]);
        NSLog(@"=================================================================");

        // 1. Swizzle AWEAwemeModel (JSON Filter, Ad-Block, Progress Bar)
        Class awemeCls = NSClassFromString(@"AWEAwemeModel");
        if (awemeCls) {
            SwizzleMethod(awemeCls, @selector(initWithDictionary:error:), @selector(lq_initWithDictionary:error:));
            if (class_getInstanceMethod(awemeCls, @selector(isAds))) {
                SwizzleMethod(awemeCls, @selector(isAds), @selector(lq_isAds));
            }
            if (class_getInstanceMethod(awemeCls, @selector(isUserRecommendBigCard))) {
                SwizzleMethod(awemeCls, @selector(isUserRecommendBigCard), @selector(lq_isUserRecommendBigCard));
            }
            if (class_getInstanceMethod(awemeCls, @selector(progressBarDraggable))) {
                SwizzleMethod(awemeCls, @selector(progressBarDraggable), @selector(lq_progressBarDraggable));
            }
            if (class_getInstanceMethod(awemeCls, @selector(progressBarVisible))) {
                SwizzleMethod(awemeCls, @selector(progressBarVisible), @selector(lq_progressBarVisible));
            }
            NSLog(@"[TikTok-LQ] ✅ Swizzled AWEAwemeModel (init, Ad-Block, Progress Bar)");
        }

        // 2. Swizzle AWEAwemeACLItem (No Watermark)
        Class aclCls = NSClassFromString(@"AWEAwemeACLItem");
        if (aclCls) {
            if (class_getInstanceMethod(aclCls, @selector(watermarkType))) {
                SwizzleMethod(aclCls, @selector(watermarkType), @selector(lq_watermarkType));
            }
            if (class_getInstanceMethod(aclCls, @selector(setWatermarkType:))) {
                SwizzleMethod(aclCls, @selector(setWatermarkType:), @selector(lq_setWatermarkType:));
            }
            NSLog(@"[TikTok-LQ] ✅ Swizzled AWEAwemeACLItem (No Watermark)");
        }

        // 3. Swizzle AWETextInputController (Extended Comment Limit)
        Class inputCls = NSClassFromString(@"AWETextInputController");
        if (inputCls) {
            if (class_getInstanceMethod(inputCls, @selector(maxLength))) {
                SwizzleMethod(inputCls, @selector(maxLength), @selector(lq_maxLength));
            }
            NSLog(@"[TikTok-LQ] ✅ Swizzled AWETextInputController (Extended Comment)");
        }

        // 4. Swizzle Comment Panel ViewControllers
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

        // 5. Swizzle Video Feed Cells
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

        // 6. Hiển thị thông báo khi app mở và thiết lập cử chỉ
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            updateFloatingWidgetVisibility();
            showToastBanner(@"🟢 TikTok Mod v3.0 (Auto-Comment & Ad Block)\nNhấn giữ hoặc chạm 2 lần vào 'Trang chủ' để mở Menu!", 4.5);
        });
    }
}
