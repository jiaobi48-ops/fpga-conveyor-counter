#include "platform.h"
#include "cup_commands.h"
#include "preview_service.h"
#include "studio_protocol.h"
#include "studio_snapshot.h"
#include "xiltimer.h"
#include "gpio_bus.h"
#include "sensor.h"
#include "sccb_verify.h"
#include "frame_audit.h"
#include "xaxivdma.h"
#include "xaxivdma_hw.h"
#include "xvtc.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xpseudo_asm.h"
#include "sleep.h"
#include "xuartps_hw.h"
#include "xil_io.h"
#include <string.h>
#define STRIDE 3840U
#define FRAME_BYTES (STRIDE*720U)
#define BASE_FRAME 0x01000000U
#define BUFFER_STEP 0x00400000U
#define GUARDS 64U
#define CROP_OFFSET (120U*STRIDE+240U*3U)
static XAxiVdma dma;
static XVtc vtc;
static probe_bus bus;
static u32 base;
static u32 status(int dir) {return XAxiVdma_ReadReg(base,dir==XAXIVDMA_WRITE?0x34:0x04);}
static int reset_channel(int dir)
{
 unsigned i;XAxiVdma_Reset(&dma,dir);
 for(i=0;i<1000U;i++) {
  if(!XAxiVdma_ResetNotDone(&dma,dir))return 0;
  usleep(100);
 }
 xil_printf("FAIL DMA_RESET direction=%d\r\n",dir);return -1;
}
static int setup_channel(int dir)
{
 XAxiVdma_DmaSetup c;unsigned i;int rc;
 memset(&c,0,sizeof c);
 c.VertSizeInput=dir==XAXIVDMA_WRITE?720:480;
 c.HoriSizeInput=dir==XAXIVDMA_WRITE?3840:2400;
 c.Stride=STRIDE;c.EnableCircularBuf=1;
 /* Writer starts independently for a bounded capture check; genlock is
    enabled on BOTH channels before the reader starts. Dynamic slave ignores
    ordinary fixed FrameDelay; it follows the master's completed buffer. */
 c.EnableSync=dir==XAXIVDMA_READ?1:0;
 for(i=0;i<3U;i++)c.FrameStoreStartAddr[i]=BASE_FRAME+i*BUFFER_STEP+(dir==XAXIVDMA_READ?CROP_OFFSET:0);
 rc=XAxiVdma_DmaConfig(&dma,dir,&c);
 if(!rc)rc=XAxiVdma_DmaSetBufferAddr(&dma,dir,c.FrameStoreStartAddr);
 return rc;
}
static int capture_ready(void)
{
 unsigned ms,events=0,observations=0;u32 sr,seen=0;
 if(XAxiVdma_DmaStart(&dma,XAXIVDMA_WRITE))return -1;
 for(ms=0;ms<1000U;ms++) {
  sr=status(XAXIVDMA_WRITE);
  if(warmup_fatal(sr)) {xil_printf("FAIL CAPTURE_WARMUP SR=%08x\r\n",sr);return -1;}
  if(sr&CAPTURE_ERROR_MASK){observations++;seen|=sr&CAPTURE_ERROR_MASK;}
  XAxiVdma_WriteReg(base,0x34,sr&0xF990U);usleep(1000);
 }
 xil_printf("WARMUP errors_observed=%u mask=%08x\r\n",observations,seen);
 sr=status(XAXIVDMA_WRITE);
 if(warmup_fatal(sr)||(sr&1U))return -1;
 XAxiVdma_WriteReg(base,0x34,sr&0xF990U);
 for(ms=0;ms<5000U;ms++) {
  sr=status(XAXIVDMA_WRITE);
  if(stream_status(sr)<0){xil_printf("FAIL CAPTURE_STEADY SR=%08x\r\n",sr);return -1;}
  if(sr&0x1000U){events++;XAxiVdma_IntrClear(&dma,XAXIVDMA_IXR_FRMCNT_MASK,XAXIVDMA_WRITE);}
  if(events>=4U){xil_printf("CAPTURE_READY clean_events=%u\r\n",events);return 0;}
  usleep(1000);
 }
 xil_printf("FAIL CAPTURE_TIMEOUT events=%u\r\n",events);return -1;
}
static int configure_timing(void)
{
 XVtc_Config *c=XVtc_LookupConfig(XPAR_XVTC_0_BASEADDR);
 XVtc_Timing t;XVtc_SourceSelect s;
 if(!c||XVtc_CfgInitialize(&vtc,c,c->BaseAddress))return -1;
 XVtc_DisableGenerator(&vtc);
 memset(&t,0,sizeof t);memset(&s,0,sizeof s);
 t.HActiveVideo=800;t.HFrontPorch=40;t.HSyncWidth=128;t.HBackPorch=88;t.HSyncPolarity=0;
 t.VActiveVideo=480;t.V0FrontPorch=10;t.V0SyncWidth=2;t.V0BackPorch=33;
 t.V1FrontPorch=10;t.V1SyncWidth=2;t.V1BackPorch=33;t.VSyncPolarity=0;t.Interlaced=0;
 s.VBlankPolSrc=1;s.VSyncPolSrc=1;s.HBlankPolSrc=1;s.HSyncPolSrc=1;
 s.ActiveVideoPolSrc=1;s.ActiveChromaPolSrc=1;s.VChromaSrc=1;s.VActiveSrc=1;
 s.VBackPorchSrc=1;s.VSyncSrc=1;s.VFrontPorchSrc=1;s.VTotalSrc=1;
 s.HActiveSrc=1;s.HBackPorchSrc=1;s.HSyncSrc=1;s.HFrontPorchSrc=1;s.HTotalSrc=1;
 if(XVtc_SelfTest(&vtc))return -1;
 XVtc_RegUpdateEnable(&vtc);XVtc_SetGeneratorTiming(&vtc,&t);XVtc_SetSource(&vtc,&s);
 return 0;
}
static int check_sensor(void)
{
 const unsigned reg[]={0x3808,0x3809,0x380A,0x380B,0x4300,0x501F,0x3036,0x503D};
 const unsigned val[]={5,0,2,0xD0,0x61,1,0x3C,0};unsigned i;u8 v;
 for(i=0;i<sizeof reg/sizeof reg[0];i++) {
  if(sensor_read(reg[i],&v)||v!=val[i]){xil_printf("FAIL SENSOR_READBACK reg=%04x\r\n",reg[i]);return -1;}
 }
 return 0;
}
static int bus_preflight(void)
{
 unsigned i;uint8_t hi,lo,hm,lm;int a,b;
 xil_printf("RECOVERY_TIMING phase_wait_us=20 power_wait_ms=500 reset_wait_ms=20 write_gap_us=1000; ninth bits recorded; write/read data verified\r\n");
 xil_printf("BUS_IDLE SCL=%u SDA=%u\r\n",bus.read(bus.context,PROBE_SCL),bus.read(bus.context,PROBE_SDA));
 for(i=1;i<=5;i++) {
  hi=lo=hm=lm=0;
  a=probe_read_register(&bus,0x300A,&hi,&hm);
  b=probe_read_register(&bus,0x300B,&lo,&lm);
  xil_printf("PREFLIGHT_ID try=%u ID=%02x%02x bus=%d/%d ninth_high=%x/%x\r\n",i,(unsigned)hi,(unsigned)lo,a,b,(unsigned)hm,(unsigned)lm);
  if(a||b||hi!=0x56||lo!=0x40){xil_printf("FAIL PREFLIGHT_ID -- check camera supply and control-wire connections\r\n");return -1;}
  usleep(20000);
 }
 xil_printf("PREFLIGHT_ID_OK matches=5/5\r\n");return 0;
}
static int pattern_read(unsigned reg,uint8_t *v)
{
 uint8_t mask=0;int rc=probe_read_register(&bus,(uint16_t)reg,v,&mask);
 if(mask)xil_printf("PROBE_READ_NINTH reg=%04x mask=%x value=%02x\r\n",reg,(unsigned)mask,(unsigned)*v);
 return rc;
}
static int pattern_write(unsigned value)
{
 sccb_write_observation o;uint8_t actual=0;int rc;
 rc=sccb_write_verified(&bus,0x503D,(uint8_t)value,&o);
 if(rc){xil_printf("FAIL PATTERN_WRITE value=%02x rc=%d mask=%x/%x read=%02x\r\n",value,rc,(unsigned)o.write_ninth,(unsigned)o.read_ninth,(unsigned)o.read_value);return -1;}
 rc=pattern_read(0x503D,&actual);
 xil_printf("PATTERN_CHECK expected=%02x actual=%02x write_ninth=%x readback=%s\r\n",value,(unsigned)actual,(unsigned)o.write_ninth,!rc&&actual==value?"OK":"FAIL");
 return rc||actual!=value?-1:0;
}
static int verify_pattern_transport(void)
{
 unsigned i;uint8_t original=0,hi=0,lo=0;
 if(pattern_read(0x503D,&original))return -1;
 xil_printf("PATTERN_BEGIN reg=503D original=%02x trials=10\r\n",(unsigned)original);
 for(i=0;i<10;i++)if(pattern_write(0)||pattern_write(0x80)||pattern_write(0))return -1;
 if(pattern_write(original)||pattern_read(0x300A,&hi)||pattern_read(0x300B,&lo)||hi!=0x56||lo!=0x40)return -1;
 xil_printf("PATTERN_TRANSPORT_OK changes=30 restored=%02x ID=5640\r\n",(unsigned)original);return 0;
}

