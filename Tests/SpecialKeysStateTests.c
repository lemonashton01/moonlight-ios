// Standalone logic tests. On macOS:
// clang -std=c11 Tests/SpecialKeysStateTests.c Limelight/Input/SpecialKeysState.c -o /tmp/special-keys-tests && /tmp/special-keys-tests

#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "../Limelight/Input/SpecialKeysState.h"

static void testThreeFingerShortTap(void) {
    SpecialKeysGestureState state;
    SpecialKeysGestureReset(&state);

    assert(!SpecialKeysGestureTouchCountChanged(&state, 1, 1.0));
    assert(!SpecialKeysGestureTouchCountChanged(&state, 2, 1.1));
    assert(SpecialKeysGestureTouchCountChanged(&state, 3, 1.2));
    assert(SpecialKeysGestureTouchesEnded(&state, 2, 1.799) == SpecialKeysGestureResultShortTap);
    assert(SpecialKeysGestureTouchesEnded(&state, 0, 1.8) == SpecialKeysGestureResultNone);
}

static void testThreeFingerLongPress(void) {
    SpecialKeysGestureState state;
    SpecialKeysGestureReset(&state);

    assert(SpecialKeysGestureTouchCountChanged(&state, 3, 4.0));
    assert(SpecialKeysGestureTimerFired(&state, 3, 4.599) == SpecialKeysGestureResultNone);
    assert(SpecialKeysGestureTimerFired(&state, 3, 4.600) == SpecialKeysGestureResultLongPress);
    assert(SpecialKeysGestureTouchesEnded(&state, 0, 4.7) == SpecialKeysGestureResultNone);
}

static void testDelayedTimerStillProducesLongPress(void) {
    SpecialKeysGestureState state;
    SpecialKeysGestureReset(&state);

    assert(SpecialKeysGestureTouchCountChanged(&state, 3, 8.0));
    assert(SpecialKeysGestureTouchesEnded(&state, 2, 8.7) == SpecialKeysGestureResultLongPress);
}

static void testOneTwoAndFourFingersDoNotTrigger(void) {
    SpecialKeysGestureState state;
    SpecialKeysGestureReset(&state);

    SpecialKeysGestureTouchCountChanged(&state, 1, 1.0);
    assert(SpecialKeysGestureTouchesEnded(&state, 0, 1.1) == SpecialKeysGestureResultNone);
    SpecialKeysGestureTouchCountChanged(&state, 2, 2.0);
    assert(SpecialKeysGestureTouchesEnded(&state, 0, 2.1) == SpecialKeysGestureResultNone);
    SpecialKeysGestureTouchCountChanged(&state, 3, 3.0);
    SpecialKeysGestureTouchCountChanged(&state, 4, 3.1);
    assert(SpecialKeysGestureTimerFired(&state, 4, 4.0) == SpecialKeysGestureResultNone);
    assert(SpecialKeysGestureTouchesEnded(&state, 0, 4.1) == SpecialKeysGestureResultNone);
}

static void testPanelSessionBehavior(void) {
    SpecialKeysPanelState state;
    SpecialKeysPanelResetSession(&state);
    assert(state.selectedTab == SpecialKeysTabFunction);

    SpecialKeysPanelShow(&state);
    SpecialKeysPanelSetSelectedTab(&state, SpecialKeysTabSpecial);
    assert(SpecialKeysPanelShouldCloseAfterKey(&state));
    SpecialKeysPanelHide(&state);
    SpecialKeysPanelShow(&state);
    assert(state.selectedTab == SpecialKeysTabSpecial);

    SpecialKeysPanelSetFixed(&state, true);
    assert(!SpecialKeysPanelShouldCloseAfterKey(&state));
    SpecialKeysPanelHide(&state);
    assert(!state.fixed);
    SpecialKeysPanelShow(&state);
    SpecialKeysPanelSetFixed(&state, true);
    SpecialKeysPanelSetFixed(&state, false);
    assert(SpecialKeysPanelShouldCloseAfterKey(&state));

    SpecialKeysPanelResetSession(&state);
    assert(state.selectedTab == SpecialKeysTabFunction);
    assert(!state.visible);
}

static void testKeyCodesAndHoldDuration(void) {
    assert(SpecialKeyCodeF1 == 0x70);
    assert(SpecialKeyCodeF2 == 0x71);
    assert(SpecialKeyCodeF3 == 0x72);
    assert(SpecialKeyCodeF4 == 0x73);
    assert(SpecialKeyCodeF5 == 0x74);
    assert(SpecialKeyCodeF6 == 0x75);
    assert(SpecialKeyCodeF7 == 0x76);
    assert(SpecialKeyCodeF8 == 0x77);
    assert(SpecialKeyCodeF9 == 0x78);
    assert(SpecialKeyCodeF10 == 0x79);
    assert(SpecialKeyCodeF11 == 0x7A);
    assert(SpecialKeyCodeF12 == 0x7B);
    assert(SpecialKeyCodeEscape == 0x1B && SpecialKeyCodeTab == 0x09);
    assert(SpecialKeyCodeInsert == 0x2D && SpecialKeyCodeDelete == 0x2E);
    assert(SpecialKeyCodeHome == 0x24 && SpecialKeyCodeEnd == 0x23);
    assert(SpecialKeyCodePageUp == 0x21 && SpecialKeyCodePageDown == 0x22);
    assert(SPECIAL_KEYS_KEY_HOLD_DURATION >= 0.060);
}

