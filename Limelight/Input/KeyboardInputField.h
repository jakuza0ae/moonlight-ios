//
//  KeyboardInputField.h
//  Moonlight
//
//  Created by Cameron Gutman on 12/2/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LMKeyboardAction) {
    LMKeyboardActionEscape,
    LMKeyboardActionTab,
    LMKeyboardActionControl,
    LMKeyboardActionShift,
    LMKeyboardActionAlt,
    LMKeyboardActionWindows,
    LMKeyboardActionDelete,
};

FOUNDATION_EXPORT BOOL LMKeyboardActionIsModifier(LMKeyboardAction action);

typedef void (^LMKeyboardActionHandler)(LMKeyboardAction action, BOOL pressed);

@interface KeyboardInputField : UITextField

- (void)sendKeyboardAction:(LMKeyboardAction)action pressed:(BOOL)pressed;
- (void)releaseAllKeyboardActions;
- (NSSet<NSNumber *> *)activeKeyboardActions;

@property (nonatomic, copy, nullable) LMKeyboardActionHandler keyboardActionHandler;

@end

NS_ASSUME_NONNULL_END
