#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <Photos/Photos.h>
#import <zlib.h>
#import <dlfcn.h>
#import <sys/stat.h>

#import "TikTokPlusPlus_Payload.h"

// ==============================================================================
// 1. HARDENED CYDIASUBSTRATE SHIM (PAC / ARM64 / ARM64E & INHERITANCE SAFE)
// ==============================================================================

/**
 * Hardened CydiaSubstrate Shim for Non-Jailbroken / Sideloaded iOS (arm64 & arm64e)
 *
 * Prevents superclass method pollution:
 * If `sel` is declared on a superclass rather than `_class`, we add the hook method
 * directly to `_class` instead of mutating the superclass `Method` object.
 * This guarantees sibling classes and system classes are never polluted or corrupted.
 */
__attribute__((weak, visibility("default")))
void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result) {
    if (!_class || !sel || !imp) {
        if (result) *result = NULL;
        return;
    }

    Method origMethod = class_getInstanceMethod(_class, sel);
    if (!origMethod) {
        // Method does not exist anywhere in class hierarchy; register safely
        const char *defaultType = "@@:@";
        class_addMethod(_class, sel, imp, defaultType);
        if (result) *result = NULL;
        return;
    }

    const char *typeEncoding = method_getTypeEncoding(origMethod);
    IMP origImp = method_getImplementation(origMethod);

    BOOL isDeclaredDirectly = NO;
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(_class, &methodCount);
    if (methodList) {
        for (unsigned int i = 0; i < methodCount; i++) {
            if (method_getName(methodList[i]) == sel) {
                isDeclaredDirectly = YES;
                break;
            }
        }
        free(methodList);
    }

    if (isDeclaredDirectly) {
        IMP prevImp = method_setImplementation(origMethod, imp);
        if (result) *result = prevImp ? prevImp : origImp;
    } else {
        // Inherited from superclass! Add hook directly to _class to isolate scope
        BOOL added = class_addMethod(_class, sel, imp, typeEncoding ? typeEncoding : "v@:");
        if (added) {
            if (result) *result = origImp;
        } else {
            IMP prevImp = class_replaceMethod(_class, sel, imp, typeEncoding ? typeEncoding : "v@:");
            if (result) *result = prevImp ? prevImp : origImp;
        }
    }
}

// ==============================================================================
// 2. EMBEDDED TIKTOK++ CORE LOADER (SIDELOAD RESILIENT)
// ==============================================================================

static void unpackAndLoadTikTokPlusPlus(void) {
    @autoreleasepool {
        // 1. Check if TikTokPlusPlus is already bundled or linked via Frameworks
        void *existingHandle = dlopen("TikTokPlusPlus.dylib", RTLD_NOLOAD);
        if (existingHandle) {
            NSLog(@"[TikTok++-AIO] 🚀 TikTok++ Core is already loaded in process!");
            return;
        }

        NSString *frameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
        NSString *bundledDylib = [frameworksPath stringByAppendingPathComponent:@"TikTokPlusPlus.dylib"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundledDylib]) {
            void *bHandle = dlopen([bundledDylib UTF8String], RTLD_NOW | RTLD_GLOBAL);
            if (bHandle) {
                NSLog(@"[TikTok++-AIO] 🚀 Loaded bundled TikTok++ from %@", bundledDylib);
                return;
            }
        }

        // 2. Unpack embedded payload to temp directory (fallback for TrollStore / dev environments)
        NSString *tmpDir = NSTemporaryDirectory();
        if (!tmpDir || tmpDir.length == 0) tmpDir = @"/tmp";
        NSString *destPath = [tmpDir stringByAppendingPathComponent:@"TikTokPlusPlus_Core.dylib"];

        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL needWrite = YES;
        if ([fm fileExistsAtPath:destPath]) {
            NSDictionary *attrs = [fm attributesOfItemAtPath:destPath error:nil];
            if ([attrs fileSize] == (unsigned long long)kTikTokPlusRawLength) {
                needWrite = NO;
            }
        }

        if (needWrite) {
            NSLog(@"[TikTok++-AIO] 📦 Unpacking TikTok++ core payload (%zu bytes)...", kTikTokPlusRawLength);
            Bytef *destBuf = (Bytef *)malloc(kTikTokPlusRawLength);
            if (!destBuf) {
                NSLog(@"[TikTok++-AIO] ❌ Out of memory while unpacking payload!");
                return;
            }

            uLongf destLen = (uLongf)kTikTokPlusRawLength;
            int zerr = uncompress(destBuf, &destLen, (const Bytef *)kTikTokPlusCompressedData, (uLong)kTikTokPlusCompressedLength);
            if (zerr != Z_OK) {
                NSLog(@"[TikTok++-AIO] ❌ zlib payload decompression error: %d", zerr);
                free(destBuf);
                return;
            }

            NSData *dylibData = [NSData dataWithBytesNoCopy:destBuf length:destLen freeWhenDone:YES];
            BOOL written = [dylibData writeToFile:destPath atomically:YES];
            if (!written) {
                NSLog(@"[TikTok++-AIO] ❌ Failed to write dylib to %@", destPath);
                return;
            }
            chmod([destPath UTF8String], 0755);
            NSLog(@"[TikTok++-AIO] ✅ Unpacked TikTok++ Core into %@", destPath);
        }

        void *handle = dlopen([destPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
        if (handle) {
            NSLog(@"[TikTok++-AIO] 🚀 Successfully loaded TikTok++ Core into process!");
        } else {
            const char *err = dlerror();
            NSLog(@"[TikTok++-AIO] ⚠️ dlopen fallback returned: %s", err ? err : "unknown");
        }
    }
}

// ==============================================================================
// 3. CONFIGURATION & PERSISTENCE (NSUserDefaults + Presets)
// ==============================================================================

#define PREF_ENABLED                @"lq_auto_comment_enabled"
#define PREF_TEMPLATES              @"lq_comment_templates_list"
#define PREF_ACTIVE_TEMPLATE        @"lq_active_template_idx"
#define PREF_RANDOM_TEMPLATE        @"lq_random_template_enabled"
#define PREF_TEXT                   @"lq_auto_comment_text" // Legacy single text key
#define PREF_KEYWORDS               @"lq_auto_comment_keywords"
#define PREF_AUTOSCROLL             @"lq_auto_comment_autoscroll"
#define PREF_APPEND_TAG             @"lq_auto_comment_append_tag"
#define PREF_DELAY                  @"lq_auto_comment_delay_sec"
#define PREF_HIDE_ADS               @"lq_hide_ads_enabled"
#define PREF_REMOVE_WATERMARK       @"lq_remove_watermark"
#define PREF_AUTO_PLAY              @"lq_auto_play_next"
#define PREF_PROGRESS_BAR           @"lq_progress_bar"
#define PREF_EXTENDED_COMMENT       @"lq_extended_comment"
#define PREF_TRANSPARENT_COMMENT    @"lq_transparent_comment"
#define PREF_FAKE_VERIFIED          @"lq_fake_verified"
#define PREF_ANTIBOT_SPINTAX        @"lq_antibot_spintax_enabled"
#define PREF_ANTIBOT_HUMAN_CADENCE  @"lq_antibot_human_cadence"

#define PREF_RANDOM_EMOJI           @"lq_comment_random_emoji"
#define PREF_INVISIBLE_HASH         @"lq_comment_invisible_hash"
#define PREF_MIN_WATCH_SEC          @"lq_min_watch_seconds"
#define PREF_DOWNLOAD_HD            @"lq_download_hd_enabled"

#define DEFAULT_KEYWORDS_STR @"#lienquan,#aov,#lienquanmobile,liên quân"

static NSArray<NSString *> *getDefaultCommentTemplates(void) {
    return @[
        @"{Nhập mã|Code nhận vé|Mã ưu đãi}: avsqjyM3n7 {nhận ngay 38 vé nhảy|nhận quà liền tay} {🔥|✨|👍}",
        @"Giao lưu chia sẻ kinh nghiệm leo rank Liên Quân nha anh em! {🎮|⚔️}",
        @"Clip đỉnh quá bạn ơi, cho mình xin bí quyết với ạ! {👏|🔥}"
    ];
}

static void registerDefaultPreferencesIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *defaults = @{
            PREF_ENABLED: @YES,
            PREF_TEMPLATES: getDefaultCommentTemplates(),
            PREF_ACTIVE_TEMPLATE: @0,
            PREF_RANDOM_TEMPLATE: @NO,
            PREF_KEYWORDS: DEFAULT_KEYWORDS_STR,
            PREF_AUTOSCROLL: @YES,
            PREF_APPEND_TAG: @NO,
            PREF_DELAY: @3.5,
            PREF_HIDE_ADS: @YES,
            PREF_REMOVE_WATERMARK: @YES,
            PREF_AUTO_PLAY: @NO,
            PREF_PROGRESS_BAR: @YES,
            PREF_EXTENDED_COMMENT: @YES,
            PREF_TRANSPARENT_COMMENT: @NO,
            PREF_FAKE_VERIFIED: @NO,
            PREF_ANTIBOT_SPINTAX: @YES,
            PREF_ANTIBOT_HUMAN_CADENCE: @YES
        };
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    });
}

static BOOL getAutoCommentEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_ENABLED];
}
static void setAutoCommentEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_ENABLED];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSArray<NSString *> *getCommentTemplates(void) {
    registerDefaultPreferencesIfNeeded();
    NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:PREF_TEMPLATES];
    if (!list || list.count == 0) {
        NSString *legacyText = [[NSUserDefaults standardUserDefaults] stringForKey:PREF_TEXT];
        if (legacyText && legacyText.length > 0) {
            list = @[legacyText];
        } else {
            list = getDefaultCommentTemplates();
        }
        [[NSUserDefaults standardUserDefaults] setObject:list forKey:PREF_TEMPLATES];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return list;
}
static void setCommentTemplates(NSArray<NSString *> *templates) {
    [[NSUserDefaults standardUserDefaults] setObject:(templates ?: @[]) forKey:PREF_TEMPLATES];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSInteger getActiveTemplateIndex(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] integerForKey:PREF_ACTIVE_TEMPLATE];
}
static void setActiveTemplateIndex(NSInteger idx) {
    [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:PREF_ACTIVE_TEMPLATE];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getRandomTemplateEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_RANDOM_TEMPLATE];
}
static void setRandomTemplateEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_RANDOM_TEMPLATE];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getAutoPlayNextEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_AUTO_PLAY];
}
static void setAutoPlayNextEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_AUTO_PLAY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getHideAdsEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_HIDE_ADS];
}
static void setHideAdsEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_HIDE_ADS];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getRemoveWatermarkEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_REMOVE_WATERMARK];
}
static void setRemoveWatermarkEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_REMOVE_WATERMARK];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getProgressBarEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_PROGRESS_BAR];
}
static void setProgressBarEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_PROGRESS_BAR];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getExtendedCommentEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_EXTENDED_COMMENT];
}
static void setExtendedCommentEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_EXTENDED_COMMENT];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getTransparentCommentEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_TRANSPARENT_COMMENT];
}
static void setTransparentCommentEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_TRANSPARENT_COMMENT];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getFakeVerifiedEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_FAKE_VERIFIED];
}
static void setFakeVerifiedEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_FAKE_VERIFIED];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSArray<NSString *> *getKeywords(void) {
    registerDefaultPreferencesIfNeeded();
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
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_AUTOSCROLL];
}
static void setAutoScroll(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_AUTOSCROLL];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getAppendMatchedTag(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_APPEND_TAG];
}
static void setAppendMatchedTag(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_APPEND_TAG];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


static BOOL getRandomEmojiEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_RANDOM_EMOJI] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_RANDOM_EMOJI];
}
static void setRandomEmojiEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_RANDOM_EMOJI];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getInvisibleHashEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_INVISIBLE_HASH] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_INVISIBLE_HASH];
}
static void setInvisibleHashEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_INVISIBLE_HASH];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static CGFloat getMinWatchSeconds(void) {
    CGFloat s = [[NSUserDefaults standardUserDefaults] floatForKey:PREF_MIN_WATCH_SEC];
    if (s < 1.0) return 3.0; // Mặc định 3.0s xem trước khi auto comment
    return s;
}
static void setMinWatchSeconds(CGFloat s) {
    [[NSUserDefaults standardUserDefaults] setFloat:s forKey:PREF_MIN_WATCH_SEC];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getDownloadHDEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PREF_DOWNLOAD_HD] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_DOWNLOAD_HD];
}
static void setDownloadHDEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_DOWNLOAD_HD];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static CGFloat getCommentDelay(void) {
    registerDefaultPreferencesIfNeeded();
    CGFloat d = [[NSUserDefaults standardUserDefaults] floatForKey:PREF_DELAY];
    if (d < 0.5) return 3.5;
    return d;
}
static void setCommentDelay(CGFloat d) {
    [[NSUserDefaults standardUserDefaults] setFloat:d forKey:PREF_DELAY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getSpintaxEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_ANTIBOT_SPINTAX];
}
static void setSpintaxEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_ANTIBOT_SPINTAX];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL getHumanCadenceEnabled(void) {
    registerDefaultPreferencesIfNeeded();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PREF_ANTIBOT_HUMAN_CADENCE];
}
static void setHumanCadenceEnabled(BOOL b) {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:PREF_ANTIBOT_HUMAN_CADENCE];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Runtime tracking
static NSMutableSet<NSString *> *sCommentedAwemeIDs = nil;
static id sCurrentlyActiveAwemeModel = nil;
static NSTimeInterval sCurrentWatchStartTime = 0;
static NSString *sCurrentlyPlayingAwemeID = nil;
static NSString *sCurrentlyPendingMatchedTag = nil;

