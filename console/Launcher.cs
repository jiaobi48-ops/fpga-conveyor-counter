using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Threading;
[assembly: System.Reflection.AssemblyTitle("FPGA视觉计数控制台")]
[assembly: System.Reflection.AssemblyProduct("ABC Integrated 1.4")]
class Launcher {
 static string Python() {
  string configured=Environment.GetEnvironmentVariable("FPGA_PYTHON");
  if(!String.IsNullOrEmpty(configured) && File.Exists(configured))return configured;
  string user=Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
  string bundled=Path.Combine(user,@".cache\codex-runtimes\codex-primary-runtime\dependencies\python\pythonw.exe");
  if(File.Exists(bundled))return bundled;
  foreach(string folder in (Environment.GetEnvironmentVariable("PATH")??"").Split(';')) {
   foreach(string name in new string[]{"pythonw.exe","python.exe"}) {
    string candidate=Path.Combine(folder.Trim('"'),name);if(File.Exists(candidate))return candidate;
   }
  }
  throw new Exception("设置FPGA_PYTHON为Python解释器完整路径，并安装NumPy和Pillow。");
 }
 [STAThread] static void Main() {
  string root=AppDomain.CurrentDomain.BaseDirectory;bool first;
  using(Mutex mutex=new Mutex(true,"Local\\FPGAVisionABC14",out first)) {
   if(!first){MessageBox.Show("控制台已经打开。","FPGA视觉计数控制台");return;}
   try {
    ProcessStartInfo p=new ProcessStartInfo(Python(),"-I -X utf8 \""+Path.Combine(root,"app.py")+"\"");
    p.WorkingDirectory=root;p.UseShellExecute=false;p.CreateNoWindow=true;
    Process child=Process.Start(p);child.WaitForExit();
   } catch(Exception e){MessageBox.Show(e.Message,"启动失败");}
  }
 }
}
