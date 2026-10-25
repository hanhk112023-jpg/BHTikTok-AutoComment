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
static void presentNativeSettingsUI(void);

// ==============================================================================
// VISUAL TOAST BANNER (CLEAN & MINIMALIST)
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

        UIView *toast = [[UIView alloc] initWithFrame:CGRectMake(24, 60, window.bounds.size.width - 48, 46)];
        toast.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:0.95];
        toast.layer.cornerRadius = 12.0;
        toast.layer.masksToBounds = YES;
        toast.layer.borderWidth = 1.0;
        toast.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.8].CGColor;
        toast.alpha = 0.0;
        toast.tag = 987654;

        UILabel *label = [[UILabel alloc] initWithFrame:toast.bounds];
        label.text = message;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        [toast addSubview:label];

        [window addSubview:toast];

        [UIView animateWithDuration:0.2 animations:^{
            toast.alpha = 1.0;
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.25 animations:^{
                    toast.alpha = 0.0;
                } completion:^(BOOL fin) {
                    [toast removeFromSuperview];
                }];
            });
        }];
    });
}

// ==============================================================================
// CACHE CLEANING ENGINE
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
                freedBytes += cleanDirectoryWithExtensions(fullPath, targetExts);
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

static void performCleanCache(void (^completion)(double mbFreed)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint64_t totalFreed = 0;

        NSString *cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        totalFreed += cleanDirectoryWithExtensions(cachesPath, nil);

        NSString *tmpPath = NSTemporaryDirectory();
        totalFreed += cleanDirectoryWithExtensions(tmpPath, nil);

        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSArray *mediaExts = @[@"mp4", @"mov", @"tmp", @"m4a", @"mp3", @"jpeg", @"jpg", @"png"];
        totalFreed += cleanDirectoryWithExtensions(docPath, mediaExts);

        [[NSURLCache sharedURLCache] removeAllCachedResponses];

        double mbFreed = (double)totalFreed / (1024.0 * 1024.0);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(mbFreed);
        });
    });
}

// ==============================================================================
// GESTURE MANAGER: HOME TAB LONG-PRESS & DOUBLE-TAP
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
    return YES;
}
@end

static void handleHomeTabLongPress(UILongPressGestureRecognizer *rec) {
    if (rec.state == UIGestureRecognizerStateBegan) {
        UIView *view = rec.view;
        CGPoint pt = [rec locationInView:view];
        CGFloat h = view.bounds.size.height;
        CGFloat w = view.bounds.size.width;

        if (pt.y >= h - 110 && pt.x <= w * 0.28) {
            UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [fb impactOccurred];
            presentNativeSettingsUI();
        }
    }
}

static void handleHomeTabDoubleTap(UITapGestureRecognizer *rec) {
    if (rec.state == UIGestureRecognizerStateEnded) {
        UIView *view = rec.view;
        CGPoint pt = [rec locationInView:view];
        CGFloat h = view.bounds.size.height;
        CGFloat w = view.bounds.size.width;

        if (pt.y >= h - 110 && pt.x <= w * 0.28) {
            UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [fb impactOccurred];
            presentNativeSettingsUI();
        }
    }
}

static void setupHomeTabGesturesOnWindow(UIWindow *window) {
    if (!window) return;
    if (objc_getAssociatedObject(window, "lq_gestures_installed")) return;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[LQGestureDelegateHandler class] action:@selector(handleLongPressHelper:)];
    lp.minimumPressDuration = 0.50;
    lp.delegate = [LQGestureDelegateHandler shared];
    [window addGestureRecognizer:lp];

    UITapGestureRecognizer *dt = [[UITapGestureRecognizer alloc] initWithTarget:[LQGestureDelegateHandler class] action:@selector(handleDoubleTapHelper:)];
    dt.numberOfTapsRequired = 2;
    dt.delegate = [LQGestureDelegateHandler shared];
    [window addGestureRecognizer:dt];

    objc_setAssociatedObject(window, "lq_gestures_installed", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation LQGestureDelegateHandler (ActionHelpers)
+ (void)handleLongPressHelper:(UILongPressGestureRecognizer *)rec { handleHomeTabLongPress(rec); }
+ (void)handleDoubleTapHelper:(UITapGestureRecognizer *)rec { handleHomeTabDoubleTap(rec); }
@end

// ==============================================================================
// NATIVE IOS SETTINGS UI (CLEAN INSET GROUPED - NO UGLY EMOJIS)
// ==============================================================================

@interface LQHashtagManagerViewController : UITableViewController
@end

@implementation LQHashtagManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Quản lý Hashtag";
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTagTapped)];
}

