#ifndef PREVIEW_SERVICE_H
#define PREVIEW_SERVICE_H
int preview_init(void);
int preview_poll(unsigned);
int preview_stream_id(unsigned *);
void preview_work_time(unsigned);
void preview_publish(const unsigned char *,unsigned);
#endif
