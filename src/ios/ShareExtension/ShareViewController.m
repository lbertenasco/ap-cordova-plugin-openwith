//
//  ShareViewController.m
//  OpenWith - Share Extension
//

//
// The MIT License (MIT)
//
// Copyright (c)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import "ShareViewController.h"

@interface ShareViewController : UIViewController {
    int _verbosityLevel;
    NSUserDefaults *_userDefaults;
    NSString *_backURL;
}
@property (nonatomic) int verbosityLevel;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@property (nonatomic,retain) NSString *backURL;
@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;
@synthesize backURL = _backURL;

- (void) log:(int)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[ShareViewController.m]%@", message);
    }
}
- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

-(void) viewDidLoad {
    [super viewDidLoad];
    printf("did load");
    [self debug:@"[viewDidLoad]"];
    [self submit];
}

- (void) setup {
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
    [self debug:@"[setup]"];
}

- (BOOL) isContentValid {
    return YES;
}

- (void) openURL:(nonnull NSURL *)url {

    SEL selector = NSSelectorFromString(@"openURL:options:completionHandler:");

    UIResponder* responder = self;
    while ((responder = [responder nextResponder]) != nil) {
        NSLog(@"responder = %@", responder);
        if([responder respondsToSelector:selector] == true) {
            NSMethodSignature *methodSignature = [responder methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];

            // Arguments
            NSDictionary<NSString *, id> *options = [NSDictionary dictionary];
            void (^completion)(BOOL success) = ^void(BOOL success) {
                NSLog(@"Completions block: %i", success);
            };

            [invocation setTarget: responder];
            [invocation setSelector: selector];
            [invocation setArgument: &url atIndex: 2];
            [invocation setArgument: &options atIndex:3];
            [invocation setArgument: &completion atIndex: 4];
            [invocation invoke];
            break;
        }
    }
}

- (void)setParameters:(NSString *)fileIdentifier itemProvider:(NSItemProvider *)itemProvider suggestedName:(NSString **)suggestedName uti:(NSString **)uti utis:(NSArray<NSString *> **)utis {
    [self.extensionContext completeRequestReturningItems:@[]
                                       completionHandler:nil];
    *suggestedName = @"";
    if ([itemProvider respondsToSelector:NSSelectorFromString(@"getSuggestedName")]) {
        *suggestedName = [itemProvider valueForKey:@"suggestedName"];
    }

    *uti = @"";
    *utis = [NSArray new];
    if ([itemProvider.registeredTypeIdentifiers count] > 0) {
        *uti = itemProvider.registeredTypeIdentifiers[0];
        *utis = itemProvider.registeredTypeIdentifiers;
    }
    else {
        *uti = fileIdentifier;
    }
}

- (void) submit {

    [self setup];
    [self debug:@"[submit]"];

    // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
    for (NSItemProvider* itemProvider in ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments) {

        NSString *fileIdentifier;
        for (NSString* identifier in SHAREEXT_UNIFORM_TYPE_ENABLED_IDENTIFIERS) {
            if ([itemProvider hasItemConformingToTypeIdentifier:identifier]) {
                fileIdentifier = identifier;
            }
        }

        if ([fileIdentifier isEqualToString: @"public.image"]) {

            NSExtensionItem *item = self.extensionContext.inputItems.firstObject;
            NSItemProvider *itemProvider = item.attachments.firstObject;

            if ([itemProvider hasItemConformingToTypeIdentifier:fileIdentifier]) {
                [itemProvider loadItemForTypeIdentifier:fileIdentifier options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {

                    NSData *data = [[NSData alloc] init];

                    UIImage *sharedImage = nil;
                    if ([(NSObject*)item isKindOfClass:[NSURL class]]) {
                        sharedImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:(NSURL*)item]];
                    }
                    if ([(NSObject*)item isKindOfClass:[UIImage class]]) {
                        sharedImage = (UIImage*)item;
                    }

                    data = UIImagePNGRepresentation((UIImage*)sharedImage);

                    NSString * suggestedName;
                    NSString * uti;
                    NSArray<NSString *> * utis;

                    [self setParameters:fileIdentifier itemProvider:itemProvider suggestedName:&suggestedName uti:&uti utis:&utis];

                    NSDictionary *dict = @{
                        @"backURL": self.backURL,
                        @"data" : data,
                        @"uti": uti,
                        @"utis": utis,
                        @"name": suggestedName
                    };

                    [self.userDefaults setObject:dict forKey:@"image"];
                    [self.userDefaults synchronize];

                    // Emit a URL that opens the cordova app
                    NSString *redirectUrl = [NSString stringWithFormat:@"%@://image", SHAREEXT_URL_SCHEME];

                    [self openURL:[NSURL URLWithString:redirectUrl]];

                    // Inform the host that we're done, so it un-blocks its UI.
                    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                }];
            }

        } else if ([fileIdentifier isEqualToString: @"public.url"]) {

            NSExtensionItem *item = self.extensionContext.inputItems.firstObject;
            NSItemProvider *itemProvider = item.attachments.firstObject;

            if ([itemProvider hasItemConformingToTypeIdentifier:fileIdentifier]) {
                [itemProvider loadItemForTypeIdentifier:fileIdentifier options:nil completionHandler:^(NSURL *url, NSError *error) {
                    NSString *urlString = url.absoluteString;

                    NSString * suggestedName;
                    NSString * uti;
                    NSArray<NSString *> * utis;

                    [self setParameters:fileIdentifier itemProvider:itemProvider suggestedName:&suggestedName uti:&uti utis:&utis];

                    NSDictionary *dict = @{
                         @"backURL": self.backURL,
                         @"data" : urlString,
                         @"uti": uti,
                         @"utis": utis,
                         @"name": suggestedName
                    };

                    [self.userDefaults setObject:dict forKey:@"url"];
                    [self.userDefaults synchronize];

                    // Emit a URL that opens the cordova app
                    NSString *redirectUrl = [NSString stringWithFormat:@"%@://url", SHAREEXT_URL_SCHEME];

                    [self openURL:[NSURL URLWithString:redirectUrl]];

                    // Inform the host that we're done, so it un-blocks its UI.
                    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                }];
            }

        } else if ([fileIdentifier isEqualToString: @"public.plain-text"]) {

            NSExtensionItem *item = self.extensionContext.inputItems.firstObject;
            NSItemProvider *itemProvider = item.attachments.firstObject;

            if ([itemProvider hasItemConformingToTypeIdentifier:fileIdentifier]) {
                [itemProvider loadItemForTypeIdentifier:fileIdentifier options:nil completionHandler:^(id<NSSecureCoding, NSObject> item, NSError *error) {

                    NSString *text = (NSString*)item;
                    NSLog(@"Text %@", text);

                    NSString * suggestedName;
                    NSString * uti;
                    NSArray<NSString *> * utis;

                    [self setParameters:fileIdentifier itemProvider:itemProvider suggestedName:&suggestedName uti:&uti utis:&utis];

                    NSDictionary *dict = @{
                        @"backURL": self.backURL,
                        @"data" : text,
                        @"uti": uti,
                        @"utis": utis,
                        @"name": suggestedName
                    };

                    [self.userDefaults setObject:dict forKey:@"text"];
                    [self.userDefaults synchronize];

                    // Emit a URL that opens the cordova app
                    NSString *redirectUrl = [NSString stringWithFormat:@"%@://text", SHAREEXT_URL_SCHEME];

                    [self openURL:[NSURL URLWithString:redirectUrl]];

                    // Inform the host that we're done, so it un-blocks its UI.
                    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];

                }];
            }
        } else {
          // Get itemProvider type
          UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"File type not supported"
                                                                         message:@"We only accept images, links and text."
                                                                  preferredStyle:UIAlertControllerStyleAlert];

          UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                                handler:^(UIAlertAction * action) {}];

          [alert addAction:defaultAction];
          [self presentViewController:alert animated:YES completion:nil];
        }
    }
    return;
}