// Anti-flood & rate limit tracking
static NSTimeInterval sLastCommentTimestamp = 0;
static NSUInteger sCommentsInCurrentHour = 0;
static NSTimeInterval sHourWindowStart = 0;
#define MAX_COMMENTS_PER_HOUR 25
#define MIN_COMMENT_COOLDOWN_SEC 18.0

// Forward declarations
static void presentNativeSettingsUI(void);
static void showToastBanner(NSString *message, CGFloat duration);

// ==============================================================================
// 4. ANTI-BOT EVASION ENGINES (SPINTAX, ENTROPY, VELOCITY THROTTLE)
// ==============================================================================

static NSString *expandSpintax(NSString *input) {
    if (!input || input.length == 0) return @"";
    NSMutableString *result = [input mutableCopy];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\{([^{}]+)\\}" options:0 error:nil];
    if (!regex) return result;

    while (YES) {
        NSTextCheckingResult *match = [regex firstMatchInString:result options:0 range:NSMakeRange(0, result.length)];
        if (!match) break;
        NSRange contentRange = [match rangeAtIndex:1];
        NSString *rawChoices = [result substringWithRange:contentRange];
        NSArray<NSString *> *choices = [rawChoices componentsSeparatedByString:@"|"];
        if (choices.count > 0) {
            uint32_t rIdx = arc4random_uniform((uint32_t)choices.count);
            NSString *chosen = choices[rIdx];
            [result replaceCharactersInRange:match.range withString:chosen];
        } else {
            [result replaceCharactersInRange:match.range withString:@""];
        }
    }
    return result;
}

static NSString *injectInvisibleEntropy(NSString *source) {
    if (!source || source.length == 0) return @"";
    static const unichar zeroWidthChars[] = { 0x200B, 0x200C, 0x200D, 0xFEFF };
    NSMutableString *mut = [source mutableCopy];
    int count = 1 + arc4random_uniform(3);
    for (int i = 0; i < count; i++) {
        unichar ch = zeroWidthChars[arc4random_uniform(4)];
        NSUInteger insertPos = arc4random_uniform((uint32_t)mut.length + 1);
        [mut insertString:[NSString stringWithCharacters:&ch length:1] atIndex:insertPos];
    }
    return mut;
}

static NSString *getRawCommentTemplate(void) {
    NSArray<NSString *> *list = getCommentTemplates();
    if (list.count == 0) return @"";
    if (getRandomTemplateEnabled()) {
        uint32_t idx = arc4random_uniform((uint32_t)list.count);
        return list[idx];
    }
    NSInteger idx = getActiveTemplateIndex();
    if (idx >= 0 && idx < (NSInteger)list.count) {
        return list[idx];
    }
    return list.firstObject;
}

static NSString *getCommentText(void) {
    NSString *raw = getRawCommentTemplate();
    if (!raw || raw.length == 0) return @"";
    return getSpintaxEnabled() ? expandSpintax(raw) : raw;
}

static void setCommentText(NSString *t) {
    if (!t) return;
    NSMutableArray *list = [NSMutableArray arrayWithArray:getCommentTemplates()];
    NSInteger idx = getActiveTemplateIndex();
    if (idx >= 0 && idx < (NSInteger)list.count) {
        list[idx] = t;
    } else {
        [list addObject:t];
    }
    setCommentTemplates(list);
    [[NSUserDefaults standardUserDefaults] setObject:t forKey:PREF_TEXT];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// ==============================================================================
// 5. VISUAL TOAST BANNER (CLEAN & MINIMALIST)
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
// WATERMARK-FREE HD MEDIA DOWNLOAD ENGINE (1080P H264/H265, ALBUMS, AUDIO)
// ==============================================================================

@interface LQMediaDownloadItem : NSObject
@property (nonatomic, copy) NSString *videoURL;
@property (nonatomic, copy) NSString *audioURL;
@property (nonatomic, strong) NSArray<NSString *> *photoURLs;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *authorName;
@property (nonatomic, copy) NSString *gearName;
@property (nonatomic, assign) BOOL isH265;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@end

@implementation LQMediaDownloadItem
@end

static LQMediaDownloadItem *extractPristineMediaFromAwemeModel(id model) {
    if (!model) return nil;
    LQMediaDownloadItem *item = [[LQMediaDownloadItem alloc] init];

    @try {
        item.title = [model valueForKey:@"descriptionString"] ?: [model valueForKey:@"desc"] ?: [model valueForKey:@"title"] ?: @"TikTok_Video";
        id author = [model valueForKey:@"author"];
        item.authorName = [author valueForKey:@"nickname"] ?: [author valueForKey:@"uniqueID"] ?: @"creator";
    } @catch (NSException *e) {}

    // 1. Quét Album ảnh (Slide photo mode)
    @try {
        id album = [model valueForKey:@"photoAlbum"];
        if (album) {
            id photos = [album valueForKey:@"photos"];
            if ([photos isKindOfClass:[NSArray class]] && [photos count] > 0) {
                NSMutableArray<NSString *> *pURLs = [NSMutableArray array];
                for (id p in photos) {
                    id originPhoto = [p valueForKey:@"originPhotoURL"] ?: [p valueForKey:@"displayImageURL"] ?: [p valueForKey:@"watermarkPhotoURL"];
                    if (originPhoto) {
                        NSArray *urlList = [originPhoto valueForKey:@"originURLList"] ?: [originPhoto valueForKey:@"urlList"];
                        if ([urlList isKindOfClass:[NSArray class]] && urlList.count > 0) {
                            NSString *u = urlList.firstObject;
                            if (u && [u isKindOfClass:[NSString class]] && u.length > 0) {
                                [pURLs addObject:u];
                            }
                        }
                    }
                }
                if (pURLs.count > 0) {
                    item.photoURLs = pURLs;
                }
            }
        }
    } @catch (NSException *e) {}

    // 2. Quét Âm thanh / Nhạc nền (Music audio track)
    @try {
        id music = [model valueForKey:@"music"];
        if (music) {
            id musicPlayURL = [music valueForKey:@"playURL"];
            if (musicPlayURL) {
                NSArray *urls = [musicPlayURL valueForKey:@"originURLList"] ?: [musicPlayURL valueForKey:@"urlList"];
                if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                    item.audioURL = urls.firstObject;
                }
            }
        }
    } @catch (NSException *e) {}

    // 3. Quét Video HD không logo (play_addr vs download_addr, bitRate 1080p, H.264/H.265)
    // Lưu ý: play_addr là luồng phát video trực tiếp cho player, hoàn toàn KHÔNG có Watermark (TikTok render watermark bằng UI layer).
    // Ngược lại, download_addr là video được nén kèm logo đóng dấu. Do đó ưu tiên tuyệt đối lấy từ bitRate / play_addr.
    @try {
        id video = [model valueForKey:@"video"];
        if (video) {
            id bitRates = [video valueForKey:@"bitRate"] ?: [video valueForKey:@"bitRateList"] ?: [video valueForKey:@"bitrateModels"];

            id bestBitrateObj = nil;
            NSInteger bestScore = -1;

            if ([bitRates isKindOfClass:[NSArray class]] && [bitRates count] > 0) {
                for (id br in bitRates) {
                    NSInteger bitrateVal = [[br valueForKey:@"bitrate"] integerValue];
                    NSInteger qualityType = [[br valueForKey:@"qualityType"] integerValue];
                    NSString *gear = [br valueForKey:@"gearName"] ?: @"";
                    BOOL isBytevc1 = [[br valueForKey:@"isBytevc1"] boolValue]; // ByteVC1 = H.265
                    NSInteger w = [[br valueForKey:@"width"] integerValue];
                    NSInteger h = [[br valueForKey:@"height"] integerValue];

                    NSInteger score = 0;
                    if (qualityType >= 1080 || [gear localizedCaseInsensitiveContainsString:@"1080"] || h >= 1080 || w >= 1080) {
                        score += 1000000;
                    } else if (qualityType >= 720 || [gear localizedCaseInsensitiveContainsString:@"720"] || h >= 720 || w >= 720) {
                        score += 500000;
                    }
                    if (!isBytevc1) {
                        score += 50000; // Ưu tiên H.264 MP4 tương thích rộng hơn nếu chất lượng ngang nhau
                    }
                    score += (bitrateVal / 1000);

                    if (score > bestScore) {
                        bestScore = score;
                        bestBitrateObj = br;
                    }
                }
            }

            if (bestBitrateObj) {
                item.gearName = [bestBitrateObj valueForKey:@"gearName"] ?: @"HD 1080p";
                item.isH265 = [[bestBitrateObj valueForKey:@"isBytevc1"] boolValue];
                item.width = [[bestBitrateObj valueForKey:@"width"] integerValue];
                item.height = [[bestBitrateObj valueForKey:@"height"] integerValue];

                id playAddr = [bestBitrateObj valueForKey:@"playAddr"] ?: [bestBitrateObj valueForKey:@"playAddrH264"] ?: [bestBitrateObj valueForKey:@"playAddrBytevc1"];
                if (playAddr) {
                    NSArray *urls = [playAddr valueForKey:@"originURLList"] ?: [playAddr valueForKey:@"urlList"];
                    if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                        for (NSString *u in urls) {
                            if ([u isKindOfClass:[NSString class]] && ![u localizedCaseInsensitiveContainsString:@"watermark"]) {
                                item.videoURL = u;
                                break;
                            }
                        }
                        if (!item.videoURL && urls.count > 0) item.videoURL = urls.firstObject;
                    }
                }
            }

            // Dự phòng 1: video.playAddrH264
            if (!item.videoURL) {
                id p264 = [video valueForKey:@"playAddrH264"];
                if (p264) {
                    NSArray *urls = [p264 valueForKey:@"originURLList"] ?: [p264 valueForKey:@"urlList"];
                    if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) item.videoURL = urls.firstObject;
                }
            }
            // Dự phòng 2: video.playAddrBytevc1 (H.265)
            if (!item.videoURL) {
                id p265 = [video valueForKey:@"playAddrBytevc1"];
                if (p265) {
                    NSArray *urls = [p265 valueForKey:@"originURLList"] ?: [p265 valueForKey:@"urlList"];
                    if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                        item.videoURL = urls.firstObject;
                        item.isH265 = YES;
                    }
                }
            }
            // Dự phòng 3: video.playURL / playAddr (Stream gốc không đóng dấu)
            if (!item.videoURL) {
                id playURL = [video valueForKey:@"playURL"] ?: [video valueForKey:@"playAddr"];
                if (playURL) {
                    NSArray *urls = [playURL valueForKey:@"originURLList"] ?: [playURL valueForKey:@"urlList"];
                    if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                        item.videoURL = urls.firstObject;
                    } else if ([playURL respondsToSelector:@selector(recommendUrl)]) {
                        NSURL *rec = [playURL performSelector:@selector(recommendUrl)];
                        if (rec) item.videoURL = [rec absoluteString];
                    }
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[TikTok-Media] Lỗi trích xuất video URL: %@", e);
    }

    return item;
}

@interface LQMediaDownloader : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSURLSessionDownloadTask *, NSString *> *taskFileTypes;
@property (nonatomic, strong) NSMutableDictionary<NSURLSessionDownloadTask *, NSString *> *taskTitles;
+ (instancetype)shared;
- (void)downloadVideoWithURL:(NSString *)url title:(NSString *)title isH265:(BOOL)isH265;
- (void)downloadAudioWithURL:(NSString *)url title:(NSString *)title;
- (void)downloadPhotosWithURLs:(NSArray<NSString *> *)urls title:(NSString *)title;
@end

@implementation LQMediaDownloader