static volatile u32 *studio_box=(volatile u32 *)STUDIO_BASE;
static unsigned studio_seen;
static unsigned studio_millis(void){XTime t;XTime_GetTime(&t);return (unsigned)(t/(COUNTS_PER_SECOND/1000U));}
static int studio_refresh(volatile u32 *h){
 unsigned c[10],p[16],i;
 if(cup_studio_snapshot(c,p))return -23;
 for(i=0;i<10;i++)h[S_CFG+i]=c[i];
 for(i=0;i<16;i++)h[S_PAGES+i]=p[i];
 h[S_UPTIME_MS]=studio_millis();return 0;
}
static int stop_for_studio(int dir){
 unsigned n;u32 sr;XAxiVdma_DmaStop(&dma,dir);
 for(n=0;n<10000;n++){
  sr=status(dir);if(sr&CAPTURE_ERROR_MASK)return -1;
  if(sr&1U)return 0;
  usleep(100);
 }
 return -1;
}
static int resume_for_studio(void){
 XAxiVdma_FrameCounter f;u32 cr;
 if(reset_channel(XAXIVDMA_WRITE)||reset_channel(XAXIVDMA_READ)||configure_timing())return -1;
 if(setup_channel(XAXIVDMA_WRITE)||setup_channel(XAXIVDMA_READ))return -1;
 memset(&f,0,sizeof f);f.ReadFrameCount=1;f.WriteFrameCount=1;
 if(XAxiVdma_SetFrameCounter(&dma,&f))return -1;
 XAxiVdma_IntrEnable(&dma,XAXIVDMA_IXR_FRMCNT_MASK|XAXIVDMA_IXR_ERROR_MASK,XAXIVDMA_WRITE);
 XAxiVdma_IntrEnable(&dma,XAXIVDMA_IXR_FRMCNT_MASK|XAXIVDMA_IXR_ERROR_MASK,XAXIVDMA_READ);
 if(capture_ready())return -1;
 cr=XAxiVdma_ReadReg(base,0x30);XAxiVdma_WriteReg(base,0x30,cr|8U);
 if(XAxiVdma_DmaStart(&dma,XAXIVDMA_READ))return -1;
 XVtc_EnableGenerator(&vtc);return 0;
}
#include "control_dispatch.h"
static int studio_handle(unsigned command,const unsigned args[5],volatile u32 *h,void *ctx){
 unsigned before,after,started,stream_id;int selected,rc;uint8_t polarity;
 (void)ctx;
 if(control_dispatch(command,args))return -28;
 if(studio_refresh(h))return -23;
 if(command!=STUDIO_CAPTURE)return 0;
 if(cup_set_mode(12)||studio_refresh(h))return -27; /* Photo/ROI work stays paused. */
 started=studio_millis();
 if(stop_for_studio(XAXIVDMA_READ))return -20;
 XVtc_DisableGenerator(&vtc);
 before=(XAxiVdma_ReadReg(base,0x28)&XAXIVDMA_PARKPTR_WRTSTR_MASK)>>XAXIVDMA_WRTSTR_SHIFT;
 if(stop_for_studio(XAXIVDMA_WRITE))return -21;
 after=(XAxiVdma_ReadReg(base,0x28)&XAXIVDMA_PARKPTR_WRTSTR_MASK)>>XAXIVDMA_WRTSTR_SHIFT;
 selected=select_stopped_buffer(before,after);
 if(selected<0||sensor_read(0x4740,&polarity)||polarity!=0x20)return -22;
 h[S_POLARITY]=polarity;h[S_FREEZE_MS]=studio_millis();
 rc=studio_copy(h,(volatile u8 *)STUDIO_PIXELS,(const volatile u8 *)(BASE_FRAME+(unsigned)selected*BUFFER_STEP),
  (unsigned)selected,before,after,status(XAXIVDMA_WRITE),status(XAXIVDMA_READ));
 if(rc)return rc;
 if(preview_stream_id(&stream_id))return -26;
 h[S_STREAM_COUNTER]=stream_id; // Diagnostic at stop; NOT an identity tag of the selected DDR frame.
 if(resume_for_studio())return -24;
 h[S_RESUME_WR]=status(XAXIVDMA_WRITE);h[S_RESUME_RD]=status(XAXIVDMA_READ);
 h[S_ELAPSED_MS]=studio_millis()-started;h[S_UPTIME_MS]=studio_millis();
 xil_printf("STUDIO_CAPTURE_READY capture_seq=%u FNV=%08x selected=%u elapsed_ms=%u -- original immutable BGR, no overlay\r\n",h[S_SEQUENCE],h[S_FNV],h[S_SELECTED],h[S_ELAPSED_MS]);
 return 0;
}