- (NSArray*) configurationItems {
    // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
    return @[];
}

- (NSString*) backURLFromBundleID: (NSString*)bundleId {
    if (bundleId == nil) return nil;
    // App Store - com.apple.AppStore
    if ([bundleId isEqualToString:@"com.apple.AppStore"]) return @"itms-apps://";
    // Calculator - com.apple.calculator
    // Calendar - com.apple.mobilecal
    // Camera - com.apple.camera
    // Clock - com.apple.mobiletimer
    // Compass - com.apple.compass
    // Contacts - com.apple.MobileAddressBook
    // FaceTime - com.apple.facetime
    // Find Friends - com.apple.mobileme.fmf1
    // Find iPhone - com.apple.mobileme.fmip1
    // Game Center - com.apple.gamecenter
    // Health - com.apple.Health
    // iBooks - com.apple.iBooks
    // iTunes Store - com.apple.MobileStore
    // Mail - com.apple.mobilemail - message://
    if ([bundleId isEqualToString:@"com.apple.mobilemail"]) return @"message://";
    // Maps - com.apple.Maps - maps://
    if ([bundleId isEqualToString:@"com.apple.Maps"]) return @"maps://";
    // Messages - com.apple.MobileSMS
    // Music - com.apple.Music
    // News - com.apple.news - applenews://
    if ([bundleId isEqualToString:@"com.apple.news"]) return @"applenews://";
    // Notes - com.apple.mobilenotes - mobilenotes://
    if ([bundleId isEqualToString:@"com.apple.mobilenotes"]) return @"mobilenotes://";
    // Phone - com.apple.mobilephone
    // Photos - com.apple.mobileslideshow
    if ([bundleId isEqualToString:@"com.apple.mobileslideshow"]) return @"photos-redirect://";
    // Podcasts - com.apple.podcasts
    // Reminders - com.apple.reminders - x-apple-reminder://
    if ([bundleId isEqualToString:@"com.apple.reminders"]) return @"x-apple-reminder://";
    // Safari - com.apple.mobilesafari
    // Settings - com.apple.Preferences
    // Stocks - com.apple.stocks
    // Tips - com.apple.tips
    // Videos - com.apple.videos - videos://
    if ([bundleId isEqualToString:@"com.apple.videos"]) return @"videos://";
    // Voice Memos - com.apple.VoiceMemos - voicememos://
    if ([bundleId isEqualToString:@"com.apple.VoiceMemos"]) return @"voicememos://";
    // Wallet - com.apple.Passbook
    // Watch - com.apple.Bridge
    // Weather - com.apple.weather
    return @"";
}

// This is called at the point where the Post dialog is about to be shown.
// We use it to store the _hostBundleID
- (void) willMoveToParentViewController: (UIViewController*)parent {
    NSString *hostBundleID = [parent valueForKey:(@"_hostBundleID")];
    self.backURL = [self backURLFromBundleID:hostBundleID];
}

@end
