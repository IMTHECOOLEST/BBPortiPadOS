#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <CoreHaptics/CoreHaptics.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "bb_ios_pad.h"

/* ---- finding the controller ---- */

static GCController *extras_controller(void) {
    for (GCController *c in [GCController controllers]) {
        GCExtendedGamepad *g = c.extendedGamepad;
        if ([g isKindOfClass:[GCDualSenseGamepad class]] || [g isKindOfClass:[GCDualShockGamepad class]]) return c;
    }
    return nil;
}

static GCController *haptics_controller(void) {
    GCController *ds = extras_controller();
    if (ds && ds.haptics) return ds;
    for (GCController *c in [GCController controllers]) if (c.haptics) return c;
    return nil;
}

/* ---- touchpad and motion ---- */

static void add_finger(GCControllerDirectionPad *pad, BBNativePad *out) {
    if (!pad || out->touch_count >= 2) return;
    const float x = pad.xAxis.value, y = pad.yAxis.value;
    /* The framework reports 0,0 when no finger rests on the pad; a finger exactly in the middle
     * is indistinguishable from none (a known limit of this API). */
    if (x == 0.0f && y == 0.0f) return;
    const float fx = fminf(1.0f, fmaxf(0.0f, x * 0.5f + 0.5f));
    const float fy = fminf(1.0f, fmaxf(0.0f, 0.5f - y * 0.5f)); /* +1 is the top edge; the game's y=0 is the top */
    out->x[out->touch_count] = (uint16_t)(fx * 1919.0f);
    out->y[out->touch_count] = (uint16_t)(fy * 942.0f);
    out->touch_count++;
}

int bb_ios_pad_sample(BBNativePad *out) {
    memset(out, 0, sizeof *out);
    out->orientation[3] = 1.0f;
    GCController *c = extras_controller();
    if (!c) return 0;
    GCExtendedGamepad *g = c.extendedGamepad;
    if ([g isKindOfClass:[GCDualSenseGamepad class]]) {
        GCDualSenseGamepad *ds = (GCDualSenseGamepad *)g;
        add_finger(ds.touchpadPrimary, out);
        add_finger(ds.touchpadSecondary, out);
    } else if ([g isKindOfClass:[GCDualShockGamepad class]]) {
        GCDualShockGamepad *ds = (GCDualShockGamepad *)g;
        add_finger(ds.touchpadPrimary, out);
        add_finger(ds.touchpadSecondary, out);
    }
    GCMotion *m = c.motion;
    if (m) {
        if (m.sensorsRequireManualActivation && !m.sensorsActive) m.sensorsActive = YES;
        if (m.sensorsActive) {
            out->has_motion = 1;
            if (m.hasRotationRate) {
                out->angular_velocity[0] = (float)m.rotationRate.x;
                out->angular_velocity[1] = (float)m.rotationRate.y;
                out->angular_velocity[2] = (float)m.rotationRate.z;
            }
            if (m.hasGravityAndUserAcceleration) {
                out->acceleration[0] = (float)(m.gravity.x + m.userAcceleration.x);
                out->acceleration[1] = (float)(m.gravity.y + m.userAcceleration.y);
                out->acceleration[2] = (float)(m.gravity.z + m.userAcceleration.z);
            }
            if (m.hasAttitude) {
                out->orientation[0] = (float)m.attitude.x;
                out->orientation[1] = (float)m.attitude.y;
                out->orientation[2] = (float)m.attitude.z;
                out->orientation[3] = (float)m.attitude.w;
            }
        }
    }
    return 1;
}

/* ---- haptics ----
 * One continuous event per motor (left handle: the large motor, right handle: the small one),
 * whose intensity is changed with dynamic parameters. A timer silences both when the game stops
 * refreshing them, as the PS4 pad does. */

typedef struct {
    GCController *controller;
    CHHapticEngine *engine;
    id<CHHapticAdvancedPatternPlayer> player;
    CFAbsoluteTime started;
} Motor;

static Motor motors[2];
static dispatch_queue_t haptic_queue;
static dispatch_source_t haptic_timer;
static CFAbsoluteTime haptic_deadline;
static float haptic_level[2];

