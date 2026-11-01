"""Execute actual C mailbox, control dispatch and count configuration together; mock only PL MMIO."""
from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parent
O=R/'validation/mailbox_host';O.mkdir(exist_ok=True)
code=r'''
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include "studio_protocol.h"
#include "control_dispatch.h"
#include "cup_commands.h"
static unsigned staged[10],active[10],response,epoch,session,total,commits,fail,token;
static unsigned pages[16];static const char *rx="";
int xil_printf(const char *s,...){(void)s;return 0;}
void usleep(unsigned n){(void)n;}
int XUartPs_IsReceiveData(unsigned p){(void)p;return *rx!=0;}
unsigned XUartPs_ReadReg(unsigned p,unsigned o){(void)p;(void)o;return (unsigned char)*rx++;}
unsigned Xil_In32(unsigned p){(void)p;return response;}
void Xil_Out32(unsigned p,unsigned v){
 unsigned op=(v>>24)&127,d=v&0xffffff,bits;(void)p;
 response=(v&0x80000000U)|(op<<24);
 if(op==0)response|=0xc30401;
 if(op>=1&&op<=10)staged[op-1]=d;
 if(op==11){if(fail){response|=0x40000001;return;}memcpy(active,staged,sizeof active);epoch++;commits++;response|=epoch;}
 if(op==12){session++;total=0;response|=session;}
 if(op==13){memset(pages,0,sizeof pages);bits=active[9]&12;pages[0]=total|(1U<<20);pages[1]=13|((bits&4)<<8)|((bits&8)<<8)|(bits==12?4096:0);pages[3]=epoch;pages[4]=session;pages[13]=active[5];pages[14]=0xc30401;}
 if(op==14){assert(d<16);response|=pages[d];}
}
static int handle(unsigned op,const unsigned args[5],volatile uint32_t *h,void *ctx){
 unsigned c[10],p[16],i;(void)ctx;
 if(control_dispatch(op,args))return -28;
 if(cup_studio_snapshot(c,p))return -23;
 for(i=0;i<10;i++)h[S_CFG+i]=c[i];for(i=0;i<16;i++)h[S_PAGES+i]=p[i];return 0;
}
static void request(volatile uint32_t *h,unsigned op,unsigned value,unsigned *seen){
 unsigned i,seal=STUDIO_SEAL;h[2]=++token;h[3]=op;h[4]=h[S_SEQUENCE];
 for(i=5;i<10;i++)h[i]=0;h[5]=value;
 for(i=2;i<10;i++)seal^=h[i];h[10]=seal;
 studio_poll(h,seen,handle,0);
 assert(h[S_ACK]==token);
}
int main(void){
 volatile uint32_t h[128];unsigned seen=0,before,e;
 studio_init(h);assert(h[1]==3);h[S_RUNNING]=1;assert(!cup_start());total=17;
 request(h,STUDIO_MODE,4,&seen);assert(h[S_STATE]==2&&h[S_CFG+9]==5&&((h[S_PAGES+1]>>10)&7)==1&&total==17);
 before=commits;assert(!studio_poll(h,&seen,handle,0)&&commits==before);
 request(h,STUDIO_MODE,12,&seen);assert(h[S_STATE]==2&&h[S_CFG+9]==13&&((h[S_PAGES+1]>>10)&7)==7&&total==17);
 request(h,STUDIO_MODE,0,&seen);assert(h[S_STATE]==2&&h[S_CFG+9]==1&&total==17);
 request(h,STUDIO_THRESHOLD,160,&seen);assert(h[S_CFG+5]==160&&total==17);
 request(h,STUDIO_MASK,1,&seen);assert(h[S_CFG+9]==3&&total==17);
 before=commits;
 request(h,STUDIO_MODE,8,&seen);assert(h[S_STATE]==3&&h[S_ERROR]==2);
 request(h,STUDIO_THRESHOLD,225,&seen);assert(h[S_STATE]==3&&h[S_ERROR]==2);
 request(h,STUDIO_MASK,2,&seen);assert(h[S_STATE]==3&&h[S_ERROR]==2);
 assert(commits==before&&total==17);
 e=epoch;rx="U\r\n";assert(!cup_poll());assert(active[9]==7&&epoch>e&&total==17);
 rx="H\r\n";assert(!cup_poll());assert(active[9]==15&&total==17);
 request(h,STUDIO_RESET,0,&seen);assert(h[S_STATE]==2&&total==0&&h[S_PAGES+4]==session);
 fail=1;request(h,STUDIO_MODE,4,&seen);assert(h[S_STATE]==3&&h[S_RUNNING]==2&&h[S_ERROR]==28);
 puts("PASS actual C mailbox -> control dispatch -> MMIO: manual clear/blocked/auto, effective flags, threshold/mask/reset, token once-only, invalid input rejection, UART coexistence, hardware error propagation; PL mocked");
 return 0;
}
'''
(O/'test.c').write_text(code,encoding='utf-8')
sources=['studio_protocol.c','control_dispatch.c','cup_commands.c']
gcc='D:/vivado/2025.2/tps/mingw/10.0.0/win64.o/nt/bin/gcc.exe'
cmd=[gcc,'-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-O2','-I',str(R/'validation/firmware_host'),'-I',str(R/'src'),*[str(R/'src'/n) for n in sources],str(O/'test.c'),'-o',str(O/'test.exe')]
p=subprocess.run(cmd,capture_output=True,text=True);(O/'compile.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
p=subprocess.run([str(O/'test.exe')],capture_output=True,text=True);(O/'run.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
(R/'validation/mailbox_controls_receipt.json').write_text(json.dumps({'status':'PASS','scope':'Actual C sources linked together with mocked PL MMIO; no board execution','sources':{n:hashlib.sha256((R/'src'/n).read_bytes()).hexdigest() for n in sources},'result':p.stdout.strip()},indent=2),encoding='utf-8')
print(p.stdout.strip())
