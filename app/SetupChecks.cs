using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace KCCAutomate {
    public partial class Settings {
        // Serialize the approval carried by this app release; saved JSON cannot change it in the GUI.
        public string ApprovedKccVersion {get{return ReleaseClient.ApprovedKccVersion;}}
        public string KindlegenExe { get; set; }
        public string SevenZipExe { get; set; }
        public bool SetupCompleted { get; set; }
    }
    public class ToolPaths {
        public string Kcc { get; set; }
        public string Jxl { get; set; }
        public string Kindlegen { get; set; }
        public string SevenZip { get; set; }
    }
    public class SetupTestResult {
        public string Root { get; set; }
        public string Output { get; set; }
        public string Log { get; set; }
        public bool Passed { get; set; }
    }
    public static class SetupChecks {
        public static void DefaultFolders(Settings settings,string root) {
            if(String.IsNullOrWhiteSpace(settings.WatchFolder))settings.WatchFolder=Path.Combine(root,"Incoming");
            if(String.IsNullOrWhiteSpace(settings.ConvertedFolder))settings.ConvertedFolder=Path.Combine(root,"Converted");
            if(String.IsNullOrWhiteSpace(settings.ArchiveFolder))settings.ArchiveFolder=Path.Combine(root,"Originals");
            if(String.IsNullOrWhiteSpace(settings.WorkFolder))settings.WorkFolder=Path.Combine(root,"Working");
        }
        public static string ResolveToolPath(string key,string path) {
            path=(path??"").Trim().Trim('"');if(!Directory.Exists(path))return path;
            string name=key=="Kcc"?"kcc-c2e.exe":key=="Jxl"?"djxl.exe":key=="Kindle"?"kindlegen.exe":"7z.exe";
            if(key=="Kcc"&&File.Exists(Path.Combine(path,ReleaseClient.ApprovedKccAsset)))return Path.Combine(path,ReleaseClient.ApprovedKccAsset);
            if(File.Exists(Path.Combine(path,name)))return Path.Combine(path,name);
            var found=Discover(new[]{path});return key=="Kcc"?found.Kcc??path:key=="Jxl"?found.Jxl??path:key=="Kindle"?found.Kindlegen??path:found.SevenZip??path;
        }
        public static void ProbeSevenZip(string executable) {
            string root=Path.Combine(Path.GetTempPath(),"KCCAutomate-7z-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
            string input=Path.Combine(root,"probe.txt"),archive=Path.Combine(root,"probe.7z"),token=Guid.NewGuid().ToString("N");
            try {
                File.WriteAllText(input,token);
                var created=Run(executable,"a -t7z -y -bd "+Desktop.Quote(archive)+" "+Desktop.Quote(input),20000);
                if(created.Item1!=0||!File.Exists(archive))throw new Exception("7-Zip cannot create archives. Reinstall its complete Windows package, including 7z.dll.");
                var extracted=Run(executable,"x -so -bd -spd "+Desktop.Quote(archive)+" probe.txt",20000);
                if(extracted.Item1!=0||extracted.Item2.Trim()!=token)throw new Exception("7-Zip CLI extraction failed. Reinstall its complete Windows package, including 7z.dll.");
            } finally {
                // Remove only the two known files in this unique, owned probe directory.
                foreach(string file in new[]{input,archive})try{if(File.Exists(file))File.Delete(file);}catch{}
                try{Directory.Delete(root,false);}catch{}
            }
        }
        public static string FindUsableSevenZip(IEnumerable<string> extra) {
            var paths=new List<string>();if(extra!=null)paths.AddRange(extra);
            foreach(string root in new[]{Environment.GetEnvironmentVariable("ProgramW6432"),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86)})if(!String.IsNullOrEmpty(root))paths.Add(Path.Combine(root,@"7-Zip\7z.exe"));
            foreach(string root in (Environment.GetEnvironmentVariable("PATH")??"").Split(';'))try{if(!String.IsNullOrWhiteSpace(root))paths.Add(Path.Combine(root.Trim('"'),"7z.exe"));}catch(ArgumentException){}
            foreach(string path in paths.Where(p=>!String.IsNullOrWhiteSpace(p)).Distinct(StringComparer.OrdinalIgnoreCase)) {
                var settings=new Settings{SevenZipExe=path,ConvertJxl=false};if(File.Exists(path)&&ToolValidation.Check(settings,"SevenZip").Passed)return path;
            }
            return null;
        }
        public static ToolPaths Discover(IEnumerable<string> roots) {
            var found=new ToolPaths(); var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var pending=new Queue<Tuple<string,int>>();
            foreach(var root in roots.Where(r=>!String.IsNullOrWhiteSpace(r))) pending.Enqueue(Tuple.Create(root,0));
            int inspected=0;
            while(pending.Count>0 && inspected<5000) {
                var item=pending.Dequeue(); string directory=item.Item1;
                if(!seen.Add(directory))continue;
                try {
                    if((File.GetAttributes(directory)&FileAttributes.ReparsePoint)!=0)continue;
                    foreach(var file in Directory.GetFiles(directory,"*.exe").OrderByDescending(f=>File.GetLastWriteTimeUtc(f))) {
                        inspected++;string name=Path.GetFileName(file);
                        if(found.Kcc==null && (name.Equals("kcc-c2e.exe",StringComparison.OrdinalIgnoreCase) || (name.StartsWith("tool_cli_c2e_",StringComparison.OrdinalIgnoreCase)&&name.EndsWith("_AMD64.exe",StringComparison.OrdinalIgnoreCase))))found.Kcc=file;
                        if(found.Jxl==null && name.Equals("djxl.exe",StringComparison.OrdinalIgnoreCase))found.Jxl=file;
                        if(found.Kindlegen==null && name.Equals("kindlegen.exe",StringComparison.OrdinalIgnoreCase))found.Kindlegen=file;
                        if(found.SevenZip==null && name.Equals("7z.exe",StringComparison.OrdinalIgnoreCase))found.SevenZip=file;
                    }
                    if(item.Item2<5)foreach(var sub in Directory.GetDirectories(directory)){pending.Enqueue(Tuple.Create(sub,item.Item2+1));}
                } catch(IOException){} catch(UnauthorizedAccessException){} catch(ArgumentException){}
                inspected++;
                if(found.Kcc!=null && found.Jxl!=null && found.Kindlegen!=null && found.SevenZip!=null)break;
            }
            return found;
        }
        public static string ProbeFolders(Settings settings) {
            Desktop.ValidateFolders(settings);
            var report=new StringBuilder();
            foreach(var item in new[]{Tuple.Create("Incoming",settings.WatchFolder),Tuple.Create("Converted",settings.ConvertedFolder),Tuple.Create("Archive",settings.ArchiveFolder),Tuple.Create("Working",settings.WorkFolder)}) {
                if(item.Item1=="Archive"&&settings.OriginalsAction=="Delete")continue;
                Directory.CreateDirectory(item.Item2);
                string token=Guid.NewGuid().ToString("N");
                string path=Path.Combine(item.Item2,".kccautomate-check-"+token+".tmp"),moved=path+".moved";
                try {
                    File.WriteAllText(path,token);
                    if(File.ReadAllText(path)!=token)throw new IOException("Folder read-back check failed.");
                    File.Move(path,moved);File.Delete(moved);
                    report.AppendLine(item.Item1+": read, write, rename and delete access OK.");
                } catch(Exception ex) {throw new Exception(item.Item1+" folder: "+ex.Message);}
                finally {
                    foreach(var probe in new[]{path,moved})try{if(File.Exists(probe)&&File.ReadAllText(probe)==token)File.Delete(probe);}catch{}
                }
            }
            return report.ToString();
        }
        public static string CheckTools(Settings s) {
            var checks=ToolValidation.Check(s);string report=ToolValidation.Report(checks);
            if(!ToolValidation.Passed(checks))throw new Exception(report);
            return report;
        }
        public static Tuple<int,string> Run(string program,string arguments,int timeout=0) {
            var info=new ProcessStartInfo(program,arguments){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
            info.StandardOutputEncoding=Encoding.UTF8;info.StandardErrorEncoding=Encoding.UTF8;
            using(var process=Process.Start(info)) {
                var output=process.StandardOutput.ReadToEndAsync();var error=process.StandardError.ReadToEndAsync();
                if(timeout>0 && !process.WaitForExit(timeout)){process.Kill();throw new Exception("The check did not respond within "+(timeout/1000)+" seconds.");}
                process.WaitForExit();return Tuple.Create(process.ExitCode,output.Result+Environment.NewLine+error.Result);
            }
        }
        public static SetupTestResult ConvertTest(Settings original,string book,string appDirectory) {
            if(!File.Exists(book))throw new Exception("Choose an existing, completed comic file.");
            var extension=Path.GetExtension(book).ToLowerInvariant();
            if(!new[]{".cbz",".pdf",".epub",".cbr",".cb7"}.Contains(extension))throw new Exception("Choose a CBZ, PDF, EPUB, CBR or CB7 comic.");
            var serializer=new JavaScriptSerializer();
            var test=serializer.Deserialize<Settings>(serializer.Serialize(original));
            // Keep test paths compact for older converters, including KindleGen.
            string root;
            do{root=Path.Combine(original.WorkFolder,"SetupTests",Guid.NewGuid().ToString("N").Substring(0,12));}while(Directory.Exists(root));
            test.WatchFolder=Path.Combine(root,"input");test.ConvertedFolder=Path.Combine(root,"converted");test.ArchiveFolder=Path.Combine(root,"copied-original");test.WorkFolder=Path.Combine(root,"w");
            test.OriginalsAction="Archive";test.DeleteOriginalsConfirmed=false;
            if(Path.Combine(test.WorkFolder,new string('0',64),new string('0',32),"book.mobi").Length>=260)
                throw new Exception("The working folder path is too long for this isolated test and older conversion tools. Choose a shorter working path on the same share, then try again.");
            test.QuietMinutes=0;test.InputExtensions=new[]{extension};test.NotificationMode="Off";test.AutoCleanup=false;test.OutputNaming="{name}";test.FolderRules=new List<FolderRule>();
            Directory.CreateDirectory(test.WatchFolder);
            string hash=ReleaseClient.Hash(book),copy=Path.Combine(test.WatchFolder,"sample"+extension);
            File.Copy(book,copy);
            if(ReleaseClient.Hash(copy)!=hash)throw new Exception("The test copy could not be verified. No conversion was started.");
            string config=Path.Combine(root,"test-settings.json");File.WriteAllText(config,serializer.Serialize(test));
            string powershell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");
            var result=Run(powershell,"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "+Desktop.Quote(Path.Combine(appDirectory,"Convert-Manga.ps1"))+" -ConfigPath "+Desktop.Quote(config));
            if(ReleaseClient.Hash(book)!=hash)throw new Exception("The selected source changed during the test. It was not moved or removed by this test.");
            bool produced=Directory.Exists(test.ConvertedFolder)&&Directory.GetFiles(test.ConvertedFolder,"*",SearchOption.AllDirectories).Length>0;
            return new SetupTestResult{Root=root,Output=test.ConvertedFolder,Log=result.Item2,Passed=result.Item1==0&&produced};
        }
    }
}
