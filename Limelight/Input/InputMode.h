//
//  InputMode.h
//  Moonlight
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, LMInputMode) {
    LMInputModeNativeTouch = 0,
    LMInputModeMouseCompatibility,
    LMInputModeHybrid,
};

typedef NS_ENUM(NSInteger, LMInputRoute) {
    LMInputRouteNativeTouch = 0,
    LMInputRouteMouseCompatibility,
};
