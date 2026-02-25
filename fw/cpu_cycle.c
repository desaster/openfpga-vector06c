#include "cpu_cycle.h"

uint32_t rdcycle(void)
{
    uint32_t val;
    __asm__ volatile("rdcycle %0" : "=r"(val));
    return val;
}
