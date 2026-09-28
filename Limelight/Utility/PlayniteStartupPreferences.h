// Session-independent preferences for the optional Playnite startup cover.
#ifndef PLAYNITE_STARTUP_PREFERENCES_H
#define PLAYNITE_STARTUP_PREFERENCES_H

#define PLAYNITE_STARTUP_ANIMATION_ENABLED_KEY @"playniteStartupAnimationEnabled"
#define PLAYNITE_READINESS_SHARED_KEY @"playniteReadinessSharedKey"

#if DEBUG
// Temporary A/B controls for isolating AVPlayer pause during stream startup.
#define PLAYNITE_STARTUP_DIAGNOSTIC_MODE_KEY @"playniteStartupDiagnosticMode"
#define PLAYNITE_DIAGNOSTIC_NORMAL 0
#define PLAYNITE_DIAGNOSTIC_NO_STREAM_AUDIO 1
#define PLAYNITE_DIAGNOSTIC_NO_VIDEO_ENQUEUE 2
#endif

#endif
