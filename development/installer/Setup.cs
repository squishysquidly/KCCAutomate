using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;
using KCCAutomate;

namespace KCCAutomateInstaller {
    public class InstallRecord {
        public string Product {get;set;}
        public string Location {get;set;}
        public string Version {get;set;}
        public string[] Files {get;set;}
        public bool DesktopShortcut {get;set;}
    }
    public static class InstallCore {
        const string Product="KCCAutomate-2EB9D3B3-43C7-4C80-8DDA-CBE275EAF190";
        const string RegistryPath=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\KCCAutomate";
        const string RecordName=".kccautomate-install.json";
        const string Uninstaller="Uninstall-KCCAutomate.exe";
        static readonly JavaScriptSerializer json=new JavaScriptSerializer();
        static string SettingsPath {get{string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),current=Path.Combine(local,@"KCCAutomate\settings.json");return File.Exists(current)?current:Path.Combine(local,@"MangaFlow\settings.json");}}
        static string Full(string path) {
            if(!Path.IsPathRooted(path))throw new Exception("Choose a full installation path.");
            string result=Path.GetFullPath(path).TrimEnd('\\');
            if(result.Equals(Path.GetPathRoot(result).TrimEnd('\\'),StringComparison.OrdinalIgnoreCase))throw new Exception("Choose an application subfolder, not a drive or share root.");
            return result;
        }
        static string[] AppFiles {get{return ReleaseClient.RequiredFiles.Concat(new[]{Uninstaller}).ToArray();}}
        sealed class InstallerGate:IDisposable {
            readonly System.Threading.Mutex mutex;
            public InstallerGate(){mutex=new System.Threading.Mutex(false,@"Local\KCCAutomate-Installation-"+WindowsIdentity.GetCurrent().User.Value);if(!mutex.WaitOne(0)){mutex.Dispose();throw new Exception("Another installation or removal is in progress. Let it finish first.");}}
            public void Dispose(){mutex.ReleaseMutex();mutex.Dispose();}
        }
        static void NoLink(string path){if((File.Exists(path)||Directory.Exists(path))&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new Exception("Linked installation files/folders are not supported: "+path);}
        static InstallRecord Record(string root) {
            var record=json.Deserialize<InstallRecord>(File.ReadAllText(Path.Combine(root,RecordName)));
            if(record.Product!=Product || !String.Equals(record.Location,Full(root),StringComparison.OrdinalIgnoreCase) || record.Files==null || record.Files.Any(name=>!AppFiles.Contains(name)))throw new Exception("The installation record is invalid. No files were removed.");
            return record;
        }
        static void CheckRunning(string root) {
            foreach(var process in Process.GetProcessesByName("KCCAutomate"))using(process){
                string program;
                try{program=process.MainModule.FileName;}catch{throw new Exception("Close KCCAutomate before changing its installation.");}
                if(String.Equals(Path.GetDirectoryName(program),root,StringComparison.OrdinalIgnoreCase))throw new Exception("Close KCCAutomate, then run setup again.");
            }
        }
        static IDisposable ConversionLock(bool test) {
            if(test || !File.Exists(SettingsPath))return null;
            var settings=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(SettingsPath));
            if(!settings.ContainsKey("WorkFolder")||String.IsNullOrWhiteSpace(Convert.ToString(settings["WorkFolder"])))return null;
            string work=Convert.ToString(settings["WorkFolder"]);
            if(!Directory.Exists(work))throw new Exception("The configured working folder is unavailable. Reconnect it before changing the installation.");
            try{return File.Open(Path.Combine(work,"running.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
            catch(IOException){throw new Exception("A conversion may be running. Let it finish before installing or uninstalling KCCAutomate.");}
        }
        static void ResourceTo(string resource,string destination) {
            using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream(resource)){
                if(input==null)throw new Exception("Setup is missing its embedded application files.");
                using(var output=File.Create(destination))input.CopyTo(output);
            }
        }
        public static void Install(string location,bool desktop,bool test) {
            string root=Full(location);NoLink(root);CheckRunning(root);
            if(File.Exists(Path.Combine(root,"portable.flag")))throw new Exception("This is a portable copy. Choose a separate installation folder; your portable data will be preserved.");
            if(Directory.Exists(root)&&Directory.GetFileSystemEntries(root).Length>0){if(!File.Exists(Path.Combine(root,RecordName)))throw new Exception("Choose an empty folder, or the existing KCCAutomate installation folder.");Record(root);}
            if(!test)using(var key=Registry.CurrentUser.OpenSubKey(RegistryPath)){if(key!=null&&!String.Equals(Convert.ToString(key.GetValue("InstallLocation")),root,StringComparison.OrdinalIgnoreCase))throw new Exception("KCCAutomate is installed in another folder. Choose that folder to upgrade it, or uninstall it first.");}
            foreach(var name in AppFiles)NoLink(Path.Combine(root,name));
            using(var gate=new InstallerGate())using(var guard=ConversionLock(test)) {
                string transaction=Path.Combine(test?Path.GetDirectoryName(root):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),@"KCCAutomate\Installer"),"transaction-"+Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(transaction);string archive=Path.Combine(transaction,"payload.zip");
                ResourceTo("KCCAutomate.Payload.zip",archive);
                string expected;
                using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("KCCAutomate.Payload.sha256"))using(var reader=new StreamReader(stream))expected=reader.ReadToEnd().Trim();
                ReleaseClient.Verify(archive,"sha256:"+expected);
                string extracted=Path.Combine(transaction,"extracted");ReleaseClient.SafeExtract(archive,extracted);
                string payload=Path.Combine(extracted,"KCCAutomate");
                foreach(var name in ReleaseClient.RequiredFiles)if(!File.Exists(Path.Combine(payload,name)))throw new Exception("Incomplete application package: "+name);
                ResourceTo("KCCAutomate.Uninstaller.exe",Path.Combine(payload,Uninstaller));
                Directory.CreateDirectory(root);string backup=Path.Combine(transaction,"backup");Directory.CreateDirectory(backup);
                var replaced=new List<string>();var created=new List<string>();
                var all=AppFiles.Concat(new[]{RecordName}).ToArray();
                foreach(var name in all){if(File.Exists(Path.Combine(root,name))){File.Copy(Path.Combine(root,name),Path.Combine(backup,name));replaced.Add(name);}else created.Add(name);}
                var registryBefore=test?null:ReadRegistry();
                var shortcutsBefore=new Dictionary<string,byte[]>();
                if(!test)foreach(var shortcut in new[]{MenuShortcut,DesktopShortcut})shortcutsBefore[shortcut]=File.Exists(shortcut)?File.ReadAllBytes(shortcut):null;
                try {
                    foreach(var name in AppFiles){File.Copy(Path.Combine(payload,name),Path.Combine(root,name),true);if(ReleaseClient.Hash(Path.Combine(root,name))!=ReleaseClient.Hash(Path.Combine(payload,name)))throw new Exception("Installed file verification failed: "+name);}
                    var record=new InstallRecord{Product=Product,Location=root,Version=ReleaseClient.AppVersion,Files=AppFiles,DesktopShortcut=desktop};
                    File.WriteAllText(Path.Combine(root,RecordName),json.Serialize(record));
                    if(!test){Register(root);Shortcuts(root,desktop);}
                }catch{
                    foreach(var name in replaced)File.Copy(Path.Combine(backup,name),Path.Combine(root,name),true);
                    foreach(var name in created){string path=Path.GetFullPath(Path.Combine(root,name));if(path.StartsWith(root+"\\",StringComparison.OrdinalIgnoreCase)&&File.Exists(path))File.Delete(path);}
                    if(!test){RestoreRegistry(registryBefore);foreach(var shortcut in shortcutsBefore){if(shortcut.Value!=null)File.WriteAllBytes(shortcut.Key,shortcut.Value);else RemoveShortcut(shortcut.Key,Path.Combine(root,"KCCAutomate.exe"));}}
                    throw;
                }
            }
        }
        static Dictionary<string,Tuple<object,RegistryValueKind>> ReadRegistry(){using(var key=Registry.CurrentUser.OpenSubKey(RegistryPath)){if(key==null)return null;return key.GetValueNames().ToDictionary(name=>name,name=>Tuple.Create(key.GetValue(name),key.GetValueKind(name)));}}
        static void RestoreRegistry(Dictionary<string,Tuple<object,RegistryValueKind>> previous){if(previous==null){Registry.CurrentUser.DeleteSubKeyTree(RegistryPath,false);return;}using(var key=Registry.CurrentUser.CreateSubKey(RegistryPath)){foreach(var name in key.GetValueNames())if(!previous.ContainsKey(name))key.DeleteValue(name,false);foreach(var item in previous)key.SetValue(item.Key,item.Value.Item1,item.Value.Item2);}}
        static void Register(string root) {
            using(var key=Registry.CurrentUser.CreateSubKey(RegistryPath)) {
                key.SetValue("DisplayName","KCCAutomate");key.SetValue("DisplayVersion",ReleaseClient.AppVersion);key.SetValue("Publisher","squishysquidly");key.SetValue("InstallLocation",root);key.SetValue("DisplayIcon",Path.Combine(root,"KCCAutomate.exe")+",0");
                key.SetValue("UninstallString","\""+Path.Combine(root,Uninstaller)+"\"");key.SetValue("URLInfoAbout","https://github.com/squishysquidly/KCCAutomate");key.SetValue("NoModify",1,RegistryValueKind.DWord);key.SetValue("NoRepair",1,RegistryValueKind.DWord);
            }
        }
        static string MenuShortcut {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),@"KCCAutomate\KCCAutomate.lnk");}}
        static string DesktopShortcut {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"KCCAutomate.lnk");}}
        static void Shortcut(string path,string target) {
            Directory.CreateDirectory(Path.GetDirectoryName(path));dynamic shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));dynamic link=shell.CreateShortcut(path);
            link.TargetPath=target;link.WorkingDirectory=Path.GetDirectoryName(target);link.Description="KCCAutomate comic conversion";link.Save();
        }
        static void Shortcuts(string root,bool desktop){string target=Path.Combine(root,"KCCAutomate.exe");Shortcut(MenuShortcut,target);if(desktop)Shortcut(DesktopShortcut,target);}
        static void RemoveShortcut(string path,string target) {
            if(!File.Exists(path))return;dynamic shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));dynamic link=shell.CreateShortcut(path);
            if(String.Equals(Convert.ToString(link.TargetPath),target,StringComparison.OrdinalIgnoreCase))File.Delete(path);
        }
        static void RemoveOwnedSchedule(string root) {
            dynamic service=Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));service.Connect();dynamic folder=service.GetFolder("\\");
            string name="KCCAutomate-"+WindowsIdentity.GetCurrent().User.Value;
            dynamic task;
            try{task=folder.GetTask(name);}catch(System.Runtime.InteropServices.COMException ex){if(unchecked((uint)ex.HResult)==0x80070002)return;throw;}
            foreach(dynamic action in task.Definition.Actions){
                if(Convert.ToString(action.Arguments).IndexOf(Path.Combine(root,"Convert-Manga.ps1"),StringComparison.OrdinalIgnoreCase)>=0){if((int)task.State==4)throw new Exception("A scheduled conversion is active. Wait for it to finish.");folder.DeleteTask(name,0);return;}
            }
        }
        public static void Uninstall(string location,bool test) {
            string root=Full(location);NoLink(root);CheckRunning(root);var record=Record(root);
            foreach(var name in record.Files)NoLink(Path.Combine(root,name));
            using(var gate=new InstallerGate())using(var guard=ConversionLock(test)) {
                if(!test)RemoveOwnedSchedule(root);
                foreach(var name in record.Files){string path=Path.GetFullPath(Path.Combine(root,name));if(!path.StartsWith(root+"\\",StringComparison.OrdinalIgnoreCase))throw new Exception("Invalid uninstall target.");if(File.Exists(path))File.Delete(path);}
                File.Delete(Path.Combine(root,RecordName));
                if(!test){RemoveShortcut(MenuShortcut,Path.Combine(root,"KCCAutomate.exe"));RemoveShortcut(DesktopShortcut,Path.Combine(root,"KCCAutomate.exe"));using(var key=Registry.CurrentUser.OpenSubKey(RegistryPath)){if(key!=null&&String.Equals(Convert.ToString(key.GetValue("InstallLocation")),root,StringComparison.OrdinalIgnoreCase))Registry.CurrentUser.DeleteSubKeyTree(RegistryPath);}}
                if(Directory.GetFileSystemEntries(root).Length==0)Directory.Delete(root,false);
            }
        }
    }
    public static class SetupProgram {
        [STAThread]public static void Main(string[] args) {
            bool test=args.Length==2&&(args[0]=="--test-install"||args[0]=="--test-remove");
            try {
                if(test){if(args[0]=="--test-install")InstallCore.Install(args[1],false,true);else InstallCore.Uninstall(args[1],true);return;}
#if UNINSTALL_BUILD
                if(args.Length==2&&args[0]=="--remove-root"){InstallCore.Uninstall(args[1],false);MessageBox.Show("KCCAutomate was removed. Your settings, books and external converter tools were kept.","KCCAutomate");return;}
                string root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
                if(MessageBox.Show("Remove KCCAutomate and its matching scheduled task? Your books, settings and external tools will be kept.","Uninstall KCCAutomate",MessageBoxButtons.OKCancel,MessageBoxIcon.Question)!=DialogResult.OK)return;
                string helper=Path.Combine(Path.GetTempPath(),"KCCAutomate-remove-"+Guid.NewGuid().ToString("N")+".exe");File.Copy(Assembly.GetExecutingAssembly().Location,helper);
                Process.Start(new ProcessStartInfo(helper,"--remove-root \""+root+"\""){UseShellExecute=false,CreateNoWindow=true});
#else
                if(args.Length==2&&args[0]=="--render-setup"){
                    Application.EnableVisualStyles();using(var form=new SetupForm()){form.CreateControl();form.PerformLayout();using(var image=new Bitmap(form.ClientSize.Width,form.ClientSize.Height)){using(var graphics=Graphics.FromImage(image))graphics.Clear(form.BackColor);foreach(Control control in form.Controls){var handle=control.Handle;control.DrawToBitmap(image,control.Bounds);}image.Save(args[1],System.Drawing.Imaging.ImageFormat.Png);}}return;
                }
                Application.EnableVisualStyles();Application.Run(new SetupForm());
#endif
            }catch(Exception ex){Environment.ExitCode=1;if(test){File.WriteAllText(args[1]+".setup-error.txt",ex.ToString());}else MessageBox.Show(ex.Message,"KCCAutomate setup",MessageBoxButtons.OK,MessageBoxIcon.Error);}
        }
    }
