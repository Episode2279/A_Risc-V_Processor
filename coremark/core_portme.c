#include "core_portme.h"

/* CoreMark expects this global */
ee_u32 default_num_contexts = MULTITHREAD;

/* These globals are consumed by CoreMark's standard SEED_VOLATILE path in
 * core_util.c. Keep them non-static so the benchmark framework can read them.
 * seed1..seed3 select the benchmark dataset, seed4 controls the iteration
 * count, and seed5 selects which algorithm groups run. This port keeps seed5
 * at 0 so CoreMark enables its default "run everything" behavior.
 */
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

/* ---------------- MMIO helpers ---------------- */
static inline void mmio_write32(uintptr_t addr, uint32_t value) {
    // The simulated peripherals are simple memory-mapped registers, so a plain
    // volatile store is enough to emit UART bytes or signal test completion.
    *(volatile uint32_t *)addr = value;
}

static inline uint32_t mmio_read32(uintptr_t addr) {
    // Reads are currently only used to touch fromhost so the symbol remains
    // live and to mirror the way a real bare-metal environment would poll MMIO.
    return *(volatile uint32_t *)addr;
}

static inline void uart_putc(char c) {
    // The testbench watches writes to UART_TX_ADDR and mirrors them to the
    // simulation console, which is how CoreMark prints status text.
    mmio_write32(UART_TX_ADDR, (uint32_t)(uint8_t)c);
}

static void uart_puts(const char *s) {
    // Convert "\n" to CRLF so UART text looks correct in simple terminal
    // viewers that expect carriage return before line feed.
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void uart_put_unsigned(uint32_t value, uint32_t base, int width, char pad) {
    char buf[32];
    int pos = 0;

    // Build the string in reverse order, then emit it forward. This keeps the
    // implementation tiny and avoids needing libc formatting support.
    if (value == 0) {
        buf[pos++] = '0';
    } else {
        while (value != 0) {
            uint32_t digit = value % base;
            buf[pos++] = (digit < 10u) ? (char)('0' + digit) : (char)('a' + digit - 10u);
            value /= base;
        }
    }

    while (pos < width) {
        uart_putc(pad);
        width--;
    }

    while (pos > 0) {
        uart_putc(buf[--pos]);
    }
}

static void uart_put_signed(int32_t value, int width, char pad) {
    uint32_t magnitude;

    // Handle INT32_MIN safely by converting through unsigned magnitude math.
    if (value < 0) {
        uart_putc('-');
        magnitude = (uint32_t)(-(value + 1)) + 1u;
    } else {
        magnitude = (uint32_t)value;
    }

    uart_put_unsigned(magnitude, 10u, width, pad);
}

/* Small UART-backed printf for bare-metal simulation output.
 * Supports the CoreMark formats used by this port: %d, %u, %x, %s, %c,
 * optional zero padding/width such as %04x, and the ignored 'l' length flag.
 * This replaces libc printf so the benchmark can run with -nostdlib while
 * still producing useful progress and summary text in simulation.
 */

int ee_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);

    for (const char *p = fmt; *p; ++p) {
        int width = 0;
        char pad = ' ';
        int long_arg = 0;

        if (*p != '%') {
            if (*p == '\n') uart_putc('\r');
            uart_putc(*p);
            continue;
        }

        p++;
        if (*p == '%') {
            uart_putc('%');
            continue;
        }

        if (*p == '0') {
            pad = '0';
            p++;
        }

        while ((*p >= '0') && (*p <= '9')) {
            width = (width * 10) + (*p - '0');
            p++;
        }

        if (*p == 'l') {
            long_arg = 1;
            p++;
        }

        switch (*p) {
            case 'd':
            case 'i':
                uart_put_signed(long_arg ? (int32_t)va_arg(ap, long) : va_arg(ap, int), width, pad);
                break;
            case 'u':
                uart_put_unsigned(long_arg ? (uint32_t)va_arg(ap, unsigned long) : va_arg(ap, unsigned int),
                                  10u, width, pad);
                break;
            case 'x':
            case 'X':
                uart_put_unsigned(long_arg ? (uint32_t)va_arg(ap, unsigned long) : va_arg(ap, unsigned int),
                                  16u, width, pad);
                break;
            case 'c':
                uart_putc((char)va_arg(ap, int));
                break;
            case 's': {
                const char *s = va_arg(ap, const char *);
                uart_puts(s ? s : "(null)");
                break;
            }
            default:
                uart_putc('%');
                if (*p) uart_putc(*p);
                break;
        }
    }

    va_end(ap);
    return 0;
}

