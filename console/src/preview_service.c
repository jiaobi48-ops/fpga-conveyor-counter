#include "preview_service.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xpseudo_asm.h"
#define GPIO 0x43C30000U
static unsigned token,capture,last_ms,first=1;
static unsigned char pixels[14400];
static int io(unsigned op,unsigned data,unsigned *value){
 unsigned n,v;token^=1U;Xil_Out32(GPIO+8,(token<<31)|(op<<24)|(data&0xffffff));dsb();
 for(n=0;n<20000;n++){
  v=Xil_In32(GPIO);if((v>>31)==token&&((v>>24)&63U)==op){if(value)*value=v&0xffffff;return (v&0x40000000U)?-1:0;}
 }
 xil_printf("FAIL PREVIEW_TIMEOUT op=%u\r\n",op);return -1;
}
int preview_init(void){unsigned v;if(io(0,0,&v)||v!=0xf10401U)return -1;return io(6,0,0);}
int preview_stream_id(unsigned *v){return io(5,0,v);}
void preview_work_time(unsigned us){(void)us;}
int preview_poll(unsigned ms){
 unsigned flags,i,v,id;
 if(!capture){if(io(1,0,0))return -1;capture=1;last_ms=ms;return 0;}
 if(ms-last_ms<10)return 0;
 last_ms=ms;if(io(2,0,&flags))return -1;
 if(!(flags&1))return 0;
 if(flags&2){capture=0;return 0;}
 if(io(4,0,&id))return -1;
 for(i=0;i<4800;i++){
  if(io(3,i,&v))return -1;
  pixels[3*i]=(unsigned char)v;pixels[3*i+1]=(unsigned char)(v>>8);pixels[3*i+2]=(unsigned char)(v>>16);
 }
 capture=0;preview_publish(pixels,id);
 if(first){first=0;xil_printf("CONTROL_PREVIEW_READY source_id=%u -- fixed manual controls, no automatic following\r\n",id);}
 return 0;
}
