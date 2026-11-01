#include "studio_snapshot.h"
#include "frame_audit.h"
#include "xpseudo_asm.h"
#define N (1280U*720U*3U)
int studio_copy(volatile uint32_t *h,volatile unsigned char *dst,const volatile unsigned char *src,
 unsigned selected,unsigned before,unsigned after,unsigned wr,unsigned rd){
 unsigned i;frame_audit a,b;
 if(selected>=3U||select_stopped_buffer(before,after)!=(int)selected||
 !(wr&1U)||!(rd&1U)||(wr&CAPTURE_ERROR_MASK)||(rd&CAPTURE_ERROR_MASK))return -10;
 a=audit_frame(src,N,src-64,src+N,64);
 if(a.guard_errors||a.nonquantized_bytes||a.sentinel_bytes)return -11;
 for(i=0;i<64;i++){dst[(int)i-64]=0x5a;dst[N+i]=0x5a;}
 for(i=0;i<N;i++){dst[i]=src[i];}dsb();
 b=audit_frame(dst,N,dst-64,dst+N,64);
 if(b.guard_errors||b.nonquantized_bytes||b.sentinel_bytes||a.checksum!=b.checksum)return -12;
 h[S_WIDTH]=1280;h[S_HEIGHT]=720;h[S_STRIDE]=3840;h[S_BYTES]=N;h[S_FNV]=b.checksum;
 h[S_SELECTED]=selected;h[S_SOURCE]=0x01000000U+selected*0x00400000U;
 h[S_BEFORE]=before;h[S_AFTER]=after;h[S_WR]=wr;h[S_RD]=rd;h[S_PIXELS]=STUDIO_PIXELS;
 h[S_SEQUENCE]++;dsb();return 0;
}