/* ---------------- Timing ----------------
 * The core now exposes the architectural cycle CSR, so CoreMark can measure
 * real elapsed core cycles instead of using a placeholder duration.
 */
static CORE_TICKS t0 = 0, t1 = 0;

static inline CORE_TICKS read_cycle32(void) {
    CORE_TICKS value;
    // rdcycle reads the user-visible alias of mcycle. On this core it is
    // backed by the CSRFile counter and advances once per core clock.
    __asm__ volatile ("rdcycle %0" : "=r"(value));
    return value;
}

void start_time(void) { t0 = read_cycle32(); }
void stop_time(void)  { t1 = read_cycle32(); }
CORE_TICKS get_time(void) { return (CORE_TICKS)(t1 - t0); }

secs_ret time_in_secs(CORE_TICKS ticks) {
    /* This port keeps CoreMark in its integer-seconds mode, so round up any
     * non-zero sub-second interval to 1 rather than reporting an unhelpful 0.
     * The raw "Total ticks" line in CoreMark output is the more precise metric
     * for short simulation runs.
     */
    if (ticks == 0u) {
        return (secs_ret)0;
    }

    return (secs_ret)((ticks + (CORE_CLOCK_HZ - 1u)) / CORE_CLOCK_HZ);
}

/* ---------------- Memory allocation ----------------
 * CoreMark uses portable_malloc/free for its working memory.
 * Implement a simple bump allocator from a static pool.
 * A bump allocator is enough here because CoreMark allocates its work areas
 * during setup and never relies on real free/reuse behavior afterward.
 */
#ifndef PORTABLE_HEAP_SIZE
#define PORTABLE_HEAP_SIZE (16 * 1024)  /* 16KB is enough for most default builds */
#endif

static uint8_t  portable_heap[PORTABLE_HEAP_SIZE];
static ee_size_t heap_off = 0;

void *align_mem(void *p) {
    uintptr_t x = (uintptr_t)p;
    x = (x + 7u) & ~((uintptr_t)7u); /* align to 8 bytes */
    return (void *)x;
}

void *portable_malloc(ee_size_t size) {
    /* align requested size */
    size = (size + 7u) & ~((ee_size_t)7u);

    /* align the start pointer too */
    ee_size_t off = (heap_off + 7u) & ~((ee_size_t)7u);
    if (off + size > (ee_size_t)PORTABLE_HEAP_SIZE) return NULL;

    // Allocation is monotonic: each call hands out the next chunk of the
    // static pool and advances heap_off.
    void *p = &portable_heap[off];
    heap_off = off + size;
    return p;
}

void portable_free(void *p) {
    (void)p;
    /* bump allocator: no free */
}

/* ---------------- Init / fini ---------------- */
void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc; (void)argv;
    // Reset the simple allocator and touch fromhost once so the symbol remains
    // part of the linked image even if software does not otherwise use it.
    heap_off = 0;
    (void)mmio_read32(FROMHOST_ADDR);
    // portable_id is a small self-check field used by the CoreMark harness to
    // confirm portable_init ran before the benchmark starts.
    if (p) p->portable_id = 1;
    uart_puts("[coremark] UART online, benchmark starting\n");
    uart_puts("[coremark] Timing uses CSR cycle/mcycle\n");
    uart_puts("[coremark] Core clock for seconds conversion = ");
    uart_put_unsigned((uint32_t)CORE_CLOCK_HZ, 10u, 0, ' ');
    uart_puts(" Hz\n");
}

void portable_fini(core_portable *p) {
    (void)p;
    uart_puts("[coremark] Benchmark finished, signaling tohost=1\n");
    // The testbench treats tohost=1 as success and stops the simulation. The
    // infinite loop models bare-metal software handing control back to the
    // environment without an operating-system exit syscall.
    mmio_write32(TOHOST_ADDR, 1u);
    for (;;) {}
}
