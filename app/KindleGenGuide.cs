using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;

namespace KCCAutomate {
    public class KindleGenLocation {
        public string Compiler {get;set;}
        public string Folder {get;set;}
        public bool PreviewerFolderFound {get;set;}
    }
    public static class KindleGenGuide {
        public const string GuideUrl="https://github.com/ciromattia/kcc/wiki/Installation#kindlegen";
        public const string PreviewerUrl="https://kdp.amazon.com/en_US/help/topic/G202131170";

        public static string[] InstallationRoots(string local,string programFiles,string programFilesX86) {
            var roots=new List<string>();
            foreach(string parent in new[]{local,programFiles,programFilesX86}.Where(p=>!String.IsNullOrWhiteSpace(p))) {
                foreach(string name in new[]{"Kindle Previewer 4","Kindle Previewer 3","Kindle Comic Creator"}) {
                    roots.Add(Path.Combine(parent,"Amazon",name));
                    roots.Add(Path.Combine(parent,name));
                    if(parent==local){roots.Add(Path.Combine(parent,"Programs",name));roots.Add(Path.Combine(parent,"Programs","Amazon",name));}
                }
            }
            foreach(string parent in new[]{programFiles,programFilesX86}.Where(p=>!String.IsNullOrWhiteSpace(p)))roots.Add(Path.Combine(parent,"WindowsApps"));
            return roots.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        }
        public static string[] InstallationRoots() {
            return InstallationRoots(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86));
        }
        static bool StoreContainer(string path){return Path.GetFileName(path.TrimEnd('\\')).Equals("WindowsApps",StringComparison.OrdinalIgnoreCase);}
        static bool AbsolutePath(string path){try{return Path.IsPathRooted(path);}catch(ArgumentException){return false;}}
        public static bool StoreCompiler(string path){
            if(String.IsNullOrWhiteSpace(path)||!AbsolutePath(path))return false;
            string full=Path.GetFullPath(path);
            return full.IndexOf(@"\WindowsApps\KindlePreviewerApp_",StringComparison.OrdinalIgnoreCase)>=0&&full.EndsWith(@"\KindlePreviewerApp\Resources\KFXGen\bin\kindlegen.exe",StringComparison.OrdinalIgnoreCase);
        }
        static bool PreviewerRoot(string path){string name=Path.GetFileName(path.TrimEnd('\\'));return name.StartsWith("Kindle Previewer",StringComparison.OrdinalIgnoreCase)||name.StartsWith("KindlePreviewerApp",StringComparison.OrdinalIgnoreCase);}
        static IEnumerable<string> CompilerFolders(IEnumerable<string> roots){
            foreach(string root in roots.Where(p=>!String.IsNullOrWhiteSpace(p)).Distinct(StringComparer.OrdinalIgnoreCase)){
                if(!Path.IsPathRooted(root)||StoreContainer(root))continue;
                foreach(string relative in new[]{@"lib\fc\bin",@"KindlePreviewerApp\Resources\KFXGen\bin",@"Resources\KFXGen\bin",""})yield return relative.Length==0?root:Path.Combine(root,relative);
            }
        }
        static string[] RegisteredStoreRoots(){
            try{
                string shell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");
                if(!File.Exists(shell))return new string[0];
                string script="$ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); Import-Module (Join-Path $PSHOME 'Modules\\Appx\\Appx.psd1') -ErrorAction Stop; Get-AppxPackage -Name '*KindlePreviewer*' -ErrorAction Stop | ForEach-Object { if ($_.InstallLocation) { [Console]::WriteLine($_.InstallLocation) } }";
                var result=SetupChecks.Run(shell,"-NoProfile -NonInteractive -EncodedCommand "+Convert.ToBase64String(Encoding.Unicode.GetBytes(script)),8000);
                if(result.Item1!=0)return new string[0];
                // PowerShell can emit progress XML on stderr alongside its paths.
                return result.Item2.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries).Where(AbsolutePath).ToArray();
            }catch{return new string[0];}
        }
        public static string FindFolder(string selected,IEnumerable<string> installationRoots) {return Locate(selected,installationRoots).Folder;}
        public static KindleGenLocation Locate(string selected,IEnumerable<string> installationRoots) {return Locate(selected,installationRoots,RegisteredStoreRoots);}
        public static KindleGenLocation Locate(string selected,IEnumerable<string> installationRoots,Func<string[]> registeredStoreRoots) {
            var roots=new List<string>();
            try {
                string path=(selected??"").Trim().Trim('"');
                if(Path.IsPathRooted(path)) {
                    if(File.Exists(path)&&Path.GetFileName(path).Equals("kindlegen.exe",StringComparison.OrdinalIgnoreCase))roots.Add(Path.GetDirectoryName(path));
                    else if(Directory.Exists(path))roots.Add(path);
                }
            }catch(ArgumentException){}catch(NotSupportedException){}
            if(installationRoots!=null)roots.AddRange(installationRoots);
            roots=roots.Where(p=>!String.IsNullOrWhiteSpace(p)&&AbsolutePath(p)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            var candidates=CompilerFolders(roots).ToList();
            string folder=candidates.FirstOrDefault(p=>File.Exists(Path.Combine(p,"kindlegen.exe")));
            bool previewer=roots.Any(r=>PreviewerRoot(r)&&Directory.Exists(r));
            if(folder==null&&roots.Any(StoreContainer)){
                var packages=new List<string>();
                foreach(string container in roots.Where(StoreContainer)){
                    try{packages.AddRange(Directory.GetDirectories(container,"KindlePreviewerApp_*",SearchOption.TopDirectoryOnly));}
                    catch(UnauthorizedAccessException){}catch(IOException){}catch(SecurityException){}
                }
                var packageFolders=CompilerFolders(packages).ToList();
                folder=packageFolders.FirstOrDefault(p=>File.Exists(Path.Combine(p,"kindlegen.exe")));
                // Registered package locations work even when WindowsApps cannot be listed.
                if(folder==null&&registeredStoreRoots!=null){
                    try{var registered=registeredStoreRoots()??new string[0];packages.AddRange(registered);previewer|=registered.Length>0;}catch{}
                    packageFolders=CompilerFolders(packages).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                    folder=packageFolders.FirstOrDefault(p=>File.Exists(Path.Combine(p,"kindlegen.exe")));
                }
                previewer|=packages.Any(r=>PreviewerRoot(r)&&Directory.Exists(r));
                candidates.AddRange(packageFolders);
            }
            if(folder==null)folder=candidates.FirstOrDefault(Directory.Exists);
            return new KindleGenLocation{Folder=folder,Compiler=folder!=null&&File.Exists(Path.Combine(folder,"kindlegen.exe"))?Path.Combine(folder,"kindlegen.exe"):null,PreviewerFolderFound=previewer};
        }
        public static string OpenFolder(string selected) {
            string folder=FindFolder(selected,InstallationRoots());
            if(folder==null)return "No Kindle Previewer or Comic Creator folder was found in the usual locations. Open KCC's guide for installation instructions, or choose an existing working kindlegen.exe. Custom installations can be selected with Choose kindlegen.exe.";
            Process.Start(new ProcessStartInfo(folder){UseShellExecute=true});
            return "Opened: "+folder+"\nLook for kindlegen.exe. Return to setup and choose it; opening a folder does not validate a tool.";
        }
        public static Window Create(Window owner,Func<string> selected) {
            Window guide;
            using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("KCCAutomate.KindleGenGuide.xaml"))guide=(Window)XamlReader.Load(stream);
            guide.Icon=AppBranding.Icon;
            guide.Resources.MergedDictionaries.Add(owner.Resources);if(owner.IsVisible)guide.Owner=owner;
            var message=(TextBlock)guide.FindName("GuideFeedback");
            ((Button)guide.FindName("GuideOpenFolder")).Click+=delegate{try{message.Text=OpenFolder(selected());}catch(Exception ex){message.Text="Windows could not open that folder. Choose the file manually in setup. "+ex.Message;}};
            ((Button)guide.FindName("GuideKccLink")).Click+=delegate{try{Process.Start(new ProcessStartInfo(GuideUrl){UseShellExecute=true});}catch(Exception ex){message.Text=ex.Message;}};
            ((Button)guide.FindName("GuideDone")).Click+=delegate{guide.Close();};
            return guide;
        }
    }
}
