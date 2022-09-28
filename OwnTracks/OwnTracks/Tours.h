//
//  Tours.h
//  OwnTracks
//
//  Created by Christoph Krey on 02.08.22.
//  Copyright © 2022 OwnTracks. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface Tour: NSObject
@property (strong, nonatomic) NSString *label;
@property (strong, nonatomic) NSString *uuid;
@property (strong, nonatomic) NSString *url;
@property (strong, nonatomic) NSDate *from;
@property (strong, nonatomic) NSDate *to;

- (instancetype)initFromDictionary:(nullable NSDictionary *)dictionary;
- (NSDictionary *)asDictionary;
- (NSComparisonResult)compare:(Tour *)tour;
@end

@interface Tours : NSObject
@property (strong, nonatomic, nullable) NSMutableDictionary *response;
@property (strong, nonatomic) NSDate *timestamp;
@property (strong, nonatomic) NSString *message;
@property (strong, nonatomic) NSNumber *activity;

+ (Tours *)sharedInstance;
- (void)refresh;
- (NSInteger)count;
- (nullable Tour *)tourAtIndex:(NSInteger)index;
- (void)requestTour:(nonnull Tour *)tour;
- (void)addTour:(nonnull Tour *)tour;
- (BOOL)removeTourAtIndex:(NSInteger)index;
- (BOOL)processResponse:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
