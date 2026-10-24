using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;

namespace KCCAutomate {
    public static class KindleGenGuide {
        public const string GuideUrl="https://github.com/ciromattia/kcc/wiki/Installation#kindlegen";

        public static string[] InstallationRoots(string local,string programFiles,string programFilesX86) {
            var roots=new List<string>();
            foreach(string parent in new[]{local,programFiles,programFilesX86}.Where(p=>!String.IsNullOrWhiteSpace(p))) {
                foreach(string name in new[]{"Kindle Previewer 4","Kindle Previewer 3","Kindle Comic Creator"}) {
                    roots.Add(Path.Combine(parent,"Amazon",name));
                    roots.Add(Path.Combine(parent,name));
                    if(parent==local){roots.Add(Path.Combine(parent,"Programs",name));roots.Add(Path.Combine(parent,"Programs","Amazon",name));}
                }
            }
            return roots.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        }
        public static string[] InstallationRoots() {
            return InstallationRoots(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86));
        }
        public static string FindFolder(string selected,IEnumerable<string> installationRoots) {
            var roots=new List<string>();
            try {
                string path=(selected??"").Trim().Trim('"');
                if(Path.IsPathRooted(path)) {
                    if(File.Exists(path)&&Path.GetFileName(path).Equals("kindlegen.exe",StringComparison.OrdinalIgnoreCase))roots.Add(Path.GetDirectoryName(path));
                    else if(Directory.Exists(path))roots.Add(path);
                }
            }catch(ArgumentException){}catch(NotSupportedException){}
            if(installationRoots!=null)roots.AddRange(installationRoots);
            var candidates=new List<string>();
            foreach(string root in roots.Where(p=>!String.IsNullOrWhiteSpace(p)).Distinct(StringComparer.OrdinalIgnoreCase)) {
                try {
                    if(!Path.IsPathRooted(root))continue;
                    candidates.Add(Path.Combine(root,@"lib\fc\bin"));candidates.Add(root);
                }catch(ArgumentException){}catch(NotSupportedException){}
            }
            // Prefer a folder containing the requested file over an empty, newer installation.
            foreach(string folder in candidates)if(File.Exists(Path.Combine(folder,"kindlegen.exe")))return folder;
            return candidates.FirstOrDefault(Directory.Exists);
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
            guide.Resources.MergedDictionaries.Add(owner.Resources);if(owner.IsVisible)guide.Owner=owner;
            var message=(TextBlock)guide.FindName("GuideFeedback");
            ((Button)guide.FindName("GuideOpenFolder")).Click+=delegate{try{message.Text=OpenFolder(selected());}catch(Exception ex){message.Text="Windows could not open that folder. Choose the file manually in setup. "+ex.Message;}};
            ((Button)guide.FindName("GuideKccLink")).Click+=delegate{try{Process.Start(new ProcessStartInfo(GuideUrl){UseShellExecute=true});}catch(Exception ex){message.Text=ex.Message;}};
            ((Button)guide.FindName("GuideDone")).Click+=delegate{guide.Close();};
            return guide;
        }
    }
}
