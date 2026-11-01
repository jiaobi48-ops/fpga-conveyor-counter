#ifndef FRAME_AUDIT_H
#define FRAME_AUDIT_H
#include <stdint.h>
#include <stddef.h>
/* PG020 S2MM includes EOLLateErr bit15, absent from the legacy ALL mask. */
#define CAPTURE_ERROR_MASK 0x0000CFF0U
typedef struct {
 uint32_t sentinel_bytes,guard_errors,checksum,nonquantized_bytes;
 uint8_t minimum,maximum;
} frame_audit;
/* -1 error, 0 pending, 1 frame-count completion AND channel halted. */
int capture_status(uint32_t status);
int stream_status(uint32_t status);
int warmup_fatal(uint32_t status);
int select_stopped_buffer(unsigned before,unsigned after);
frame_audit audit_frame(const volatile uint8_t *pixels,size_t bytes,
                       const volatile uint8_t *before,
                       const volatile uint8_t *after,size_t guard_bytes);
#endif