- (void)addTagTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thêm Hashtag" message:@"Nhập hashtag hoặc từ khóa cần quét:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"#lienquan, #aov...";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Thêm" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *val = alert.textFields.firstObject.text;
        if (val.length > 0) {
            addCustomKeyword(val);
            [self.tableView reloadData];
            showToastBanner([NSString stringWithFormat:@"Đã thêm hashtag: %@", val], 1.5);
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return getKeywords().count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Danh sách từ khóa quét";
    return @"";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Hệ thống sẽ quét caption video. Nếu chứa bất kỳ từ khóa nào trên, video sẽ được tự động bình luận.";
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"TagCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
        cell.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.16 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    }
    if (indexPath.section == 0) {
        NSArray *tags = getKeywords();
        if (indexPath.row < tags.count) {
            cell.textLabel.text = tags[indexPath.row];
            cell.textLabel.textColor = [UIColor whiteColor];
        }
    } else {
        cell.textLabel.text = @"Khôi phục danh sách mặc định";
        cell.textLabel.textColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 0) {
        NSArray *tags = getKeywords();
        if (indexPath.row < tags.count) {
            NSString *tag = tags[indexPath.row];
            removeKeyword(tag);
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        resetKeywordsToDefault();
        [tableView reloadData];
        showToastBanner(@"Đã khôi phục hashtag mặc định", 1.5);
    }
}

@end

@interface LQSettingsViewController : UITableViewController
@end

