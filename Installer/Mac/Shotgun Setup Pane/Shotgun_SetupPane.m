//
//  Shotgun_SetupPane.m
//  Shotgun Setup
//
//  Created by Jonathon Mah on 2010-02-14.
//  Copyright (c) 2010 Rising Sun Research Pty Ltd. All rights reserved.
//

#import "Shotgun_SetupPane.h"


@implementation Shotgun_SetupPane

+ (void)initialize;
{
    [self setKeys:[NSArray arrayWithObject:@"browserTag"] triggerChangeNotificationsForDependentKey:@"firefoxSDSelected"];
}


- (id)init;
{
    /* Contrary to the documentation, this is the initialization method that
     * actually gets run (not -initWithSection:) */
    if ((self = [super init])) {
        scriptName = @"cineSync";
        browserTag = CSCBrowserSafari;
        [self setValuesFromExistingConfig];
    }
    return self;
}


- (void)willEnterPane:(InstallerSectionDirection)dir;
{
    NSString *path = [[self myBundle] pathForImageResource:@"Shotgun Scripts"];
    NSImage *scriptsImage = [[NSImage alloc] initWithContentsOfFile:path];
    [scriptImageView setImage:scriptsImage];
    [scriptsImage release];
    
    [self updateNextEnabled];
}


- (void)dealloc;
{
    if (setupTask) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSTaskDidTerminateNotification
                                                      object:setupTask];
        [setupTask waitUntilExit];
        [setupTask release];
        setupTask = nil;
    }
    [shotgunURL release];
    [scriptName release];
    [APIKey release];
    [super dealloc];
}


- (NSBundle *)myBundle; { return [NSBundle bundleForClass:[self class]]; }
- (NSString *)installPath; { return [@"~/Library/Application Support/cineSync/Scripts/Shotgun" stringByExpandingTildeInPath]; }
- (NSString *)title; { return [[self myBundle] localizedStringForKey:@"PaneTitle" value:nil table:nil]; }


- (BOOL)isFirefoxSDSelected; { return browserTag == CSCBrowserFirefoxSD; }
- (BOOL)checkingAPIKey; { return setupTask != nil; }


- (BOOL)validateShotgunURL:(id *)ioURL error:(NSError **)outError;
{
    if (!*ioURL)
        return YES;
    
    NSScanner *scanner = [NSScanner scannerWithString:*ioURL];
    NSString *scheme = @"http://";
    BOOL scannedScheme = [scanner scanString:@"http://" intoString:&scheme];
    if (!scannedScheme)
        scannedScheme = [scanner scanString:@"https://" intoString:&scheme];
    NSString *host = nil;
    [scanner scanUpToString:@"/" intoString:&host];
    
    NSString *mogrifiedURL = *ioURL;
    if (scheme && host)
        mogrifiedURL = [NSString stringWithFormat:@"%@%@/", scheme, host];
    
    if (![*ioURL isEqual:mogrifiedURL])
        *ioURL = mogrifiedURL;
    return YES;
}


- (void)setShotgunURL:(NSString *)url;
{
    id oldValue = shotgunURL;
    shotgunURL = [url copy]; [oldValue release];
    [self updateNextEnabled];
}


- (void)setScriptName:(NSString *)name;
{
    id oldValue = scriptName;
    scriptName = [name copy]; [oldValue release];
    [self updateNextEnabled];
}


- (void)setAPIKey:(NSString *)key;
{
    id oldValue = APIKey;
    APIKey = [key copy]; [oldValue release];
    [self updateNextEnabled];
}


- (void)updateNextEnabled;
{
    BOOL shotgunURLValid = [shotgunURL length] > 8;
    BOOL scriptNameValid = [scriptName length] > 0;
    BOOL APIKeyLengthValid = [APIKey length] == 40;
    [self setNextEnabled:(![self checkingAPIKey] && shotgunURLValid && scriptNameValid && APIKeyLengthValid)];
}


- (BOOL)shouldExitPane:(InstallerSectionDirection)dir;
{
    if (dir == InstallerDirectionForward) {
        if (validatedAPIKey) {
            return YES;
        } else {
            [self beginValidatingAPIKey];
            return NO;
        }
    } else {
        return YES;
    }
}


- (void)setValuesFromExistingConfig;
{
    NSString *readConfigScriptPath = [[self myBundle] pathForResource:@"read_shotgun_config" ofType:@"rb"];
    NSArray *args = [NSArray arrayWithObjects:readConfigScriptPath, [self installPath], nil];
    
    NSTask *readConfigTask = [[NSTask alloc] init];
    [readConfigTask setLaunchPath:@"/usr/bin/ruby"];
    [readConfigTask setArguments:args];
    NSPipe *pipe = [NSPipe pipe];
    [readConfigTask setStandardOutput:pipe];
    [readConfigTask launch];
    [readConfigTask waitUntilExit];
    
    if ([readConfigTask terminationStatus] == 0) {
        NSFileHandle *outputHandle = [pipe fileHandleForReading];
        NSString *output = [[NSString alloc] initWithData:[outputHandle readDataToEndOfFile] encoding:NSUTF8StringEncoding];
        NSArray *lines = [output componentsSeparatedByString:@"\n"];
        if ([lines count] == 5) { // Expect a blank line at the end
            [self setShotgunURL:[lines objectAtIndex:0]];
            [self setScriptName:[lines objectAtIndex:1]];
            [self setAPIKey:[lines objectAtIndex:2]];
            unsigned tag = [[lines objectAtIndex:3] intValue];
            [self setValue:[NSNumber numberWithUnsignedInt:tag] forKey:@"browserTag"];
        }
        [output release];
    }
    [readConfigTask release];
}


- (void)beginValidatingAPIKey;
{
    if ([self checkingAPIKey])
        return;
    
    [self setValue:[[self myBundle] localizedStringForKey:@"StatusCheckingInput" value:nil table:nil]
            forKey:@"APIKeyStatus"];
    
    NSString *setupScriptPath = [[self myBundle] pathForResource:@"setup_shotgun" ofType:@"rb"];
    NSArray *args = [NSArray arrayWithObjects:
        setupScriptPath, [self installPath], shotgunURL, scriptName, APIKey, [NSString stringWithFormat:@"%d", browserTag], nil];
    
    [self willChangeValueForKey:@"checkingAPIKey"];
    setupTask = [[NSTask alloc] init];
    [setupTask setLaunchPath:@"/usr/bin/ruby"];
    [setupTask setArguments:args];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(setupTaskDidTerminate:)
                                                 name:NSTaskDidTerminateNotification
                                               object:setupTask];
    [setupTask launch];
    [self didChangeValueForKey:@"checkingAPIKey"];
    
    [self updateNextEnabled];
    [self setPreviousEnabled:NO];
}


- (void)setupTaskDidTerminate:(NSNotification *)notification;
{
    if ([setupTask terminationStatus] == 0) {
        validatedAPIKey = YES;
        [self setValue:[[self myBundle] localizedStringForKey:@"StatusSuccess" value:nil table:nil]
                forKey:@"APIKeyStatus"];
    } else {
        [self setValue:[[self myBundle] localizedStringForKey:@"StatusFailure" value:nil table:nil]
                forKey:@"APIKeyStatus"];
    }
    
    [self willChangeValueForKey:@"checkingAPIKey"];
    [setupTask release];
    setupTask = nil;
    [self didChangeValueForKey:@"checkingAPIKey"];
    
    [self updateNextEnabled];
    [self setPreviousEnabled:YES];
    
    if (validatedAPIKey)
        [self gotoNextPane];
}


@end
