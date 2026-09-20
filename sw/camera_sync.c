// camera_sync.c — what the chip is actually for.
//
// Fire a camera shutter at a fixed rate, timestamp the strobe return and an
// inertial measurement unit (IMU) data-ready line against the same clock,
// and report the offset between them. On a microcontroller the interrupt
// latency between those two events is tens of microseconds and it varies;
// here both are timestamped in hardware and the shutter edge is exact.

#include "tinypulse.h"

#define FRAME_TICKS   640000u      // 100 Hz at 64 MHz
#define CH_STROBE     0u           // CAP0: camera strobe return
#define CH_IMU        1u           // CAP1: IMU data ready
#define TRIG_SHUTTER  0u           // TRIG0 -> camera trigger input

volatile uint32_t last_skew;
volatile uint32_t frames;

int main(void) {
    // capture CAP0 and CAP1 on their rising edges
    tp_cfg((1u << CH_STROBE) | (1u << CH_IMU));
    tp_pw(64);                          // 1 us shutter pulse at 64 MHz

    uint32_t next = tp_time() + FRAME_TICKS;

    for (;;) {
        // Arm the shutter for the exact tick, then park until just after it.
        // The pin edge does not depend on when this loop gets around to it.
        tp_arm(next, TRIG_SHUTTER);
        tp_wait(next + 2000);

        uint32_t strobe_ts = 0, imu_ts = 0;
        uint32_t got = 0;

        while (!TP_STAT_EMPTY(tp_stat())) {
            uint32_t e = tp_pop();
            if (TP_EVT_IS_SOFTWARE(e))
                continue;
            if (TP_EVT_CHANNEL(e) == CH_STROBE) {
                strobe_ts = TP_EVT_TIMESTAMP(e);
                got |= 1u;
            } else if (TP_EVT_CHANNEL(e) == CH_IMU) {
                imu_ts = TP_EVT_TIMESTAMP(e);
                got |= 2u;
            }
        }

        if (got == 3u)
            last_skew = (imu_ts - strobe_ts) & 0x07FFFFFFu;

        frames++;
        next += FRAME_TICKS;
    }
}
