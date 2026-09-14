//
//  SpecialKeysState.h
//  Moonlight
//
//  State shared by the Special Keys gesture and panel. This file intentionally
//  has no UIKit dependency so the timing and session behavior can be unit tested.
//

#ifndef SpecialKeysState_h
#define SpecialKeysState_h

#include <stdbool.h>
#include <stddef.h>

#define SPECIAL_KEYS_THREE_FINGER_COUNT 3
#define SPECIAL_KEYS_LONG_PRESS_DURATION 0.600
#define SPECIAL_KEYS_KEY_HOLD_DURATION 0.060

typedef enum {
    SpecialKeysGestureResultNone = 0,
    SpecialKeysGestureResultShortTap,
    SpecialKeysGestureResultLongPress,
} SpecialKeysGestureResult;

typedef struct {
    bool tracking;
    bool completed;
    unsigned int peakTouchCount;
    double threeFingerStartTime;
} SpecialKeysGestureState;

void SpecialKeysGestureReset(SpecialKeysGestureState *state);
bool SpecialKeysGestureTouchCountChanged(SpecialKeysGestureState *state,
                                         unsigned int touchCount,
                                         double timestamp);
SpecialKeysGestureResult SpecialKeysGestureTimerFired(SpecialKeysGestureState *state,
                                                      unsigned int touchCount,
                                                      double timestamp);
SpecialKeysGestureResult SpecialKeysGestureTouchesEnded(SpecialKeysGestureState *state,
                                                        unsigned int remainingTouchCount,
                                                        double timestamp);
void SpecialKeysGestureCancel(SpecialKeysGestureState *state);

typedef enum {
    SpecialKeysTabFunction = 0,
    SpecialKeysTabSpecial = 1,
} SpecialKeysTab;

typedef struct {
    bool visible;
    bool fixed;
    SpecialKeysTab selectedTab;
} SpecialKeysPanelState;

void SpecialKeysPanelResetSession(SpecialKeysPanelState *state);
void SpecialKeysPanelShow(SpecialKeysPanelState *state);
void SpecialKeysPanelHide(SpecialKeysPanelState *state);
void SpecialKeysPanelSetFixed(SpecialKeysPanelState *state, bool fixed);
void SpecialKeysPanelSetSelectedTab(SpecialKeysPanelState *state, SpecialKeysTab tab);
bool SpecialKeysPanelShouldCloseAfterKey(const SpecialKeysPanelState *state);

typedef enum {
    SpecialKeyCodeTab = 0x09,
    SpecialKeyCodeEscape = 0x1B,
    SpecialKeyCodePageUp = 0x21,
    SpecialKeyCodePageDown = 0x22,
    SpecialKeyCodeEnd = 0x23,
    SpecialKeyCodeHome = 0x24,
    SpecialKeyCodeInsert = 0x2D,
    SpecialKeyCodeDelete = 0x2E,
    SpecialKeyCodeF1 = 0x70,
    SpecialKeyCodeF2 = 0x71,
    SpecialKeyCodeF3 = 0x72,
    SpecialKeyCodeF4 = 0x73,
    SpecialKeyCodeF5 = 0x74,
    SpecialKeyCodeF6 = 0x75,
    SpecialKeyCodeF7 = 0x76,
    SpecialKeyCodeF8 = 0x77,
    SpecialKeyCodeF9 = 0x78,
    SpecialKeyCodeF10 = 0x79,
    SpecialKeyCodeF11 = 0x7A,
    SpecialKeyCodeF12 = 0x7B,
} SpecialKeyCode;

#endif /* SpecialKeysState_h */
