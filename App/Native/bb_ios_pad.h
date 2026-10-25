/* DualSense / DualShock 4 extras on iPadOS through Apple's GameController framework: touchpad
 * fingers, motion and CoreHaptics rumble. The runtime's runtime_pad.c calls these (see
 * patches/runtime/0001-ios-pad-extras.patch); buttons, sticks and triggers stay on SDL3. */
#ifndef BB_IOS_PAD_H
#define BB_IOS_PAD_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    int touch_count;                 /* fingers on the pad, 0..2 */
    uint16_t x[2], y[2];             /* PS4 touchpad units: x 0..1919, y 0..942 */
    int has_motion;
    float orientation[4];            /* quaternion x y z w (identity when unknown) */
    float acceleration[3];           /* g, controller frame */
    float angular_velocity[3];       /* rad/s, controller frame */
} BBNativePad;

/* 1 when a DualSense or DualShock 4 is connected and `out` is filled. */
int bb_ios_pad_sample(BBNativePad *out);
/* scePadSetVibration: large (left) and small (right) motor, 0..255, held for `ms` unless
 * refreshed. Returns 1 when this call handled it (also when haptics are switched off in the
 * settings), 0 when the caller should fall back to SDL_RumbleGamepad. */
int bb_ios_vibrate(uint8_t large, uint8_t small, uint32_t ms);
#ifdef __cplusplus
}
#endif
#endif
