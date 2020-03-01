//
//  OwnTracking.h
//  OwnTracks
//
//  Created by Christoph Krey on 28.06.15.
//  Copyright © 2015-2020  OwnTracks. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Friend+CoreDataClass.h"
#import "Waypoint+CoreDataClass.h"
#import "Region+CoreDataClass.h"
#import <CoreLocation/CoreLocation.h>

@interface OwnTracking : NSObject
@property (strong, nonatomic) NSNumber *inQueue;

+ (OwnTracking *)sharedInstance;
- (void)syncProcessing;

- (BOOL)processMessage:(NSString *)topic data:(NSData *)data retained:(BOOL)retained context:(NSManagedObjectContext *)context;

- (Waypoint *)addWaypointFor:(Friend *)friend location:(CLLocation *)location trigger:(NSString *)trigger context:(NSManagedObjectContext *)context;

- (void)limitWaypointsFor:(Friend *)friend toMaximum:(NSInteger)max;

- (Region *)addRegionFor:(Friend *)friend
name:(NSString *)name
uuid:(NSString *)uuid
major:(unsigned int)major
minor:(unsigned int)minor
radius:(double)radius
lat:(double)lat
lon:(double)lon
context:(NSManagedObjectContext *)context;
- (void)removeRegion:(Region *)region context:(NSManagedObjectContext *)context;

- (NSDictionary *)waypointAsJSON:(Waypoint *)waypoint;
- (NSDictionary *)regionAsJSON:(Region *)region;

@end
