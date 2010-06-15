//
//  Shotgun_SetupPane.h
//  Shotgun Setup
//
//  Created by Jonathon Mah on 2010-02-14.
//  Copyright (c) 2010 Rising Sun Research Pty Ltd. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <InstallerPlugins/InstallerPlugins.h>


enum CSCBrowserTag {
    CSCNoBrowser = 0,
    CSCBrowserSafari = 1,
    CSCBrowserFirefoxSD = 2,
};


@interface Shotgun_SetupPane : InstallerPane
{
    NSString *shotgunURL;
    NSString *scriptName;
    NSString *APIKey;
    unsigned browserTag;
    
    IBOutlet NSImageView *scriptImageView;
    
    BOOL validatedAPIKey;
    
    NSString *APIKeyStatus;
    NSTask *setupTask;
}


- (BOOL)isFirefoxSDSelected;
- (BOOL)checkingAPIKey;

- (NSBundle *)myBundle;
- (NSString *)installPath;
- (void)setValuesFromExistingConfig;
- (void)updateNextEnabled;
- (void)beginValidatingAPIKey;
- (void)setupTaskDidTerminate:(NSNotification *)notification;

@end
