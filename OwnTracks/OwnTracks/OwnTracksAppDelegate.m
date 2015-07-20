//
//  OwnTracksAppDelegate.m
//  OwnTracks
//
//  Created by Christoph Krey on 03.02.14.
//  Copyright (c) 2014-2015 OwnTracks. All rights reserved.
//

#import "OwnTracksAppDelegate.h"
#import "CoreData.h"
#import "Friend+Create.h"
#import "Setting+Create.h"
#import "AlertView.h"
#import "Settings.h"
#import "Location.h"
#import "OwnTracking.h"
#import <NotificationCenter/NotificationCenter.h>
#import <Fabric/Fabric.h>
#import <Crashlytics/Crashlytics.h>
#import <CocoaLumberjack/CocoaLumberjack.h>

@interface OwnTracksAppDelegate()
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@property (strong, nonatomic) void (^completionHandler)(UIBackgroundFetchResult);
@property (strong, nonatomic) CoreData *coreData;
@property (strong, nonatomic) CMStepCounter *stepCounter;
@property (strong, nonatomic) CMPedometer *pedometer;

@property (strong, nonatomic) NSManagedObjectContext *queueManagedObjectContext;
@end

@implementation OwnTracksAppDelegate
static const DDLogLevel ddLogLevel = DDLogLevelError;

#pragma ApplicationDelegate

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    //NSLog(@"willFinishLaunchingWithOptions");
    NSEnumerator *enumerator = [launchOptions keyEnumerator];
    NSString *key;
    while ((key = [enumerator nextObject])) {
        //NSLog(@"%@:%@", key, [[launchOptions objectForKey:key] description]);
    }
    
    self.backgroundTask = UIBackgroundTaskInvalid;
    self.completionHandler = nil;
    
    if ([[[UIDevice currentDevice] systemVersion] compare:@"7.0"] != NSOrderedAscending) {
        //NSLog(@"setMinimumBackgroundFetchInterval %f", UIApplicationBackgroundFetchIntervalMinimum);
        [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    }
    
    if ([[[UIDevice currentDevice] systemVersion] compare:@"8.0"] != NSOrderedAscending) {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:
                                                UIUserNotificationTypeAlert |
                                                UIUserNotificationTypeBadge
                                                                                 categories:[NSSet setWithObjects:nil]];
        // NSLog(@"registerUserNotificationSettings %@", settings);
        [application registerUserNotificationSettings:settings];
    }
    
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [Fabric with:@[CrashlyticsKit]];
    
#ifdef DEBUG
    [DDLog addLogger:[DDTTYLogger sharedInstance] withLevel:DDLogLevelAll];
#else
    [DDLog addLogger:[DDTTYLogger sharedInstance] withLevel:DDLogLevelError];