static BOOL haptics_enabled(void) {
    const char *v = getenv("BB_HAPTICS");
    return !(v && v[0] == '0');
}

static void motor_reset(Motor *m) {
    if (m->player) { [m->player cancelAndReturnError:nil]; m->player = nil; }
    if (m->engine) { [m->engine stopWithCompletionHandler:nil]; m->engine = nil; }
}

static BOOL motor_ready(int i, GCController *c) {
    Motor *m = &motors[i];
    if (m->controller != c) { motor_reset(m); m->controller = c; }
    GCHapticsLocality locality = i == 0 ? GCHapticsLocalityLeftHandle : GCHapticsLocalityRightHandle;
    if (!m->engine) {
        CHHapticEngine *engine = [c.haptics createEngineWithLocality:locality];
        if (!engine) return NO;
        engine.autoShutdownEnabled = NO;
        NSError *error = nil;
        if (![engine startAndReturnError:&error]) return NO;
        const int index = i;
        engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
            dispatch_async(haptic_queue, ^{ motors[index].player = nil; motors[index].engine = nil; });
        };
        m->engine = engine;
    }
    /* A continuous event lasts 30 s at most: start a new one a little before that. */
    if (m->player && CFAbsoluteTimeGetCurrent() - m->started > 25.0) {
        [m->player cancelAndReturnError:nil];
        m->player = nil;
    }
    if (!m->player) {
        CHHapticEventParameter *intensity = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1.0f];
        CHHapticEventParameter *sharpness = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:(i == 0 ? 0.2f : 0.9f)];
        CHHapticEvent *event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
                                                              parameters:@[intensity, sharpness]
                                                            relativeTime:0
                                                                duration:30.0];
        NSError *error = nil;
        CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[event] parameters:@[] error:&error];
        if (!pattern) return NO;
        id<CHHapticAdvancedPatternPlayer> player = [m->engine createAdvancedPlayerWithPattern:pattern error:&error];
        if (!player) return NO;
        CHHapticDynamicParameter *zero = [[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:0.0f relativeTime:0];
        [player sendParameters:@[zero] atTime:CHHapticTimeImmediate error:nil];
        if (![player startAtTime:CHHapticTimeImmediate error:&error]) return NO;
        m->player = player;
        m->started = CFAbsoluteTimeGetCurrent();
    }
    return YES;
}

static void apply_level(int i, float level) {
    Motor *m = &motors[i];
    if (!m->player) return;
    CHHapticDynamicParameter *p = [[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:level relativeTime:0];
    [m->player sendParameters:@[p] atTime:CHHapticTimeImmediate error:nil];
}

static void haptic_setup_once(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        haptic_queue = dispatch_queue_create("bb.haptics", DISPATCH_QUEUE_SERIAL);
        haptic_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, haptic_queue);
        dispatch_source_set_timer(haptic_timer, DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(haptic_timer, ^{
            if ((haptic_level[0] > 0.0f || haptic_level[1] > 0.0f) && CFAbsoluteTimeGetCurrent() > haptic_deadline) {
                for (int i = 0; i < 2; ++i) { haptic_level[i] = 0.0f; apply_level(i, 0.0f); }
            }
        });
        dispatch_resume(haptic_timer);
    });
}

int bb_ios_vibrate(uint8_t large, uint8_t small, uint32_t ms) {
    if (!haptics_enabled()) return 1;
    haptic_setup_once();
    __block int handled = 0;
    dispatch_sync(haptic_queue, ^{
        GCController *c = haptics_controller();
        if (!c) return;
        const float levels[2] = { large / 255.0f, small / 255.0f };
        for (int i = 0; i < 2; ++i) {
            /* Nothing to start for an idle motor; an existing player just gets 0. */
            if (levels[i] > 0.0f && !motor_ready(i, c)) return;
            haptic_level[i] = levels[i];
            apply_level(i, levels[i]);
        }
        haptic_deadline = CFAbsoluteTimeGetCurrent() + (ms ? ms : 1000) / 1000.0;
        handled = 1;
    });
    return handled;
}
