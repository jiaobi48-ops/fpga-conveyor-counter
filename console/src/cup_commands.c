#include "cup_commands.h"
#include "vision_control.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xuartps_hw.h"
#include "xpseudo_asm.h"
#include "sleep.h"
#include <string.h>
#include <stdlib.h>
#define GPIO 0x43C20000U
static unsigned logging=1,mask;
static unsigned cfg[10]={410,220,4,2,478,128,70,5,48,13};
static char line[80];static unsigned length,idle,discard;
/* Payload remains held until the complete acknowledged reply crosses back.
   Only one request is outstanding. Timeouts stop the application. */
static unsigned config_indices[10]={VCFG_CFG_LINE_A,VCFG_CFG_LINE_B,VCFG_CFG_MIN_WIDTH,VCFG_CFG_SAFETY_ROI_Y0,VCFG_CFG_SAFETY_ROI_Y1,VCFG_CFG_THRESHOLD,VCFG_CFG_HIGH,VCFG_CFG_LOW,VCFG_CFG_GUARD_WARM_ON,VCFG_SYS_COUNT_ENABLE};
static int transaction(unsigned op,unsigned data,unsigned *value){
 unsigned i,v=0,flags,phase,total;
 if(op==0){v=0xC31401U;}
 else if(op>=1 && op<=10){
  if(op==10){if(vision_set(VCFG_SYS_COUNT_ENABLE,data&1U)||vision_set(VCFG_SYS_MASK,(data>>1)&1U)||vision_set(VCFG_SYS_MANUAL_MODE,(data>>2)&1U)||vision_set(VCFG_SYS_MANUAL_BLOCK,(data>>3)&1U))return -1;}
  else if(op==3){/* Legacy gate width is a display setting; B object width has its own parameter. */}
  else if(vision_set(config_indices[op-1],data))return -1;
 }else if(op==11){if(vision_commit()||vision_get(VCFG_CFG_CONFIG_VERSION,&v))return -1;}
 else if(op==12){if(vision_clear())return -1;}
 else if(op==13){if(vision_snapshot())return -1;v=vision_result(VRES_RESULT_FRAME_ID);}
 else if(op==14){
  if(data==0){total=vision_result(vision_result(VRES_ACTIVE_SOURCE)?VRES_TEST_TOTAL:VRES_CAMERA_TOTAL);phase=vision_result(VRES_SAFETY_BLOCKED)?0:1;v=(total&0xfffffU)|(phase<<20);}
  else if(data==1){flags=cfg[9]&3U;flags|=(vision_result(VRES_SAFETY_FRAME_GOOD)?8U:0U)|(vision_result(VRES_PIPELINE_RST_N)?4U:0U);flags|=(cfg[9]&12U)<<8;flags|=(vision_result(VRES_SAFETY_BLOCKED)||((cfg[9]&12U)==12U))<<12;v=flags;}
  else if(data==2)v=vision_result(VRES_RESULT_FRAME_ID);
  else if(data==3)v=vision_result(2);
  else if(data==4)v=vision_result(VRES_MOTION_SESSION_ID);
  else if(data==5)v=vision_result(VRES_RESULT_COUNT);
  else if(data==6)v=vision_result(VRES_STABLE_COUNT);
  else if(data==7||data==8)v=0;
  else if(data==9)v=vision_result(VRES_SAFETY_GUARD_WARM);
  else if(data==10)v=vision_result(VRES_SAFETY_GUARD_DARK);
  else if(data==11)v=vision_result(VRES_DROPPED_FRAMES);
  else if(data==12)v=vision_result(VRES_SAFETY_BLOCKED_FRAMES);
  else if(data==13)v=vision_result(VRES_ACTIVE_THRESHOLD);
  else if(data==14)v=0xC31401U;
  else if(data==15)v=0;
  else return -1;
 }else if(op==15){if(data>=10)return -1;i=config_indices[data];if(vision_get(i,&v))return -1;}
 else return -1;
 if(value)*value=v;
 return 0;
}
static int refresh_legacy(void){
 unsigned i,v;
 for(i=0;i<9;i++){if(i==2)continue;if(vision_get(config_indices[i],&v))return -1;cfg[i]=v;}
 cfg[9]=0;
 if(vision_get(VCFG_SYS_COUNT_ENABLE,&v))return -1;
 cfg[9]|=v&1U;
 if(vision_get(VCFG_SYS_MASK,&v))return -1;
 cfg[9]|=(v&1U)<<1;
 if(vision_get(VCFG_SYS_MANUAL_MODE,&v))return -1;
 cfg[9]|=(v&1U)<<2;
 if(vision_get(VCFG_SYS_MANUAL_BLOCK,&v))return -1;
 cfg[9]|=(v&1U)<<3;
 return 0;
}
static int apply(void){
 unsigned i,v;
 for(i=0;i<10;i++)if(transaction(i+1U,cfg[i],0))return -1;
 if(transaction(11,0,&v))return -1;
 xil_printf("VISION_CONFIG_APPLIED version=%u line_a=%u line_b=%u roi_y=%u:%u threshold=%u\r\n",v,cfg[0],cfg[1],cfg[3],cfg[4],cfg[5]);
 return 0;
}
static void help(void)
{
 xil_printf("COMMANDS fixed manual ROI; R=clear A=auto U=manual_clear H=manual_block M=mask +/-=threshold P=snapshot L=log_on_off ?=help\r\n");
 xil_printf("ROI ax bx width y0 y1 + newline; default: ROI 410 220 4 2 478\r\n");
 xil_printf("ROI uses LCD pixels, right-to-left. Edit with gates empty; totals retained, history rearmed.\r\n");
}
int cup_logging(void){return (int)logging;}
int cup_set_mode(unsigned bits){
 if(bits!=0&&bits!=4&&bits!=12)return -1;
 if(refresh_legacy())return -1;
 cfg[9]=(cfg[9]&~12U)|bits;
 if(bits==0 && vision_set(VCFG_CFG_GUARD_ENABLE,1))return -1;
 return apply();
}
int cup_set_threshold(unsigned value){
 if(value<32U||value>224U)return -1;
 if(refresh_legacy())return -1;
 cfg[5]=value;if(vision_set(VCFG_CFG_AUTO_THRESHOLD,0))return -1;return apply();
}
int cup_set_mask(unsigned value){
 if(value>1U)return -1;
 if(refresh_legacy())return -1;
 mask=value;cfg[9]=(cfg[9]&~2U)|(mask<<1);return apply();
}
int cup_reset_count(void){return transaction(12,0,0);}
int cup_report(void)
{
 unsigned p[16],i,v,f;
 if(transaction(13,0,&v))return -1;
 for(i=0;i<16;i++)if(transaction(14,i,&p[i]))return -1;
 if(p[14]!=0xC31401U){xil_printf("FAIL COUNT_SNAPSHOT_VERSION\r\n");return -1;}
 f=p[1];
 xil_printf("PREVIEW_FLAGS active=%u hold=%u\r\n",p[15]&1U,(p[15]>>1)&1U);
 xil_printf("OCCLUSION_STATUS mode=%s manual_block=%u effective_block=%u raw_warm=%u raw_upper=%u\r\n",(f&(1U<<10))?"MANUAL":"AUTO",(f>>11)&1U,(f>>12)&1U,(f>>7)&1U,(f>>8)&1U);
 xil_printf("VISION_COUNT_V14 total=%u A=%u B=%u phase=%u enabled=%u locked=%u frame_good=%u threshold=%u\r\n",
  p[0]&0xfffffU,(p[0]>>22)&1U,(p[0]>>23)&1U,(p[0]>>20)&3U,f&1U,(f>>2)&1U,(f>>3)&1U,p[13]);
 xil_printf("COUNT_SNAPSHOT display_frame=%u epoch=%u session=%u ap=%u bp=%u pending=%u warm=%u/%u upper=%u/%u BLOCK_SEEN=%u Q_OVERFLOW=%u bad_frames=%u blocked_frames=%u\r\n",
  p[2],p[3],p[4],p[5]&65535U,p[6],(p[5]>>16)&15U,p[7],p[8],p[9],p[10],(f>>5)&1U,(f>>6)&1U,p[11],p[12]);
 return vision_report();
}
int cup_start(void)
{
 unsigned id;
 if(vision_init()||transaction(0,0,&id)||id!=0xC31401U){xil_printf("FAIL COUNT_PROTOCOL_VERSION\r\n");return -1;}
 if(apply()||transaction(12,0,0))return -1;
 xil_printf("CUP_COUNTER_STARTED ABC_INTEGRATED MANUAL_PAUSED; manual controls U/H/A; normal sensor clock\r\n");help();return 0;
}
static int single(unsigned c)
{
 unsigned v;
 if(refresh_legacy())return -1;
 if(c=='R'||c=='r'){
  if(transaction(12,0,&v))return -1;
  xil_printf("COUNT_RESET session=%u -- wait for clear gates\r\n",v);
 }else if(c=='A'||c=='a'||c=='U'||c=='u'||c=='H'||c=='h'){
  unsigned bits=(c=='A'||c=='a')?0U:(c=='U'||c=='u')?4U:12U;
  cfg[9]=(cfg[9]&~12U)|bits;
 if(bits==0 && vision_set(VCFG_CFG_GUARD_ENABLE,1))return -1;
  if(apply())return -1;
  xil_printf("OCCLUSION_APPLIED mode=%s blocked=%u -- total retained; mode changes rearm; wait for empty gates\r\n",bits?"MANUAL":"AUTO",(bits>>3)&1U);
 }else if(c=='M'||c=='m'){
  mask=((cfg[9]>>1)&1U)^1U;cfg[9]=(cfg[9]&~2U)|(mask<<1);
  if(transaction(10,cfg[9],0)||transaction(11,0,0))return -1;
  xil_printf("MASK_VIEW enabled=%u\r\n",mask);
 }else if(c=='+'||c=='-'){
  if(c=='+'&&cfg[5]<224U)cfg[5]+=4U;
  if(c=='-'&&cfg[5]>32U)cfg[5]-=4U;
  if(vision_set(VCFG_CFG_AUTO_THRESHOLD,0)||apply())return -1;
 }else if(c=='P'||c=='p'){if(cup_report())return -1;}
 else if(c=='L'||c=='l'){logging^=1U;xil_printf("PERIODIC_LOG enabled=%u -- video/counting continue\r\n",logging);}
 else if(c=='?')help();
 else xil_printf("COMMAND_INVALID -- send ? for help\r\n");
 return 0;
}
static int finish_line(void)
{
 unsigned values[5],i,n=0;const char *p=line;char *end;
 line[length]=0;
 if(line[0]=='V'){
  int rc=vision_command(line);length=idle=discard=0;
  if(rc==-2){xil_printf("VISION_CONFIG_REJECTED -- active settings retained\r\n");return 0;}
  return rc;
 }
 if(discard){xil_printf("COMMAND_TOO_LONG -- discarded entire line\r\n");goto done;}
 if(!strcmp(line,"STATUS")){if(cup_report())return -1;goto done;}
 if(!strncmp(line,"SETTHR ",7)||!strncmp(line,"SETMASK ",8)){
  int is_mask=!strncmp(line,"SETMASK ",8);p=line+(is_mask?8:7);
  if(*p<'0'||*p>'9')goto invalid;
  n=(unsigned)strtoul(p,&end,10);while(*end==' ')end++;
  if(*end||(is_mask?n>1U:(n<32U||n>224U)))goto invalid;
  if(is_mask){if(cup_set_mask(n))return -1;}else if(cup_set_threshold(n))return -1;
  goto done;
 }
 
 if(length==1U){i=(unsigned char)line[0];length=idle=0;return single(i);}
 if(length>=3U&&(p[0]=='R'||p[0]=='r')&&(p[1]=='O'||p[1]=='o')&&(p[2]=='I'||p[2]=='i')){
  p+=3;
  for(i=0;i<5U;i++){
   if(*p!=' ')goto invalid;
   while(*p==' ')p++;
   if(*p<'0'||*p>'9')goto invalid;
   n=0;
   do{n=n*10U+(unsigned)(*p-'0');if(n>9999U)goto invalid;p++;}while(*p>='0'&&*p<='9');
   values[i]=n;
  }
  while(*p==' ')p++;
  if(*p)goto invalid;
  if(values[0]<2U||values[1]<2U||values[2]<1U||values[2]>32U||
     values[0]+values[2]>798U||values[1]+values[2]>=values[0]||
     values[3]<2U||values[4]>478U||values[4]<values[3]+8U)goto invalid;
  
  n=values[2]*(values[4]-values[3]);
  for(i=0;i<5U;i++)cfg[i]=values[i];
  (void)n;
  if(apply())return -1;
  goto done;
 }
invalid:xil_printf("ROI_INVALID -- active configuration unchanged; send ?\r\n");
done:length=idle=discard=0;return 0;
}
int cup_poll(void)
{
 unsigned c,received=0;
 while(XUartPs_IsReceiveData(XPAR_XUARTPS_0_BASEADDR)){
  c=XUartPs_ReadReg(XPAR_XUARTPS_0_BASEADDR,XUARTPS_FIFO_OFFSET)&255U;received=1;idle=0;
  if(c=='\r'||c=='\n'){if((length||discard)&&finish_line())return -1;continue;}
  if(!length&&!discard&&strchr("AaUuHhMmPpLl?+-",(int)c)){
   if(single(c))return -1;
   continue;
  }
  if(c>=32U&&c<127U){if(length<sizeof(line)-1U)line[length++]=(char)c;else discard=1;}
  else discard=1;
 }
 if(!received&&(length||discard)&&++idle>=30U)return finish_line();
 return 0;
}