#endif
    
    [DDLog addLogger:[DDASLLogger sharedInstance] withLevel:DDLogLevelError];
    
    DDLogVerbose(@"ddLogLevel %lu", (unsigned long)ddLogLevel);
    DDLogVerbose(@"didFinishLaunchingWithOptions");
    
    NSEnumerator *enumerator = [launchOptions keyEnumerator];
    NSString *key;
    while ((key = [enumerator nextObject])) {
        DDLogVerbose(@"%@:%@", key, [[launchOptions objectForKey:key] description]);
    }
    
    
    self.coreData = [[CoreData alloc] init];
    
    UIDocumentState state;
    
    do {
        state = self.coreData.documentState;
        if (state & UIDocumentStateClosed || ![CoreData theManagedObjectContext]) {
            DDLogVerbose(@"documentState 0x%02lx theManagedObjectContext %@",
                         (long)self.coreData.documentState,
                         [CoreData theManagedObjectContext]);
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } while (state & UIDocumentStateClosed || ![CoreData theManagedObjectContext]);
    
    //
    // Migrate Waypoints from 8.0.32 to 8.2.0
    //
    Friend *myself = [Friend existsFriendWithTopic:[Settings theGeneralTopic]
                            inManagedObjectContext:[CoreData theManagedObjectContext]];
    if (myself) {
        for (Location *location in myself.hasLocations) {
            if (![location.automatic boolValue]) {
                if (location.remark && location.remark.length) {
                    NSArray *components = [location.remark componentsSeparatedByString:@":"];
                    NSString *name = components.count >= 1 ? components[0] : nil;
                    NSString *uuid = components.count >= 2 ? components[1] : nil;
                    unsigned int major = components.count >= 3 ? [components[2] unsignedIntValue]: 0;
                    unsigned int minor = components.count >= 4 ? [components[3] unsignedIntValue]: 0;
                    
                    [[OwnTracking sharedInstance] addRegionFor:myself
                                                          name:name
                                                          uuid:uuid
                                                         major:major
                                                         minor:minor
                                                         share:[location.share boolValue]
                                                        radius:[location.regionradius doubleValue]
                                                           lat:[location.latitude doubleValue]
                                                           lon:[location.longitude doubleValue]
                                                       context:[CoreData theManagedObjectContext]];
                }
            }
            [[CoreData theManagedObjectContext] deleteObject:location];
        }
        [CoreData saveContext];
    }

    
    if (![Setting existsSettingWithKey:@"mode"
                inManagedObjectContext:[CoreData theManagedObjectContext]]) {
        if (![Setting existsSettingWithKey:@"host_preference"
                    inManagedObjectContext:[CoreData theManagedObjectContext]]) {
            [Settings setInt:2 forKey:@"mode"];
        } else {
            [Settings setInt:0 forKey:@"mode"];
        }
    }
    
    self.connectionOut = [[Connection alloc] init];
    self.connectionOut.delegate = self;
    [self.connectionOut start];
    
    self.connectionIn = [[Connection alloc] init];
    self.connectionIn.delegate = self;
    [self.connectionIn start];
    
    [self connect];
    
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:TRUE];
    
    LocationManager *locationManager = [LocationManager sharedInstance];
    locationManager.delegate = self;
    locationManager.monitoring = [Settings intForKey:@"monitoring_preference"];
    locationManager.ranging = [Settings boolForKey:@"ranging_preference"];
    locationManager.minDist = [Settings doubleForKey:@"mindist_preference"];
    locationManager.minTime = [Settings doubleForKey:@"mintime_preference"];
    [locationManager start];
    
    [[Messaging sharedInstance] updateCounter:self.coreData.managedObjectContext];
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    //
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    DDLogVerbose(@"openURL %@ from %@ annotation %@", url, sourceApplication, annotation);
    
    if (url) {
        DDLogVerbose(@"URL scheme %@", url.scheme);
        
        if ([url.scheme isEqualToString:@"owntracks"]) {
            DDLogVerbose(@"URL path %@ query %@", url.path, url.query);
            
            NSMutableDictionary *queryStrings = [[NSMutableDictionary alloc] init];
            for (NSString *parameter in [url.query componentsSeparatedByString:@"&"]) {
                NSArray *pair = [parameter componentsSeparatedByString:@"="];
                if (pair.count == 2) {
                    NSString *key = pair[0];
                    NSString *value = pair[1];
                    value = [value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
                    value = [value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                    queryStrings[key] = value;
                }
            }
            if ([url.path isEqualToString:@"/beacon"]) {
                NSString *name = queryStrings[@"name"];
                NSString *uuid = queryStrings[@"uuid"];
                int major = [queryStrings[@"major"] intValue];
                int minor = [queryStrings[@"minor"] intValue];
                
                NSString *desc = [NSString stringWithFormat:@"%@:%@%@%@",
                                  name,
                                  uuid,
                                  major ? [NSString stringWithFormat:@":%d", major] : @"",
                                  minor ? [NSString stringWithFormat:@":%d", minor] : @""
                                  ];
                
                [Settings waypointsFromDictionary:@{@"_type":@"waypoints",
                                                    @"waypoints":@[@{@"_type":@"waypoint",
                                                                     @"desc":desc,
                                                                     @"tst":@((int)([[NSDate date] timeIntervalSince1970])),
                                                                     @"lat":@([LocationManager sharedInstance].location.coordinate.latitude),
                                                                     @"lon":@([LocationManager sharedInstance].location.coordinate.longitude),
                                                                     @"rad":@(-1)
                                                                     }]
                                                    }];
                [CoreData saveContext];
                self.processingMessage = @"Beacon QR successfully processed";
                return TRUE;
            } else if ([url.path isEqualToString:@"/hosted"]) {
                NSString *user = queryStrings[@"user"];
                NSString *device = queryStrings[@"device"];
                NSString *token = queryStrings[@"token"];
                
                [[LocationManager sharedInstance] resetRegions];
                NSArray *friends = [Friend allFriendsInManagedObjectContext:[CoreData theManagedObjectContext]];
                for (Friend *friend in friends) {
                    [[CoreData theManagedObjectContext] deleteObject:friend];
                }
                
                
                [Settings fromDictionary:@{@"_type":@"configuration",
                                           @"mode":@(1),
                                           @"username":user,
                                           @"deviceId":device,
                                           @"password":token
                                           }];
                self.configLoad = [NSDate date];
                [CoreData saveContext];
                self.processingMessage = @"Hosted QR successfully processed";
                return TRUE;
            } else {
                self.processingMessage = [NSString stringWithFormat:@"unkown url path %@",
                                          url.path];
                return FALSE;
            }
        } else if ([url.scheme isEqualToString:@"file"]) {
            NSInputStream *input = [NSInputStream inputStreamWithURL:url];
            if ([input streamError]) {
                self.processingMessage = [NSString stringWithFormat:@"inputStreamWithURL %@ %@",
                                          [input streamError],
                                          url];
                return FALSE;
            }
            [input open];
            if ([input streamError]) {
                self.processingMessage = [NSString stringWithFormat:@"open %@ %@",
                                          [input streamError],
                                          url];
                return FALSE;
            }
            
            DDLogVerbose(@"URL pathExtension %@", url.pathExtension);
            
            NSError *error;
            NSString *extension = [url pathExtension];
            if ([extension isEqualToString:@"otrc"] || [extension isEqualToString:@"mqtc"]) {
                [[LocationManager sharedInstance] resetRegions];
                NSArray *friends = [Friend allFriendsInManagedObjectContext:[CoreData theManagedObjectContext]];
                for (Friend *friend in friends) {
                    [[CoreData theManagedObjectContext] deleteObject:friend];
                }
                [CoreData saveContext];
                error = [Settings fromStream:input];
                [CoreData saveContext];
                self.configLoad = [NSDate date];
            } else if ([extension isEqualToString:@"otrw"] || [extension isEqualToString:@"mqtw"]) {
                error = [Settings waypointsFromStream:input];
                [CoreData saveContext];
            } else if ([extension isEqualToString:@"otrp"] || [extension isEqualToString:@"otre"]) {
                NSURL *directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory
                                                                             inDomain:NSUserDomainMask
                                                                    appropriateForURL:nil
                                                                               create:YES
                                                                                error:&error];
                NSString *fileName = [url lastPathComponent];
                NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
                [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
                [[NSFileManager defaultManager] copyItemAtURL:url toURL:fileURL error:nil];
            } else {
                error = [NSError errorWithDomain:@"OwnTracks"
                                            code:2
                                        userInfo:@{@"extension":extension ? extension : @"(null)"}];
            }
            
            [input close];
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
            if (error) {
                self.processingMessage = [NSString stringWithFormat:@"Error processing file %@: %@ %@",
                                          [url lastPathComponent],
                                          error.localizedDescription,
                                          error.userInfo];
                return FALSE;
            }
            self.processingMessage = [NSString stringWithFormat:@"File %@ successfully processed",
                                      [url lastPathComponent]];
            return TRUE;
        } else {
            self.processingMessage = [NSString stringWithFormat:@"unkown url scheme %@",
                                      url.scheme];
            return FALSE;
        }
    }
    self.processingMessage = [NSString stringWithFormat:@"no url specified"];
    return FALSE;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    DDLogVerbose(@"applicationDidEnterBackground");
    self.backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        DDLogVerbose(@"BackgroundTaskExpirationHandler");
        /*
         * we might end up here if the connection could not be closed within the given
         * background time
         */
        if (self.backgroundTask) {
            [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
            self.backgroundTask = UIBackgroundTaskInvalid;
        }
    }];
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    DDLogVerbose(@"applicationDidBecomeActive");
    
    if (self.processingMessage) {
        [AlertView alert:@"openURL" message:self.processingMessage];
        self.processingMessage = nil;
        [self reconnect];
    }
    
    if (self.coreData.documentState) {
        NSString *message = [NSString stringWithFormat:@"documentState 0x%02lx %@",
                             (long)self.coreData.documentState,
                             self.coreData.fileURL];
        [AlertView alert:@"CoreData" message:message];
    }
    
    if (![Settings validIds]) {
        NSString *message = [NSString stringWithFormat:@"To publish your location userID and deviceID must be set"];
        [AlertView alert:@"Settings" message:message];
    }
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    DDLogVerbose(@"performFetchWithCompletionHandler");
    self.completionHandler = completionHandler;
    [[LocationManager sharedInstance] wakeup];
    [self.connectionOut connectToLast];
    [self.connectionIn connectToLast];
    
    if ([LocationManager sharedInstance].monitoring) {
        CLLocation *lastLocation = [LocationManager sharedInstance].location;
        CLLocation *location = [[CLLocation alloc] initWithLatitude:lastLocation.coordinate.latitude
                                                          longitude:lastLocation.coordinate.longitude];
        [self publishLocation:location trigger:@"p"];
    }
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings {
    DDLogVerbose(@"didRegisterUserNotificationSettings %@", notificationSettings);
}

/*
 *
 * LocationManagerDelegate
 *
 */

- (void)newLocation:(CLLocation *)location {
    [self publishLocation:location trigger:nil];
    [[Messaging sharedInstance] newLocation:location.coordinate.latitude
                longitude:location.coordinate.longitude
                  context:[CoreData theManagedObjectContext]];
}

- (void)timerLocation:(CLLocation *)location {
    [self publishLocation:location trigger:@"t"];
    [[Messaging sharedInstance] newLocation:location.coordinate.latitude
                longitude:location.coordinate.longitude
                  context:[CoreData theManagedObjectContext]];
}

- (void)regionEvent:(CLRegion *)region enter:(BOOL)enter {
    NSString *message = [NSString stringWithFormat:@"%@ %@", (enter ? @"Entering" : @"Leaving"), region.identifier];
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    notification.alertBody = message;
    notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    
    Friend *myself = [Friend existsFriendWithTopic:[Settings theGeneralTopic]
                            inManagedObjectContext:[CoreData theManagedObjectContext]];

    CLLocation *location = [LocationManager sharedInstance].location;
    [[Messaging sharedInstance] newLocation:location.coordinate.latitude
                longitude:location.coordinate.longitude
                  context:[CoreData theManagedObjectContext]];
    
    if ([LocationManager sharedInstance].monitoring && [Settings validIds]) {
        NSMutableDictionary *jsonObject = [@{
                                             @"_type": @"transition",
                                             @"lat": @(location.coordinate.latitude),
                                             @"lon": @(location.coordinate.longitude),
                                             @"tst": @(floor([location.timestamp timeIntervalSince1970])),
                                             @"acc": @(location.horizontalAccuracy),
                                             @"tid": [myself getEffectiveTid],
                                             @"event": enter ? @"enter" : @"leave",
                                             @"t": [region isKindOfClass:[CLBeaconRegion class]] ? @"b" : @"c"
                                             } mutableCopy];
        
        for (Region *anyRegion in myself.hasRegions) {
            if ([region.identifier isEqualToString:anyRegion.CLregion.identifier]) {
                anyRegion.name = anyRegion.name;
                if ([anyRegion.share boolValue]) {
                    [jsonObject setValue:region.identifier forKey:@"desc"];
                    [self.connectionOut sendData:[self jsonToData:jsonObject]
                                           topic:[[Settings theGeneralTopic] stringByAppendingString:@"/event"]
                                             qos:[Settings intForKey:@"qos_preference"]
                                          retain:NO];
                }
                if ([anyRegion isKindOfClass:[CLBeaconRegion class]]) {
                    if ([anyRegion.radius doubleValue] < 0) {
                        anyRegion.lat = [NSNumber numberWithDouble:location.coordinate.latitude];
                        anyRegion.lon = [NSNumber numberWithDouble:location.coordinate.longitude];
                        [self sendRegion:anyRegion];
                    }
                }

            }
        }
        
        if ([region isKindOfClass:[CLBeaconRegion class]]) {
            [self publishLocation:[LocationManager sharedInstance].location trigger:@"b"];
        } else {
            [self publishLocation:[LocationManager sharedInstance].location trigger:@"c"];
        }
    }
}

- (void)regionState:(CLRegion *)region inside:(BOOL)inside {
    CLLocation *location = [LocationManager sharedInstance].location;
    
    Friend *myself = [Friend existsFriendWithTopic:[Settings theGeneralTopic]
                            inManagedObjectContext:[CoreData theManagedObjectContext]];

    for (Region *anyRegion in myself.hasRegions) {
        if ([region.identifier isEqualToString:anyRegion.CLregion.identifier]) {
            anyRegion.name = anyRegion.name;
        }
    }
    [[Messaging sharedInstance] newLocation:location.coordinate.latitude
                longitude:location.coordinate.longitude
                  context:[CoreData theManagedObjectContext]];
    
}

- (void)beaconInRange:(CLBeacon *)beacon region:(CLBeaconRegion *)region{
    if ([Settings validIds]) {
        NSDictionary *jsonObject = @{
                                     @"_type": @"beacon",
                                     @"tst": @(floor([[LocationManager sharedInstance].location.timestamp timeIntervalSince1970])),
                                     @"uuid": [beacon.proximityUUID UUIDString],
                                     @"major": beacon.major,
                                     @"minor": beacon.minor,
                                     @"prox": @(beacon.proximity),
                                     @"acc": @(round(beacon.accuracy)),
                                     @"rssi": @(beacon.rssi)
                                     };
        [self.connectionOut sendData:[self jsonToData:jsonObject]
                               topic:[[Settings theGeneralTopic] stringByAppendingString:@"/beacon"]
                                 qos:[Settings intForKey:@"qos_preference"]
                              retain:NO];
    }
}

#pragma ConnectionDelegate

- (void)showState:(Connection *)connection state:(NSInteger)state {
    if (connection == self.connectionOut) {
        self.connectionStateOut = @(state);
    }
    /**
     ** This is a hack to ensure the connection gets gracefully closed at the server
     **
     ** If the background task is ended, occasionally the disconnect message is not received well before the server senses the tcp disconnect
     **/
    
    if ([self.connectionStateOut intValue] == state_closed) {
        if (self.backgroundTask) {
            DDLogVerbose(@"endBackGroundTask");
            [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
            self.backgroundTask = UIBackgroundTaskInvalid;
        }
        if (self.completionHandler) {
            DDLogVerbose(@"completionHandler");
            self.completionHandler(UIBackgroundFetchResultNewData);
            self.completionHandler = nil;
        }
    }
}

- (NSManagedObjectContext *)queueManagedObjectContext
{
    if (!_queueManagedObjectContext) {
        _queueManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [_queueManagedObjectContext setParentContext:[CoreData theManagedObjectContext]];
    }
    return _queueManagedObjectContext;
}

- (void)handleMessage:(Connection *)connection data:(NSData *)data onTopic:(NSString *)topic retained:(BOOL)retained {
    DDLogVerbose(@"handleMessage");
    
    if ([[Messaging sharedInstance] processMessage:topic data:data retained:retained context:self.queueManagedObjectContext]) {
        return;
    }
    
    if ([[OwnTracking sharedInstance] processMessage:topic data:data retained:retained context:self.queueManagedObjectContext]) {
        // return;
    }
    
    NSArray *topicComponents = [topic componentsSeparatedByCharactersInSet:
                                [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSArray *baseComponents = [[Settings theGeneralTopic] componentsSeparatedByCharactersInSet:
                               [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    
    NSString *device = @"";
    BOOL ownDevice = true;
    
    for (int i = 0; i < [baseComponents count]; i++) {
        if (i > 0) {
            device = [device stringByAppendingString:@"/"];
        }
        if (i < topicComponents.count) {
            device = [device stringByAppendingString:topicComponents[i]];
            if (![baseComponents[i] isEqualToString:topicComponents [i]]) {
                ownDevice = false;
            }
        } else {
            ownDevice = false;
        }
    }
    
    DDLogVerbose(@"device %@", device);
    
    if (ownDevice) {
        
        NSError *error;
        NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (dictionary) {
            if ([dictionary[@"_type"] isEqualToString:@"cmd"]) {
                DDLogVerbose(@"App msg received cmd:%@", dictionary[@"action"]);
                if ([Settings boolForKey:@"cmd_preference"]) {
                    if ([dictionary[@"action"] isEqualToString:@"dump"]) {
                        [self dumpTo:topic];
                    } else if ([dictionary[@"action"] isEqualToString:@"reportLocation"]) {
                        if ([LocationManager sharedInstance].monitoring || [Settings boolForKey:@"allowremotelocation_preference"]) {
                            [self publishLocation:[LocationManager sharedInstance].location trigger:@"r"];
                        }
                    } else if ([dictionary[@"action"] isEqualToString:@"reportSteps"]) {
                        [self stepsFrom:dictionary[@"from"] to:dictionary[@"to"]];
                    } else if ([dictionary[@"action"] isEqualToString:@"setWaypoints"]) {
                        NSDictionary *payload = dictionary[@"payload"];
                        [Settings waypointsFromDictionary:payload];
                    } else {
                        DDLogVerbose(@"unknown action %@", dictionary[@"action"]);
                    }
                }
            } else {
                DDLogVerbose(@"unhandled record type %@", dictionary[@"_type"]);
            }
        } else {
            DDLogVerbose(@"illegal json %@ %@ %@", error.localizedDescription, error.userInfo, data.description);
        }
    }
}

- (void)messageDelivered:(Connection *)connection msgID:(UInt16)msgID {
    DDLogVerbose(@"Message delivered id=%u", msgID);
}

- (void)totalBuffered:(Connection *)connection count:(NSUInteger)count {
    DDLogVerbose(@"totalBuffered %lu", (unsigned long)count);
    if (connection == self.connectionOut) {
        self.connectionBufferedOut = @(count);
        [UIApplication sharedApplication].applicationIconBadgeNumber = count;
    }
}

- (void)dumpTo:(NSString *)topic {
    NSDictionary *dumpDict = @{
                               @"_type":@"dump",
                               @"configuration":[Settings toDictionary],
                               };
    
    [self.connectionOut sendData:[self jsonToData:dumpDict]
                           topic:[[Settings theGeneralTopic] stringByAppendingString:@"/dump"]
                             qos:[Settings intForKey:@"qos_preference"]
                          retain:NO];
}

- (void)stepsFrom:(NSNumber *)from to:(NSNumber *)to {
    NSDate *toDate;
    NSDate *fromDate;
    if (to && [to isKindOfClass:[NSNumber class]]) {
        toDate = [NSDate dateWithTimeIntervalSince1970:[to doubleValue]];
    } else {
        toDate = [NSDate date];
    }
    if (from && [from isKindOfClass:[NSNumber class]]) {
        fromDate = [NSDate dateWithTimeIntervalSince1970:[from doubleValue]];
    } else {
        NSDateComponents *components = [[NSCalendar currentCalendar]
                                        components: NSCalendarUnitDay |
                                        NSCalendarUnitHour |
                                        NSCalendarUnitMinute |
                                        NSCalendarUnitSecond |
                                        NSCalendarUnitMonth |
                                        NSCalendarUnitYear
                                        fromDate:toDate];
        components.hour = 0;
        components.minute = 0;
        components.second = 0;
        
        fromDate = [[NSCalendar currentCalendar] dateFromComponents:components];
    }
    
    if ([[[UIDevice currentDevice] systemVersion] compare:@"8.0"] != NSOrderedAscending) {
        DDLogVerbose(@"isStepCountingAvailable %d", [CMPedometer isStepCountingAvailable]);
        DDLogVerbose(@"isFloorCountingAvailable %d", [CMPedometer isFloorCountingAvailable]);
        DDLogVerbose(@"isDistanceAvailable %d", [CMPedometer isDistanceAvailable]);
        if (!self.pedometer) {
            self.pedometer = [[CMPedometer alloc] init];
        }
        [self.pedometer queryPedometerDataFromDate:fromDate
                                            toDate:toDate
                                       withHandler:^(CMPedometerData *pedometerData, NSError *error) {
                                           DDLogVerbose(@"StepCounter queryPedometerDataFromDate handler %ld %ld %ld %ld %@",
                                                        [pedometerData.numberOfSteps longValue],
                                                        [pedometerData.floorsAscended longValue],
                                                        [pedometerData.floorsDescended longValue],
                                                        [pedometerData.distance longValue],
                                                        error.localizedDescription);
                                           dispatch_async(dispatch_get_main_queue(), ^{
                                               
                                               NSMutableDictionary *jsonObject = [[NSMutableDictionary alloc] init];
                                               [jsonObject addEntriesFromDictionary:@{
                                                                                      @"_type": @"steps",
                                                                                      @"tst": @(floor([[NSDate date] timeIntervalSince1970])),
                                                                                      @"from": @(floor([fromDate timeIntervalSince1970])),
                                                                                      @"to": @(floor([toDate timeIntervalSince1970])),
                                                                                      }];
                                               if (pedometerData) {
                                                   [jsonObject setObject:pedometerData.numberOfSteps forKey:@"steps"];
                                                   if (pedometerData.floorsAscended) {
                                                       [jsonObject setObject:pedometerData.floorsAscended forKey:@"floorsup"];
                                                   }
                                                   if (pedometerData.floorsDescended) {
                                                       [jsonObject setObject:pedometerData.floorsDescended forKey:@"floorsdown"];
                                                   }
                                                   if (pedometerData.distance) {
                                                       [jsonObject setObject:pedometerData.distance forKey:@"distance"];
                                                   }
                                               } else {
                                                   [jsonObject setObject:@(-1) forKey:@"steps"];
                                               }
                                               
                                               [self.connectionOut sendData:[self jsonToData:jsonObject]
                                                                      topic:[[Settings theGeneralTopic] stringByAppendingString:@"/step"]
                                                                        qos:[Settings intForKey:@"qos_preference"]
                                                                     retain:NO];
                                           });
                                       }];
        
    } else if ([[[UIDevice currentDevice] systemVersion] compare:@"7.0"] != NSOrderedAscending) {
        DDLogVerbose(@"isStepCountingAvailable %d", [CMStepCounter isStepCountingAvailable]);
        if (!self.stepCounter) {
            self.stepCounter = [[CMStepCounter alloc] init];
        }
        [self.stepCounter queryStepCountStartingFrom:fromDate
                                                  to:toDate
                                             toQueue:[[NSOperationQueue alloc] init]
                                         withHandler:^(NSInteger steps, NSError *error)
         {
             DDLogVerbose(@"StepCounter queryStepCountStartingFrom handler %ld %@ %@", (long)steps,
                          error.localizedDescription,
                          error.userInfo);
             dispatch_async(dispatch_get_main_queue(), ^{
                 
                 NSDictionary *jsonObject = @{
                                              @"_type": @"steps",
                                              @"tst": @(floor([[NSDate date] timeIntervalSince1970])),
                                              @"from": @(floor([fromDate timeIntervalSince1970])),
                                              @"to": @(floor([toDate timeIntervalSince1970])),
                                              @"steps": error ? @(-1) : @(steps)
                                              };
                 
                 [self.connectionOut sendData:[self jsonToData:jsonObject]
                                        topic:[[Settings theGeneralTopic] stringByAppendingString:@"/step"]
                                          qos:[Settings intForKey:@"qos_preference"]
                                       retain:NO];
             });
         }];
    } else {
        NSDictionary *jsonObject = @{
                                     @"_type": @"steps",
                                     @"tst": @(floor([[NSDate date] timeIntervalSince1970])),
                                     @"from": @(floor([fromDate timeIntervalSince1970])),
                                     @"to": @(floor([toDate timeIntervalSince1970])),
                                     @"steps": @(-1)
                                     };
        
        [self.connectionOut sendData:[self jsonToData:jsonObject]
                               topic:[[Settings theGeneralTopic] stringByAppendingString:@"/step"]
                                 qos:[Settings intForKey:@"qos_preference"]
                              retain:NO];
    }
}

#pragma actions

- (void)sendNow {
    DDLogVerbose(@"App sendNow");
    CLLocation *location = [LocationManager sharedInstance].location;
    [self publishLocation:location trigger:@"u"];
    [[Messaging sharedInstance] newLocation:location.coordinate.latitude
                longitude:location.coordinate.longitude
                  context:[CoreData theManagedObjectContext]];
    
    
}

- (void)connectionOff {
    DDLogVerbose(@"App connectionOff");
    [self.connectionOut disconnect];
    [self.connectionIn disconnect];
}

- (void)terminateSession {
    [self connectionOff];
    [[OwnTracking sharedInstance] syncProcessing];
    [[LocationManager sharedInstance] resetRegions];
    NSArray *friends = [Friend allFriendsInManagedObjectContext:[CoreData theManagedObjectContext]];
    for (Friend *friend in friends) {
        [[CoreData theManagedObjectContext] deleteObject:friend];
    }
    [CoreData saveContext];
}

- (void)reconnect {
    DDLogVerbose(@"App reconnect");
    [self.connectionOut disconnect];
    [self.connectionIn disconnect];
    [self connect];
    [self sendNow];
}

- (void)publishLocation:(CLLocation *)location trigger:(NSString *)trigger {
    if (location &&
        CLLocationCoordinate2DIsValid(location.coordinate) &&
        location.coordinate.latitude != 0.0 &&
        location.coordinate.longitude != 0.0 &&
        [Settings validIds]) {
        Friend *friend = [Friend friendWithTopic:[Settings theGeneralTopic]
                          inManagedObjectContext:[CoreData theManagedObjectContext]];
        friend.tid = [Settings stringForKey:@"trackerid_preference"];
        
        Waypoint *waypoint = [[OwnTracking sharedInstance] addWaypointFor:friend
                                            location:location
                                             trigger:trigger
                                             context:[CoreData theManagedObjectContext]];
        [CoreData saveContext];
        
        NSDictionary *json = [[OwnTracking sharedInstance] waypointAsJSON:waypoint];
        NSData *data = [self jsonToData:json];
        [self.connectionOut sendData:data
                               topic:[Settings theGeneralTopic]
                                 qos:[Settings intForKey:@"qos_preference"]
                              retain:[Settings boolForKey:@"retain_preference"]];
        
        [self.connectionIn connectToLast];
    }
}

- (void)sendEmpty:(NSString *)topic {
    [self.connectionOut sendData:nil
                           topic:topic
                             qos:[Settings intForKey:@"qos_preference"]
                          retain:YES];
}

- (void)requestLocationFromFriend:(Friend *)friend {
    NSDictionary *jsonObject = @{
                                 @"_type": @"cmd",
                                 @"action": @"reportLocation"
                                 };
    
    [self.connectionOut sendData:[self jsonToData:jsonObject]
                           topic:[friend.topic stringByAppendingString:@"/cmd"]
                             qos:[Settings intForKey:@"qos_preference"]
                          retain:NO];
}

- (void)sendRegion:(Region *)region {
    if ([Settings validIds]) {
        NSDictionary *json = [[OwnTracking sharedInstance] regionAsJSON:region];
        NSData *data = [self jsonToData:json];
        [self.connectionOut sendData:data
                               topic:[[Settings theGeneralTopic] stringByAppendingString:@"/waypoint"]
                                 qos:[Settings intForKey:@"qos_preference"]
                              retain:NO];
    }
}

#pragma internal helpers

- (void)connect {
    NSURL *directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory
                                                                 inDomain:NSUserDomainMask
                                                        appropriateForURL:nil
                                                                   create:YES
                                                                    error:nil];
    NSArray *certificates = nil;
    NSString *fileName = [Settings stringForKey:@"clientpkcs"];
    if (fileName && fileName.length) {
        NSString *clientPKCSPath = [directoryURL.path stringByAppendingPathComponent:fileName];
        certificates = [MQTTSession clientCertsFromP12:clientPKCSPath
                                                 passphrase:[Settings stringForKey:@"passphrase"]];
        if (!certificates) {
            [AlertView alert:@"TLS Client Certificate" message:@"incorrect file or passphrase"];
        }
    }
    
    MQTTSSLSecurityPolicy *securityPolicy = nil;
    if ([Settings boolForKey:@"usepolicy"]) {
       securityPolicy = [MQTTSSLSecurityPolicy policyWithPinningMode:[Settings intForKey:@"policymode"]];
        if (!securityPolicy) {
            [AlertView alert:@"TLS Security Policy" message:@"invalide mode"];
        }

        NSString *fileName = [Settings stringForKey:@"servercer"];
        if (fileName && fileName.length) {
            NSString *serverCERpath = [directoryURL.path stringByAppendingPathComponent:fileName];;
            NSData *certificateData = [NSData dataWithContentsOfFile:serverCERpath];
            if (certificateData) {
                securityPolicy.pinnedCertificates = [[NSArray alloc] initWithObjects:certificateData, nil];
            } else {
                [AlertView alert:@"TLS Security Policy" message:@"invalid certificates file"];
            }
        }
        securityPolicy.allowInvalidCertificates = [Settings boolForKey:@"allowinvalidcerts"];
        securityPolicy.validatesCertificateChain = [Settings boolForKey:@"validatecertificatechain"];
        securityPolicy.validatesDomainName = [Settings boolForKey:@"validatedomainname"];
    }
    
    [self.connectionOut connectTo:[Settings stringForKey:@"host_preference"]
                             port:[Settings intForKey:@"port_preference"]
                              tls:[Settings boolForKey:@"tls_preference"]
                        keepalive:[Settings intForKey:@"keepalive_preference"]
                            clean:[Settings intForKey:@"clean_preference"]
                             auth:[Settings theMqttAuth]
                             user:[Settings theMqttUser]
                             pass:[Settings theMqttPass]
                        willTopic:[Settings theWillTopic]
                             will:[self jsonToData:@{
                                                     @"tst": [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]],
                                                     @"_type": @"lwt"}]
                          willQos:[Settings intForKey:@"willqos_preference"]
                   willRetainFlag:[Settings boolForKey:@"willretain_preference"]
                     withClientId:[NSString stringWithFormat:@"%@-o", [Settings theClientId]]
                   securityPolicy:securityPolicy
                     certificates:certificates];
    
    MQTTQosLevel subscriptionQos =[Settings intForKey:@"subscriptionqos_preference"];
    NSArray *subscriptions = [[Settings theSubscriptions] componentsSeparatedByCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
    
    self.connectionIn.subscriptions = subscriptions;
    self.connectionIn.subscriptionQos = subscriptionQos;
    
    [self.connectionIn connectTo:[Settings stringForKey:@"host_preference"]
                            port:[Settings intForKey:@"port_preference"]
                             tls:[Settings boolForKey:@"tls_preference"]
                       keepalive:[Settings intForKey:@"keepalive_preference"]
                           clean:[Settings intForKey:@"clean_preference"]
                            auth:[Settings theMqttAuth]
                            user:[Settings theMqttUser]
                            pass:[Settings theMqttPass]
                       willTopic:nil
                            will:nil
                         willQos:MQTTQosLevelAtMostOnce
                  willRetainFlag:NO
                    withClientId:[NSString stringWithFormat:@"%@-i", [Settings theClientId]]
                  securityPolicy:securityPolicy
                    certificates:certificates];
}

- (NSData *)jsonToData:(NSDictionary *)jsonObject {
    NSData *data;
    
    if ([NSJSONSerialization isValidJSONObject:jsonObject]) {
        NSError *error;
        data = [NSJSONSerialization dataWithJSONObject:jsonObject options:0 /* not pretty printed */ error:&error];
        if (!data) {
            NSString *message = [NSString stringWithFormat:@"%@ %@ %@",
                                 error.localizedDescription,
                                 error.userInfo,
                                 [jsonObject description]];
            [AlertView alert:@"dataWithJSONObject" message:message];
        }
    } else {
        NSString *message = [NSString stringWithFormat:@"%@", [jsonObject description]];
        [AlertView alert:@"isValidJSONObject" message:message];
    }
    return data;
}

@end
