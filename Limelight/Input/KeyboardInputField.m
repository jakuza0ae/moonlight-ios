//
//  KeyboardInputField.m
//  Moonlight
//
//  Created by Cameron Gutman on 12/2/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import "KeyboardInputField.h"

@implementation KeyboardInputField {
    NSMutableSet<NSNumber *> *_activeKeyboardActions;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _activeKeyboardActions = [[NSMutableSet alloc] init];
    }
    return self;
}

BOOL LMKeyboardActionIsModifier(LMKeyboardAction action) {
    return action == LMKeyboardActionControl ||
        action == LMKeyboardActionShift ||
        action == LMKeyboardActionAlt ||
        action == LMKeyboardActionWindows;
}

- (void)sendKeyboardAction:(LMKeyboardAction)action pressed:(BOOL)pressed {
    NSNumber *actionNumber = @(action);
    if (LMKeyboardActionIsModifier(action)) {
        if (pressed) {
            if ([_activeKeyboardActions containsObject:actionNumber]) {
                return;
            }
            [_activeKeyboardActions addObject:actionNumber];
        }
        else if (![_activeKeyboardActions containsObject:actionNumber]) {
            return;
        }
        else {
            [_activeKeyboardActions removeObject:actionNumber];
        }

        if (self.keyboardActionHandler != nil) {
            self.keyboardActionHandler(action, pressed);
        }
        return;
    }

    if (pressed && self.keyboardActionHandler != nil) {
        self.keyboardActionHandler(action, YES);
        self.keyboardActionHandler(action, NO);
    }
}

- (void)releaseAllKeyboardActions {
    NSArray<NSNumber *> *actions = [_activeKeyboardActions allObjects];
    for (NSNumber *actionNumber in actions) {
        [self sendKeyboardAction:actionNumber.integerValue pressed:NO];
    }
    [_activeKeyboardActions removeAllObjects];
}

- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    [self releaseAllKeyboardActions];
    return resigned;
}

- (NSSet<NSNumber *> *)activeKeyboardActions {
    return [_activeKeyboardActions copy];
}

- (void)dealloc {
    [self releaseAllKeyboardActions];
}

- (UIEditingInteractionConfiguration) editingInteractionConfiguration {
    // Suppress the Undo menu that appears with a 3 finger tap
    return UIEditingInteractionConfigurationNone;
}

@end