void cup_get_roi(count_roi *r){r->ax=cfg[0];r->bx=cfg[1];r->width=cfg[2];r->y0=cfg[3];r->y1=cfg[4];}
int cup_set_roi(count_roi r){
 unsigned area;
 if(refresh_legacy())return -1;
 if(r.bx<2||r.width<1||r.width>32||r.ax+r.width>798||r.bx+r.width>=r.ax||r.y0<2||r.y1>478||r.y1-r.y0<8)return -1;
 cfg[0]=(unsigned)r.ax;cfg[1]=(unsigned)r.bx;cfg[2]=(unsigned)r.width;cfg[3]=(unsigned)r.y0;cfg[4]=(unsigned)r.y1;
 area=cfg[2]*(cfg[4]-cfg[3]);(void)area;
 return apply();
}
int cup_empty(int *empty){
 unsigned a,b;if(transaction(13,0,0)||transaction(14,5,&a)||transaction(14,6,&b))return 0;
 *empty=(a&65535U)<=cfg[7] && b<=cfg[7];return 1;
}

int cup_studio_snapshot(unsigned *configuration,unsigned *pages){
 unsigned i;
 if(refresh_legacy())return -1;
 if(transaction(13,0,0))return -1;
 for(i=0;i<16;i++)if(transaction(14,i,pages+i))return -1;
 for(i=0;i<10;i++)configuration[i]=cfg[i];
 return 0;
}
