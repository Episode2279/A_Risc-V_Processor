#include <stdint.h>

#include "core_portme.h"

#define UART_TX  (*(volatile uint32_t *)UART_TX_ADDR)
#define TOHOST   (*(volatile uint32_t *)TOHOST_ADDR)

static void putc_uart(char c) {
  UART_TX = (uint32_t)(uint8_t)c;
}

static void puts_uart(const char *s) {
  while (*s) putc_uart(*s++);
}

int main(void) {
  puts_uart("12345\n");
  TOHOST = 1;      // TB should stop (thread0 only)
  while (1) {}
}
