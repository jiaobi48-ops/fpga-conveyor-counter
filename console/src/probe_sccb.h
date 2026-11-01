#ifndef PROBE_SCCB_H
#define PROBE_SCCB_H
#include <stdint.h>
enum { PROBE_SCL=0, PROBE_SDA=1 };
enum { PROBE_OK=0, PROBE_CLOCK_LOW=-1, PROBE_DATA_LOW=-2, PROBE_INVALID=-3 };
typedef struct {
    void *context;
    void (*low)(void *, unsigned);
    void (*release)(void *, unsigned);
    unsigned (*read)(void *, unsigned);
    void (*delay_us)(void *, unsigned);
} probe_bus;
/* Only writes the sensor's register-address pointer; no register-data write.
 * The ninth bit after transmitted bytes is released and sampled, never forced
 * low by the controller. Report its four observed levels as diagnostic bits.
 */
int probe_read_register(probe_bus *bus, uint16_t reg, uint8_t *value,
                        uint8_t *ninth_high_mask);
int probe_write_register(probe_bus *bus, uint16_t reg, uint8_t value,
                         uint8_t *ninth_high_mask);
#endif
