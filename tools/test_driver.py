"""Execute the production native GPIO driver against an acknowledged endpoint model."""
from pathlib import Path
import os,subprocess,shutil
R=Path(__file__).resolve().parents[1];O=R/'rebuild/driver';O.mkdir(parents=True,exist_ok=True)
cc=os.environ.get('HOST_CC') or shutil.which('gcc')
if not cc:raise SystemExit('Set HOST_CC to the host C compiler')
for name,source in {
 'xil_io.h':'void Xil_Out32(unsigned,unsigned); unsigned Xil_In32(unsigned);\n',
 'xpseudo_asm.h':'#define dsb() ((void)0)\n',
 'xil_printf.h':'int xil_printf(const char *,...);\n',
 'sleep.h':'void usleep(unsigned);\n',
}.items():(O/name).write_text(source)
source=r'''
#include <assert.h>
#include <stdio.h>
#include "vision_control.h"
static unsigned active[VISION_CONFIG_COUNT], staged[VISION_CONFIG_COUNT], reply;
static unsigned reject_once, requests;
int xil_printf(const char *f,...){(void)f;return 0;}
void usleep(unsigned n){(void)n;}
void Xil_Out32(unsigned address,unsigned value){
 unsigned op=(value>>24)&127,data=value&0xffffff,index=data>>16,i;
 assert(address==0x43c40008);requests++;
 reply=(value&0x80000000)|(op<<24);
 switch(op){
 case 0:reply|=0xc31401;break;
 case 1:assert(index<VISION_CONFIG_COUNT);staged[index]=(staged[index]&0xffff0000)|(data&65535);break;
 case 2:assert(index<VISION_CONFIG_COUNT);staged[index]=(staged[index]&65535)|((data&65535)<<16);break;
 case 3:
  if(reject_once){reject_once=0;reply|=0x40000002;}
  else for(i=0;i<VISION_CONFIG_COUNT;i++)active[i]=staged[i];break;
 case 4:assert(data<VISION_CONFIG_COUNT);reply|=active[data]&65535;break;
 case 5:assert(data<VISION_CONFIG_COUNT);reply|=active[data]>>16;break;
 case 6:break;
 case 7:reply|=(data==VRES_ACTIVE_SOURCE||data==VRES_SWITCH_BUSY)?0:data&65535;break;
 case 8:reply|=0;break;
 default:assert(!"unexpected operation");
 }
}
unsigned Xil_In32(unsigned address){assert(address==0x43c40000);return reply;}
int main(void){
 unsigned i,value;
 for(i=0;i<VISION_CONFIG_COUNT;i++)active[i]=staged[i]=i*19;
 assert(vision_init()==0);
 assert(vision_set(VCFG_CFG_THRESHOLD,91)==0);
 assert(vision_set(VCFG_CFG_MEAN_OFFSET,(unsigned)-24)==0);
 assert(vision_commit()==0);
 assert(vision_get(VCFG_CFG_THRESHOLD,&value)==0&&value==91);
 assert(vision_get(VCFG_CFG_MEAN_OFFSET,&value)==0&&value==(unsigned)-24);
 assert(vision_set(VCFG_CFG_THRESHOLD,255)==0);
 reject_once=1;assert(vision_commit()==-2);
 for(i=0;i<VISION_CONFIG_COUNT;i++)assert(staged[i]==active[i]);
 assert(vision_command("VDIP 167")==0);
 assert(active[VCFG_SYS_DIP_BITS]==167&&active[VCFG_SYS_DIP_OVERRIDE]==1);
 assert(vision_command("VTEST 4")==0);
 assert(active[VCFG_SYS_DIP_OVERRIDE]==0&&active[VCFG_CFG_TEST_ASYNC]==1);
 assert(active[VCFG_CFG_BIST_PROFILE]==2&&active[VCFG_CFG_BIST_DYNAMIC]==1&&active[VCFG_SYS_MANUAL_BLOCK]==0);
 assert(vision_set(VISION_CONFIG_COUNT,0)==-1);
 assert(vision_snapshot()==0);
 for(i=0;i<VISION_RESULT_WORDS;i++)assert(vision_result(i)==((i==VRES_ACTIVE_SOURCE||i==VRES_SWITCH_BUSY)?0:i));
 printf("PASS DRIVER GPIO acknowledge, signed32, commit/reject rollback77, DIP, BIST, snapshot303 requests=%u\n",requests);
 return 0;
}
'''
(O/'test.c').write_text(source)
commands=[[cc,'-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-I'+str(O),'-I'+str(R/'console/src'),str(O/'test.c'),str(R/'console/src/vision_control.c'),'-o',str(O/'test.exe')],[str(O/'test.exe')]]
log=''
for command in commands:
 p=subprocess.run(command,capture_output=True,text=True);log+=p.stdout+p.stderr
 (O/'test.log').write_text(log)
 if p.returncode:raise SystemExit(log)
print(log,end='')
