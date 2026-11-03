"""Persistent XSDB transport for camera frames and the firmware control mailbox."""
from pathlib import Path
import base64,os,queue,subprocess,threading,time
class TransportError(RuntimeError):pass
class DDRTransport:
 def __init__(self,root,log):
  self.root=Path(root);self.log=Path(log);self.process=None;self.lines=queue.Queue();self.serial=0
 def _reader(self):
  with self.log.open('a',encoding='utf-8') as f:
   for line in self.process.stdout:
    if line.startswith('STUDIO_DATA '):
     parts=line.split(' ',2);f.write(' '.join(parts[:2])+f' <base64 payload chars={len(parts[2].strip()) if len(parts)>2 else 0}>\n')
    else:f.write(line)
    f.flush()
    if line.startswith('STUDIO_'):self.lines.put(line.strip())
  self.lines.put('STUDIO_CLOSED')
 def connect(self):
  from tool_paths import xsdb_path
  xsdb=xsdb_path()
  if not xsdb.is_file():raise TransportError('找不到 AMD XSDB，请核对安装路径')
  self.process=subprocess.Popen([os.environ.get('COMSPEC','cmd.exe'),'/d','/c',str(xsdb),str(self.root/'ddr_bridge.tcl')],cwd=self.root,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
  threading.Thread(target=self._reader,daemon=True).start()
  line=self._line(40)
  if line!='STUDIO_CONNECTED 0':self._fail(line)
 def _line(self,timeout):
  try:return self.lines.get(timeout=timeout)
  except queue.Empty:raise TransportError('JTAG读取超时；请检查板卡、JTAG和采集固件')
 def _fail(self,line):
  if line.startswith('STUDIO_ERROR '):
   try:line=base64.b64decode(line.split(' ',2)[2]).decode('utf-8',errors='replace')
   except Exception:pass
  raise TransportError(line)
 def _request(self,op,*args):
  self.serial+=1;sid=self.serial
  if not self.process or self.process.poll() is not None:raise TransportError('JTAG连接已经关闭')
  self.process.stdin.write(' '.join(map(str,[sid,op,*args]))+'\n');self.process.stdin.flush()
  line=self._line(30);parts=line.split(' ',2)
  if len(parts)<2 or parts[1]!=str(sid):self._fail(line)
  if parts[0]=='STUDIO_ERROR':self._fail(line)
  return parts
 def read(self,address,n):
  if n%4 or address%4:raise ValueError('word alignment')
  out=bytearray()
  while len(out)<n:
   length=min(32768,n-len(out));parts=self._request('READ',hex(address+len(out)),length)
   if parts[0]!='STUDIO_DATA' or len(parts)!=3:self._fail('DDR data response missing')
   b=base64.b64decode(parts[2],validate=True)
   if len(b)!=length:raise TransportError('DDR短读')
   out.extend(b)
  return bytes(out)
 def write(self,address,values):
  parts=self._request('WRITE',hex(address),*[hex(v&0xffffffff) for v in values])
  if parts[0]!='STUDIO_OK':self._fail('DDR write acknowledgement missing')
 def close(self):
  if self.process and self.process.poll() is None:
   try:self._request('QUIT')
   except Exception:pass
   try:self.process.stdin.close();self.process.wait(timeout=3)
   except Exception:self.process.terminate()
