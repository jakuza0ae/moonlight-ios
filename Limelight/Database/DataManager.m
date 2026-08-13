//
//  DataManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "DataManager.h"
#import "TemporaryApp.h"
#import "TemporarySettings.h"

@implementation DataManager {
    NSManagedObjectContext *_managedObjectContext;
    AppDelegate *_appDelegate;
    BOOL _available;
    NSError *_storeError;
}

@synthesize available = _available;
@synthesize storeError = _storeError;

- (id) init {
    self = [super init];
    _available = NO;
    
    // HACK: Avoid calling [UIApplication delegate] off the UI thread to keep
    // Main Thread Checker happy.
    if ([NSThread isMainThread]) {
        _appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            self->_appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
        });
    }
    
    NSManagedObjectContext *parentContext = [_appDelegate managedObjectContext];
    if (parentContext == nil) {
        _storeError = [NSError errorWithDomain:@"com.moonlight.database"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Moonlight could not open its settings store."}];
        Log(LOG_E, @"DataManager unavailable: %@", _storeError.localizedDescription);
        return self;
    }

    _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [_managedObjectContext setParentContext:parentContext];
    _available = YES;
    
    return self;
}

- (void) updateUniqueId:(NSString*)uniqueId {
    if (!_available) {
        return;
    }
    [_managedObjectContext performBlockAndWait:^{
        [self retrieveSettings].uniqueId = uniqueId;
        [self saveData];
    }];
}

- (NSString*) getUniqueId {
    __block NSString *uid;

    if (!_available) {
        return nil;
    }
    
    [_managedObjectContext performBlockAndWait:^{
        uid = [self retrieveSettings].uniqueId;
    }];

    return uid;
}

- (void) saveSettingsWithBitrate:(NSInteger)bitrate
                       framerate:(NSInteger)framerate
                          height:(NSInteger)height
                           width:(NSInteger)width
                     audioConfig:(NSInteger)audioConfig
                onscreenControls:(NSInteger)onscreenControls
                   optimizeGames:(BOOL)optimizeGames
                 multiController:(BOOL)multiController
                 swapABXYButtons:(BOOL)swapABXYButtons
                       audioOnPC:(BOOL)audioOnPC
                  preferredCodec:(uint32_t)preferredCodec
                  useFramePacing:(BOOL)useFramePacing
                       enableHdr:(BOOL)enableHdr
                  btMouseSupport:(BOOL)btMouseSupport
                           absoluteTouchMode:(BOOL)absoluteTouchMode
                     statsOverlay:(BOOL)statsOverlay {
    if (!_available) {
        return;
    }
    
    [_managedObjectContext performBlockAndWait:^{
        Settings* settingsToSave = [self retrieveSettings];
        settingsToSave.framerate = [NSNumber numberWithInteger:framerate];
        settingsToSave.bitrate = [NSNumber numberWithInteger:bitrate];
        settingsToSave.height = [NSNumber numberWithInteger:height];
        settingsToSave.width = [NSNumber numberWithInteger:width];
        settingsToSave.audioConfig = [NSNumber numberWithInteger:audioConfig];
        settingsToSave.onscreenControls = [NSNumber numberWithInteger:onscreenControls];
        settingsToSave.optimizeGames = optimizeGames;
        settingsToSave.multiController = multiController;
        settingsToSave.swapABXYButtons = swapABXYButtons;
        settingsToSave.playAudioOnPC = audioOnPC;
        settingsToSave.preferredCodec = preferredCodec;
        settingsToSave.useFramePacing = useFramePacing;
        settingsToSave.enableHdr = enableHdr;
        settingsToSave.btMouseSupport = btMouseSupport;
        settingsToSave.absoluteTouchMode = absoluteTouchMode;
        settingsToSave.statsOverlay = statsOverlay;
        
        [self saveData];
    }];
}

- (void) updateHost:(TemporaryHost *)host {
    if (!_available) {
        return;
    }
    [_managedObjectContext performBlockAndWait:^{
        // Add a new persistent managed object if one doesn't exist
        Host* parent = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (parent == nil) {
            NSEntityDescription* entity = [NSEntityDescription entityForName:@"Host" inManagedObjectContext:self->_managedObjectContext];
            parent = [[Host alloc] initWithEntity:entity insertIntoManagedObjectContext:self->_managedObjectContext];
        }
        
        // Push changes from the temp host to the persistent one
        [host propagateChangesToParent:parent];
        
        [self saveData];
    }];
}

