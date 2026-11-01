#include "probe_sccb.h"
#define HALF_US 20U /* Recovery diagnostic: 4x longer phase waits. */
#define CLOCK_WAIT_US 1000U
int probe_write_register(probe_bus *,uint16_t,uint8_t,uint8_t *);
static void delay(probe_bus *b) { b->delay_us(b->context, HALF_US); }
static int raise_clock(probe_bus *b)
{
    unsigned n;
    b->release(b->context, PROBE_SCL);
    for(n=0;n<CLOCK_WAIT_US;n++) {
        if(b->read(b->context, PROBE_SCL)) return PROBE_OK;
        b->delay_us(b->context,1);
    }
    return PROBE_CLOCK_LOW;
}
static int start(probe_bus *b)
{
    int rc;
    b->release(b->context,PROBE_SDA);
    rc=raise_clock(b); if(rc) return rc;
    delay(b);
    if(!b->read(b->context,PROBE_SDA)) return PROBE_DATA_LOW;
    b->low(b->context,PROBE_SDA); delay(b);
    b->low(b->context,PROBE_SCL); delay(b);
    return PROBE_OK;
}
static int stop(probe_bus *b)
{
    int rc;
    b->low(b->context,PROBE_SCL);
    b->low(b->context,PROBE_SDA); delay(b);
    rc=raise_clock(b); delay(b);
    b->release(b->context,PROBE_SDA); delay(b);
    return rc;
}
static int transmit(probe_bus *b,uint8_t data,unsigned slot,uint8_t *mask)
{
    unsigned i; int rc;
    for(i=0;i<8;i++) {
        b->low(b->context,PROBE_SCL);
        if(data&0x80) b->release(b->context,PROBE_SDA);
        else b->low(b->context,PROBE_SDA);
        data=(uint8_t)(data<<1); delay(b);
        rc=raise_clock(b); if(rc) return rc;
        delay(b); b->low(b->context,PROBE_SCL); delay(b);
    }
    b->release(b->context,PROBE_SDA); delay(b);
    rc=raise_clock(b); if(rc) return rc;
    delay(b);
    if(b->read(b->context,PROBE_SDA)) *mask|=(uint8_t)(1U<<slot);
    b->low(b->context,PROBE_SCL); delay(b);
    return PROBE_OK;
}
static int receive(probe_bus *b,uint8_t *value)
{
    unsigned i; int rc; uint8_t data=0;
    b->release(b->context,PROBE_SDA);
    for(i=0;i<8;i++) {
        delay(b); rc=raise_clock(b); if(rc) return rc;
        delay(b);
        data=(uint8_t)((data<<1)|(b->read(b->context,PROBE_SDA)&1U));
        b->low(b->context,PROBE_SCL); delay(b);
    }
    // Single-byte read ends with the controller releasing the ninth bit.
    b->release(b->context,PROBE_SDA); delay(b);
    rc=raise_clock(b); if(rc) return rc;
    delay(b); b->low(b->context,PROBE_SCL); delay(b);
    *value=data;
    return PROBE_OK;
}
int probe_read_register(probe_bus *b,uint16_t reg,uint8_t *value,uint8_t *mask)
{
    int rc; uint8_t read_value=0;
    if(!b||!value||!mask||!b->low||!b->release||!b->read||!b->delay_us)
        return PROBE_INVALID;
    *mask=0;
    rc=start(b); if(rc) goto done;
    rc=transmit(b,0x78,0,mask); if(rc) goto done;
    rc=transmit(b,(uint8_t)(reg>>8),1,mask); if(rc) goto done;
    rc=transmit(b,(uint8_t)reg,2,mask); if(rc) goto done;
    rc=stop(b); if(rc) goto done;
    rc=start(b); if(rc) goto done;
    rc=transmit(b,0x79,3,mask); if(rc) goto done;
    rc=receive(b,&read_value); if(rc) goto done;
    rc=stop(b);
    if(!rc) *value=read_value;
done:
    b->release(b->context,PROBE_SDA);
    b->release(b->context,PROBE_SCL);
    return rc;
}
int probe_write_register(probe_bus *b,uint16_t reg,uint8_t value,uint8_t *mask)
{
    int rc;
    if(!b||!mask||!b->low||!b->release||!b->read||!b->delay_us)
        return PROBE_INVALID;
    *mask=0;
    rc=start(b);if(rc)goto done_write;
    rc=transmit(b,0x78,0,mask);if(rc)goto done_write;
    rc=transmit(b,(uint8_t)(reg>>8),1,mask);if(rc)goto done_write;
    rc=transmit(b,(uint8_t)reg,2,mask);if(rc)goto done_write;
    rc=transmit(b,value,3,mask);if(rc)goto done_write;
    rc=stop(b);
done_write:
    b->release(b->context,PROBE_SDA);
    b->release(b->context,PROBE_SCL);
    return rc;
}
