#include "sccb_verify.h"
int sccb_write_verified(probe_bus *b,uint16_t reg,uint8_t value,sccb_write_observation *o)
{
 int rc;
 if(!o)return PROBE_INVALID;
 *o=(sccb_write_observation){0,0,0,0,0};
 if(!b||!b->delay_us)return PROBE_INVALID;
 rc=probe_write_register(b,reg,value,&o->write_ninth);
 if(rc)return rc;
 b->delay_us(b->context,(reg==0x3008U&&value==0x82U)?20000U:1000U);
 if(!o->write_ninth)return 0;
 rc=probe_read_register(b,reg,&o->read_value,&o->read_ninth);
 if(rc)return rc;
 o->compared=1;
 /* 3008[7] clears after software reset; it must not remain asserted.
    Other readback fields are not claimed to equal the transient reset word. */
 o->compare_mask=(reg==0x3008U&&value==0x82U)?0x80U:0xFFU;
 if(o->compare_mask==0x80U)
  return (o->read_value&0x80U)?SCCB_READBACK_MISMATCH:0;
 return o->read_value==value?0:SCCB_READBACK_MISMATCH;
}
