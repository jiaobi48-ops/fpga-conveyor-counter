#include "frame_audit.h"
int stream_status(uint32_t status)
{
 if(status&CAPTURE_ERROR_MASK)return -1;
 if(status&1U)return -2;
 return (status&0x1000U)?1:0;
}
int warmup_fatal(uint32_t status)
{
 /* Bus/address faults and standalone internal errors are never startup noise. */
 if(status&0x60U)return 1;
 if((status&0x10U)&&!(status&0x8980U))return 1;
 return 0;
}
int select_stopped_buffer(unsigned before,unsigned after)
{
 unsigned i;
 if(before>=3U||after>=3U)return -1;
 for(i=0;i<3U;i++)if(i!=before&&i!=after)return (int)i;
 return -1;
}
int capture_status(uint32_t status)
{
 if(status&CAPTURE_ERROR_MASK)return -1;
 return (status&0x1001U)==0x1001U?1:0;
}
frame_audit audit_frame(const volatile uint8_t *p,size_t n,
                       const volatile uint8_t *before,
                       const volatile uint8_t *after,size_t guards)
{
 frame_audit a={0,0,2166136261U,0,255,0};size_t i;uint8_t x;
 for(i=0;i<n;i++) {
  x=p[i];if(x==0xA5U)a.sentinel_bytes++;
  if(x&3U)a.nonquantized_bytes++;
  if(x<a.minimum)a.minimum=x;
  if(x>a.maximum)a.maximum=x;
  a.checksum=(a.checksum^x)*16777619U;
 }
 for(i=0;i<guards;i++) {
  if(before[i]!=0x5AU)a.guard_errors++;
  if(after[i]!=0x5AU)a.guard_errors++;
 }
 return a;
}
