#ifndef VISION_CONTROL_H
#define VISION_CONTROL_H
#include "vision_registers.h"
int vision_init(void);
int vision_set(unsigned index,unsigned value);
int vision_commit(void);
int vision_get(unsigned index,unsigned *value);
int vision_snapshot(void);
unsigned vision_result(unsigned index);
int vision_clear(void);
int vision_rearm(void);
int vision_event(unsigned seq,unsigned *words);
int vision_test_finished(void);
int vision_command(const char *line);
int vision_report(void);
void vision_publish(void);
#endif
