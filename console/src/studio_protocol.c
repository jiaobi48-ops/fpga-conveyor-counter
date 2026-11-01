#include "studio_protocol.h"
#include "xpseudo_asm.h"
void studio_init(volatile uint32_t *h){unsigned i;for(i=0;i<STUDIO_WORDS;i++)h[i]=0;dsb();h[1]=3;h[0]=STUDIO_MAGIC;dsb();}
static int valid_roi(const unsigned *v){
 return v[0]>=2&&v[0]<=798&&v[1]>=2&&v[1]<=798&&v[2]>=1&&v[2]<=32&&
 v[0]+v[2]<=798&&v[1]+v[2]<v[0]&&v[3]>=54&&v[3]<=478&&v[4]<=478&&
 v[4]>=v[3]+8&&v[4]-v[3]<=128;
}
int studio_poll(volatile uint32_t *h,unsigned *seen,studio_handler fn,void *ctx){
 unsigned token=h[2],r[9],i,seal=STUDIO_SEAL;int rc=0;
 if(!token||token==*seen)return 0;
 for(i=0;i<9;i++){r[i]=h[i+2];}dsb();
 if(h[2]!=token)return 0;
 *seen=token;h[S_STATE]=1;h[S_ERROR]=0;dsb();
 for(i=0;i<8;i++)seal^=r[i];
 if(seal!=r[8]||r[1]>STUDIO_RESET)rc=1;
 else if(r[1]==STUDIO_ROI&&(r[2]!=h[S_SEQUENCE]||!valid_roi(r+3)))rc=2;
 else if(r[1]>=STUDIO_MODE && (r[2]!=h[S_SEQUENCE]||r[4]||r[5]||r[6]||r[7]||
   (r[1]==STUDIO_MODE && r[3]!=0U && r[3]!=4U && r[3]!=12U)||
   (r[1]==STUDIO_THRESHOLD && (r[3]<32U||r[3]>224U))||
   (r[1]==STUDIO_MASK && r[3]>1U)||
   (r[1]==STUDIO_RESET && r[3])))rc=2;
 else rc=fn(r[1],r+3,h,ctx);
 h[S_ERROR]=rc<0?(unsigned)-rc:(unsigned)rc;
 h[S_STATE]=rc?3U:2U;if(rc<0)h[S_RUNNING]=2;
 dsb();h[S_ACK]=token;dsb();return rc<0?-1:1;
}