@implementation LQSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cài đặt TikTok Mod";
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Xong" style:UIBarButtonItemStyleDone target:self action:@selector(dismissSelf)];
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 5; // Tự động bình luận
        case 1: return 4; // Tính năng Mod BHTikTok
        case 2: return 2; // Dọn dẹp & Bộ nhớ
        case 3: return 2; // Thống kê
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"TỰ ĐỘNG BÌNH LUẬN (AUTO-COMMENT)";
        case 1: return @"TÍNH NĂNG MOD & BẢO MẬT";
        case 2: return @"BỘ NHỚ & DỮ LIỆU";
        case 3: return @"THÔNG TIN";
        default: return @"";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.16 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:14.0];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Bật Auto Comment";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getAutoCommentEnabled();
            [sw addTarget:self action:@selector(toggleAutoComment:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Nội dung bình luận";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            NSString *t = getCommentText();
            if (t.length > 20) t = [[t substringToIndex:18] stringByAppendingString:@"..."];
            cell.detailTextLabel.text = t;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Danh sách Hashtag";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu từ khóa", (unsigned long)getKeywords().count];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Tự ghép hashtag vào cuối";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getAppendMatchedTag();
            [sw addTarget:self action:@selector(toggleAppendTag:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Tự động lướt video sau khi gửi";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getAutoScroll();
            [sw addTarget:self action:@selector(toggleAutoScroll:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Chặn quảng cáo (Ad Block)";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getHideAdsEnabled();
            [sw addTarget:self action:@selector(toggleHideAds:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Tải video không Watermark";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getRemoveWatermarkEnabled();
            [sw addTarget:self action:@selector(toggleWatermark:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Thanh tua cho mọi video";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getProgressBarEnabled();
            [sw addTarget:self action:@selector(toggleProgressBar:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Mở rộng độ dài bình luận";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getExtendedCommentEnabled();
            [sw addTarget:self action:@selector(toggleExtendedComment:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Dọn dẹp bộ nhớ đệm (Clean Cache)";
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.55 blue:1.0 alpha:1.0];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Xóa lịch sử video đã comment";
            cell.textLabel.textColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Số video đã comment";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu video", (unsigned long)sCommentedAwemeIDs.count];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Phiên bản";
            cell.detailTextLabel.text = @"v3.1.0 (Esign Ready)";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0 && indexPath.row == 1) {
        UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"Nội dung bình luận" message:@"Nhập nội dung muốn auto comment:" preferredStyle:UIAlertControllerStyleAlert];
        [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = getCommentText();
        }];
        [inputAlert addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            NSString *newText = inputAlert.textFields.firstObject.text;
            if (newText.length > 0) {
                setCommentText(newText);
                [self.tableView reloadData];
                showToastBanner(@"Đã lưu nội dung bình luận", 1.5);
            }
        }]];
        [inputAlert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:inputAlert animated:YES completion:nil];
    } else if (indexPath.section == 0 && indexPath.row == 2) {
        LQHashtagManagerViewController *vc = [[LQHashtagManagerViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        performCleanCache(^(double mbFreed) {
            showToastBanner([NSString stringWithFormat:@"Đã giải phóng %.1f MB bộ nhớ đệm", mbFreed], 2.5);
        });
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        [sCommentedAwemeIDs removeAllObjects];
        [self.tableView reloadData];
        showToastBanner(@"Đã xóa danh sách video đã comment", 1.5);
    }
}

- (void)toggleAutoComment:(UISwitch *)sw { setAutoCommentEnabled(sw.on); }
- (void)toggleAppendTag:(UISwitch *)sw { setAppendMatchedTag(sw.on); }
- (void)toggleAutoScroll:(UISwitch *)sw { setAutoScroll(sw.on); }
- (void)toggleHideAds:(UISwitch *)sw { setHideAdsEnabled(sw.on); }
- (void)toggleWatermark:(UISwitch *)sw { setRemoveWatermarkEnabled(sw.on); }
- (void)toggleProgressBar:(UISwitch *)sw { setProgressBarEnabled(sw.on); }
- (void)toggleExtendedComment:(UISwitch *)sw { setExtendedCommentEnabled(sw.on); }

@end

static void presentNativeSettingsUI(void) {
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

        LQSettingsViewController *settingsVC = [[LQSettingsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        if (@available(iOS 15.0, *)) {
            nav.sheetPresentationController.prefersGrabberVisible = YES;
        }
        [topVC presentViewController:nav animated:YES completion:nil];
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
// HOOK 1: AWEAwemeModel (CLEAN AD BLOCK & CAPTION TAG STORAGE)
// ==============================================================================

@interface NSObject (LQAwemeHook)
- (id)lq_initWithDictionary:(id)arg1 error:(id *)arg2;
- (id)lq_init;
- (BOOL)lq_isUserRecommendBigCard;
- (BOOL)lq_progressBarDraggable;
- (BOOL)lq_progressBarVisible;
@end

@implementation NSObject (LQAwemeHook)

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

- (id)lq_init {
    id orig = [self lq_init];
    if (getHideAdsEnabled() && orig) {
        @try {
            if ([orig respondsToSelector:@selector(isAds)]) {
                if ([[orig valueForKey:@"isAds"] boolValue]) {
                    return nil;
                }
            }
        } @catch (NSException *e) {}
    }
    return orig;
}

- (id)lq_initWithDictionary:(id)arg1 error:(id *)arg2 {
    id orig = [self lq_initWithDictionary:arg1 error:arg2];

    // CHẶN QUẢNG CÁO CHUẨN (KHÔNG ĐỤNG ĐẾN isAds METHOD ĐỂ TRÁNH HỎNG APP)
    if (getHideAdsEnabled() && orig) {
        BOOL isAdItem = NO;
        @try {
            if ([orig respondsToSelector:@selector(isAds)]) {
                isAdItem = [[orig valueForKey:@"isAds"] boolValue];
            }
        } @catch (NSException *e) {}

        if (!isAdItem && [arg1 isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)arg1;
            isAdItem = [dict[@"is_ads"] boolValue] ||
                       [dict[@"is_ad"] boolValue] ||
                       (dict[@"ad_info"] != nil) ||
                       (dict[@"raw_ad_data"] != nil) ||
                       [dict[@"commercial_type"] integerValue] > 0 ||
                       dict[@"ad_style"] != nil;
        }

        if (isAdItem) {
            NSLog(@"[TikTok-AdBlock] 🛡️ Loại bỏ triệt để video quảng cáo khỏi Feed!");
            return nil; // Trả về nil để TikTok loại khỏi danh sách video
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
// HOOK 2: BHTikTok Extra Features
// ==============================================================================

@interface NSObject (LQExtraFeaturesHook)
- (NSUInteger)lq_watermarkType;
- (void)lq_setWatermarkType:(NSUInteger)type;
- (NSUInteger)lq_maxLength;
@end

@implementation NSObject (LQExtraFeaturesHook)

- (NSUInteger)lq_watermarkType {
    if (getRemoveWatermarkEnabled()) return 1;
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
// COMMENT AUTOMATION ENGINE
// ==============================================================================

static UIButton *findTikTokCommentButtonOnScreen(void) {
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    NSMutableArray<UIButton *> *candidateButtons = [NSMutableArray array];

    UIWindow *window = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in scene.windows) { if (w.isKeyWindow) { window = w; break; } }
            if (window) break;
        }
    }
    if (!window) window = [UIApplication sharedApplication].windows.firstObject;
    if (!window) return nil;

    void (^scanViews)(UIView *) = ^(UIView *root) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
        while (queue.count > 0) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];

            if ([v isKindOfClass:[UIButton class]] && !v.hidden && v.alpha > 0.5) {
                UIButton *b = (UIButton *)v;
                CGRect r = [b convertRect:b.bounds toView:nil];
                if (r.origin.x > screenWidth * 0.70 &&
                    r.origin.y > 120 && r.origin.y < screenHeight - 110 &&
                    r.size.width >= 24 && r.size.width <= 90 &&
                    r.size.height >= 24 && r.size.height <= 90) {
                    [candidateButtons addObject:b];
                }
            }
            [queue addObjectsFromArray:v.subviews];
        }
    };
    scanViews(window);

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
        return candidateButtons[1];
    }
    return candidateButtons.firstObject;
}

static UIView *findActiveTextInput(UIView *root) {
    if (!root) return nil;
    if (([root isKindOfClass:[UITextView class]] || [root isKindOfClass:[UITextField class]]) && root.window != nil) {
        return root;
    }
    for (UIView *sub in root.subviews) {
        UIView *f = findActiveTextInput(sub);
        if (f) return f;
    }
    return nil;
}

static UIView *findCommentPlaceholderBar(UIView *root) {
    if (!root) return nil;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];

    void (^scanBottom)(UIView *) = ^(UIView *p) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:p];
        while (queue.count > 0) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            CGRect r = [v convertRect:v.bounds toView:nil];
            if (r.origin.y > screenHeight - 150 && r.size.width > 120 && r.size.height >= 26 && r.size.height <= 65) {
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

static UIButton *findSendButtonNearInput(UIView *root, UIView *inputView) {
    if (!root) return nil;
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];

    void (^scanBtns)(UIView *) = ^(UIView *p) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:p];
        while (queue.count > 0) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([v isKindOfClass:[UIButton class]] && !v.hidden && v.alpha > 0.5) {
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
            if (bRect.origin.x > inputRect.origin.x + inputRect.size.width - 60 && fabs(bRect.origin.y - inputRect.origin.y) < 40) {
                return b;
            }
        }
    }
    return nil;
}

static void fillTextIntoInput(UIView *inputView, NSString *text) {
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

static void executeRealCommentSubmission(UIWindow *window, NSString *finalMsg, UIView *cellView) {
    UIView *inputView = findActiveTextInput(window);

    void (^typeAndSend)(UIView *) = ^(UIView *activeInput) {
        if (!activeInput) return;
        [activeInput becomeFirstResponder];
        fillTextIntoInput(activeInput, finalMsg);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIButton *sendBtn = findSendButtonNearInput(window, activeInput);
            if (sendBtn) {
                [sendBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
                showToastBanner(@"Đã gửi bình luận thành công", 2.0);
            } else {
                if ([activeInput isKindOfClass:[UITextView class]]) {
                    UITextView *tv = (UITextView *)activeInput;
                    if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
                        [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(tv.text.length, 0) replacementText:@"\n"];
                    }
                }
                showToastBanner(@"Đã nhập bình luận", 2.0);
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
                    }
                }
            });
        });
    };

    if (inputView) {
        typeAndSend(inputView);
    } else {
        UIView *placeholder = findCommentPlaceholderBar(window);
        if (placeholder) {
            if ([placeholder respondsToSelector:@selector(sendActionsForControlEvents:)]) {
                [((UIControl *)placeholder) sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
            for (UIGestureRecognizer *g in placeholder.gestureRecognizers) {
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *recheckedInput = findActiveTextInput(window);
            typeAndSend(recheckedInput);
        });
    }
}

// ==============================================================================
// PRECISION TRIGGER: ONLY TRIGGER ON-SCREEN VISIBLE PLAYING CELL
// ==============================================================================

static BOOL isCellTrulyPlayingOnScreen(UIView *cellView) {
    if (!cellView || !cellView.window) return NO;
    CGRect rectInWindow = [cellView convertRect:cellView.bounds toView:nil];
    CGFloat screenCenterY = [UIScreen mainScreen].bounds.size.height / 2.0;
    // Kiểm tra xem cell có đang bao phủ điểm chính giữa màn hình hay không
    return (rectInWindow.origin.y <= screenCenterY && (rectInWindow.origin.y + rectInWindow.size.height) >= screenCenterY);
}

static void evaluateAndTriggerVideo(UIView *cellView, id model) {
    if (!getAutoCommentEnabled() || !model || !cellView) return;

    // 1. KIỂM TRA TỨC THÌ: CELL CÓ ĐANG NẰM CHÍNH GIỮA MÀN HÌNH KHÔNG?
    // Nếu cell chỉ đang được pre-render/pre-load ở ngoài màn hình -> BỎ QUA NGAY!
    if (!isCellTrulyPlayingOnScreen(cellView)) {
        return;
    }

    NSString *awemeId = objc_getAssociatedObject(model, "lq_aweme_id");
    if (!awemeId) {
        @try {
            awemeId = [model valueForKey:@"itemID"] ?: [model valueForKey:@"awemeId"] ?: [model valueForKey:@"aid"];
        } @catch (NSException *e) {}
    }
    if (!awemeId || [sCommentedAwemeIDs containsObject:awemeId]) return;

    NSString *caption = objc_getAssociatedObject(model, "lq_caption");
    if (!caption) {
        @try {
            caption = [model valueForKey:@"descriptionString"] ?: [model valueForKey:@"desc"] ?: [model valueForKey:@"title"];
        } @catch (NSException *e) {}
    }
    if (!caption || caption.length == 0) return;

    NSString *lower = [caption lowercaseString];
    NSString *matchedTag = nil;
    for (NSString *kw in getKeywords()) {
        if ([lower containsString:kw]) {
            matchedTag = kw;
            break;
        }
    }
    if (!matchedTag) return; // Không khớp từ khóa -> Bỏ qua

    // Khớp hashtag! Đánh dấu và chờ delay
    [sCommentedAwemeIDs addObject:awemeId];
    sCurrentlyPendingAwemeID = awemeId;
    sCurrentlyPendingMatchedTag = matchedTag;

    CGFloat delaySec = getCommentDelay();
    showToastBanner([NSString stringWithFormat:@"Khớp [%@] • Đang chờ %.1fs...", matchedTag, delaySec], delaySec + 0.3);

    NSString *baseText = getCommentText();
    NSMutableString *fullComment = [NSMutableString stringWithString:baseText];
    if (getAppendMatchedTag() && matchedTag.length > 0) {
        if (![matchedTag hasPrefix:@"#"]) {
            [fullComment appendFormat:@" #%@", matchedTag];
        } else {
            [fullComment appendFormat:@" %@", matchedTag];
        }
    }

    // 2. SAU KHI HẾT THỜI GIAN DELAY: KIỂM TRA LẠI LẦN NỮA!
    // Nếu người dùng đã lướt qua video khác rồi -> HỦY BỎ BÌNH LUẬN TRÁNH COMMENT NHẦM!
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySec * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!isCellTrulyPlayingOnScreen(cellView)) {
            NSLog(@"[TikTok-LQ] ⚠️ Người dùng đã lướt qua video khác, hủy lệnh comment!");
            return;
        }

        UIWindow *window = cellView.window ?: [UIApplication sharedApplication].windows.firstObject;
        UIButton *commentBtn = findTikTokCommentButtonOnScreen();
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
                executeRealCommentSubmission(window, fullComment, cellView);
            });
        } else {
            executeRealCommentSubmission(window, fullComment, cellView);
        }
    });
}

