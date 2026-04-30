/* Software 64-bit signed division for RV32IM (no hardware divider) */
typedef          int  int32_t;
typedef unsigned int uint32_t;
typedef          long long int64_t;
typedef unsigned long long uint64_t;

int64_t __divdi3(int64_t a, int64_t b) {
    int neg = 0;
    if (a < 0) { a = -a; neg = !neg; }
    if (b < 0) { b = -b; neg = !neg; }
    uint64_t ua = (uint64_t)a;
    uint64_t ub = (uint64_t)b;
    uint64_t q = 0;
    for (int i = 63; i >= 0; i--) {
        q <<= 1;
        if ((ua >> i) >= ub) {
            uint64_t t = (uint64_t)ub << i;
            if (t <= ua) { ua -= t; q |= 1; }
        }
    }
    return neg ? -(int64_t)q : (int64_t)q;
}

uint64_t __udivdi3(uint64_t a, uint64_t b) {
    uint64_t q = 0;
    for (int i = 63; i >= 0; i--) {
        q <<= 1;
        if ((a >> i) >= b) {
            uint64_t t = b << i;
            if (t <= a) { a -= t; q |= 1; }
        }
    }
    return q;
}

int64_t __moddi3(int64_t a, int64_t b) {
    int64_t q = __divdi3(a, b);
    return a - q * b;
}

uint64_t __umoddi3(uint64_t a, uint64_t b) {
    uint64_t q = __udivdi3(a, b);
    return a - q * b;
}
