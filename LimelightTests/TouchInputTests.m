#import <XCTest/XCTest.h>

#import "AbsoluteTouchHandler.h"
#import "RelativeTouchHandler.h"

@interface TouchInputTests : XCTestCase
@end

@implementation TouchInputTests

- (void)testAspectFitVideoMapsTheDisplayedCenter {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(0, 96, 1024, 576);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(512, 384),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.5, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 0.5, 0.0001);
}

- (void)testCroppedVideoMapsTheVisibleViewportIntoTheVideo {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(-128, -64, 1280, 896);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(0, 0),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.1, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 64.0 / 896.0, 0.0001);
}

- (void)testLandscapeVideoUsesTheDisplayedRectAfterRotation {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(128, 0, 768, 768);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(512, 192),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.5, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 0.25, 0.0001);
}

- (void)testPointOutsideDisplayedVideoClampsToTheNearestVideoEdge {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(128, 96, 768, 576);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(0, 0),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 0.0, 0.0001);
}

- (void)testVideoEdgesClampNormalizedCoordinatesToUnitRange {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(128, 96, 768, 576);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(1024, 768),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 1.0, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 1.0, 0.0001);
}

- (void)testTwoFingerScrollUsesTheCenterMovementDelta {
    CGPoint delta = LMScrollDeltaForTouchMovement(CGPointMake(100, 200),
                                                   CGPointMake(100, 224));

    XCTAssertEqualWithAccuracy(delta.x, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(delta.y, 24.0, 0.0001);
}

@end
