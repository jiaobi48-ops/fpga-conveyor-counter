#ifndef CAMERA_SENSOR_H
#define CAMERA_SENSOR_H
#include "probe_sccb.h"
int sensor_init(probe_bus *bus);
int sensor_write(unsigned reg,unsigned value);
int sensor_read(unsigned reg,uint8_t *value);
#endif
