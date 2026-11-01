using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Threading;
[assembly: System.Reflection.AssemblyTitle("控制台")]
[assembly: System.Reflection.AssemblyProduct("控制台")]
class Launcher {
 [STAThread] static void Main() {
  string root=AppDomain.CurrentDomain.BaseDirectory;
  string python=@"C:\Users\asus\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\pythonw.exe";
  if(!File.Exists(python)){MessageBox.Show("未找到配套Python运行环境，请查看使用说明。","启动失败");return;}
  bool first;
  using(Mutex mutex=new Mutex(true,"Local\\CoffeeCupFixedConsole",out first)) {
  if(!first){MessageBox.Show("控制台已经打开，请使用现有窗口。","控制台");return;}
  try {
   ProcessStartInfo p=new ProcessStartInfo(python,"-I -X utf8 \""+Path.Combine(root,"app.py")+"\"");
   p.WorkingDirectory=root;p.UseShellExecute=false;p.CreateNoWindow=true;Process child=Process.Start(p);child.WaitForExit();
  } catch(Exception e){MessageBox.Show(e.Message,"启动失败");}
  }
 }
}
