//
//  NSBundle+privateLocalization.h
//  OwnTracks
//
//  Created by Christoph Krey on 21.04.16.
//  Copyright © 2016-2022  OwnTracks. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSBundle (privateLocalization)
+ (void)load;
- (NSString *)privateLocalizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table;
@end