#if !UNINSTALL_BUILD
    public class SetupForm:Form {
        readonly TextBox location=new TextBox();readonly CheckBox desktop=new CheckBox(),launch=new CheckBox();readonly Button install=new Button();readonly Label status=new Label();
        public SetupForm(){
            Text="Install KCCAutomate "+ReleaseClient.AppVersion;ClientSize=new Size(660,440);MinimumSize=new Size(650,470);StartPosition=FormStartPosition.CenterScreen;Font=new Font("Segoe UI",10);BackColor=Color.FromArgb(244,245,241);
            var title=new Label{Text="Make room for your next read.",Font=new Font("Segoe UI",20,FontStyle.Bold),AutoSize=true,Location=new Point(28,25)};Controls.Add(title);
            var description=new Label{Text="Install KCCAutomate for your Windows account. No administrator password is needed. The app's setup wizard will guide your folders and converter tools.",Location=new Point(30,80),Size=new Size(595,80)};Controls.Add(description);
            Controls.Add(new Label{Text="Installation folder",AutoSize=true,Location=new Point(30,177)});
            location.SetBounds(30,203,500,30);location.Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),@"Programs\KCCAutomate");Controls.Add(location);
            var browse=new Button{Text="Browse",Location=new Point(540,200),Size=new Size(86,32)};browse.Click+=delegate{using(var dialog=new FolderBrowserDialog{Description="Choose an empty folder or existing KCCAutomate installation",SelectedPath=location.Text})if(dialog.ShowDialog()==DialogResult.OK)location.Text=dialog.SelectedPath;};Controls.Add(browse);
            desktop.Text="Create a desktop shortcut";desktop.SetBounds(30,251,400,25);Controls.Add(desktop);launch.Text="Open KCCAutomate after installation";launch.Checked=true;launch.SetBounds(30,284,460,25);Controls.Add(launch);
            status.SetBounds(30,322,595,55);status.Text="Includes a Start menu shortcut and an entry in Windows Installed apps. KCC and JXL tools are selected separately.";Controls.Add(status);
            install.Text="Install KCCAutomate";install.SetBounds(385,390,240,40);install.BackColor=Color.FromArgb(35,101,76);install.ForeColor=Color.White;Controls.Add(install);
            install.Click+=async delegate{install.Enabled=false;browse.Enabled=false;location.Enabled=false;desktop.Enabled=false;launch.Enabled=false;status.Text="Verifying and installing the app...";try{string target=location.Text;bool addDesktop=desktop.Checked;await System.Threading.Tasks.Task.Run(delegate{InstallCore.Install(target,addDesktop,false);});status.Text="Installation finished. Your books and settings were kept.";if(launch.Checked)Process.Start(new ProcessStartInfo(Path.Combine(target,"KCCAutomate.exe")){UseShellExecute=true});Close();}catch(Exception ex){status.Text=ex.Message;install.Enabled=true;browse.Enabled=true;location.Enabled=true;desktop.Enabled=true;launch.Enabled=true;}};
            FormClosing+=delegate(object sender,FormClosingEventArgs e){if(!install.Enabled&&status.Text.StartsWith("Verifying"))e.Cancel=true;};
        }
    }
#endif
}