- (void) updateAppsForExistingHost:(TemporaryHost *)host {
    if (!_available) {
        return;
    }
    [_managedObjectContext performBlockAndWait:^{
        Host* parent = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (parent == nil) {
            // The host must exist to be updated
            return;
        }
        
        NSMutableSet *applist = [[NSMutableSet alloc] init];
        NSArray *appRecords = [self fetchRecords:@"App"];
        for (TemporaryApp* app in host.appList) {
            // Add a new persistent managed object if one doesn't exist
            App* parentApp = [self getAppForTemporaryApp:app withAppRecords:appRecords];
            if (parentApp == nil) {
                NSEntityDescription* entity = [NSEntityDescription entityForName:@"App" inManagedObjectContext:self->_managedObjectContext];
                parentApp = [[App alloc] initWithEntity:entity insertIntoManagedObjectContext:self->_managedObjectContext];
            }
            
            [app propagateChangesToParent:parentApp withHost:parent];
            
            [applist addObject:parentApp];
        }
        
        parent.appList = applist;
        
        [self saveData];
    }];
}

- (TemporarySettings*) getSettings {
    __block TemporarySettings *tempSettings;

    if (!_available) {
        return nil;
    }
    
    [_managedObjectContext performBlockAndWait:^{
        tempSettings = [[TemporarySettings alloc] initFromSettings:[self retrieveSettings]];
    }];
    
    return tempSettings;
}

- (LMStreamProfile*) getProfileForHost:(NSString*)hostUuid profileName:(NSString*)profileName {
    return [LMStreamProfileStore loadProfileForHost:hostUuid profileName:profileName];
}

- (void) saveProfile:(LMStreamProfile*)profile forHost:(NSString*)hostUuid profileName:(NSString*)profileName {
    [LMStreamProfileStore saveProfile:profile forHost:hostUuid profileName:profileName];
}

- (LMStreamProfile*) getSecondMonitorProfileForHost:(NSString*)hostUuid {
    return [self getProfileForHost:hostUuid profileName:@"second-monitor"];
}

- (void) saveSecondMonitorProfile:(LMStreamProfile*)profile forHost:(NSString*)hostUuid {
    [self saveProfile:profile forHost:hostUuid profileName:@"second-monitor"];
}

- (Settings*) retrieveSettings {
    NSArray* fetchedRecords = [self fetchRecords:@"Settings"];
    if (fetchedRecords.count == 0) {
        // create a new settings object with the default values
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"Settings" inManagedObjectContext:_managedObjectContext];
        Settings* settings = [[Settings alloc] initWithEntity:entity insertIntoManagedObjectContext:_managedObjectContext];
        
        return settings;
    } else {
        // we should only ever have 1 settings object stored
        return [fetchedRecords objectAtIndex:0];
    }
}

- (void) removeApp:(TemporaryApp*)app {
    if (!_available) {
        return;
    }
    [_managedObjectContext performBlockAndWait:^{
        App* managedApp = [self getAppForTemporaryApp:app withAppRecords:[self fetchRecords:@"App"]];
        if (managedApp != nil) {
            [self->_managedObjectContext deleteObject:managedApp];
            [self saveData];
        }
    }];
}

- (void) removeHost:(TemporaryHost*)host {
    if (!_available) {
        return;
    }
    [_managedObjectContext performBlockAndWait:^{
        Host* managedHost = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (managedHost != nil) {
            [self->_managedObjectContext deleteObject:managedHost];
            [self saveData];
        }
    }];
}

- (void) saveData {
    if (!_available) {
        return;
    }
    NSError* error;
    if ([_managedObjectContext hasChanges] && ![_managedObjectContext save:&error]) {
        Log(LOG_E, @"Unable to save hosts to database: %@", error);
    }

    [_appDelegate saveContext];
}

- (NSArray*) getHosts {
    __block NSMutableArray *tempHosts = [[NSMutableArray alloc] init];

    if (!_available) {
        return tempHosts;
    }
    
    [_managedObjectContext performBlockAndWait:^{
        NSArray *hosts = [self fetchRecords:@"Host"];
        
        for (Host* host in hosts) {
            [tempHosts addObject:[[TemporaryHost alloc] initFromHost:host]];
        }
    }];
    
    return tempHosts;
}

// Only call from within performBlockAndWait!!!
- (Host*) getHostForTemporaryHost:(TemporaryHost*)tempHost withHostRecords:(NSArray*)hosts {
    for (Host* host in hosts) {
        if ([tempHost.uuid isEqualToString:host.uuid]) {
            return host;
        }
    }
    
    return nil;
}

// Only call from within performBlockAndWait!!!
- (App*) getAppForTemporaryApp:(TemporaryApp*)tempApp withAppRecords:(NSArray*)apps {
    for (App* app in apps) {
        if ([app.id isEqualToString:tempApp.id] &&
            [app.host.uuid isEqualToString:tempApp.host.uuid]) {
            return app;
        }
    }
    
    return nil;
}

- (NSArray*) fetchRecords:(NSString*)entityName {
    NSArray* fetchedRecords;

    if (!_available || _managedObjectContext == nil) {
        return @[];
    }
    
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:_managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSError* error;
    fetchedRecords = [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    //TODO: handle errors
    
    return fetchedRecords;
}

@end