static void testCursorActionAndSequence(void) {
    size_t actionCount;
    const SpecialKeysActionDescriptor *actions = SpecialKeysGetSpecialActions(&actionCount);
    assert(actionCount == 11);
    assert(strcmp(actions[8].title, "Cursor") == 0);
    assert(actions[8].action == SpecialKeysActionCursorToggle);
    assert(actions[8].action != SpecialKeysActionKey);
    assert(strcmp(actions[9].title, "OSC") == 0);
    assert(actions[9].action == SpecialKeysActionOscToggle);
    assert(actions[9].keyCode == SpecialKeyCodeNone);
    assert(strcmp(actions[10].title, "ALT+F4") == 0);
    assert(actions[10].action == SpecialKeysActionAltF4);
    assert(actions[10].keyCode == SpecialKeyCodeNone);

    const SpecialKeyCode expectedKeyCodes[] = {
        SpecialKeyCodeEscape,
        SpecialKeyCodeTab,
        SpecialKeyCodeInsert,
        SpecialKeyCodeDelete,
        SpecialKeyCodeHome,
        SpecialKeyCodeEnd,
        SpecialKeyCodePageUp,
        SpecialKeyCodePageDown,
    };
    for (size_t i = 0; i < 8; i++) {
        assert(actions[i].action == SpecialKeysActionKey);
        assert(actions[i].keyCode == expectedKeyCodes[i]);
    }

    size_t eventCount;
    const SpecialKeysSequenceEvent *events = SpecialKeysGetCursorToggleSequence(&eventCount);
    assert(eventCount == 8);
    assert(events[0].keyCode == SpecialKeyCodeControl && events[0].keyAction == SpecialKeysSequenceKeyDown);
    assert(events[1].keyCode == SpecialKeyCodeAlt && events[1].keyAction == SpecialKeysSequenceKeyDown);
    assert(events[2].keyCode == SpecialKeyCodeShift && events[2].keyAction == SpecialKeysSequenceKeyDown);
    assert(events[3].keyCode == SpecialKeyCodeN && events[3].keyAction == SpecialKeysSequenceKeyDown);
    assert(events[3].delayAfter >= 0.060);
    assert(events[4].keyCode == SpecialKeyCodeN && events[4].keyAction == SpecialKeysSequenceKeyUp);
    assert(events[5].keyCode == SpecialKeyCodeShift && events[5].keyAction == SpecialKeysSequenceKeyUp);
    assert(events[6].keyCode == SpecialKeyCodeAlt && events[6].keyAction == SpecialKeysSequenceKeyUp);
    assert(events[7].keyCode == SpecialKeyCodeControl && events[7].keyAction == SpecialKeysSequenceKeyUp);
    for (size_t i = 0; i < eventCount; i++) {
        if (i != 3) {
            assert(events[i].delayAfter == 0);
        }
    }
}

static void testAltF4Sequence(void) {
    size_t eventCount;
    const SpecialKeysSequenceEvent *events = SpecialKeysGetAltF4Sequence(&eventCount);
    assert(eventCount == 4);
    assert(events[0].keyCode == SpecialKeyCodeAlt && events[0].keyAction == SpecialKeysSequenceKeyDown);
    assert(events[1].keyCode == SpecialKeyCodeF4 && events[1].keyAction == SpecialKeysSequenceKeyDown);
    assert(events[1].delayAfter >= 0.060);
    assert(events[2].keyCode == SpecialKeyCodeF4 && events[2].keyAction == SpecialKeysSequenceKeyUp);
    assert(events[3].keyCode == SpecialKeyCodeAlt && events[3].keyAction == SpecialKeysSequenceKeyUp);

    // The sequence leaves neither the function key nor Alt held.
    unsigned int held = 0;
    for (size_t i = 0; i < eventCount; i++) {
        unsigned int bit = events[i].keyCode == SpecialKeyCodeAlt ? 1u : 2u;
        if (events[i].keyAction == SpecialKeysSequenceKeyDown) {
            held |= bit;
        }
        else {
            held &= ~bit;
        }
    }
    assert(held == 0);
}

int main(void) {
    testThreeFingerShortTap();
    testThreeFingerLongPress();
    testDelayedTimerStillProducesLongPress();
    testOneTwoAndFourFingersDoNotTrigger();
    testPanelSessionBehavior();
    testKeyCodesAndHoldDuration();
    testCursorActionAndSequence();
    testAltF4Sequence();
    puts("Special Keys state tests passed");
    return 0;
}
