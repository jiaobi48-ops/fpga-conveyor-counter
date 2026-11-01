"""Small Windows 115200/8N1 serial adapter using the system API (no extra install)."""
import ctypes as C,threading,time,winreg
from ctypes import wintypes as W
K=C.WinDLL('kernel32',use_last_error=True)
class DCB(C.Structure):
 _fields_=[('DCBlength',W.DWORD),('BaudRate',W.DWORD),('flags',W.DWORD),('wReserved',W.WORD),('XonLim',W.WORD),('XoffLim',W.WORD),('ByteSize',W.BYTE),('Parity',W.BYTE),('StopBits',W.BYTE),('XonChar',C.c_char),('XoffChar',C.c_char),('ErrorChar',C.c_char),('EofChar',C.c_char),('EvtChar',C.c_char),('wReserved1',W.WORD)]
class Timeouts(C.Structure):_fields_=[(n,W.DWORD) for n in ['ReadIntervalTimeout','ReadTotalTimeoutMultiplier','ReadTotalTimeoutConstant','WriteTotalTimeoutMultiplier','WriteTotalTimeoutConstant']]
class Comstat(C.Structure):_fields_=[('flags',W.DWORD),('cbInQue',W.DWORD),('cbOutQue',W.DWORD)]
K.CreateFileW.argtypes=[W.LPCWSTR,W.DWORD,W.DWORD,C.c_void_p,W.DWORD,W.DWORD,W.HANDLE];K.CreateFileW.restype=W.HANDLE
for name,args in [('CloseHandle',[W.HANDLE]),('GetCommState',[W.HANDLE,C.POINTER(DCB)]),('SetCommState',[W.HANDLE,C.POINTER(DCB)]),('SetCommTimeouts',[W.HANDLE,C.POINTER(Timeouts)]),('ClearCommError',[W.HANDLE,C.POINTER(W.DWORD),C.POINTER(Comstat)]),('ReadFile',[W.HANDLE,C.c_void_p,W.DWORD,C.POINTER(W.DWORD),C.c_void_p]),('WriteFile',[W.HANDLE,C.c_void_p,W.DWORD,C.POINTER(W.DWORD),C.c_void_p])]:
 getattr(K,name).argtypes=args;getattr(K,name).restype=W.BOOL
def ports():
 result=[]
 try:
  with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,r'HARDWARE\DEVICEMAP\SERIALCOMM') as key:
   i=0
   while True:
    try:result.append(winreg.EnumValue(key,i)[1]);i+=1
    except OSError:break
 except OSError:pass
 return sorted(set(result),key=lambda s:int(s[3:]) if s.startswith('COM') and s[3:].isdigit() else 9999)
def check(ok):
 if not ok:raise C.WinError(C.get_last_error())
class SerialPort:
 def __init__(self):self.handle=None;self.name='';self.lock=threading.RLock()
 def open(self,name):
  if name not in ports():raise ValueError('未找到这个串口，请检查USB串口线后点击刷新')
  self.close();h=K.CreateFileW('\\\\.\\'+name,0xc0000000,0,None,3,0,None)
  if h==C.c_void_p(-1).value:
   err=C.get_last_error()
   if err==5:raise RuntimeError(f'{name}被其他软件占用。请在SSCOM点击“关闭串口”，再连接本程序。')
   raise C.WinError(err)
  try:
   d=DCB();d.DCBlength=C.sizeof(d);check(K.GetCommState(h,C.byref(d)));d.BaudRate=115200;d.flags=1;d.ByteSize=8;d.Parity=0;d.StopBits=0;check(K.SetCommState(h,C.byref(d)))
   t=Timeouts(0xffffffff,0,0,0,1000);check(K.SetCommTimeouts(h,C.byref(t)))
  except Exception:K.CloseHandle(h);raise
  with self.lock:self.handle=h;self.name=name
 def read(self):
  with self.lock:
   if not self.handle:return b''
   e=W.DWORD();s=Comstat();check(K.ClearCommError(self.handle,C.byref(e),C.byref(s)))
   if not s.cbInQue:return b''
   b=C.create_string_buffer(min(s.cbInQue,65536));n=W.DWORD();check(K.ReadFile(self.handle,b,len(b),C.byref(n),None));return b.raw[:n.value]
 def write(self,data):
  if not isinstance(data,bytes) or not 0<len(data)<=256:raise ValueError('每次发送1～256字节')
  with self.lock:
   if not self.handle:raise RuntimeError('请先连接串口')
   n=W.DWORD();b=C.create_string_buffer(data);check(K.WriteFile(self.handle,b,len(data),C.byref(n),None))
   if n.value!=len(data):raise RuntimeError('串口发送不完整，请查看板上状态；没有自动重复发送')
 def close(self):
  with self.lock:
   if self.handle:K.CloseHandle(self.handle)
   self.handle=None;self.name=''