// ==============================================================================
// HOOK 3: Feed Cells
// ==============================================================================

@interface UIView (LQCellDisplayHook)
- (void)lq_configWithModel:(id)model;
- (void)lq_configureWithModel:(id)model;
@end

@implementation UIView (LQCellDisplayHook)

- (void)lq_configWithModel:(id)model {
    [self lq_configWithModel:model];
    setupHomeTabGesturesOnWindow(self.window);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        evaluateAndTriggerVideo(self, model);
    });
}

- (void)lq_configureWithModel:(id)model {
    [self lq_configureWithModel:model];
    setupHomeTabGesturesOnWindow(self.window);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        evaluateAndTriggerVideo(self, model);
    });
}

@end

// ==============================================================================
// INITIALIZER
// ==============================================================================

__attribute__((constructor))
static void initTikTokAutoCommentLienQuan(void) {
    @autoreleasepool {
        sCommentedAwemeIDs = [[NSMutableSet alloc] init];
        NSLog(@"[TikTok-LQ] Standalone AutoComment LQ v3.1.0 Loaded!");

        // 1. Swizzle AWEAwemeModel
        Class awemeCls = NSClassFromString(@"AWEAwemeModel");
        if (awemeCls) {
            SwizzleMethod(awemeCls, @selector(initWithDictionary:error:), @selector(lq_initWithDictionary:error:));
            SwizzleMethod(awemeCls, @selector(init), @selector(lq_init));
            if (class_getInstanceMethod(awemeCls, @selector(isUserRecommendBigCard))) {
                SwizzleMethod(awemeCls, @selector(isUserRecommendBigCard), @selector(lq_isUserRecommendBigCard));
            }
            if (class_getInstanceMethod(awemeCls, @selector(progressBarDraggable))) {
                SwizzleMethod(awemeCls, @selector(progressBarDraggable), @selector(lq_progressBarDraggable));
            }
            if (class_getInstanceMethod(awemeCls, @selector(progressBarVisible))) {
                SwizzleMethod(awemeCls, @selector(progressBarVisible), @selector(lq_progressBarVisible));
            }
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
        }

        // 3. Swizzle AWETextInputController (Comment Length)
        Class inputCls = NSClassFromString(@"AWETextInputController");
        if (inputCls) {
            if (class_getInstanceMethod(inputCls, @selector(maxLength))) {
                SwizzleMethod(inputCls, @selector(maxLength), @selector(lq_maxLength));
            }
        }

        // 4. Swizzle Feed Cells
        NSArray *cellClassNames = @[@"AWEFeedViewTemplateCell", @"AWEAwemeDetailTableViewCell", @"TTKFeedViewCell", @"AWEFeedCell"];
        for (NSString *clsName in cellClassNames) {
            Class cls = NSClassFromString(clsName);
            if (cls) {
                if (class_getInstanceMethod(cls, @selector(configWithModel:))) {
                    SwizzleMethod(cls, @selector(configWithModel:), @selector(lq_configWithModel:));
                }
                if (class_getInstanceMethod(cls, @selector(configureWithModel:))) {
                    SwizzleMethod(cls, @selector(configureWithModel:), @selector(lq_configureWithModel:));
                }
            }
        }

        // 5. Hiển thị thông báo hướng dẫn mở Menu
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
            setupHomeTabGesturesOnWindow(w);
            showToastBanner(@"Nhấn giữ hoặc chạm 2 lần vào 'Trang chủ' để mở Cài đặt", 4.0);
        });
    }
}
