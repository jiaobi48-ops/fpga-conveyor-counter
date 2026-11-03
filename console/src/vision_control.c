#include "vision_control.h"
#include "xil_io.h"
#include "xpseudo_asm.h"
#include "xil_printf.h"
#include "sleep.h"
#include <string.h>
#include <stdlib.h>
#define VGPIO 0x43C40000U
#define VPUBLISH 0x03001000U
static unsigned token,snapshot[VISION_RESULT_WORDS],publish_seq;
static int transaction(unsigned op,unsigned data,unsigned *value){
 unsigned i,r;token^=1U;
 Xil_Out32(VGPIO+8U,(token<<31)|(op<<24)|(data&0xffffffU));dsb();
 for(i=0;i<1000000U;i++){
  r=Xil_In32(VGPIO);
  if((r>>31)==token && ((r>>24)&63U)==op){
   if(r&0x40000000U){xil_printf("VISION_REJECT op=%u reason=%u\r\n",op,r&0xffffffU);return -2;}
   if(value)*value=r&0xffffffU;
   return 0;
  }
  usleep(2);
 }
 xil_printf("VISION_TIMEOUT op=%u\r\n",op);return -1;
}
int vision_set(unsigned index,unsigned value){
 if(index>=VISION_CONFIG_COUNT)return -1;
 return transaction(1,(index<<16)|(value&65535U),0)||transaction(2,(index<<16)|(value>>16),0)?-1:0;
}
int vision_commit(void){
 int rc=transaction(3,0,0);unsigned i,value;
 /* A rejected edit restores the staging bank from the current active settings. */
 if(rc==-2)for(i=0;i<VISION_CONFIG_COUNT;i++){
  if(vision_get(i,&value)||vision_set(i,value))return -1;
 }
 return rc;
}
int vision_get(unsigned index,unsigned *value){
 unsigned a,b;if(index>=VISION_CONFIG_COUNT||transaction(4,index,&a)||transaction(5,index,&b))return -1;
 *value=(a&65535U)|(b<<16);return 0;
}
int vision_snapshot(void){
 unsigned i,a,b;if(transaction(6,0,0))return -1;
 for(i=0;i<VISION_RESULT_WORDS;i++){
  if(transaction(7,i,&a)||transaction(8,i,&b))return -1;
  snapshot[i]=(a&65535U)|(b<<16);
 }
 return 0;
}
unsigned vision_result(unsigned index){return index<VISION_RESULT_WORDS?snapshot[index]:0;}
int vision_clear(void){return transaction(9,0,0);}
int vision_rearm(void){return transaction(10,0,0);}
int vision_event(unsigned seq,unsigned *words){
 unsigned i,a,b,index;
 for(i=0;i<12;i++){
  index=(seq&31U)*12U+i;
  if(transaction(14,index,&a)||transaction(15,index,&b))return -1;
  words[i]=(a&65535U)|(b<<16);
 }
 /* Detect a journal-slot wrap during the multi-command read. */
 index=(seq&31U)*12U;
 if(transaction(14,index,&a)||transaction(15,index,&b))return -1;
 return words[0]==seq && ((a&65535U)|(b<<16))==seq?0:-1;
}
void vision_publish(void){
 volatile unsigned *p=(volatile unsigned *)VPUBLISH;unsigned i,v;
 publish_seq+=2U;if(!publish_seq)publish_seq=2;
 p[0]=publish_seq|1U;dsb();p[1]=0xC31401;p[2]=VISION_CONFIG_COUNT;p[3]=VISION_RESULT_WORDS;
 for(i=0;i<VISION_CONFIG_COUNT;i++){if(vision_get(i,&v))v=0xffffffffU;p[16+i]=v;}
 for(i=0;i<VISION_RESULT_WORDS;i++)p[128+i]=snapshot[i];
 dsb();p[0]=publish_seq;dsb();
}
int vision_test_finished(void){
 unsigned a,b,valid,test;
 if(transaction(6,0,0)||transaction(7,VRES_BIST_VALID,&a)||transaction(7,VRES_ACTIVE_SOURCE,&b))return 0;
 valid=a&1U;test=b&1U;return valid && test;
}
int vision_report(void){
 if(vision_snapshot())return -1;
 vision_publish();
 xil_printf("VISION_V14 camera=%u test=%u static=%u stable=%u T=%u/%u/%u mode=%u state=%u reason=%x events=%u\r\n",
  snapshot[VRES_CAMERA_TOTAL],snapshot[VRES_TEST_TOTAL],snapshot[VRES_RESULT_COUNT],snapshot[VRES_STABLE_COUNT],
  snapshot[VRES_PARALLEL_THRESHOLD_LOW],snapshot[VRES_ACTIVE_THRESHOLD],snapshot[VRES_PARALLEL_THRESHOLD_HIGH],
  snapshot[VRES_ACTIVE_MODE],snapshot[VRES_SAFETY_STATE],snapshot[VRES_SAFETY_REASON],snapshot[VRES_MOTION_EVENT_SEQ]);
 xil_printf("VISION_SPEED valid=%u dx=%d dt_cycles=%u merge=%u recovering=%u restored=%u BIST=%u/%u expected=%u actual=%u cfg=%u\r\n",
  snapshot[VRES_SPEED_VALID],(int)(short)snapshot[VRES_SPEED_DX],snapshot[VRES_SPEED_CYCLES_PER_FRAME],
  snapshot[VRES_MOTION_MERGE_ACTIVE],snapshot[VRES_MOTION_MERGE_RECOVERING],snapshot[VRES_MOTION_MERGE_RESTORED_GROUPS],
  snapshot[VRES_BIST_VALID],snapshot[VRES_BIST_PASS],snapshot[VRES_BIST_EXPECTED_COUNT],snapshot[VRES_BIST_ACTUAL_COUNT],snapshot[2]);
 return 0;
}
int vision_init(void){
 unsigned id;if(transaction(0,0,&id)||id!=0xC31401U)return -1;
 xil_printf("VISION_V14_READY native_ports=351 cfg=%u results=%u clock_hz=75000000\r\n",VISION_CONFIG_COUNT,VISION_RESULT_WORDS);
 return 0;
}
int vision_command(const char *line){
 char *end;unsigned a,b;
 if(!strcmp(line,"VSTATUS"))return vision_report();
 if(!strcmp(line,"VCOMMIT"))return vision_commit();
 if(!strcmp(line,"VREARM"))return vision_rearm();
 if(!strncmp(line,"VSET ",5)){
  a=(unsigned)strtoul(line+5,&end,0);if(*end!=' '||a>=VISION_CONFIG_COUNT)return -1;
  b=(unsigned)strtoul(end+1,&end,0);if(*end)return -1;
  return vision_set(a,b);
 }
 if(!strncmp(line,"VGET ",5)){
  a=(unsigned)strtoul(line+5,&end,0);if(*end||vision_get(a,&b))return -1;
  xil_printf("VCFG %u %u\r\n",a,b);return 0;
 }
 if(!strncmp(line,"VDIP ",5)){
  a=(unsigned)strtoul(line+5,&end,0);if(*end||a>255U)return -1;
  return vision_set(VCFG_SYS_DIP_BITS,a)||vision_set(VCFG_SYS_DIP_OVERRIDE,1)||vision_commit()?-1:0;
 }
 if(!strncmp(line,"VTEST ",6)){
  a=(unsigned)strtoul(line+6,&end,0);if(*end||a>5U)return -1;
  if(a){
   unsigned tries,source,busy;
   if(vision_set(VCFG_SYS_DIP_OVERRIDE,0)||vision_set(VCFG_CFG_TEST_ASYNC,0)||vision_commit())return -1;
   for(tries=0;tries<500U;tries++){
    if(transaction(6,0,0)||transaction(7,VRES_ACTIVE_SOURCE,&source)||transaction(7,VRES_SWITCH_BUSY,&busy))return -1;
    if(!(source&1U)&&!(busy&1U))break;
    usleep(1000);
   }
   if(tries==500U)return -1;
  }
  if(vision_set(VCFG_SYS_DIP_OVERRIDE,0)||vision_set(VCFG_CFG_TEST_ASYNC,a!=0)||
     vision_set(VCFG_CFG_BIST_DYNAMIC,a>=2)||vision_set(VCFG_CFG_BIST_PROFILE,a>=2?a-2:0)||
     vision_set(VCFG_SYS_MANUAL_BLOCK,0)||vision_commit())return -1;
  return 0;
 }
 return -1;
}