+ (instancetype)shared {
    static LQMediaDownloader *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[LQMediaDownloader alloc] init];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 45.0;
        self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
        self.taskFileTypes = [NSMutableDictionary dictionary];
        self.taskTitles = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)downloadVideoWithURL:(NSString *)urlStr title:(NSString *)title isH265:(BOOL)isH265 {
    if (!urlStr || urlStr.length == 0) {
        showToastBanner(@"❌ Không tìm thấy link video HD!", 2.5);
        return;
    }
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    showToastBanner(@"⏳ Đang kết nối tải Video HD...", 3.0);
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url];
    self.taskFileTypes[task] = isH265 ? @"video_h265" : @"video_h264";
    self.taskTitles[task] = title ?: @"TikTok_Video";
    [task resume];
}

- (void)downloadAudioWithURL:(NSString *)urlStr title:(NSString *)title {
    if (!urlStr || urlStr.length == 0) {
        showToastBanner(@"❌ Không có link âm thanh để tải!", 2.5);
        return;
    }
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    showToastBanner(@"⏳ Đang tải Audio...", 3.0);
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url];
    self.taskFileTypes[task] = @"audio";
    self.taskTitles[task] = title ?: @"TikTok_Audio";
    [task resume];
}

- (void)downloadPhotosWithURLs:(NSArray<NSString *> *)urls title:(NSString *)title {
    if (!urls || urls.count == 0) {
        showToastBanner(@"❌ Không có ảnh nào để tải!", 2.5);
        return;
    }
    showToastBanner([NSString stringWithFormat:@"⏳ Đang tải trọn bộ %lu ảnh...", (unsigned long)urls.count], 3.5);

    __block NSInteger completed = 0;
    NSInteger total = urls.count;

    for (NSString *uStr in urls) {
        NSURL *u = [NSURL URLWithString:uStr];
        if (!u) continue;
        [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
            if (data && !err) {
                UIImage *img = [UIImage imageWithData:data];
                if (img) {
                    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                        [PHAssetCreationRequest creationRequestForAssetFromImage:img];
                    } completionHandler:^(BOOL success, NSError *pErr) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completed++;
                            if (completed == total) {
                                showToastBanner([NSString stringWithFormat:@"✅ Đã lưu trọn bộ %lu ảnh vào Thư viện!", (unsigned long)total], 3.0);
                            }
                        });
                    }];
                }
            }
        }] resume];
    }
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite > 0) {
        float prog = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
        int pct = (int)(prog * 100);
        if (pct % 25 == 0 || pct == 99) {
            NSString *type = self.taskFileTypes[downloadTask];
            NSString *name = [type containsString:@"video"] ? @"Video HD" : @"Audio";
            showToastBanner([NSString stringWithFormat:@"⏳ Đang tải %@: %d%%", name, pct], 1.5);
        }
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    NSString *type = self.taskFileTypes[downloadTask] ?: @"video_h264";
    NSString *title = self.taskTitles[downloadTask] ?: @"TikTok";
    [self.taskFileTypes removeObjectForKey:downloadTask];
    [self.taskTitles removeObjectForKey:downloadTask];

    NSString *tmpDir = NSTemporaryDirectory();
    NSString *ext = [type isEqualToString:@"audio"] ? @"mp3" : @"mp4";
    NSString *destPath = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%u.%@", title, arc4random_uniform(10000), ext]];
    NSURL *destURL = [NSURL fileURLWithPath:destPath];

    [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
    NSError *moveErr = nil;
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:destURL error:&moveErr];

    if (moveErr) {
        showToastBanner(@"❌ Lỗi lưu file tải về!", 2.5);
        return;
    }

    if ([type isEqualToString:@"audio"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[destURL] applicationActivities:nil];
            UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
            [w.rootViewController presentViewController:act animated:YES completion:nil];
            showToastBanner(@"✅ Đã tải xong Audio! Mở bảng chia sẻ để lưu.", 3.0);
        });
    } else {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:destURL];
                } completionHandler:^(BOOL success, NSError *saveErr) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                            showToastBanner(@"✅ Đã lưu Video HD không Watermark vào Thư viện ảnh!", 3.0);
                        } else {
                            showToastBanner([NSString stringWithFormat:@"❌ Lỗi lưu thư viện: %@", saveErr.localizedDescription], 3.0);
                        }
                        [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
                    });
                }];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    showToastBanner(@"⚠️ Vui lòng cấp quyền Thư viện ảnh trong Cài đặt!", 3.5);
                });
            }
        }];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        [self.taskFileTypes removeObjectForKey:(NSURLSessionDownloadTask *)task];
        [self.taskTitles removeObjectForKey:(NSURLSessionDownloadTask *)task];
        showToastBanner([NSString stringWithFormat:@"❌ Lỗi kết nối tải file: %@", error.localizedDescription], 3.0);
    }
}

@end

static void presentMediaDownloadMenuForModel(id model, UIViewController *presentingVC) {
    if (!model) {
        showToastBanner(@"⚠️ Không tìm thấy dữ liệu video hiện tại!", 2.0);
        return;
    }

    LQMediaDownloadItem *item = extractPristineMediaFromAwemeModel(model);
    if (!item) {
        showToastBanner(@"⚠️ Không thể trích xuất media!", 2.0);
        return;
    }

    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"🎬 TẢI MEDIA TIKTOK HD"
                                                                         message:@"Trích xuất trực tiếp từ máy chủ gốc (Không Watermark)"
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    if (item.videoURL.length > 0) {
        NSString *vTitle = item.isH265 ? @"🎬 Tải Video HD 1080p (HEVC Không Watermark)" : @"🎬 Tải Video HD 1080p (MP4 Không Watermark)";
        [actionSheet addAction:[UIAlertAction actionWithTitle:vTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            [[LQMediaDownloader shared] downloadVideoWithURL:item.videoURL title:item.title isH265:item.isH265];
        }]];

        [actionSheet addAction:[UIAlertAction actionWithTitle:@"🔗 Sao chép Link Video HD gốc" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            [UIPasteboard generalPasteboard].string = item.videoURL;
            showToastBanner(@"📋 Đã sao chép link video HD vào bộ nhớ tạm!", 2.5);
        }]];
    }

    if (item.photoURLs.count > 0) {
        [actionSheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📸 Tải trọn bộ Album (%lu ảnh HD)", (unsigned long)item.photoURLs.count] style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            [[LQMediaDownloader shared] downloadPhotosWithURLs:item.photoURLs title:item.title];
        }]];
    }

    if (item.audioURL.length > 0) {
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"🎵 Tải Nhạc nền / Audio (MP3)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            [[LQMediaDownloader shared] downloadAudioWithURL:item.audioURL title:item.title];
        }]];
    }

    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

    if (!presentingVC) {
        UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
        presentingVC = w.rootViewController;
        while (presentingVC.presentedViewController) presentingVC = presentingVC.presentedViewController;
    }

    [presentingVC presentViewController:actionSheet animated:YES completion:nil];
}

// ==============================================================================
// 6. CACHE ENGINE: CALCULATION & SAFE PURGING (SESSION PRESERVING)
// ==============================================================================

static NSString *formatByteSize(uint64_t bytes) {
    if (bytes >= 1024ULL * 1024ULL * 1024ULL) {
        return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    } else if (bytes >= 1024ULL * 1024ULL) {
        return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    } else if (bytes >= 1024ULL) {
        return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
    } else {
        return [NSString stringWithFormat:@"%llu B", (unsigned long long)bytes];
    }
}

static uint64_t calculateAppCacheSizeBytes(void) {
    uint64_t totalBytes = 0;
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1. Library/Caches (Purgeable caches, skip preferences, cookies, webkit auth)
    NSString *cachesDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    if (cachesDir) {
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:cachesDir];
        NSString *sub;
        while ((sub = [en nextObject])) {
            if ([sub localizedCaseInsensitiveContainsString:@"Preferences"] ||
                [sub localizedCaseInsensitiveContainsString:@"Cookies"] ||
                [sub localizedCaseInsensitiveContainsString:@"WebKit"]) {
                continue;
            }
            NSString *fp = [cachesDir stringByAppendingPathComponent:sub];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fp error:nil];
            if ([attrs fileType] == NSFileTypeRegular) {
                totalBytes += [attrs fileSize];
            }
        }
    }

    // 2. tmp (Temporary downloads/buffers, preserve payload dylib)
    NSString *tmpDir = NSTemporaryDirectory();
    if (tmpDir) {
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:tmpDir];
        NSString *sub;
        while ((sub = [en nextObject])) {
            if ([sub isEqualToString:@"TikTokPlusPlus_Core.dylib"]) continue;
            NSString *fp = [tmpDir stringByAppendingPathComponent:sub];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fp error:nil];
            if ([attrs fileType] == NSFileTypeRegular) {
                totalBytes += [attrs fileSize];
            }
        }
    }

    // 3. Documents media files (.mp4, .mov, .tmp, etc., exclude account/auth/db)
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (docDir) {
        NSArray *mediaExts = @[@"mp4", @"mov", @"tmp", @"m4a", @"mp3", @"aac", @"jpg", @"jpeg", @"png", @"log"];
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:docDir];
        NSString *sub;
        while ((sub = [en nextObject])) {
            NSString *ext = [sub pathExtension].lowercaseString;
            if ([mediaExts containsObject:ext]) {
                if (![sub localizedCaseInsensitiveContainsString:@"auth"] &&
                    ![sub localizedCaseInsensitiveContainsString:@"account"] &&
                    ![sub localizedCaseInsensitiveContainsString:@"session"] &&
                    ![sub localizedCaseInsensitiveContainsString:@"cookie"]) {
                    NSString *fp = [docDir stringByAppendingPathComponent:sub];
                    NSDictionary *attrs = [fm attributesOfItemAtPath:fp error:nil];
                    if ([attrs fileType] == NSFileTypeRegular) {
                        totalBytes += [attrs fileSize];
                    }
                }
            }
        }
    }

    // 4. URL Cache disk usage
    @try {
        totalBytes += [[NSURLCache sharedURLCache] currentDiskUsage];
    } @catch (NSException *e) {}

    return totalBytes;
}

static uint64_t performSafeAppCacheClean(void) {
    uint64_t freedBytes = 0;
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1. Library/Caches
    NSString *cachesDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    if (cachesDir) {
        NSArray *items = [fm contentsOfDirectoryAtPath:cachesDir error:nil];
        for (NSString *item in items) {
            if ([item localizedCaseInsensitiveContainsString:@"Preferences"] ||
                [item localizedCaseInsensitiveContainsString:@"Cookies"] ||
                [item localizedCaseInsensitiveContainsString:@"WebKit"]) {
                continue;
            }
            NSString *fp = [cachesDir stringByAppendingPathComponent:item];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:fp isDirectory:&isDir]) {
                if (isDir) {
                    NSDirectoryEnumerator *en = [fm enumeratorAtPath:fp];
                    NSString *sub;
                    while ((sub = [en nextObject])) {
                        NSString *subFp = [fp stringByAppendingPathComponent:sub];
                        NSDictionary *attrs = [fm attributesOfItemAtPath:subFp error:nil];
                        if ([attrs fileType] == NSFileTypeRegular) {
                            freedBytes += [attrs fileSize];
                        }
                    }
                    [fm removeItemAtPath:fp error:nil];
                } else {
                    NSDictionary *attrs = [fm attributesOfItemAtPath:fp error:nil];
                    freedBytes += [attrs fileSize];
                    [fm removeItemAtPath:fp error:nil];
                }
            }
        }
    }

    // 2. tmp
    NSString *tmpDir = NSTemporaryDirectory();
    if (tmpDir) {
        NSArray *items = [fm contentsOfDirectoryAtPath:tmpDir error:nil];
        for (NSString *item in items) {
            if ([item isEqualToString:@"TikTokPlusPlus_Core.dylib"]) continue;
            NSString *fp = [tmpDir stringByAppendingPathComponent:item];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:fp isDirectory:&isDir]) {
                if (isDir) {
                    NSDirectoryEnumerator *en = [fm enumeratorAtPath:fp];
                    NSString *sub;
                    while ((sub = [en nextObject])) {
                        NSString *subFp = [fp stringByAppendingPathComponent:sub];
                        NSDictionary *attrs = [fm attributesOfItemAtPath:subFp error:nil];
                        if ([attrs fileType] == NSFileTypeRegular) {
                            freedBytes += [attrs fileSize];
                        }
                    }
                    [fm removeItemAtPath:fp error:nil];
                } else {
                    NSDictionary *attrs = [fm attributesOfItemAtPath:fp error:nil];
                    freedBytes += [attrs fileSize];
                    [fm removeItemAtPath:fp error:nil];
                }
            }
        }
    }

    // 3. Documents media files
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (docDir) {
        NSArray *mediaExts = @[@"mp4", @"mov", @"tmp", @"m4a", @"mp3", @"aac", @"jpg", @"jpeg", @"png", @"log"];
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:docDir];
        NSString *sub;
        while ((sub = [en nextObject])) {
            NSString *ext = [sub pathExtension].lowercaseString;
            if ([mediaExts containsObject:ext]) {
                if (![sub localizedCaseInsensitiveContainsString:@"auth"] &&
                    ![sub localizedCaseInsensitiveContainsString:@"account"] &&
                    ![sub localizedCaseInsensitiveContainsString:@"session"] &&
                    ![sub localizedCaseInsensitiveContainsString:@"cookie"]) {
                    NSString *fp = [docDir stringByAppendingPathComponent:sub];
                    NSDictionary *attrs = [fm attributesOfItemAtPath:fp error:nil];
                    if ([attrs fileType] == NSFileTypeRegular) {
                        freedBytes += [attrs fileSize];
                        [fm removeItemAtPath:fp error:nil];
                    }
                }
            }
        }
    }

    // 4. URL Cache
    @try {
        freedBytes += [[NSURLCache sharedURLCache] currentDiskUsage];
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
    } @catch (NSException *e) {}

    return freedBytes;
}