int main(void)
{
 XAxiVdma_Config *c;XAxiVdma_FrameCounter f;unsigned i,j,ms,sec=0,w_events=0,r_events=0;
 u32 wr,rd,cr;volatile u8 *p;
 init_platform();Xil_ExceptionDisable();Xil_DCacheDisable();
 studio_init(studio_box);
 *(volatile unsigned *)0x02000000U=0;dsb(); /* Invalidate any previous-run thumbnail before initialization. */
 xil_printf("\r\nCAMERA_CONTROL_CONSOLE_V1_2 -- control mailbox v3 and UART; STARTS MANUALLY PAUSED\r\n");
 xil_printf("INPUT 1280x720 BGR bytes; LCD 800x480 central crop x=240 y=120; pixel_clk=25MHz\r\n");
 xil_printf("WIRING direct camera connection; U1=D4 input; K7=PWDN; LCD on existing RGB connector\r\n");
 if(camera_bus_init(&bus))goto stopped;
 usleep(500000);
 if(bus_preflight()||verify_pattern_transport()||sensor_init(&bus)||sensor_write(0x503D,0)||check_sensor())goto stopped;
 c=XAxiVdma_LookupConfig(XPAR_XAXIVDMA_0_BASEADDR);
 if(!c||!c->HasS2Mm||!c->HasMm2S||c->MaxFrameStoreNum!=3||
    c->S2MmStreamWidth!=24||c->Mm2SStreamWidth!=24||
    c->S2MmGenLock!=2||c->Mm2SGenLock!=3||!c->InternalGenLock) {
  xil_printf("FAIL BSP_CONFIG\r\n");goto stopped;
 }
 base=c->BaseAddress;
 if(XAxiVdma_CfgInitialize(&dma,c,base)||reset_channel(XAXIVDMA_WRITE)||reset_channel(XAXIVDMA_READ)||configure_timing())goto stopped;
 for(i=0;i<3U;i++) {
  p=(volatile u8 *)(BASE_FRAME+i*BUFFER_STEP);memset((void *)p,0xA5,FRAME_BYTES);
  for(j=0;j<GUARDS;j++){p[(int)j-(int)GUARDS]=0x5A;p[FRAME_BYTES+j]=0x5A;}
 }
 dsb();
 if(setup_channel(XAXIVDMA_WRITE)||setup_channel(XAXIVDMA_READ))goto stopped;
 memset(&f,0,sizeof f);f.ReadFrameCount=1;f.WriteFrameCount=1;
 if(XAxiVdma_SetFrameCounter(&dma,&f))goto stopped;
 XAxiVdma_IntrEnable(&dma,XAXIVDMA_IXR_FRMCNT_MASK|XAXIVDMA_IXR_ERROR_MASK,XAXIVDMA_WRITE);
 XAxiVdma_IntrEnable(&dma,XAXIVDMA_IXR_FRMCNT_MASK|XAXIVDMA_IXR_ERROR_MASK,XAXIVDMA_READ);
 if(capture_ready())goto stopped;
 /* Internal dynamic master/slave synchronization prevents read/write buffer
    collision across the unequal camera and LCD frame rates (PG020). */
 cr=XAxiVdma_ReadReg(base,0x30);XAxiVdma_WriteReg(base,0x30,cr|0x8U);
 if(XAxiVdma_DmaStart(&dma,XAXIVDMA_READ))goto stopped;
 if((XAxiVdma_ReadReg(base,0)&0x88U)!=0x88U||
    (XAxiVdma_ReadReg(base,0x30)&0x88U)!=0x88U) {
  xil_printf("FAIL GENLOCK_REGISTERS\r\n");goto stopped;
 }
 if(cup_start()||preview_init())goto stopped;
 
 XVtc_EnableGenerator(&vtc);
 studio_box[S_RUNNING]=1;
 xil_printf("LCD_STREAM_STARTED -- inspect moving picture; UART events alone do not prove screen output\r\n");
 for(;;) {
  for(ms=0;ms<1000U;ms++) {
   wr=status(XAXIVDMA_WRITE);rd=status(XAXIVDMA_READ);
   if((wr&CAPTURE_ERROR_MASK)||(rd&CAPTURE_ERROR_MASK)||(wr&1U)||(rd&1U)) {
    xil_printf("FAIL LIVE_DMA S2MM=%08x MM2S=%08x\r\n",wr,rd);goto stopped;
   }
   if(wr&0x1000U){w_events++;XAxiVdma_IntrClear(&dma,XAXIVDMA_IXR_FRMCNT_MASK,XAXIVDMA_WRITE);}
   if(rd&0x1000U){r_events++;XAxiVdma_IntrClear(&dma,XAXIVDMA_IXR_FRMCNT_MASK,XAXIVDMA_READ);}
   if(cup_poll())goto stopped;
   if(studio_poll(studio_box,&studio_seen,studio_handle,0)<0)goto stopped;
   {XTime now,end;XTime_GetTime(&now);if(preview_poll((unsigned)(now/(COUNTS_PER_SECOND/1000U))))goto stopped;XTime_GetTime(&end);preview_work_time((unsigned)((end-now)*1000000U/COUNTS_PER_SECOND));}
   usleep(1000);
  }
  if(!w_events||!r_events){xil_printf("FAIL LIVE_FRAME_TIMEOUT write=%u read=%u\r\n",w_events,r_events);goto stopped;}
  for(i=0;i<3U;i++) {
   p=(volatile u8 *)(BASE_FRAME+i*BUFFER_STEP);
   for(j=0;j<GUARDS;j++)if(p[(int)j-(int)GUARDS]!=0x5A||p[FRAME_BYTES+j]!=0x5A){xil_printf("FAIL BUFFER_GUARD\r\n");goto stopped;}
  }
  sec++;
  if(cup_logging()) {
   xil_printf("LCD_LIVE_STATUS seconds=%u write_events=%u read_events=%u S2MM=%08x MM2S=%08x PARK=%08x\r\n",sec,w_events,r_events,wr,rd,XAxiVdma_ReadReg(base,0x28));
   if(cup_report())goto stopped;
  }
  w_events=r_events=0;
 }
stopped:
 studio_box[S_RUNNING]=2;if(studio_box[S_STATE]!=3){studio_box[S_ERROR]=99;studio_box[S_STATE]=3;}dsb();
 if(vtc.IsReady)XVtc_DisableGenerator(&vtc);
 if(dma.IsReady){XAxiVdma_DmaStop(&dma,XAXIVDMA_READ);XAxiVdma_DmaStop(&dma,XAXIVDMA_WRITE);}
 if(bus.release){bus.release(bus.context,PROBE_SDA);bus.release(bus.context,PROBE_SCL);}
 xil_printf("STOP_CAMERA_LCD -- inspect preceding failure; no LCD acceptance recorded\r\n");
 while(1)usleep(1000000);
}

void preview_publish(const unsigned char *image,unsigned id){
 volatile unsigned *h=(volatile unsigned *)0x02000000U;
 volatile unsigned char *p=(volatile unsigned char *)0x02000040U;
 unsigned i,hash=2166136261U;h[0]=0;dsb();
 for(i=0;i<14400U;i++){p[i]=image[i];hash=(hash^image[i])*16777619U;}
 h[1]=id;h[2]=160;h[3]=90;h[4]=14400;h[5]=hash;h[6]=0xC30401;h[7]=0;
 {XTime t;XTime_GetTime(&t);h[8]=(unsigned)(t/(COUNTS_PER_SECOND/1000U));}h[10]=STUDIO_MAGIC;
 h[9]=0;for(i=11;i<16;i++)h[i]=0;
 dsb();h[0]=0x464F4C31U;dsb();
}
