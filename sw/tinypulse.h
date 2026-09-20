// tinypulse.h — the Xpulse time extension from C, with a stock toolchain.
//
// No custom compiler and no patched binutils. Every instruction below is
// emitted with the GNU assembler's `.insn` directive, which takes the raw
// field values and assembles them into the custom-0 opcode space. Build with:
//
//   riscv32-unknown-elf-gcc -march=rv32e -mabi=ilp32e ...
//
// Field order for `.insn r` is: opcode, funct3, funct7, rd, rs1, rs2.
#ifndef TINYPULSE_H
#define TINYPULSE_H

#include <stdint.h>

#define TP_OPC 0x0B

// ---- reads -----------------------------------------------------------

// Current timebase. One tick is one core clock.
static inline uint32_t tp_time(void) {
    uint32_t v;
    __asm__ volatile (".insn r %1, 0, 0, %0, x0, x0"
                      : "=r"(v) : "i"(TP_OPC));
    return v;
}

// Pop the oldest event off the queue. Returns 0 if the queue is empty;
// check tp_stat() first if zero is a value you care about.
static inline uint32_t tp_pop(void) {
    uint32_t v;
    __asm__ volatile (".insn r %1, 1, 0, %0, x0, x0"
                      : "=r"(v) : "i"(TP_OPC));
    return v;
}

// Status word: queue depth, overflow, armed mask, live capture levels.
static inline uint32_t tp_stat(void) {
    uint32_t v;
    __asm__ volatile (".insn r %1, 2, 0, %0, x0, x0"
                      : "=r"(v) : "i"(TP_OPC));
    return v;
}

// ---- the one that matters --------------------------------------------

// Block until the timebase reaches `deadline`. The core stops fetching and
// resumes on exactly that tick. No interrupt, no polling loop, no jitter.
static inline void tp_wait(uint32_t deadline) {
    __asm__ volatile (".insn r %1, 3, 0, x0, %0, x0"
                      :: "r"(deadline), "i"(TP_OPC) : "memory");
}

// ---- outputs ---------------------------------------------------------

// Arm trigger channel `ch` to fire when the timebase reaches `deadline`.
static inline void tp_arm(uint32_t deadline, uint32_t ch) {
    __asm__ volatile (".insn r %2, 4, 0, x0, %0, %1"
                      :: "r"(deadline), "r"(ch), "i"(TP_OPC));
}

// Fire trigger channels in `mask` immediately.
static inline void tp_pulse(uint32_t mask) {
    __asm__ volatile (".insn r %1, 5, 0, x0, %0, x0"
                      :: "r"(mask), "i"(TP_OPC));
}

// Push a software event carrying `tag` (0-7) into the same ordered queue
// the hardware captures use, and return its timestamp. This is how you
// correlate "when the code got here" against "when the pin moved".
static inline uint32_t tp_mark(uint32_t tag) {
    uint32_t v;
    __asm__ volatile (".insn r %2, 6, 0, %0, %1, x0"
                      : "=r"(v) : "r"(tag), "i"(TP_OPC));
    return v;
}

// ---- clock discipline ------------------------------------------------

// Step the timebase by a signed amount, in one clock. Coarse; use once.
static inline void tp_adj(int32_t delta) {
    __asm__ volatile (".insn r %1, 7, 0, x0, %0, x0"
                      :: "r"(delta), "i"(TP_OPC));
}

// Slew the timebase. Bit 31 is the sign, bits 23:0 the magnitude in units
// of 2^-24 tick per clock (about 0.0596 parts per million per count).
// Prefer this over tp_adj once you are locked: a step can make a
// timestamp go backwards, a slew cannot.
static inline void tp_rate(uint32_t rate) {
    __asm__ volatile (".insn r %1, 7, 1, x0, %0, x0"
                      :: "r"(rate), "i"(TP_OPC));
}

// Capture configuration: bits 7:0 enable channels, bits 15:8 select the
// falling edge for that channel, bit 16 captures both edges.
static inline void tp_cfg(uint32_t cfg) {
    __asm__ volatile (".insn r %1, 7, 2, x0, %0, x0"
                      :: "r"(cfg), "i"(TP_OPC));
}

// Trigger pulse width in ticks (all channels share it).
static inline void tp_pw(uint32_t ticks) {
    __asm__ volatile (".insn r %1, 7, 3, x0, %0, x0"
                      :: "r"(ticks), "i"(TP_OPC));
}

// ---- event word helpers ----------------------------------------------

#define TP_EVT_IS_SOFTWARE(e) (((e) >> 31) & 1u)
#define TP_EVT_CHANNEL(e)     (((e) >> 28) & 7u)
#define TP_EVT_RISING(e)      (((e) >> 27) & 1u)
#define TP_EVT_TIMESTAMP(e)   ((e) & 0x07FFFFFFu)

// ---- status word helpers ---------------------------------------------

#define TP_STAT_COUNT(s)      ((s) & 0xFu)
#define TP_STAT_EMPTY(s)      (((s) >> 4) & 1u)
#define TP_STAT_FULL(s)       (((s) >> 5) & 1u)
#define TP_STAT_OVERFLOW(s)   (((s) >> 6) & 1u)
#define TP_STAT_ARMED(s)      (((s) >> 8) & 0xFu)
#define TP_STAT_TRIGGERS(s)   (((s) >> 12) & 0xFu)
#define TP_STAT_LEVELS(s)     (((s) >> 16) & 0xFFu)

// ---- memory-mapped alternative ---------------------------------------
// Same registers, reachable by load/store for a host or a debugger. Slower
// than the instructions above: a load goes out over the data bus.

#define TP_SYNC_BASE 0x20000000u
#define TP_REG(n)    (*(volatile uint32_t *)(TP_SYNC_BASE + ((n) * 4)))
#define TP_TIME      TP_REG(0)
#define TP_EVENT     TP_REG(1)   // reading pops
#define TP_STATUS    TP_REG(2)
#define TP_CFG       TP_REG(3)
#define TP_CMP0      TP_REG(4)
#define TP_CMP1      TP_REG(5)
#define TP_ARM       TP_REG(6)
#define TP_PW        TP_REG(7)
#define TP_ADJ       TP_REG(8)
#define TP_RATE      TP_REG(9)
#define TP_PULSE     TP_REG(10)

#define TP_PSRAM_BASE 0x10000000u

#endif // TINYPULSE_H
