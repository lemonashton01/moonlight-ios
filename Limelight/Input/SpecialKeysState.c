//
//  SpecialKeysState.c
//  Moonlight
//

#include "SpecialKeysState.h"

// Avoid classifying an exact 600 ms boundary as short due to binary floating-point rounding.
static const double SpecialKeysTimingEpsilon = 0.000001;

static const SpecialKeysActionDescriptor SpecialKeysSpecialActions[] = {
    { "Esc", SpecialKeysActionKey, SpecialKeyCodeEscape },
    { "Tab", SpecialKeysActionKey, SpecialKeyCodeTab },
    { "Insert", SpecialKeysActionKey, SpecialKeyCodeInsert },
    { "Delete", SpecialKeysActionKey, SpecialKeyCodeDelete },
    { "Home", SpecialKeysActionKey, SpecialKeyCodeHome },
    { "End", SpecialKeysActionKey, SpecialKeyCodeEnd },
    { "PgUp", SpecialKeysActionKey, SpecialKeyCodePageUp },
    { "PgDn", SpecialKeysActionKey, SpecialKeyCodePageDown },
    { "Cursor", SpecialKeysActionCursorToggle, SpecialKeyCodeNone },
};

static const SpecialKeysSequenceEvent SpecialKeysCursorToggleSequence[] = {
    { SpecialKeyCodeControl, SpecialKeysSequenceKeyDown, 0 },
    { SpecialKeyCodeAlt, SpecialKeysSequenceKeyDown, 0 },
    { SpecialKeyCodeShift, SpecialKeysSequenceKeyDown, 0 },
    { SpecialKeyCodeN, SpecialKeysSequenceKeyDown, SPECIAL_KEYS_KEY_HOLD_DURATION },
    { SpecialKeyCodeN, SpecialKeysSequenceKeyUp, 0 },
    { SpecialKeyCodeShift, SpecialKeysSequenceKeyUp, 0 },
    { SpecialKeyCodeAlt, SpecialKeysSequenceKeyUp, 0 },
    { SpecialKeyCodeControl, SpecialKeysSequenceKeyUp, 0 },
};

const SpecialKeysActionDescriptor *SpecialKeysGetSpecialActions(size_t *count) {
    *count = sizeof(SpecialKeysSpecialActions) / sizeof(SpecialKeysSpecialActions[0]);
    return SpecialKeysSpecialActions;
}

const SpecialKeysSequenceEvent *SpecialKeysGetCursorToggleSequence(size_t *count) {
    *count = sizeof(SpecialKeysCursorToggleSequence) / sizeof(SpecialKeysCursorToggleSequence[0]);
    return SpecialKeysCursorToggleSequence;
}

void SpecialKeysGestureReset(SpecialKeysGestureState *state) {
    state->tracking = false;
    state->completed = false;
    state->peakTouchCount = 0;
    state->threeFingerStartTime = 0;
}

bool SpecialKeysGestureTouchCountChanged(SpecialKeysGestureState *state,
                                         unsigned int touchCount,
                                         double timestamp) {
    if (touchCount > state->peakTouchCount) {
        state->peakTouchCount = touchCount;
    }

    if (state->completed) {
        return false;
    }

    if (touchCount > SPECIAL_KEYS_THREE_FINGER_COUNT) {
        state->tracking = false;
        state->completed = true;
        return false;
    }

    if (touchCount == SPECIAL_KEYS_THREE_FINGER_COUNT && !state->tracking) {
        state->tracking = true;
        state->threeFingerStartTime = timestamp;
        return true;
    }

    return false;
}

static SpecialKeysGestureResult completeGesture(SpecialKeysGestureState *state,
                                                SpecialKeysGestureResult result) {
    state->tracking = false;
    state->completed = true;
    return result;
}

SpecialKeysGestureResult SpecialKeysGestureTimerFired(SpecialKeysGestureState *state,
                                                      unsigned int touchCount,
                                                      double timestamp) {
    if (!state->tracking || state->completed ||
        touchCount != SPECIAL_KEYS_THREE_FINGER_COUNT) {
        return SpecialKeysGestureResultNone;
    }

    if (timestamp - state->threeFingerStartTime + SpecialKeysTimingEpsilon >= SPECIAL_KEYS_LONG_PRESS_DURATION) {
        return completeGesture(state, SpecialKeysGestureResultLongPress);
    }

    return SpecialKeysGestureResultNone;
}

SpecialKeysGestureResult SpecialKeysGestureTouchesEnded(SpecialKeysGestureState *state,
                                                        unsigned int remainingTouchCount,
                                                        double timestamp) {
    SpecialKeysGestureResult result = SpecialKeysGestureResultNone;

    if (state->tracking && !state->completed &&
        remainingTouchCount < SPECIAL_KEYS_THREE_FINGER_COUNT) {
        if (timestamp - state->threeFingerStartTime + SpecialKeysTimingEpsilon >= SPECIAL_KEYS_LONG_PRESS_DURATION) {
            result = completeGesture(state, SpecialKeysGestureResultLongPress);
        }
        else {
            result = completeGesture(state, SpecialKeysGestureResultShortTap);
        }
    }

    if (remainingTouchCount == 0) {
        SpecialKeysGestureReset(state);
    }

    return result;
}

void SpecialKeysGestureCancel(SpecialKeysGestureState *state) {
    SpecialKeysGestureReset(state);
}

void SpecialKeysPanelResetSession(SpecialKeysPanelState *state) {
    state->visible = false;
    state->fixed = false;
    state->selectedTab = SpecialKeysTabFunction;
}

void SpecialKeysPanelShow(SpecialKeysPanelState *state) {
    state->visible = true;
    state->fixed = false;
}

void SpecialKeysPanelHide(SpecialKeysPanelState *state) {
    state->visible = false;
    state->fixed = false;
}

void SpecialKeysPanelSetFixed(SpecialKeysPanelState *state, bool fixed) {
    state->fixed = fixed;
}

void SpecialKeysPanelSetSelectedTab(SpecialKeysPanelState *state, SpecialKeysTab tab) {
    state->selectedTab = tab;
}

bool SpecialKeysPanelShouldCloseAfterKey(const SpecialKeysPanelState *state) {
    return !state->fixed;
}
