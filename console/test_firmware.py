"""Exercise the actual UART command parser with a mocked MMIO transport."""
from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parent
O=R/'validation/firmware_host';O.mkdir(exist_ok=True)
headers={
 'xil_io.h':'unsigned Xil_In32(unsigned); void Xil_Out32(unsigned,unsigned);',
 'xil_printf.h':'int xil_printf(const char *,...);',
 'xparameters.h':'#define XPAR_XUARTPS_0_BASEADDR 0xe0000000U',
 'xuartps_hw.h':'#define XUARTPS_FIFO_OFFSET 0x30U\nint XUartPs_IsReceiveData(unsigned); unsigned XUartPs_ReadReg(unsigned,unsigned);',
 'xpseudo_asm.h':'#define dsb() ((void)0)',
 'sleep.h':'void usleep(unsigned);'}
for n,s in headers.items():(O/n).write_text(s+'\n')
harness=r'''
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "cup_commands.h"
static unsigned response,staged[10],commits,clears,timeout,session;
static const char *rx="";
int xil_printf(const char *s,...){(void)s;return 0;}
void usleep(unsigned us){(void)us;}
unsigned Xil_In32(unsigned p){(void)p;return response;}
void Xil_Out32(unsigned p,unsigned v){
 unsigned op=(v>>24)&127U,d=v&0xffffffU;(void)p;
 if(timeout)return;
 response=(v&0x80000000U)|(op<<24);
 if(op==0)response|=0xc30401U;
 if(op>=1&&op<=10)staged[op-1]=d;
 if(op==11)commits++;
 if(op==12){clears++;response|=++session;}
 if(op==14&&d==14)response|=0xc30401U;
}
int XUartPs_IsReceiveData(unsigned p){(void)p;return *rx!=0;}
unsigned XUartPs_ReadReg(unsigned p,unsigned o){(void)p;(void)o;return (unsigned char)*rx++;}
static void feed(const char *s){rx=s;assert(cup_poll()==0);}
static unsigned routed;
int follow_command(const char *s){if(!strncmp(s,"FOLLOW",6)||!strncmp(s,"TRACK",5)){routed++;return 1;}return 0;}
int follow_manual_edit(void){return 0;}
int main(void){
 unsigned c;
 assert(cup_start()==0);assert(commits==1&&clears==1);
 assert(staged[9]==13);assert(staged[0]==416&&staged[6]==52&&staged[7]==25&&staged[8]==32);
 feed("ROI 500 460 8 180 212\r\n");assert(commits==2);
 assert(staged[0]==500&&staged[1]==460&&staged[2]==8&&staged[3]==180&&staged[4]==212);
 assert(staged[6]==104&&staged[7]==50&&staged[8]==64);
 c=commits;
 feed("ROI 500 520 8 180 212\n");feed("ROI -1 460 8 180 212\n");
 feed("ROI 500 460 8 180 212 junk\n");feed("ROI 500 460 0 180 212\n");
 feed("ROI 500 460 8 180 99999\n");
 feed("ROI 500 460 8 180 212                                                                                \n");
 assert(commits==c&&clears==1);
 feed("+");assert(staged[5]==148);feed("-");assert(staged[5]==144);
 c=commits;feed("M");assert(commits==c+1&&staged[9]==15);
 feed("M");assert(staged[9]==13);
 c=clears;
 feed("U\r\n");assert(staged[9]==5&&clears==c);
 feed("M");assert(staged[9]==7);feed("m");assert(staged[9]==5);
 feed("H");assert(staged[9]==13&&clears==c);
 feed("M");assert(staged[9]==15);
 feed("+");assert(staged[9]==15);feed("-");assert(staged[9]==15);
 feed("ROI 416 376 4 376 405\r\n");assert(staged[9]==15&&staged[6]==48&&staged[7]==22&&staged[8]==29);
 feed("u");assert(staged[9]==7);feed("h");assert(staged[9]==15);
 feed("a");assert(staged[9]==3&&clears==c);feed("M");assert(staged[9]==1);
 feed("A");assert(staged[9]==1&&clears==c);
 feed("FOLLOW 0\n");feed("TRACK 160 200 416 328\n");assert(routed==0);
 feed("L");assert(!cup_logging());feed("L");assert(cup_logging());
 feed("R");assert(clears==1);for(c=0;c<30;c++)assert(cup_poll()==0);assert(clears==2);
 feed("R\r\n");assert(clears==3);
 feed("P");assert(cup_report()==0);
 feed("SETTHR 32\r\n");assert(staged[5]==32);feed("SETTHR 224\n");assert(staged[5]==224);
 c=commits;feed("SETTHR 31\n");feed("SETTHR 225\n");feed("SETTHR 144 junk\n");assert(commits==c);
 feed("SETMASK 1\n");assert(staged[9]&2);feed("SETMASK 0\n");assert(!(staged[9]&2));
 c=commits;feed("SETMASK 2\n");assert(commits==c);assert(cup_set_mode(12)==0&&staged[9]==13);assert(cup_set_mode(2)<0);
 timeout=1;rx="P";assert(cup_poll()==-1);
 puts("PASS actual C UART parser: manual U/H/A, case/CRLF, mask/ROI/threshold mode retention, no count reset, invalid/timeout propagation");
 return 0;
}
'''
(O/'test.c').write_text(harness)
gcc='D:/vivado/2025.2/tps/mingw/10.0.0/win64.o/nt/bin/gcc.exe'
cmd=[gcc,'-std=c99','-Wall','-Wextra','-Werror','-O2','-I',str(O),'-I',str(R/'src'),
     str(R/'src/cup_commands.c'),str(O/'test.c'),'-o',str(O/'test.exe')]
p=subprocess.run(cmd,capture_output=True,text=True)
(O/'compile.log').write_text(p.stdout+p.stderr)
assert p.returncode==0,p.stdout+p.stderr
p=subprocess.run([str(O/'test.exe')],capture_output=True,text=True)
(O/'run.log').write_text(p.stdout+p.stderr)
assert p.returncode==0,p.stdout+p.stderr
(R/'validation/firmware_host_receipt.json').write_text(json.dumps(dict(status='PASS',scope='Actual parser with mock MMIO; no hardware claim',
 source_sha256=hashlib.sha256((R/'src/cup_commands.c').read_bytes()).hexdigest(),terminal=p.stdout.strip()),indent=2))
print(p.stdout.strip())