static void calculateAppCacheSize(void (^completion)(uint64_t bytes, NSString *formattedSize)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint64_t b = calculateAppCacheSizeBytes();
        NSString *s = formatByteSize(b);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(b, s);
        });
    });
}

static void performCleanCache(void (^completion)(double mbFreed)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint64_t b = performSafeAppCacheClean();
        double mb = (double)b / (1024.0 * 1024.0);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(mb);
        });
    });
}

// ==============================================================================
// 7. GESTURE MANAGER: HOME TAB LONG-PRESS (>=0.5s) & DOUBLE-TAP
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

        // Bottom-left corner: Home (Trang chủ) tab area (bottom 110pt, left 28% width)
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

        // Bottom-left corner: Home (Trang chủ) tab area
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
    lp.cancelsTouchesInView = NO;
    lp.delegate = [LQGestureDelegateHandler shared];
    [window addGestureRecognizer:lp];

    UITapGestureRecognizer *dt = [[UITapGestureRecognizer alloc] initWithTarget:[LQGestureDelegateHandler class] action:@selector(handleDoubleTapHelper:)];
    dt.numberOfTapsRequired = 2;
    dt.cancelsTouchesInView = NO;
    dt.delegate = [LQGestureDelegateHandler shared];
    [window addGestureRecognizer:dt];

    UITapGestureRecognizer *twoFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:[LQGestureDelegateHandler class] action:@selector(handleTwoFingerDoubleTapHelper:)];
    twoFingerTap.numberOfTouchesRequired = 2;
    twoFingerTap.numberOfTapsRequired = 2;
    twoFingerTap.delegate = [LQGestureDelegateHandler shared];
    [window addGestureRecognizer:twoFingerTap];

    objc_setAssociatedObject(window, "lq_gestures_installed", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation LQGestureDelegateHandler (ActionHelpers)
+ (void)handleLongPressHelper:(UILongPressGestureRecognizer *)rec { handleHomeTabLongPress(rec); }
+ (void)handleDoubleTapHelper:(UITapGestureRecognizer *)rec { handleHomeTabDoubleTap(rec); }

+ (void)handleTwoFingerDoubleTapHelper:(UITapGestureRecognizer *)rec {
    if (rec.state == UIGestureRecognizerStateEnded) {
        UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [fb impactOccurred];
        presentMediaDownloadMenuForModel(sCurrentlyActiveAwemeModel, nil);
    }
}
@end

// ==============================================================================
// 8. APPLE INSET GROUPED SETTINGS UI (DARK MODE, SLEEK BADGES, CLEAN SCREEN)
// ==============================================================================

static UIImage *createSettingsIconBadge(NSString *systemImageName, NSString *glyph, UIColor *bgColor) {
    CGSize size = CGSizeMake(29.0, 29.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);

    UIBezierPath *bgPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:6.5];
    [bgColor setFill];
    [bgPath fill];

    BOOL drawn = NO;
    if (@available(iOS 13.0, *)) {
        if (systemImageName && systemImageName.length > 0) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14.5 weight:UIImageSymbolWeightMedium];
            UIImage *sysImg = [[UIImage systemImageNamed:systemImageName withConfiguration:cfg] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
            if (sysImg) {
                CGFloat x = (size.width - sysImg.size.width) / 2.0;
                CGFloat y = (size.height - sysImg.size.height) / 2.0;
                [sysImg drawInRect:CGRectMake(x, y, sysImg.size.width, sysImg.size.height)];
                drawn = YES;
            }
        }
    }

    if (!drawn && glyph && glyph.length > 0) {
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:14.0],
            NSForegroundColorAttributeName: [UIColor whiteColor]
        };
        CGSize glyphSize = [glyph sizeWithAttributes:attrs];
        CGFloat x = (size.width - glyphSize.width) / 2.0;
        CGFloat y = (size.height - glyphSize.height) / 2.0;
        [glyph drawInRect:CGRectMake(x, y, glyphSize.width, glyphSize.height) withAttributes:attrs];
    }

    UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return res;
}

// ------------------------------------------------------------------------------
// COMMENT TEMPLATES MANAGER VIEW CONTROLLER
// ------------------------------------------------------------------------------

@interface LQCommentTemplatesViewController : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSString *> *templates;
@end

@implementation LQCommentTemplatesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Mẫu bình luận";
    if (@available(iOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.22 alpha:0.6];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addNewTemplateTapped)];
    self.templates = [NSMutableArray arrayWithArray:getCommentTemplates()];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.templates = [NSMutableArray arrayWithArray:getCommentTemplates()];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1; // Random rotation mode
        case 1: return self.templates.count; // Templates list
        case 2: return 2; // Actions
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"CHẾ ĐỘ GỬI BÌNH LUẬN";
        case 1: return @"DANH SÁCH MẪU BÌNH LUẬN";
        case 2: return @"TÁC VỤ";
        default: return @"";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return @"Khi bật xoay vòng ngẫu nhiên, mỗi video khớp hashtag sẽ được comment bằng một mẫu khác nhau trong danh sách để hạn chế spam.";
        case 1:
            return @"Chạm vào mẫu để đặt làm mẫu mặc định hoặc chỉnh sửa. Vuốt sang trái để xóa mẫu.";
        default:
            return @"";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        cell.textLabel.text = @"Xoay vòng ngẫu nhiên mẫu";
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        cell.detailTextLabel.text = @"Bốc ngẫu nhiên 1 mẫu cho mỗi lần comment";

        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = getRandomTemplateEnabled();
        sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
        [sw addTarget:self action:@selector(toggleRandomMode:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    } else if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular];
        cell.textLabel.numberOfLines = 2;
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];

        if (indexPath.row < self.templates.count) {
            cell.textLabel.text = self.templates[indexPath.row];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Mẫu #%ld", (long)(indexPath.row + 1)];
        }

        BOOL isRandom = getRandomTemplateEnabled();
        if (!isRandom && indexPath.row == getActiveTemplateIndex()) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.tintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        } else {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        return cell;
    } else {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"+ Thêm mẫu bình luận mới...";
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.55 blue:1.0 alpha:1.0];
        } else {
            cell.textLabel.text = @"Khôi phục mẫu mặc định";
            cell.textLabel.textColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
        }
        return cell;
    }
}

- (void)toggleRandomMode:(UISwitch *)sw {
    setRandomTemplateEnabled(sw.on);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        if (indexPath.row >= self.templates.count) return;
        NSString *tpl = self.templates[indexPath.row];

        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Mẫu #%ld", (long)(indexPath.row + 1)] message:tpl preferredStyle:UIAlertControllerStyleActionSheet];

        [sheet addAction:[UIAlertAction actionWithTitle:@"Đặt làm mẫu mặc định" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            setRandomTemplateEnabled(NO);
            setActiveTemplateIndex(indexPath.row);
            [self.tableView reloadData];
            showToastBanner([NSString stringWithFormat:@"Đã chọn Mẫu #%ld làm mặc định", (long)(indexPath.row + 1)], 1.5);
        }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"Chỉnh sửa nội dung" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            [self showEditTemplateDialogForIndex:indexPath.row];
        }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

        if (sheet.popoverPresentationController) {
            UITableViewCell *c = [tableView cellForRowAtIndexPath:indexPath];
            sheet.popoverPresentationController.sourceView = c ?: self.view;
            sheet.popoverPresentationController.sourceRect = c ? c.bounds : CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
        }
        [self presentViewController:sheet animated:YES completion:nil];
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            [self addNewTemplateTapped];
        } else if (indexPath.row == 2) {
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Khôi phục mặc định?" message:@"Danh sách mẫu sẽ được hoàn trả về các mẫu chuẩn ban đầu." preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Khôi phục" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
                setCommentTemplates(getDefaultCommentTemplates());
                setActiveTemplateIndex(0);
                setRandomTemplateEnabled(NO);
                self.templates = [NSMutableArray arrayWithArray:getCommentTemplates()];
                [self.tableView reloadData];
                showToastBanner(@"Đã khôi phục các mẫu mặc định", 1.5);
            }]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:confirm animated:YES completion:nil];
        }
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 1) {
        if (self.templates.count <= 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Không thể xóa" message:@"Bạn cần giữ lại ít nhất 1 mẫu bình luận trong danh sách." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Đã hiểu" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }

        [self.templates removeObjectAtIndex:indexPath.row];
        setCommentTemplates(self.templates);
        if (getActiveTemplateIndex() >= self.templates.count) {
            setActiveTemplateIndex(0);
        }
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)addNewTemplateTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thêm Mẫu Bình Luận" message:@"Nhập nội dung mẫu bình luận mới (hỗ trợ Spintax):" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Nội dung bình luận...";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Thêm" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *val = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (val.length > 0) {
            [self.templates addObject:val];
            setCommentTemplates(self.templates);
            [self.tableView reloadData];
            showToastBanner(@"Đã thêm mẫu bình luận mới", 1.5);
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showEditTemplateDialogForIndex:(NSInteger)index {
    if (index >= self.templates.count) return;
    NSString *curr = self.templates[index];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sửa Mẫu Bình Luận" message:@"Cập nhật nội dung mẫu bình luận:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = curr;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *val = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (val.length > 0) {
            self.templates[index] = val;
            setCommentTemplates(self.templates);
            [self.tableView reloadData];
            showToastBanner(@"Đã cập nhật mẫu bình luận", 1.5);
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// ------------------------------------------------------------------------------
// HASHTAG FILTERS MANAGER VIEW CONTROLLER
// ------------------------------------------------------------------------------

@interface LQHashtagManagerViewController : UITableViewController
@end

@implementation LQHashtagManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Quản lý Hashtag";
    if (@available(iOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.22 alpha:0.6];

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
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"DANH SÁCH TỪ KHÓA QUÉT";
    return @"TÁC VỤ";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Tweak quét cả phần mô tả (caption) và mảng textExtra của video. Nếu khớp, video sẽ được tự động bình luận an toàn.";
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"TagCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
        cell.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    }
    if (indexPath.section == 0) {
        NSArray *tags = getKeywords();
        if (indexPath.row < tags.count) {
            cell.textLabel.text = tags[indexPath.row];
            cell.textLabel.textColor = [UIColor whiteColor];
            cell.imageView.image = createSettingsIconBadge(@"number", @"#", [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1.0]);
        }
    } else {
        cell.imageView.image = nil;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"+ Thêm từ khóa mới...";
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.55 blue:1.0 alpha:1.0];
            cell.textLabel.textAlignment = NSTextAlignmentLeft;
        } else {
            cell.textLabel.text = @"Khôi phục danh sách mặc định";
            cell.textLabel.textColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
        }
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
        if (indexPath.row == 0) {
            [self addTagTapped];
        } else {
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Khôi phục mặc định?" message:@"Danh sách hashtag sẽ được đặt lại theo các từ khóa Liên Quân chuẩn." preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Khôi phục" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
                resetKeywordsToDefault();
                [self.tableView reloadData];
                showToastBanner(@"Đã khôi phục hashtag mặc định", 1.5);
            }]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:confirm animated:YES completion:nil];
        }
    }
}

@end

// ------------------------------------------------------------------------------
// MAIN TWEAK SETTINGS VIEW CONTROLLER (INSET GROUPED DARK MODE)
// ------------------------------------------------------------------------------

@interface LQSettingsViewController : UITableViewController {
    NSString *_cachedSizeText;
}
@end

