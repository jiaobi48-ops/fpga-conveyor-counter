#ifndef SCCB_VERIFY_H
#define SCCB_VERIFY_H
#include "probe_sccb.h"
enum { SCCB_READBACK_MISMATCH=-6 };
typedef struct {
 uint8_t write_ninth,read_ninth,read_value,compared,compare_mask;
} sccb_write_observation;
/* Ninth bits remain physically released/sampled. A sampled high does not
   establish a write error in SCCB; verify register state before accepting it. */
int sccb_write_verified(probe_bus *,uint16_t,uint8_t,sccb_write_observation *);
#endif
