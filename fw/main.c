//
// Softcpu firmware entry point for Vector-06C Analogue Pocket core.
//

#include "softcpu_regs.h"
#include "fdd_service.h"
#include "vkb_ui.h"

// IRQ handler — disabled because PicoRV32 is instantiated with ENABLE_IRQ=0.
// Change #if 0 to #if 1 (here and in start.S) to restore interrupt support.
#if 0
uint32_t *irq(uint32_t *regs, uint32_t irqs)
{
    return regs;
}
#endif

int main(void)
{
    uint16_t prev_buttons = *CONT1_KEY;

    vkb_ui_init();

    for (;;) {
        uint16_t buttons = *CONT1_KEY;
        uint16_t pressed = buttons & ~prev_buttons;
        uint16_t released = ~buttons & prev_buttons;
        vkb_ui_tick(buttons);
        fdd_service_poll(pressed | released);

        prev_buttons = buttons;
    }

    return 0;
}
