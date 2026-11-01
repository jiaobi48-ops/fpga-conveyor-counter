#include "gpio_bus.h"
#include "sleep.h"
#include "xparameters.h"
#include "xgpiops_hw.h"
#include "xstatus.h"
static const u32 pins[2]={54U,55U}; // Zynq-7000 EMIO[0]=SCL, EMIO[1]=SDA.
static void line_low(void *context,unsigned line)
{
    XGpioPs *gpio=(XGpioPs *)context;
    u32 data;
    /* Release always disables OEN before DIRM=0. Set output direction first
     * so DATA writes are effective; keep the already-disabled driver off
     * until the zero latch is verified. Repeated LOW is idempotent and must
     * not briefly release SCL/SDA, which would create unwanted bus edges.
     */
    XGpioPs_SetDirectionPin(gpio,pins[line],1);
    XGpioPs_WritePin(gpio,pins[line],0);
    data=XGpioPs_ReadReg(gpio->GpioConfig.BaseAddr,
                        XGPIOPS_DATA_OFFSET+2U*XGPIOPS_DATA_BANK_OFFSET);
    if((data&((u32)1U<<line))==0)
        XGpioPs_SetOutputEnablePin(gpio,pins[line],1);
    else
        XGpioPs_SetOutputEnablePin(gpio,pins[line],0);
}
static void line_release(void *context,unsigned line)
{
    XGpioPs *gpio=(XGpioPs *)context;
    XGpioPs_SetOutputEnablePin(gpio,pins[line],0);
    XGpioPs_SetDirectionPin(gpio,pins[line],0);
}
static unsigned line_read(void *context,unsigned line)
{
    return XGpioPs_ReadPin((XGpioPs *)context,pins[line])&1U;
}
static void wait_us(void *context,unsigned usec)
{
    (void)context; usleep(usec);
}
/* EMIO DATA_RO must not be used as an output-pad readback while DIRM=1.
 * UG585 GPIO EMIO Signals. These checks verify control registers only.
 */

int camera_bus_init(probe_bus *bus) {
 static XGpioPs gpio;XGpioPs_Config *cfg=XGpioPs_LookupConfig(XPAR_XGPIOPS_0_BASEADDR);
 if(!cfg || XGpioPs_CfgInitialize(&gpio,cfg,cfg->BaseAddr)!=XST_SUCCESS)return -1;
 bus->context=&gpio;bus->low=line_low;bus->release=line_release;bus->read=line_read;bus->delay_us=wait_us;
 line_release(&gpio,0);line_release(&gpio,1);return 0;
}
