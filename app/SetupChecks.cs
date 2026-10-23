using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace MangaFlow {
    public partial class Settings {
        public string KindlegenExe { get; set; }
        public bool SetupCompleted { get; set; }
    }
    public class ToolPaths {
        public string Kcc { get; set; }
        public string Jxl { get; set; }
        public string Kindlegen { get; set; }
    }
    public class SetupTestResult {
        public string Root { get; set; }
        public string Output { get; set; }
        public string Log { get; set; }
        public bool Passed { get; set; }
    }
    public static class SetupChecks {
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
                    }
                    if(item.Item2<5)foreach(var sub in Directory.GetDirectories(directory)){pending.Enqueue(Tuple.Create(sub,item.Item2+1));}
                } catch(IOException){} catch(UnauthorizedAccessException){} catch(ArgumentException){}
                inspected++;
                if(found.Kcc!=null && found.Jxl!=null && found.Kindlegen!=null)break;
            }
            return found;
        }
        public static string ProbeFolders(Settings settings) {
            Desktop.ValidateFolders(settings);
            if(!Directory.Exists(settings.WatchFolder))throw new Exception("The incoming folder is unavailable. Choose an existing completed-download folder.");
            var report=new StringBuilder();
            foreach(var item in new[]{Tuple.Create("Incoming",settings.WatchFolder),Tuple.Create("Converted",settings.ConvertedFolder),Tuple.Create("Archive",settings.ArchiveFolder),Tuple.Create("Working",settings.WorkFolder)}) {
                Directory.CreateDirectory(item.Item2);
                string token=Guid.NewGuid().ToString("N");
                string path=Path.Combine(item.Item2,".mangaflow-check-"+token+".tmp"),moved=path+".moved";
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
            var report=new StringBuilder();
            try {ReleaseClient.ToolHelp(s.KccExe);report.AppendLine("KCC starts successfully.");}
            catch(Exception ex) {throw new Exception("KCC could not start. Choose its c2e build. A missing PySide6 error indicates a problem in that KCC package.\n"+ex.Message);}
            if(s.ConvertJxl){ReleaseClient.ToolHelp(s.DjxlExe);report.AppendLine("JPEG XL decoder starts successfully.");}
            if(s.Format=="MOBI") {
                if(!String.IsNullOrWhiteSpace(s.KindlegenExe)) {
                    if(!File.Exists(s.KindlegenExe))throw new Exception("The selected KindleGen executable does not exist.");
                    var result=Run(s.KindlegenExe,"-help",20000);
                    if(result.Item1!=0 && !result.Item2.Contains("KindleGen"))throw new Exception("KindleGen could not start: "+result.Item2);
                    report.AppendLine("KindleGen is available to conversion processes.");
                } else report.AppendLine("KindleGen was not selected. KCC may detect it itself; a real MOBI test is needed to confirm that.");
            }
            return report.ToString();
        }
        public static Tuple<int,string> Run(string program,string arguments,int timeout=0) {
            var info=new ProcessStartInfo(program,arguments){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
            info.StandardOutputEncoding=Encoding.UTF8;info.StandardErrorEncoding=Encoding.UTF8;
            using(var process=Process.Start(info)) {
                var output=process.StandardOutput.ReadToEndAsync();var error=process.StandardError.ReadToEndAsync();
                if(timeout>0 && !process.WaitForExit(timeout)){process.Kill();throw new Exception("The tool did not respond within 20 seconds.");}
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
