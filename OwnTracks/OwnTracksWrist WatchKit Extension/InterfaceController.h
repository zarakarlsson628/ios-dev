//
//  InterfaceController.h
//  OwnTracksWrist WatchKit Extension
//
//  Created by Christoph Krey on 01.04.20.
//  Copyright © 2020 OwnTracks. All rights reserved.
//

#import <WatchKit/WatchKit.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MQTTClient.h>

@interface InterfaceController : WKInterfaceController <CLLocationManagerDelegate, MQTTSessionDelegate>

@end
