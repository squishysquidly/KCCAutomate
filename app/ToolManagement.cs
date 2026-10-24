using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace KCCAutomate {
    public class ToolCheck {
        public string Key {get;set;}
        public string Message {get;set;}
        public bool Passed {get;set;}
        public bool Required {get;set;}
        public bool Optional {get;set;}
    }
    public static class ToolValidation {
        public static bool RequiresKindlegen(Settings settings) {
            return settings.Format=="MOBI"||(settings.FolderRules!=null&&settings.FolderRules.Any(r=>r!=null&&r.Options!=null&&r.Options.ContainsKey("Format")&&Convert.ToString(r.Options["Format"])=="MOBI"));
        }
        public static bool IsC2E(string path) {
            string name=Path.GetFileName(path??"");
            return name.Equals("kcc-c2e.exe",StringComparison.OrdinalIgnoreCase) ||
                (name.StartsWith("tool_cli_c2e_",StringComparison.OrdinalIgnoreCase)&&name.EndsWith("_AMD64.exe",StringComparison.OrdinalIgnoreCase));
        }
        public static List<ToolCheck> Check(Settings settings) {
            return new[]{"Kcc","Jxl","Kindle","SevenZip"}.Select(key=>Check(settings,key)).ToList();
        }
        public static ToolCheck Check(Settings settings,string key) {
            if(key=="Kcc")return CheckOne("Kcc",settings.KccExe,true,delegate(string path){
                if(!IsC2E(path))throw new Exception("Choose kcc-c2e.exe or tool_cli_c2e_…_AMD64.exe; kcc.exe and kcc-c2c.exe cannot convert books here.");
                var result=SetupChecks.Run(path,"--help",20000);
                if(result.Item1!=0 || result.Item2.IndexOf("comic2ebook",StringComparison.OrdinalIgnoreCase)<0 || !result.Item2.Contains("--profile") || !result.Item2.Contains("--format"))
                    throw new Exception("KCC c2e did not pass its startup check. Choose the approved KCC "+ReleaseClient.ApprovedKccVersion+" Windows CLI .exe. For a missing PySide6/module error, replace the bundled .exe with the approved download; installing Python separately will not repair it.\n"+Limit(result.Item2));
                ReleaseClient.ValidateKccHelp(result.Item2);
                return "Approved KCC c2e validated · "+FirstLine(result.Item2,"comic2ebook");
            });
            if(key=="Jxl")return !settings.ConvertJxl?new ToolCheck{Key="Jxl",Optional=true,Message="JPEG XL preparation is off"}:CheckOne("Jxl",settings.DjxlExe,true,delegate(string path){
                if(!Path.GetFileName(path).Equals("djxl.exe",StringComparison.OrdinalIgnoreCase))throw new Exception("Choose djxl.exe, the JPEG XL decoder.");
                var result=SetupChecks.Run(path,"--help",20000);
                if(result.Item1!=0 || !(result.Item2.IndexOf("JPEG XL",StringComparison.OrdinalIgnoreCase)>=0 || result.Item2.IndexOf("djxl",StringComparison.OrdinalIgnoreCase)>=0))throw new Exception("The JPEG XL decoder could not identify itself.\n"+Limit(result.Item2));
                return "JPEG XL decoder validated";
            });
            if(key=="Kindle")return !RequiresKindlegen(settings)?new ToolCheck{Key="Kindle",Optional=true,Message="KindleGen is not needed for "+settings.Format}:CheckOne("Kindle",settings.KindlegenExe,true,delegate(string path){
                if(!Path.GetFileName(path).Equals("kindlegen.exe",StringComparison.OrdinalIgnoreCase))throw new Exception("Choose kindlegen.exe from Kindle Previewer (see KCC guide).");
                // No input starts the program and prints its banner without compiling a book.
                // Some Amazon builds spell the banner "kindlgen" and reject -help with E30010.
                var result=SetupChecks.Run(path,"",20000);
                if(!KindlegenReplyValid(result.Item1,result.Item2)){
                    result=SetupChecks.Run(path,"-help",20000);
                    if(!KindlegenReplyValid(result.Item1,result.Item2))throw new Exception("KindleGen could not identify itself.\n"+Limit(result.Item2));
                }
                return "KindleGen validated";
            });
            bool archive=settings.ConvertJxl&&Path.GetExtension(settings.DjxlExe??"").Equals(".7z",StringComparison.OrdinalIgnoreCase);
            if(key=="SevenZip")return CheckOne("SevenZip",settings.SevenZipExe,archive,delegate(string path){
                if(!Path.GetFileName(path).Equals("7z.exe",StringComparison.OrdinalIgnoreCase))throw new Exception("Choose 7z.exe from the official Windows 7-Zip package.");
                var result=SetupChecks.Run(path,"i",20000);
                if(result.Item1!=0 || result.Item2.IndexOf("7-Zip",StringComparison.OrdinalIgnoreCase)<0)throw new Exception("7-Zip could not identify itself.\n"+Limit(result.Item2));
                SetupChecks.ProbeSevenZip(path);
                return "7-Zip validated · CLI archive support passed";
            });
            throw new ArgumentException("Unknown tool: "+key);
        }
        public static bool KindlegenReplyValid(int code,string text) {
            if(code<0||code>2||!System.Text.RegularExpressions.Regex.IsMatch(text,@"(?im)^\s*(?:Amazon\s+)?kindle?gen\s*(?:\(Windows\))?\s+V?\d+\.\d+"))return false;
            if(text.IndexOf("e-book compiler",StringComparison.OrdinalIgnoreCase)<0&&text.IndexOf("usage",StringComparison.OrdinalIgnoreCase)<0)return false;
            foreach(System.Text.RegularExpressions.Match error in System.Text.RegularExpressions.Regex.Matches(text,@"Error\(kindle?gen\):\s*([A-Z]\d+)",System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                if(error.Groups[1].Value!="E30005"&&error.Groups[1].Value!="E30010")return false;
            return true;
        }
        static ToolCheck CheckOne(string key,string path,bool required,Func<string,string> validate) {
            var result=new ToolCheck{Key=key,Required=required};
            if(String.IsNullOrWhiteSpace(path)){result.Optional=!required;result.Message=required?"Missing — choose this tool":"Optional — not selected";return result;}
            try {if(!File.Exists(path))throw new Exception("File is missing or unavailable.");result.Message=validate(path);result.Passed=true;}
            catch(Exception ex){result.Message=Limit(ex.Message);}
            return result;
        }
        static string FirstLine(string text,string match){return text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries).FirstOrDefault(l=>l.IndexOf(match,StringComparison.OrdinalIgnoreCase)>=0)??match;}
        static string Limit(string text){return text.Length>900?text.Substring(0,900)+"…":text;}
        public static bool Passed(IEnumerable<ToolCheck> checks){return checks.All(c=>c.Passed||c.Optional);}
        public static string Report(IEnumerable<ToolCheck> checks){return String.Join(Environment.NewLine,checks.Select(c=>c.Key+": "+c.Message));}
    }
    public class ToolBundleRecord {
        public Dictionary<string,string> Selections {get;set;}
        public Dictionary<string,string> Files {get;set;}
    }
    public static class ManagedTools {
        const int MaxFiles=10000;
        const long MaxBytes=2L*1024*1024*1024;
        static readonly JavaScriptSerializer Json=new JavaScriptSerializer{MaxJsonLength=8000000};
        static readonly string[] RuntimeFolders={"_internal","lib","lib64","bin","plugins","platforms","resources","translations","licenses","license","share","data"};
        static bool Under(string path,string root){return Path.GetFullPath(path).StartsWith(Path.GetFullPath(root).TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase);}
        static void Plain(string path){if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new Exception("Tool packages cannot contain links or redirected folders: "+path);}
        static void PlainAncestors(string path){for(string item=Path.GetFullPath(path);!String.IsNullOrEmpty(item);item=Path.GetDirectoryName(item)){if(Directory.Exists(item)||File.Exists(item))Plain(item);}}
        static string NewArea(string root,string prefix){PlainAncestors(root);Directory.CreateDirectory(root);string area=Path.Combine(root,prefix+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(area);return area;}
        static bool Companion(string file) {
            string name=Path.GetFileName(file).ToLowerInvariant(),extension=Path.GetExtension(name);
            return extension==".dll"||extension==".pyd"||extension==".manifest"||extension==".config"||extension==".dat"||extension==".pak"||
                (name.StartsWith("python")&&extension==".zip")||name.StartsWith("license")||name.StartsWith("licence")||name.StartsWith("copying")||name.StartsWith("copyright")||name.StartsWith("notice")||name.StartsWith("readme");
        }
        static void CopyVerified(string source,string target) {
            PlainAncestors(source);Directory.CreateDirectory(Path.GetDirectoryName(target));
            string before=ReleaseClient.Hash(source);File.Copy(source,target,false);
            if(ReleaseClient.Hash(target)!=before||ReleaseClient.Hash(source)!=before)throw new Exception("A tool changed while being copied. Retry after downloads finish: "+source);
        }
        static void CopyTree(string source,string target,ref int count,ref long bytes) {
            Plain(source);Directory.CreateDirectory(target);
            foreach(string file in Directory.GetFiles(source)){if(++count>MaxFiles||(bytes+=new FileInfo(file).Length)>MaxBytes)throw new Exception("Tool package is too large. Choose a dedicated extracted tool folder.");CopyVerified(file,Path.Combine(target,Path.GetFileName(file)));}
            foreach(string directory in Directory.GetDirectories(source))CopyTree(directory,Path.Combine(target,Path.GetFileName(directory)),ref count,ref bytes);
        }
        static string CopyTool(string executable,string target,string managedRoot) {
            PlainAncestors(executable);string source=Path.GetDirectoryName(executable);
            // Archives imported by this class carry a bounded package root. Preserve its layout,
            // including libraries in sibling directories rather than flattening it to one .exe.
            for(string parent=source;Under(parent,managedRoot);parent=Path.GetDirectoryName(parent)) {
                string marker=Path.Combine(parent,".kccautomate-jxl-package");
                if(File.Exists(marker)&&File.ReadAllText(marker)=="KCCAutomate JXL import") {
                    int count=0;long bytes=0;CopyTree(parent,target,ref count,ref bytes);
                    return Path.Combine(target,executable.Substring(parent.TrimEnd('\\').Length+1));
                }
            }
            Directory.CreateDirectory(target);
            if(new FileInfo(executable).Length>MaxBytes)throw new Exception("The selected tool executable is too large.");
            CopyVerified(executable,Path.Combine(target,Path.GetFileName(executable)));
            int files=1;long total=new FileInfo(executable).Length;
            foreach(string file in Directory.GetFiles(source).Where(Companion)) {
                if(!file.Equals(executable,StringComparison.OrdinalIgnoreCase)){if(++files>MaxFiles||(total+=new FileInfo(file).Length)>MaxBytes)throw new Exception("Tool package is too large. Choose a dedicated extracted tool folder.");CopyVerified(file,Path.Combine(target,Path.GetFileName(file)));}
            }
            // Do not copy an entire Downloads/Program Files directory. These are the runtime
            // subdirectories shipped by common one-folder Windows distributions.
            foreach(string directory in Directory.GetDirectories(source).Where(d=>RuntimeFolders.Contains(Path.GetFileName(d),StringComparer.OrdinalIgnoreCase)))
                CopyTree(directory,Path.Combine(target,Path.GetFileName(directory)),ref files,ref total);
            return Path.Combine(target,Path.GetFileName(executable));
        }
        static Dictionary<string,string> Selections(Settings settings) {
            // Inactive selections are retained in settings but are not part of this bundle.
            return new Dictionary<string,string>{{"Kcc",settings.KccExe??""},{"Jxl",settings.ConvertJxl?settings.DjxlExe??"":""},{"Kindle",ToolValidation.RequiresKindlegen(settings)?settings.KindlegenExe??"":""},{"SevenZip",settings.SevenZipExe??""}};
        }
        static bool Reusable(Settings settings,string root) {
            if(String.IsNullOrWhiteSpace(settings.KccExe)||!Under(settings.KccExe,root))return false;
            for(string parent=Path.GetDirectoryName(settings.KccExe);Under(parent,root);parent=Path.GetDirectoryName(parent)) {
                string manifest=Path.Combine(parent,"bundle.json");if(!File.Exists(manifest))continue;
                PlainAncestors(manifest);var record=Json.Deserialize<ToolBundleRecord>(File.ReadAllText(manifest));var selected=Selections(settings);
                if(record==null||record.Selections==null||record.Files==null||record.Files.Count==0||!selected.All(s=>record.Selections.ContainsKey(s.Key)&&String.Equals(record.Selections[s.Key],s.Value,StringComparison.OrdinalIgnoreCase)&&(String.IsNullOrWhiteSpace(s.Value)||(Under(s.Value,parent)&&record.Files.ContainsKey(s.Value.Substring(parent.Length+1))))))return false;
                foreach(var file in record.Files){string path=SafePath(parent,file.Key,true);PlainAncestors(path);if(!File.Exists(path)||ReleaseClient.Hash(path)!=file.Value)return false;}
                return true;
            }
            return false;
        }
        public static Settings Import(Settings original,string root) {
            var checks=ToolValidation.Check(original);if(!ToolValidation.Passed(checks))throw new Exception(ToolValidation.Report(checks));
            if(Reusable(original,root))return original;
            string area=NewArea(root,"bundle-");
            var result=Json.Deserialize<Settings>(Json.Serialize(original));
            try {
                result.KccExe=CopyTool(original.KccExe,Path.Combine(area,"kcc"),root);
                result.DjxlExe=!original.ConvertJxl?original.DjxlExe:CopyTool(original.DjxlExe,Path.Combine(area,"jxl"),root);
                result.KindlegenExe=!ToolValidation.RequiresKindlegen(original)?original.KindlegenExe:CopyTool(original.KindlegenExe,Path.Combine(area,"kindlegen"),root);
                result.SevenZipExe=String.IsNullOrWhiteSpace(original.SevenZipExe)?"":CopyTool(original.SevenZipExe,Path.Combine(area,"7zip"),root);
                // KCC versions which check beside their executable can also locate KindleGen.
                if(ToolValidation.RequiresKindlegen(original)&&!String.IsNullOrWhiteSpace(result.KindlegenExe)) {
                    string beside=Path.Combine(Path.GetDirectoryName(result.KccExe),"kindlegen.exe");
                    if(!File.Exists(beside))CopyVerified(result.KindlegenExe,beside);
                }
                var copied=ToolValidation.Check(result);if(!ToolValidation.Passed(copied))throw new Exception("The copied tools could not start. Select the original tool's complete extracted package, including its runtime folders.\n"+ToolValidation.Report(copied));
                var files=Directory.GetFiles(area,"*",SearchOption.AllDirectories).ToDictionary(f=>f.Substring(area.Length+1),f=>ReleaseClient.Hash(f));
                File.WriteAllText(Path.Combine(area,"bundle.json"),Json.Serialize(new ToolBundleRecord{Selections=Selections(result),Files=files}));
                return result;
            } catch(Exception ex){File.WriteAllText(Path.Combine(area,"import-failed.txt"),ex.ToString());throw;}
        }
        public static string PrepareJxl(string selected,string sevenZip,string root) {
            string extension=Path.GetExtension(selected??"").ToLowerInvariant();
            if(extension!=".zip"&&extension!=".7z")return selected;
            if(!File.Exists(selected))throw new Exception("The selected JXL package is missing.");
            PlainAncestors(selected);
            if(extension==".7z"){
                var check=ToolValidation.Check(new Settings{KccExe="",ConvertJxl=false,Format="EPUB",SevenZipExe=sevenZip}).Single(c=>c.Key=="SevenZip");
                if(!check.Passed)throw new Exception("Select and validate 7z.exe to import this .7z package, or use a .zip JXL download.\n"+check.Message);
            }
            string area=NewArea(root,"jxl-import-");string hash=ReleaseClient.Hash(selected);
            if(extension==".zip")ExtractZip(selected,area);else ExtractSevenZip(selected,sevenZip,area);
            if(ReleaseClient.Hash(selected)!=hash)throw new Exception("The JXL download changed during import. Wait for it to finish and try again.");
            string[] candidates=Directory.GetFiles(area,"djxl.exe",SearchOption.AllDirectories);
            if(candidates.Length!=1)throw new Exception("The package must contain one Windows djxl.exe. Choose the Windows package for your PC, or extract it yourself and select djxl.exe with its companion files.");
            File.WriteAllText(Path.Combine(area,".kccautomate-jxl-package"),"KCCAutomate JXL import");
            return candidates[0];
        }
        public static string SafePath(string root,string name) {return SafePath(root,name,false);}
        static HashSet<string> JxlMembers(IEnumerable<string> names) {
            var files=names.Where(n=>!n.EndsWith("/")&&!n.EndsWith("\\")).ToArray();
            var decoders=files.Where(n=>Path.GetFileName(n.Replace('/','\\')).Equals("djxl.exe",StringComparison.OrdinalIgnoreCase)).ToArray();
            if(decoders.Length!=1)throw new Exception("The package must contain one Windows djxl.exe. Choose the Windows package for your PC, or extract it yourself and select djxl.exe with its companion files.");
            // Keep runtime libraries/configuration and licence material in their original layout.
            // Encoders, benchmarks, samples and other unrelated utilities are not imported.
            return new HashSet<string>(files.Where(n=>n==decoders[0]||Companion(n.Replace('/','\\'))||new[]{".json",".ini",".cfg",".icc",".icm"}.Contains(Path.GetExtension(n),StringComparer.OrdinalIgnoreCase)||n.Replace('/','\\').Split('\\').Any(p=>p.Equals("licenses",StringComparison.OrdinalIgnoreCase)||p.Equals("license",StringComparison.OrdinalIgnoreCase))),StringComparer.OrdinalIgnoreCase);
        }
        static string SafePath(string root,string name,bool internalMetadata) {
            name=name.Replace('/','\\').TrimEnd('\\');
            string[] parts=name.Split('\\');
            if(String.IsNullOrWhiteSpace(name)||Path.IsPathRooted(name)||parts.Any(p=>p.Length==0||p=="."||p==".."||p.EndsWith(".")||p.EndsWith(" ")||p.IndexOfAny(Path.GetInvalidFileNameChars())>=0||System.Text.RegularExpressions.Regex.IsMatch(p,@"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$",System.Text.RegularExpressions.RegexOptions.IgnoreCase))||(!internalMetadata&&parts.Any(p=>p.StartsWith(".kccautomate-",StringComparison.OrdinalIgnoreCase))))throw new Exception("Unsafe tool archive entry: "+name);
            string full=Path.GetFullPath(Path.Combine(root,name));if(!Under(full,root))throw new Exception("Tool archive entry leaves its destination.");return full;
        }
        static void ExtractZip(string archive,string root) {
            using(var zip=ZipFile.OpenRead(archive)){
                var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);long bytes=0;
                foreach(var entry in zip.Entries){string path=SafePath(root,entry.FullName);if(!seen.Add(path)||zip.Entries.Count>MaxFiles||(bytes+=entry.Length)>MaxBytes||((entry.ExternalAttributes>>16)&0xf000)==0xa000||(entry.ExternalAttributes&0x400)!=0)throw new Exception("Unsafe, linked, duplicate or oversized tool archive entry: "+entry.FullName);}
                var selected=JxlMembers(zip.Entries.Select(e=>e.FullName));
                foreach(var entry in zip.Entries){if(!selected.Contains(entry.FullName))continue;string path=SafePath(root,entry.FullName);Directory.CreateDirectory(Path.GetDirectoryName(path));entry.ExtractToFile(path,false);}
            }
        }
        static void ExtractSevenZip(string archive,string program,string root) {
            var listing=SetupChecks.Run(program,"l -slt -ba -sccUTF-8 -pKCCAutomate-no-password -- "+Desktop.Quote(archive),30000);
            if(listing.Item1!=0)throw new Exception("7-Zip could not read the JXL package: "+listing.Item2);
            var records=new List<Dictionary<string,string>>();var record=new Dictionary<string,string>();
            foreach(string line in (listing.Item2+"\n\n").Split('\n')) {
                string value=line.TrimEnd('\r');
                if(value.Length==0){if(record.ContainsKey("Path")){records.Add(record);record=new Dictionary<string,string>();}continue;}
                int separator=value.IndexOf(" = ",StringComparison.Ordinal);if(separator>0){string key=value.Substring(0,separator);if(record.ContainsKey(key))throw new Exception("Ambiguous 7-Zip package listing.");record[key]=value.Substring(separator+3);}
            }
            var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);long bytes=0;
            if(records.Count==0||records.Count>MaxFiles)throw new Exception("The JXL archive is empty or has too many entries.");
            foreach(var item in records) {
                string path=SafePath(root,item["Path"]),attributes=item.ContainsKey("Attributes")?item["Attributes"]:"";long size;
                if(!seen.Add(path)||item.Keys.Any(k=>k.IndexOf("Link",StringComparison.OrdinalIgnoreCase)>=0)||attributes.IndexOf("Reparse",StringComparison.OrdinalIgnoreCase)>=0||attributes.Contains("l")||!item.ContainsKey("Size")||!Int64.TryParse(item["Size"],out size)||size<0||(bytes+=size)>MaxBytes)throw new Exception("Unsafe, linked, duplicate or oversized 7-Zip package entry: "+item["Path"]);
            }
            var selected=JxlMembers(records.Where(i=>!(i.ContainsKey("Folder")?i["Folder"]=="+":i.ContainsKey("Attributes")&&i["Attributes"].StartsWith("D",StringComparison.Ordinal))).Select(i=>i["Path"]));
            // Stream each named member into our own validated file path. 7-Zip never chooses
            // a filesystem destination, so traversal, links and wildcard extraction cannot write outside root.
            foreach(var item in records) {
                string path=SafePath(root,item["Path"]);bool directory=item.ContainsKey("Folder")?item["Folder"]=="+":item.ContainsKey("Attributes")&&item["Attributes"].StartsWith("D",StringComparison.Ordinal);
                if(directory||!selected.Contains(item["Path"]))continue;
                Directory.CreateDirectory(Path.GetDirectoryName(path));long expected=Int64.Parse(item["Size"]);
                var info=new ProcessStartInfo(program,"x -so -y -bd -spd -pKCCAutomate-no-password -- "+Desktop.Quote(archive)+" "+Desktop.Quote(item["Path"])){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
                using(var process=Process.Start(info))using(var output=File.Create(path)) {
                    var errors=process.StandardError.ReadToEndAsync();
                    var copying=Task.Run(delegate{try{byte[] buffer=new byte[81920];long written=0;int read;while((read=process.StandardOutput.BaseStream.Read(buffer,0,buffer.Length))>0){written+=read;if(written>expected)throw new IOException("Archive entry exceeds its declared size.");output.Write(buffer,0,read);}if(written!=expected)throw new IOException("Archive entry size did not match.");}catch{try{process.Kill();}catch{}throw;}});
                    if(!process.WaitForExit(60000)){process.Kill();process.WaitForExit();try{copying.Wait();}catch{}throw new Exception("7-Zip import timed out.");}
                    copying.GetAwaiter().GetResult();if(process.ExitCode!=0)throw new Exception("7-Zip could not extract "+item["Path"]+": "+errors.Result);
                }
            }
        }
    }
}
