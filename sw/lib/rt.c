// rt.c — the few routines a compiler calls behind your back.
//
// TinyPulse is RV32E with no M extension, so the compiler turns *, / and %
// into calls to these (the names are the ones GCC and Clang both use). It
// may also call memcpy/memset for struct copies and array initializers even
// when you never wrote them. All are small and slow on purpose: a
// shift-and-add multiply is about 32 loop iterations.
#include <stdint.h>
#include <stddef.h>

uint32_t __mulsi3(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    while (b) { if (b & 1) r += a; a <<= 1; b >>= 1; }
    return r;
}
static uint32_t udivmod(uint32_t n, uint32_t d, uint32_t *rem) {
    if (d == 0) { if (rem) *rem = n; return 0xFFFFFFFFu; }   // RISC-V's defined result
    uint32_t q = 0, r = 0;
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1);
        if (r >= d) { r -= d; q |= 1u << i; }
    }
    if (rem) *rem = r;
    return q;
}
uint32_t __udivsi3(uint32_t n, uint32_t d) { return udivmod(n, d, 0); }
uint32_t __umodsi3(uint32_t n, uint32_t d) { uint32_t r; udivmod(n, d, &r); return r; }
int32_t __divsi3(int32_t n, int32_t d) {
    int neg = (n < 0) ^ (d < 0);
    uint32_t q = udivmod(n < 0 ? -(uint32_t)n : (uint32_t)n, d < 0 ? -(uint32_t)d : (uint32_t)d, 0);
    return neg ? -(int32_t)q : (int32_t)q;
}
int32_t __modsi3(int32_t n, int32_t d) {
    uint32_t r;
    udivmod(n < 0 ? -(uint32_t)n : (uint32_t)n, d < 0 ? -(uint32_t)d : (uint32_t)d, &r);
    return n < 0 ? -(int32_t)r : (int32_t)r;
}
void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst; const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dst;
}
void *memset(void *dst, int c, size_t n) {
    uint8_t *d = dst;
    while (n--) *d++ = (uint8_t)c;
    return dst;
}