@implementation LQSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cài đặt TikTok Mod";
    if (@available(iOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.22 alpha:0.6];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Xong" style:UIBarButtonItemStyleDone target:self action:@selector(dismissSelf)];
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];

    _cachedSizeText = @"Đang tính...";
    [self refreshAppCacheSize];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [self refreshAppCacheSize];
}

- (void)refreshAppCacheSize {
    calculateAppCacheSize(^(uint64_t bytes, NSString *formattedSize) {
        self->_cachedSizeText = formattedSize;
        if (self.isViewLoaded && self.view.window) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
        }
    });
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 10; // Tự động bình luận (Nâng cấp đầy đủ)
        case 1: return 8;  // Tính năng Mod BHTikTok & Media HD
        case 2: return 2; // Dọn dẹp & Bộ nhớ
        case 3: return 2; // Thông tin
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"TỰ ĐỘNG BÌNH LUẬN (AUTO-COMMENT)";
        case 1: return @"TÍNH NĂNG BHTIKTOK MOD";
        case 2: return @"BỘ NHỚ & DỮ LIỆU";
        case 3: return @"THÔNG TIN & KÍCH HOẠT";
        default: return @"";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Hệ thống tự động phát hiện video khớp từ khóa để gửi bình luận an toàn, chống bị khóa nick.";
        case 1: return @"Các tính năng nâng cao trải nghiệm xem, tua video và tải video không dính watermark.";
        case 2: return @"Dọn dẹp an toàn bộ nhớ đệm (video cache, ảnh tạm). Dữ liệu đăng nhập và tài khoản được bảo vệ 100%.";
        case 3: return @"Mẹo: Bạn có thể nhấn giữ (>=0.5s) hoặc chạm 2 lần vào nút 'Trang chủ' ở góc dưới bên trái để mở cài đặt này.";
        default: return @"";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"LQSettingValue1Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = [UIColor colorWithRed:0.60 green:0.60 blue:0.64 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];

        UIView *selBg = [[UIView alloc] init];
        selBg.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
        cell.selectedBackgroundView = selBg;
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.detailTextLabel.text = @"";
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Bật Auto Comment";
            cell.imageView.image = createSettingsIconBadge(@"message.fill", @"💬", [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getAutoCommentEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleAutoComment:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Mẫu bình luận (Templates)";
            cell.imageView.image = createSettingsIconBadge(@"doc.text.fill", @"📝", [UIColor colorWithRed:0.69 green:0.32 blue:0.87 alpha:1.0]);
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            if (getRandomTemplateEnabled()) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Ngẫu nhiên (%lu mẫu)", (unsigned long)getCommentTemplates().count];
            } else {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Mẫu #%ld", (long)(getActiveTemplateIndex() + 1)];
            }
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Bộ lọc Hashtag & Từ khóa";
            cell.imageView.image = createSettingsIconBadge(@"number", @"#", [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1.0]);
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu từ khóa", (unsigned long)getKeywords().count];
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Xem tối thiểu trước khi gửi";
            cell.imageView.image = createSettingsIconBadge(@"eye.fill", @"👁", [UIColor colorWithRed:0.0 green:0.58 blue:1.0 alpha:1.0]);
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"> %.1fs", getMinWatchSeconds()];
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"Thời gian chờ gửi (Delay)";
            cell.imageView.image = createSettingsIconBadge(@"clock.fill", @"⏱", [UIColor colorWithRed:0.35 green:0.34 blue:0.84 alpha:1.0]);
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1fs", getCommentDelay()];
        } else if (indexPath.row == 6) {
            cell.textLabel.text = @"Tự ghép hashtag vào cuối";
            cell.imageView.image = createSettingsIconBadge(@"tag.fill", @"🏷", [UIColor colorWithRed:0.19 green:0.69 blue:0.78 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getAppendMatchedTag();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleAppendTag:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 7) {
            cell.textLabel.text = @"Chống spam: Thêm Emoji ngẫu nhiên";
            cell.imageView.image = createSettingsIconBadge(@"face.smiling.fill", @"😊", [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getRandomEmojiEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleRandomEmoji:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 7) {
            cell.textLabel.text = @"Chống spam: Mã băm ẩn Zero-Width";
            cell.imageView.image = createSettingsIconBadge(@"lock.shield.fill", @"🔒", [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getInvisibleHashEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleInvisibleHash:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 8) {
            cell.textLabel.text = @"Anti-Bot Spintax & Jitter";
            cell.imageView.image = createSettingsIconBadge(@"shuffle", @"🔀", [UIColor colorWithRed:0.69 green:0.32 blue:0.87 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getSpintaxEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleSpintax:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 9) {
            cell.textLabel.text = @"Tự động lướt video sau khi gửi";
            cell.imageView.image = createSettingsIconBadge(@"arrow.up.circle.fill", @"⬆️", [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getAutoScroll();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleAutoScroll:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Chặn sạch quảng cáo (Ad Block Pro)";
            cell.imageView.image = createSettingsIconBadge(@"shield.fill", @"🛡", [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getHideAdsEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleHideAds:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"🎬 Menu Tải Media HD hiện tại";
            cell.imageView.image = createSettingsIconBadge(@"arrow.down.circle.fill", @"⬇️", [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]);
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.detailTextLabel.text = @"Tải 1080p, Album, Nhạc";
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Tải video không Watermark";
            cell.imageView.image = createSettingsIconBadge(@"arrow.down.to.line.circle.fill", @"⬇️", [UIColor colorWithRed:0.33 green:0.75 blue:0.94 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getRemoveWatermarkEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleWatermark:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Tự động chuyển video (Auto Play)";
            cell.imageView.image = createSettingsIconBadge(@"play.rectangle.fill", @"▶️", [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getAutoPlayNextEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleAutoPlay:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Thanh tua cho mọi video";
            cell.imageView.image = createSettingsIconBadge(@"slider.horizontal.below.rectangle", @"⏩", [UIColor colorWithRed:1.0 green:0.80 blue:0.0 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getProgressBarEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleProgressBar:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"Mở rộng bình luận (1000 ký tự)";
            cell.imageView.image = createSettingsIconBadge(@"text.bubble.fill", @"💬", [UIColor colorWithRed:1.0 green:0.18 blue:0.46 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getExtendedCommentEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleExtendedComment:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 6) {
            cell.textLabel.text = @"Khung bình luận trong suốt";
            cell.imageView.image = createSettingsIconBadge(@"circle.lefthalf.filled", @"🌓", [UIColor colorWithRed:0.69 green:0.32 blue:0.87 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getTransparentCommentEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleTransparentComment:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 7) {
            cell.textLabel.text = @"Hiển thị tích xanh tài khoản";
            cell.imageView.image = createSettingsIconBadge(@"checkmark.seal.fill", @"✓", [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]);
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = getFakeVerifiedEnabled();
            sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            [sw addTarget:self action:@selector(toggleFakeVerified:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Dọn dẹp bộ nhớ đệm (Clean Cache)";
            cell.imageView.image = createSettingsIconBadge(@"trash.fill", @"🗑", [UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1.0]);
            cell.detailTextLabel.text = _cachedSizeText ?: @"Đang tính...";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Xóa lịch sử video đã comment";
            cell.imageView.image = createSettingsIconBadge(@"arrow.counterclockwise", @"↺", [UIColor colorWithRed:0.55 green:0.55 blue:0.58 alpha:1.0]);
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu video", (unsigned long)sCommentedAwemeIDs.count];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Cách mở Cài đặt";
            cell.imageView.image = createSettingsIconBadge(@"hand.tap.fill", @"👆", [UIColor colorWithRed:0.55 green:0.55 blue:0.58 alpha:1.0]);
            cell.detailTextLabel.text = @"Chạm đúp / Giữ Trang chủ";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Phiên bản Tweak";
            cell.imageView.image = createSettingsIconBadge(@"info.circle.fill", @"ℹ️", [UIColor colorWithRed:0.55 green:0.55 blue:0.58 alpha:1.0]);
            cell.detailTextLabel.text = @"v4.2.0 (Apple Inset Pro)";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 1) {
            LQCommentTemplatesViewController *vc = [[LQCommentTemplatesViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == 3) {
            LQHashtagManagerViewController *vc = [[LQHashtagManagerViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == 4) {
            [self showDelayPickerAlert];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            [self promptCleanCacheAction];
        } else if (indexPath.row == 2) {
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Xóa lịch sử comment?" message:@"Xóa danh sách ID các video đã gửi comment trong phiên làm việc này để bạn có thể comment lại." preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Xóa lịch sử" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
                [sCommentedAwemeIDs removeAllObjects];
                [self.tableView reloadData];
                showToastBanner(@"Đã xóa danh sách video đã comment", 1.5);
            }]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:confirm animated:YES completion:nil];
        }
    }
}


- (void)showMinWatchPickerAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thời gian xem tối thiểu" message:@"Chỉ tự động comment trên các video người dùng dừng lại xem vượt quá ngưỡng này (tránh comment khi lướt nhanh):" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *options = @[@(1.0), @(2.0), @(3.0), @(4.0), @(5.0), @(8.0), @(10.0)];
    CGFloat current = getMinWatchSeconds();

    for (NSNumber *opt in options) {
        CGFloat val = [opt floatValue];
        NSString *title = [NSString stringWithFormat:@"%.1f giây %@", val, (fabs(val - current) < 0.1) ? @"(Đang chọn)" : @""];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            setMinWatchSeconds(val);
            [self.tableView reloadData];
            showToastBanner([NSString stringWithFormat:@"Đã đặt thời gian xem tối thiểu: %.1fs", val], 1.5);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.tableView;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleRandomEmoji:(UISwitch *)sw {
    setRandomEmojiEnabled(sw.on);
    showToastBanner(sw.on ? @"Đã bật thêm Emoji ngẫu nhiên chống trùng lặp" : @"Đã tắt thêm Emoji ngẫu nhiên", 1.5);
}

- (void)toggleInvisibleHash:(UISwitch *)sw {
    setInvisibleHashEnabled(sw.on);
    showToastBanner(sw.on ? @"Đã bật chèn mã băm ẩn Zero-Width chống kiểm duyệt spam" : @"Đã tắt mã băm ẩn", 1.5);
}

- (void)showDelayPickerAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thời gian chờ gửi bình luận" message:@"Chọn khoảng thời gian trễ trước khi nhập & gửi comment sau khi video tải:" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *options = @[@(1.0), @(1.5), @(2.0), @(2.5), @(3.0), @(3.5), @(5.0), @(8.0)];
    CGFloat currentDelay = getCommentDelay();
    for (NSNumber *num in options) {
        CGFloat d = [num doubleValue];
        NSString *title = [NSString stringWithFormat:@"%.1f giây%@", d, (fabs(d - currentDelay) < 0.05 ? @" ✓" : @"")];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            setCommentDelay(d);
            [self.tableView reloadData];
            showToastBanner([NSString stringWithFormat:@"Đã đặt thời gian chờ: %.1fs", d], 1.5);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Tùy chỉnh số giây..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Tùy chỉnh thời gian chờ" message:@"Nhập số giây trễ (từ 0.5s đến 30.0s):" preferredStyle:UIAlertControllerStyleAlert];
        [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.keyboardType = UIKeyboardTypeDecimalPad;
            tf.text = [NSString stringWithFormat:@"%.1f", getCommentDelay()];
        }];
        [input addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            CGFloat val = [input.textFields.firstObject.text doubleValue];
            if (val < 0.5) val = 0.5;
            if (val > 30.0) val = 30.0;
            setCommentDelay(val);
            [self.tableView reloadData];
            showToastBanner([NSString stringWithFormat:@"Đã đặt thời gian chờ: %.1fs", val], 1.5);
        }]];
        [input addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:input animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

    if (alert.popoverPresentationController) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
        alert.popoverPresentationController.sourceView = cell ?: self.view;
        alert.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptCleanCacheAction {
    NSString *sizeStr = _cachedSizeText ?: @"Đang tính...";
    NSString *msg = [NSString stringWithFormat:@"Hiện tại ứng dụng đang lưu trữ %@ bộ nhớ đệm (video cache, ảnh và dữ liệu tạm).\n\nQuá trình này sẽ giải phóng dung lượng bộ nhớ mà KHÔNG làm đăng xuất tài khoản TikTok của bạn.", sizeStr];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Dọn dẹp bộ nhớ đệm?" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Dọn dẹp ngay" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        showToastBanner(@"Đang dọn dẹp bộ nhớ đệm...", 1.2);
        performCleanCache(^(double mbFreed) {
            self->_cachedSizeText = @"0 KB";
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
            UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
            [fb impactOccurred];
            showToastBanner([NSString stringWithFormat:@"Đã giải phóng thành công %.1f MB bộ nhớ đệm!", mbFreed], 2.5);
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleAutoComment:(UISwitch *)sw { setAutoCommentEnabled(sw.on); }
- (void)toggleAppendTag:(UISwitch *)sw { setAppendMatchedTag(sw.on); }
- (void)toggleSpintax:(UISwitch *)sw { setSpintaxEnabled(sw.on); }
- (void)toggleAutoScroll:(UISwitch *)sw { setAutoScroll(sw.on); }
- (void)toggleHideAds:(UISwitch *)sw { setHideAdsEnabled(sw.on); }
- (void)toggleWatermark:(UISwitch *)sw { setRemoveWatermarkEnabled(sw.on); }
- (void)toggleAutoPlay:(UISwitch *)sw { setAutoPlayNextEnabled(sw.on); }
- (void)toggleProgressBar:(UISwitch *)sw { setProgressBarEnabled(sw.on); }
- (void)toggleExtendedComment:(UISwitch *)sw { setExtendedCommentEnabled(sw.on); }
- (void)toggleTransparentComment:(UISwitch *)sw { setTransparentCommentEnabled(sw.on); }
- (void)toggleFakeVerified:(UISwitch *)sw { setFakeVerifiedEnabled(sw.on); }

@end

// ------------------------------------------------------------------------------
// SETTINGS PRESENTATION TRIGGER
// ------------------------------------------------------------------------------

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

        // Avoid presenting duplicate settings controllers
        if ([topVC isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)topVC;
            if ([nav.topViewController isKindOfClass:[LQSettingsViewController class]]) {
                return;
            }
        }
        if ([topVC isKindOfClass:[LQSettingsViewController class]]) {
            return;
        }

        LQSettingsViewController *settingsVC = [[LQSettingsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheet = nav.sheetPresentationController;
            sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
        }
        if (@available(iOS 13.0, *)) {
            nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
            [appearance configureWithDefaultBackground];
            appearance.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:0.95];
            appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
            appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
            nav.navigationBar.standardAppearance = appearance;
            nav.navigationBar.scrollEdgeAppearance = appearance;
            nav.navigationBar.compactAppearance = appearance;
        }
        nav.navigationBar.tintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        [topVC presentViewController:nav animated:YES completion:nil];
    });
}


// 9. SAFE METHOD SWIZZLING ENGINE (ARM64 / ARM64E / PAC SAFE)
// ==============================================================================

/**
 * Superclass-safe atomic method swizzler.
 * If targetCls inherits origSEL, adds the method directly to targetCls rather than
 * swapping the superclass method implementation.
 */
static BOOL TTKSafeSwizzle(Class targetCls, SEL origSEL, SEL newSEL) {
    if (!targetCls || !origSEL || !newSEL) return NO;
    Method origMethod = class_getInstanceMethod(targetCls, origSEL);
    Method newMethod = class_getInstanceMethod(targetCls, newSEL);
    if (!origMethod || !newMethod) return NO;

    const char *origTypes = method_getTypeEncoding(origMethod);
    const char *newTypes = method_getTypeEncoding(newMethod);

    BOOL didAdd = class_addMethod(targetCls,
                                  origSEL,
                                  method_getImplementation(newMethod),
                                  newTypes ? newTypes : origTypes);
    if (didAdd) {
        class_replaceMethod(targetCls,
                            newSEL,
                            method_getImplementation(origMethod),
                            origTypes);
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
    return YES;
}

// ==============================================================================
// 10. COMMENT AUTOMATION & HUMAN INTERACTION SIMULATION
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

            if ([v isKindOfClass:[UIButton class]] && !v.hidden && v.alpha > 0.4) {
                UIButton *b = (UIButton *)v;
                CGRect r = [b convertRect:b.bounds toView:nil];
                if (r.origin.x > screenWidth * 0.65 &&
                    r.origin.y > 100 && r.origin.y < screenHeight - 100 &&
                    r.size.width >= 20 && r.size.width <= 90 &&
                    r.size.height >= 20 && r.size.height <= 90) {
                    [candidateButtons addObject:b];
                }
            }
            [queue addObjectsFromArray:v.subviews];
        }
    };
    scanViews(window);

    if (candidateButtons.count == 0) return nil;

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

    [candidateButtons sortUsingComparator:^NSComparisonResult(UIButton *b1, UIButton *b2) {
        CGRect r1 = [b1 convertRect:b1.bounds toView:nil];
        CGRect r2 = [b2 convertRect:b2.bounds toView:nil];
        if (r1.origin.y < r2.origin.y) return NSOrderedAscending;
        if (r1.origin.y > r2.origin.y) return NSOrderedDescending;
        return NSOrderedSame;
    }];

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

/**
 * Safe comment placeholder bar resolver.
 * Replaces private ivar introspection (_targets) with public UIControl & view hierarchy traversal.
 */
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
            if (r.origin.y > screenHeight - 160 && r.size.width > 100 && r.size.height >= 24 && r.size.height <= 70) {
                if ([v isKindOfClass:[UIControl class]] || [v isKindOfClass:[UIButton class]] || [v isKindOfClass:[UITextField class]] || [v isKindOfClass:[UITextView class]]) {
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
            if ([v isKindOfClass:[UIButton class]] && !v.hidden && v.alpha > 0.4) {
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
            if (bRect.origin.x > inputRect.origin.x + inputRect.size.width - 60 && fabs(bRect.origin.y - inputRect.origin.y) < 45) {
                return b;
            }
        }
    }
    return nil;
}

/**
 * Simulates a realistic human touch cycle:
 * TouchDown -> human contact duration (65ms - 110ms) -> TouchUpInside.
 * Provides authentic touch event telemetry to bypass ByteDance ACTION_WITHOUT_TOUCH_EVENT filters.
 */
static void simulateHumanTap(UIControl *control, void (^completion)(void)) {
    if (!control) {
        if (completion) completion();
        return;
    }
    [control sendActionsForControlEvents:UIControlEventTouchDown];
    NSTimeInterval tapDwell = 0.065 + ((arc4random_uniform(45)) / 1000.0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(tapDwell * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (completion) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), completion);
        }
    });
}

/**
 * Human Typing Simulator:
 * Types character-by-character via UIKeyInput insertText: with variable stochastic delays
 * (50ms - 90ms for letters, 130ms - 200ms for spaces/emojis).
 * Dispatches proper text delegate lifecycle notifications identically to native iOS keyboard.
 */
static void simulateHumanTyping(UIView *activeInput, NSString *text, void (^completion)(void)) {
    if (!activeInput || !text || text.length == 0) {
        if (completion) completion();
        return;
    }
    [activeInput becomeFirstResponder];

    if (!getHumanCadenceEnabled()) {
        // Instant input mode
        if ([activeInput isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)activeInput;
            tv.text = text;
            if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
                [tv.delegate textViewDidChange:tv];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
        } else if ([activeInput isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)activeInput;
            tf.text = text;
            [tf sendActionsForControlEvents:UIControlEventEditingChanged];
        }
        if (completion) completion();
        return;
    }

    // Human cadence mode: incremental insertion
    __block NSUInteger currentIndex = 0;
    NSUInteger totalLen = text.length;

    __block __weak void (^weakTypeNextCharacter)(void);
    void (^typeNextCharacter)(void);
    weakTypeNextCharacter = typeNextCharacter = ^{
        if (currentIndex >= totalLen) {
            // Typing complete, brief pause before submitting
            NSTimeInterval finishPause = 0.35 + (arc4random_uniform(250) / 1000.0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(finishPause * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (completion) completion();
            });
            return;
        }

        NSRange charRange = [text rangeOfComposedCharacterSequenceAtIndex:currentIndex];
        NSString *glyph = [text substringWithRange:charRange];
        currentIndex += charRange.length;

        if ([activeInput conformsToProtocol:@protocol(UIKeyInput)] && [activeInput respondsToSelector:@selector(insertText:)]) {
            [(id<UIKeyInput>)activeInput insertText:glyph];
        } else if ([activeInput isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)activeInput;
            tv.text = [tv.text stringByAppendingString:glyph];
            if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
                [tv.delegate textViewDidChange:tv];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
        } else if ([activeInput isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)activeInput;
            tf.text = [tf.text stringByAppendingString:glyph];
            [tf sendActionsForControlEvents:UIControlEventEditingChanged];
        }

        // Stochastic delay per keystroke
        NSTimeInterval keyDelay = 0.045 + (arc4random_uniform(45) / 1000.0);
        if ([glyph isEqualToString:@" "] || [glyph isEqualToString:@","] || [glyph isEqualToString:@"."]) {
            keyDelay += 0.080 + (arc4random_uniform(60) / 1000.0);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(keyDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            void (^strongType)(void) = weakTypeNextCharacter;
            if (strongType) strongType();
        });
    };

    typeNextCharacter();
}

static void executeRealCommentSubmission(UIWindow *window, NSString *finalMsg, NSString *targetAwemeId) {
    UIView *inputView = findActiveTextInput(window);

    void (^typeAndSend)(UIView *) = ^(UIView *activeInput) {
        if (!activeInput) return;

        simulateHumanTyping(activeInput, finalMsg, ^{
            UIButton *sendBtn = findSendButtonNearInput(window, activeInput);
            if (sendBtn) {
                simulateHumanTap(sendBtn, ^{
                    showToastBanner(@"✅ Đã gửi bình luận an toàn (Anti-Bot Active)!", 2.0);
                    sLastCommentTimestamp = [[NSDate date] timeIntervalSince1970];
                    sCommentsInCurrentHour++;
                });
            } else {
                if ([activeInput isKindOfClass:[UITextView class]]) {
                    UITextView *tv = (UITextView *)activeInput;
                    if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
                        [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(tv.text.length, 0) replacementText:@"\n"];
                    }
                }
                showToastBanner(@"✅ Đã nhập bình luận thành công!", 2.0);
                sLastCommentTimestamp = [[NSDate date] timeIntervalSince1970];
                sCommentsInCurrentHour++;
            }

            // Post-comment dwell time: realistic delay before closing or scrolling
            NSTimeInterval postDwell = 2.0 + (arc4random_uniform(150) / 100.0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(postDwell * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [activeInput resignFirstResponder];

                if (getAutoScroll()) {
                    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                            for (UIWindow *w in scene.windows) {
                                UIViewController *root = w.rootViewController;
                                if ([root respondsToSelector:@selector(scrollToNextVideo)]) {
                                    #pragma clang diagnostic push
                                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                    [root performSelector:@selector(scrollToNextVideo)];
                                    #pragma clang diagnostic pop
                                    return;
                                }
                            }
                        }
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
            UIView *innerInput = findActiveTextInput(placeholder);
            if (innerInput) {
                [innerInput becomeFirstResponder];
            } else if ([placeholder isKindOfClass:[UIControl class]]) {
                simulateHumanTap((UIControl *)placeholder, nil);
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *recheckedInput = findActiveTextInput(window);
            typeAndSend(recheckedInput);
        });
    }
}

// ==============================================================================
// 11. UNIVERSAL VIDEO & HASHTAG PROCESSOR
// ==============================================================================

static NSString *stripAccentsAndLowercase(NSString *src) {
    if (!src) return @"";
    NSMutableString *str = [src mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)str, NULL, kCFStringTransformStripCombiningMarks, NO);
    return [str lowercaseString];
}

static NSMutableArray<NSDate *> *sCommentTimestamps = nil;
static NSTimeInterval sLastCommentTime = 0.0;

static BOOL checkRateLimitAllowsComment(void) {
    if (!sCommentTimestamps) {
        sCommentTimestamps = [[NSMutableArray alloc] init];
    }
    NSDate *now = [NSDate date];
    NSTimeInterval nowTime = [now timeIntervalSinceReferenceDate];

    // Cooldown check (minimum 18 seconds between any two comments)
    if (sLastCommentTime > 0.0 && (nowTime - sLastCommentTime) < 18.0) {
        NSLog(@"[TikTok-LQ] ⚠️ Rate limit: Giãn cách tối thiểu 18s giữa 2 comment.");
        return NO;
    }

    // Purge timestamps older than 1 hour (3600 seconds)
    NSMutableArray *fresh = [NSMutableArray array];
    for (NSDate *ts in sCommentTimestamps) {
        if ([now timeIntervalSinceDate:ts] < 3600.0) {
            [fresh addObject:ts];
        }
    }
    sCommentTimestamps = fresh;

    // Hourly cap (maximum 25 comments per hour)
    if (sCommentTimestamps.count >= 25) {
        NSLog(@"[TikTok-LQ] ⚠️ Rate limit: Đã đạt giới hạn 25 comment/giờ.");
        return NO;
    }

    [sCommentTimestamps addObject:now];
    sLastCommentTime = nowTime;
    return YES;
}

static NSTimeInterval calculateRealisticWatchDelay(id model) {
    NSTimeInterval duration = 15.0;
    @try {
        if ([model respondsToSelector:@selector(video)]) {
            id video = [model valueForKey:@"video"];
            if (video) {
                duration = [[video valueForKey:@"duration"] doubleValue];
                if (duration > 1000.0) duration /= 1000.0;
            }
        }
    } @catch (NSException *e) {}

    double ratio = 0.25 + ((double)(arc4random_uniform(15)) / 100.0);
    NSTimeInterval target = duration * ratio;
    double jitter = ((double)(arc4random_uniform(1500)) / 1000.0) - 0.5;
    target += jitter;
    if (target < 3.5) target = 3.5;
    if (target > 12.0) target = 12.0;
    return target;
}

static NSString *generateAntiBotCommentText(NSString *baseTemplate, NSString *matchedTag) {
    if (!baseTemplate || baseTemplate.length == 0) {
        baseTemplate = getCommentText();
    }
    if (!baseTemplate || baseTemplate.length == 0) {
        baseTemplate = @"Nhập mã để được nhận 38 vé nhảy: avsqjyM3n7";
    }
    NSString *expanded = getSpintaxEnabled() ? expandSpintax(baseTemplate) : baseTemplate;
    if (matchedTag && matchedTag.length > 0) {
        expanded = [expanded stringByReplacingOccurrencesOfString:@"{tag}" withString:matchedTag];
    }
    return getInvisibleHashEnabled() ? injectInvisibleEntropy(expanded) : expanded;
}


static void processVideoModelForAutoComment(id model) {
    if (!model) return;
    sCurrentlyActiveAwemeModel = model;

    if (!getAutoCommentEnabled()) return;

    NSString *itemId = nil;
    @try {
        itemId = [model valueForKey:@"itemID"] ?: [model valueForKey:@"awemeId"] ?: [model valueForKey:@"aid"];
        if (itemId) itemId = [NSString stringWithFormat:@"%@", itemId];
    } @catch (NSException *e) {}

    if (!itemId || itemId.length == 0) return;
    if ([sCommentedAwemeIDs containsObject:itemId]) return;

    // 1. Quét text mô tả (caption / title)
    NSMutableString *searchableText = [NSMutableString string];
    @try {
        NSString *desc = [model valueForKey:@"descriptionString"] ?: [model valueForKey:@"desc"] ?: [model valueForKey:@"title"];
        if (desc) [searchableText appendFormat:@"%@ ", desc];
    } @catch (NSException *e) {}

    // 2. Quét hashtags trong mảng textExtra
    @try {
        id textExtras = [model valueForKey:@"textExtra"];
        if ([textExtras isKindOfClass:[NSArray class]]) {
            for (id extra in (NSArray *)textExtras) {
                NSString *ht = [extra valueForKey:@"hashtagName"] ?: [extra valueForKey:@"tag"];
                if (ht && [ht isKindOfClass:[NSString class]]) {
                    [searchableText appendFormat:@"#%@ %@ ", ht, ht];
                }
            }
        }
    } @catch (NSException *e) {}

    // 3. Quét thông tin tác giả video (author handle / nickname)
    @try {
        id author = [model valueForKey:@"author"];
        if (author) {
            NSString *nickname = [author valueForKey:@"nickname"];
            NSString *uniqueId = [author valueForKey:@"uniqueID"];
            if (nickname) [searchableText appendFormat:@"%@ ", nickname];
            if (uniqueId) [searchableText appendFormat:@"@%@ ", uniqueId];
        }
    } @catch (NSException *e) {}

    if (searchableText.length == 0) return;

    NSString *normalizedText = stripAccentsAndLowercase(searchableText);
    NSString *matchedTag = nil;

    for (NSString *rawKw in getKeywords()) {
        NSString *normKw = stripAccentsAndLowercase(rawKw);
        NSString *normKwWithoutHash = [normKw stringByReplacingOccurrencesOfString:@"#" withString:@""];
        if ([normalizedText containsString:normKw] || (normKwWithoutHash.length > 2 && [normalizedText containsString:normKwWithoutHash])) {
            matchedTag = rawKw;
            break;
        }
    }

    if (!matchedTag) return; // Không khớp từ khóa -> Bỏ qua

    // Check anti-flood rate limits
    if (!checkRateLimitAllowsComment()) {
        return;
    }

    sCurrentlyPlayingAwemeID = itemId;
    sCurrentlyPendingMatchedTag = matchedTag;

    NSTimeInterval minWatch = calculateRealisticWatchDelay(model); // Ngưỡng xem tối thiểu (> 3s)
    NSTimeInterval startWatchTime = [NSDate timeIntervalSinceReferenceDate];
    sCurrentWatchStartTime = startWatchTime;

    showToastBanner([NSString stringWithFormat:@"🎯 Khớp [%@]!\n⏳ Đang xem video (> %.0fs)...", matchedTag, minWatch], minWatch + 0.5);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(minWatch * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Kiểm tra xem người dùng có còn đang xem video này không
        if (!sCurrentlyPlayingAwemeID || ![sCurrentlyPlayingAwemeID isEqualToString:itemId]) {
            NSLog(@"[TikTok-LQ] ⚠️ Đã lướt qua video khác trước khi đủ %.1fs xem, hủy comment %@", minWatch, itemId);
            return;
        }

        NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - startWatchTime;
        if (elapsed < minWatch - 0.3) {
            NSLog(@"[TikTok-LQ] ⚠️ Video chưa đạt ngưỡng thời gian xem %.1fs, bỏ qua", minWatch);
            return;
        }

        // Đã xem đủ ngưỡng! Áp dụng thêm độ trễ ngẫu nhiên tự nhiên (Comment Delay)
        CGFloat commentDelay = getCommentDelay();
        showToastBanner([NSString stringWithFormat:@"✅ Đã xem %.0fs! Chuẩn bị gửi sau %.1fs...", minWatch, commentDelay], commentDelay + 0.5);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(commentDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!sCurrentlyPlayingAwemeID || ![sCurrentlyPlayingAwemeID isEqualToString:itemId]) {
                NSLog(@"[TikTok-LQ] ⚠️ Đã lướt qua video khác trong thời gian chờ delay, hủy %@", itemId);
                return;
            }

            // Đánh dấu đã comment để không lặp lại
            [sCommentedAwemeIDs addObject:itemId];

            NSString *baseText = getCommentText();
            NSString *finalComment = generateAntiBotCommentText(baseText, matchedTag);

            UIWindow *window = nil;
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) { if (w.isKeyWindow) { window = w; break; } }
                    if (window) break;
                }
            }
            if (!window) window = [UIApplication sharedApplication].windows.firstObject;

            UIButton *commentBtn = findTikTokCommentButtonOnScreen();
            if (commentBtn) {
                simulateHumanTap(commentBtn, ^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        executeRealCommentSubmission(window, finalComment, itemId);
                    });
                });
            } else {
                executeRealCommentSubmission(window, finalComment, itemId);
            }
        });
    });
}

// ==============================================================================
// 12. HOOK 1: AWEPlayVideoPlayerController (PRIMARY PLAYBACK TRIGGER)
// ==============================================================================

@interface NSObject (LQPlayerHook)
- (void)lq_containerDidFullyDisplayWithReason:(NSInteger)reason;
- (void)lq_playerWillLoopPlaying:(id)arg1;
@end

@implementation NSObject (LQPlayerHook)
- (void)lq_playerWillLoopPlaying:(id)arg1 {
    if (getAutoPlayNextEnabled()) {
        id container = [self respondsToSelector:@selector(container)] ? [self performSelector:@selector(container)] : nil;
        if (container && [container respondsToSelector:@selector(parentViewController)]) {
            UIViewController *parent = [container performSelector:@selector(parentViewController)];
            if (parent && [parent respondsToSelector:@selector(scrollToNextVideo)]) {
                [parent performSelector:@selector(scrollToNextVideo)];
                return;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        UIViewController *root = w.rootViewController;
                        if (!root) continue;
                        NSMutableArray *q = [NSMutableArray arrayWithObject:root];
                        while (q.count > 0) {
                            UIViewController *vc = q.firstObject;
                            [q removeObjectAtIndex:0];
                            if ([vc respondsToSelector:@selector(scrollToNextVideo)]) {
                                [vc performSelector:@selector(scrollToNextVideo)];
                                return;
                            }
                            [q addObjectsFromArray:vc.childViewControllers];
                        }
                    }
                }
            }
        });
        return;
    }
    if ([self respondsToSelector:@selector(lq_playerWillLoopPlaying:)]) {
        [self lq_playerWillLoopPlaying:arg1];
    }
}


- (void)lq_containerDidFullyDisplayWithReason:(NSInteger)reason {
    [self lq_containerDidFullyDisplayWithReason:reason];

    @try {
        id container = [self respondsToSelector:@selector(container)] ? [self performSelector:@selector(container)] : nil;
        id currentModel = nil;

        if (container) {
            if ([container respondsToSelector:@selector(model)]) {
                currentModel = [container performSelector:@selector(model)];
            }
            if (!currentModel && [container respondsToSelector:@selector(parentViewController)]) {
                UIViewController *p = [container performSelector:@selector(parentViewController)];
                while (p) {
                    if ([p respondsToSelector:@selector(currentAweme)]) {
                        currentModel = [p performSelector:@selector(currentAweme)];
                        if (currentModel) break;
                    }
                    p = p.parentViewController;
                }
            }
        }

        if (currentModel) {
            processVideoModelForAutoComment(currentModel);
        }
    } @catch (NSException *e) {
        NSLog(@"[TikTok-LQ] Exception in containerDidFullyDisplay: %@", e);
    }
}

@end


// ==============================================================================
// BULLETPROOF FEED AD BLOCKING (RESPONSE MODEL & AD VIEW SUPPRESSION)
// ==============================================================================

static BOOL isAdAwemeModel(id model) {
    if (!model) return YES;
    @try {
        if ([[model valueForKey:@"isAds"] boolValue]) return YES;
        if ([[model valueForKey:@"isAd"] boolValue]) return YES;
        if ([[model valueForKey:@"isUserRecommendBigCard"] boolValue]) return YES;
        if ([model valueForKey:@"userRecommendModel"] != nil) return YES;
        if ([model valueForKey:@"friendsRecommendModel"] != nil) return YES;
        if ([model valueForKey:@"adInfo"] != nil) return YES;
        if ([model valueForKey:@"rawAdData"] != nil) return YES;
        if ([model valueForKey:@"adData"] != nil) return YES;
        if ([model valueForKey:@"commerceConfigData"] != nil) return YES;
        if ([[model valueForKey:@"commercialType"] integerValue] > 0) return YES;
        if ([model valueForKey:@"surveyModel"] != nil) return YES;
        if ([[model valueForKey:@"awemeType"] integerValue] == 101) return YES; // LIVE feed broadcast
        if ([[model valueForKey:@"isLive"] boolValue]) return YES;
        if ([model valueForKey:@"liveStreamURL"] != nil || [model valueForKey:@"room"] != nil) return YES;

        NSInteger awemeType = [[model valueForKey:@"awemeType"] integerValue];
        if (awemeType == 2 || awemeType == 34 || awemeType == 102 || awemeType == 103 ||
            awemeType == 107 || awemeType == 108 || awemeType == 109 || awemeType == 110 ||
            awemeType == 1001 || awemeType == 1002 || awemeType == 1003) {
            return YES;
        }
    } @catch (NSException *e) {}
    return NO;
}

@interface NSObject (LQFeedResponseHook)
- (NSArray *)lq_awemeList;
- (void)lq_setAwemeList:(NSArray *)list;
@end

@implementation NSObject (LQFeedResponseHook)

- (NSArray *)lq_awemeList {
    NSArray *orig = [self lq_awemeList];
    if (!getHideAdsEnabled() || !orig || ![orig isKindOfClass:[NSArray class]]) {
        return orig;
    }

    NSMutableArray *cleanList = [NSMutableArray arrayWithCapacity:orig.count];
    for (id item in orig) {
        if (!isAdAwemeModel(item)) {
            [cleanList addObject:item];
        } else {
            NSLog(@"[TikTok-AdBlock] 🛡️ Loại bỏ thẻ quảng cáo / live / gợi ý kết bạn khỏi feed!");
        }
    }
    return cleanList;
}

- (void)lq_setAwemeList:(NSArray *)list {
    if (getHideAdsEnabled() && [list isKindOfClass:[NSArray class]]) {
        NSMutableArray *cleanList = [NSMutableArray arrayWithCapacity:list.count];
        for (id item in list) {
            if (!isAdAwemeModel(item)) {
                [cleanList addObject:item];
            }
        }
        [self lq_setAwemeList:cleanList];
    } else {
        [self lq_setAwemeList:list];
    }
}

@end

@interface UIView (LQAdViewSuppressionHook)
- (void)lq_ad_didMoveToSuperview;
- (void)lq_ad_layoutSubviews;
@end

@implementation UIView (LQAdViewSuppressionHook)

- (void)lq_ad_didMoveToSuperview {
    [self lq_ad_didMoveToSuperview];
    if (getHideAdsEnabled()) {
        self.hidden = YES;
        self.alpha = 0.0;
        [self removeFromSuperview];
    }
}

- (void)lq_ad_layoutSubviews {
    [self lq_ad_layoutSubviews];
    if (getHideAdsEnabled()) {
        self.hidden = YES;
        self.alpha = 0.0;
        self.frame = CGRectZero;
    }
}

@end

// ==============================================================================
// 13. HOOK 2: AWEAwemeModel (CRASH-PROOF AD-BLOCK, PROGRESS BAR)
// ==============================================================================

@interface NSObject (LQAwemeHook)
- (id)lq_initWithDictionary:(id)arg1 error:(id *)arg2;
- (id)lq_init;
- (BOOL)lq_isUserRecommendBigCard;
- (BOOL)lq_progressBarDraggable;
- (BOOL)lq_progressBarVisible;
- (BOOL)lq_isAds;
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

- (id)lq_init {
    id orig = [self lq_init];
    if (getHideAdsEnabled() && orig) {
        @try {
            if ([orig respondsToSelector:@selector(isAds)]) {
                [orig setValue:@NO forKey:@"isAds"];
            }
        } @catch (NSException *e) {}
    }
    return orig;
}

- (id)lq_initWithDictionary:(id)arg1 error:(id *)arg2 {
    id orig = [self lq_initWithDictionary:arg1 error:arg2];

    // CHẶN QUẢNG CÁO AN TOÀN (NEUTRALIZE THAY VÌ TRẢ VỀ NIL ĐỂ TRÁNH CRASH ARRAY)
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
            @try {
                [orig setValue:@NO forKey:@"isAds"];
                [orig setValue:@0 forKey:@"commercialType"];
                [orig setValue:nil forKey:@"adInfo"];
                [orig setValue:nil forKey:@"rawAdData"];
            } @catch (NSException *e) {}
            objc_setAssociatedObject(orig, "lq_is_ad_filtered", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    return orig;
}

@end

// ==============================================================================
// 14. HOOK 3: BHTikTok Extra Features (Watermark, Comment Length, Verified)
// ==============================================================================

@interface NSObject (LQExtraFeaturesHook)
- (NSUInteger)lq_watermarkType;
- (void)lq_setWatermarkType:(NSUInteger)type;
- (NSUInteger)lq_maxLength;
- (NSInteger)lq_maxTextLength;
- (BOOL)lq_isVerifiedUser;
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

- (NSInteger)lq_maxTextLength {
    if (getExtendedCommentEnabled()) return 500;
    return [self lq_maxTextLength];
}

- (BOOL)lq_isVerifiedUser {
    if (getFakeVerifiedEnabled()) return YES;
    return [self lq_isVerifiedUser];
}

@end

// ==============================================================================
// 15. HOOK 4: DYNAMIC FEED CELL HOOK (ZERO-COLLISION BLOCK TRAMPOLINE)
// ==============================================================================

static void handleVideoFeedCellDisplay(UIView *cell, id model) {
    if (!cell || !model) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (cell.window) {
            CGRect r = [cell convertRect:cell.bounds toView:nil];
            CGFloat midY = [UIScreen mainScreen].bounds.size.height / 2.0;
            if (r.origin.y <= midY && (r.origin.y + r.size.height) >= midY) {
                processVideoModelForAutoComment(model);
            }
        }
    });
}

/**
 * Dynamically hooks configWithModel: / configureWithModel: on each cell class
 * using unique imp_implementationWithBlock closures.
 * Completely eliminates cross-class selector collisions and superclass pollution.
 */
static void HookFeedCellDynamic(Class cls) {
    if (!cls) return;
    SEL sel = @selector(configWithModel:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        sel = @selector(configureWithModel:);
        m = class_getInstanceMethod(cls, sel);
        if (!m) return;
    }

    const char *types = method_getTypeEncoding(m);
    __block IMP origImp = NULL;

    id block = ^(UIView *cellSelf, id model) {
        if (origImp) {
            ((void (*)(id, SEL, id))origImp)(cellSelf, sel, model);
        }
        setupHomeTabGesturesOnWindow(cellSelf.window);
        handleVideoFeedCellDisplay(cellSelf, model);
    };

    IMP hookImp = imp_implementationWithBlock(block);

    // If method was inherited, add directly to cls to protect superclass
    if (class_addMethod(cls, sel, hookImp, types ? types : "v@:@")) {
        origImp = method_getImplementation(m);
    } else {
        origImp = method_setImplementation(m, hookImp);
    }
}

// ==============================================================================
// 16. HOOK 5: COMMENT PANEL VISUAL HOOK
// ==============================================================================

@interface UIViewController (LQCommentPanelVisualHook)
- (void)lq_comment_viewWillAppear:(BOOL)animated;
@end

@implementation UIViewController (LQCommentPanelVisualHook)

- (void)lq_comment_viewWillAppear:(BOOL)animated {
    [self lq_comment_viewWillAppear:animated];
    if (getTransparentCommentEnabled() && self.view) {
        self.view.alpha = 0.88;
    }
}

@end

// ==============================================================================
// 17. INITIALIZER & DYNAMIC RUNTIME PROBING
// ==============================================================================


@interface UIWindow (LQWindowGestureHook)
- (void)lq_makeKeyAndVisible;
@end

@implementation UIWindow (LQWindowGestureHook)
- (void)lq_makeKeyAndVisible {
    [self lq_makeKeyAndVisible];
    setupHomeTabGesturesOnWindow(self);
}
@end

__attribute__((constructor))
static void initTikTokAutoCommentLienQuan(void) {
    @autoreleasepool {
        sCommentedAwemeIDs = [[NSMutableSet alloc] init];
        registerDefaultPreferencesIfNeeded();
        Class winCls = [UIWindow class];
        if (class_getInstanceMethod(winCls, @selector(makeKeyAndVisible))) {
            TTKSafeSwizzle(winCls, @selector(makeKeyAndVisible), @selector(lq_makeKeyAndVisible));
        }
        NSLog(@"[TikTok-LQ] 🚀 Standalone AutoComment LQ v4.0 (PAC-Safe & Anti-Bot) Loaded!");

        // 0. Nạp TikTok++ Core
        unpackAndLoadTikTokPlusPlus();

        // 1. Swizzle Playback Trigger (AWEPlayVideoPlayerController & fallbacks)
        NSArray *playerClassCandidates = @[@"AWEPlayVideoPlayerController", @"AWEAwemePlayVideoController", @"TTKPlayerController"];
        for (NSString *pClsName in playerClassCandidates) {
            Class playerCls = NSClassFromString(pClsName);
            if (playerCls) {
                if (class_getInstanceMethod(playerCls, @selector(containerDidFullyDisplayWithReason:))) {
                    TTKSafeSwizzle(playerCls, @selector(containerDidFullyDisplayWithReason:), @selector(lq_containerDidFullyDisplayWithReason:));
                    NSLog(@"[TikTok-LQ] ✅ Swizzled %@ containerDidFullyDisplayWithReason:", pClsName);
                    break;
                }
            }
        }

        // 2. Swizzle AWEAwemeModel (Ad-Block & Progress Bar)
        Class awemeCls = NSClassFromString(@"AWEAwemeModel");
        if (awemeCls) {
            TTKSafeSwizzle(awemeCls, @selector(initWithDictionary:error:), @selector(lq_initWithDictionary:error:));
            TTKSafeSwizzle(awemeCls, @selector(init), @selector(lq_init));
            if (class_getInstanceMethod(awemeCls, @selector(isAds))) {
                TTKSafeSwizzle(awemeCls, @selector(isAds), @selector(lq_isAds));
            }
            if (class_getInstanceMethod(awemeCls, @selector(isUserRecommendBigCard))) {
                TTKSafeSwizzle(awemeCls, @selector(isUserRecommendBigCard), @selector(lq_isUserRecommendBigCard));
            }
            if (class_getInstanceMethod(awemeCls, @selector(progressBarDraggable))) {
                TTKSafeSwizzle(awemeCls, @selector(progressBarDraggable), @selector(lq_progressBarDraggable));
            }
            if (class_getInstanceMethod(awemeCls, @selector(progressBarVisible))) {
                TTKSafeSwizzle(awemeCls, @selector(progressBarVisible), @selector(lq_progressBarVisible));
            }
        }

        
        // Swizzle Feed Response Models (Bulletproof Ad & Live Card Filtering)
        NSArray *feedResponseClasses = @[@"AWEFeedResponseModel", @"AWEAwemeResponseModel", @"TTKFeedResponseModel", @"AWEFeedDataManager"];
        for (NSString *name in feedResponseClasses) {
            Class c = NSClassFromString(name);
            if (c) {
                if (class_getInstanceMethod(c, @selector(awemeList))) {
                    TTKSafeSwizzle(c, @selector(awemeList), @selector(lq_awemeList));
                }
                if (class_getInstanceMethod(c, @selector(setAwemeList:))) {
                    TTKSafeSwizzle(c, @selector(setAwemeList:), @selector(lq_setAwemeList:));
                }
            }
        }

        // Swizzle Ad & Commercial Promo Views
        NSArray *adViewClassNames = @[
            @"AWECommerceAnchorView",
            @"AWEAdInteractiveView",
            @"AWEFeedAdEggView",
            @"AWEFeedLiveMarkView",
            @"AWECommerceLinkInformationView",
            @"AWEAdSearchEggView"
        ];
        for (NSString *name in adViewClassNames) {
            Class c = NSClassFromString(name);
            if (c && class_getInstanceMethod(c, @selector(didMoveToSuperview))) {
                TTKSafeSwizzle(c, @selector(didMoveToSuperview), @selector(lq_ad_didMoveToSuperview));
            }
        }

        // 3. Swizzle AWEAwemeACLItem (Watermark Removal)
        Class aclCls = NSClassFromString(@"AWEAwemeACLItem");
        if (aclCls) {
            if (class_getInstanceMethod(aclCls, @selector(watermarkType))) {
                TTKSafeSwizzle(aclCls, @selector(watermarkType), @selector(lq_watermarkType));
            }
            if (class_getInstanceMethod(aclCls, @selector(setWatermarkType:))) {
                TTKSafeSwizzle(aclCls, @selector(setWatermarkType:), @selector(lq_setWatermarkType:));
            }
        }

        // 4. Swizzle AWETextInputController & Bio Length
        Class inputCls = NSClassFromString(@"AWETextInputController");
        if (inputCls && class_getInstanceMethod(inputCls, @selector(maxLength))) {
            TTKSafeSwizzle(inputCls, @selector(maxLength), @selector(lq_maxLength));
        }
        Class bioCls = NSClassFromString(@"AWEProfileEditTextViewController");
        if (bioCls && class_getInstanceMethod(bioCls, @selector(maxTextLength))) {
            TTKSafeSwizzle(bioCls, @selector(maxTextLength), @selector(lq_maxTextLength));
        }

        // 5. Hook Feed Cells (Dynamic Block Trampolines - Zero Collisions)
        NSArray *cellClassNames = @[@"AWEFeedViewTemplateCell", @"AWEAwemeDetailTableViewCell", @"TTKFeedViewCell", @"AWEFeedCell", @"AWENewFeedTemplateCell"];
        for (NSString *clsName in cellClassNames) {
            Class cls = NSClassFromString(clsName);
            if (cls) {
                HookFeedCellDynamic(cls);
            }
        }

        // 6. Swizzle Comment Sheet Transparency
        NSArray *panelNames = @[@"TTKCommentPanelViewController", @"AWECommentPanelViewController"];
        for (NSString *pName in panelNames) {
            Class pCls = NSClassFromString(pName);
            if (pCls && class_getInstanceMethod(pCls, @selector(viewWillAppear:))) {
                TTKSafeSwizzle(pCls, @selector(viewWillAppear:), @selector(lq_comment_viewWillAppear:));
            }
        }

        // 7. Thiết lập cử chỉ Trang chủ khi app mở
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
            setupHomeTabGesturesOnWindow(w);
            showToastBanner(@"Nhấn giữ hoặc chạm 2 lần vào 'Trang chủ' để mở Cài đặt", 4.0);
        });
    }
}
