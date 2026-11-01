#ifndef CUP_COMMANDS_H
#define CUP_COMMANDS_H
int cup_start(void);
int cup_poll(void);
int cup_report(void);
int cup_logging(void);
#include "count_types.h"
void cup_get_roi(count_roi *);
int cup_set_roi(count_roi);
int cup_empty(int *);
int cup_studio_snapshot(unsigned *,unsigned *);
int cup_set_mode(unsigned);
int cup_set_threshold(unsigned);
int cup_set_mask(unsigned);
int cup_reset_count(void);
#endif
