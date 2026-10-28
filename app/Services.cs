using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

[assembly: AssemblyVersion("0.1.20.0")]
[assembly: AssemblyFileVersion("0.1.20.0")]
[assembly: AssemblyProduct("KCCAutomate")]
namespace KCCAutomate {
    public static class ShellIcons {
        [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
        static extern void SHChangeNotify(uint eventId,uint flags,string path,IntPtr unused);
        public static void Refresh(string path) {
            // Replacing an EXE or saving a shortcut does not reliably invalidate
            // Explorer's per-path icon cache. Notify only the item we changed.
            try {
                if(File.Exists(path))SHChangeNotify(0x2000,0x1005,Path.GetFullPath(path),IntPtr.Zero);
            } catch(Exception ex) {
                // A cosmetic shell refresh must not prevent launch or installation.
                Debug.WriteLine("KCCAutomate icon refresh: "+ex.Message);
            }
        }
    }
    public partial class Settings {
        public string OutputNaming { get; set; }
        public bool BundleChapters { get; set; }
        public bool BundleVolumes { get; set; }
        public int VolumeTargetPages { get; set; }
        public int BundleTargetPages { get; set; }
        public int ChapterPageThreshold { get; set; }
        public int BundleMaxMiB { get; set; }
        public bool HoldShortBundles { get; set; }
        public string BookTitleStyle { get; set; }
        public string OriginalsAction { get; set; }
        public bool DeleteOriginalsConfirmed { get; set; }
        public bool CoverNumberBadge { get; set; }
        public Dictionary<string,string> SeriesAliases { get; set; }
        public bool AutoCleanup { get; set; }
        public int SuccessRetentionDays { get; set; }
        public int FailureRetentionDays { get; set; }
        public string NotificationMode { get; set; }
        public bool QuietHoursEnabled { get; set; }
        public string QuietHoursStart { get; set; }
        public string QuietHoursEnd { get; set; }
        public string Theme { get; set; }
        public string UpdateRepository { get; set; }
        public string PreviousKccExe { get; set; }
        public string PreviousDjxlExe { get; set; }
        public List<FolderRule> FolderRules { get; set; }
        public void NewDefaults() {
            BundleTargetPages=200; ChapterPageThreshold=100; BundleMaxMiB=350; HoldShortBundles=false;
            VolumeTargetPages=600;
            BookTitleStyle="Original";SeriesAliases=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            OriginalsAction="Archive";
            OutputNaming="{name}"; SuccessRetentionDays=7; FailureRetentionDays=30;
            NotificationMode="Off"; QuietHoursStart="22:00"; QuietHoursEnd="08:00";
            Theme="Light"; UpdateRepository="squishysquidly/KCCAutomate"; FolderRules=new List<FolderRule>();
        }
    }
    public class FolderRule {
        public string Pattern { get; set; }
        public string PresetName { get; set; }
        public Dictionary<string,object> Options { get; set; }
    }
    public class Preset {
        public string Name { get; set; }
        public Dictionary<string,object> Options { get; set; }
    }
    public class QueueRow {
        public string SourcePath { get; set; }
        public string Name { get; set; }
        public string Batch { get; set; }
        public string Status { get; set; }
        public string Detail { get; set; }
        public string Advice { get; set; }
        public string OutputPath { get; set; }
        public string ConflictKind {get;set;}
        public int JxlPages { get; set; }
        public string UpdatedUtc { get; set; }
    }
    public class ReleaseAsset {
        public string Name { get; set; }
        public string Url { get; set; }
        public string Digest { get; set; }
        public long Size { get; set; }
    }
    public class UpdateRow {
        public string Component { get; set; }
        public string Installed { get; set; }
        public string Latest { get; set; }
        public string Status { get; set; }
        public string Notes { get; set; }
        public string Repository { get; set; }
        public ReleaseAsset Asset { get; set; }
        public string VerifiedPath { get; set; }
        public string VerifiedManifestHash { get; set; }
        public Dictionary<string,string> VerifiedToolFiles { get; set; }
    }
    public static class ReleaseClient {
        public const string AppVersion="0.1.20";
        public const string KccReleasesPage="https://github.com/ciromattia/kcc/releases";
        static readonly JavaScriptSerializer json=new JavaScriptSerializer { MaxJsonLength=8000000 };
        public static string Repository(string text) {
            text=(text ?? "").Trim().TrimEnd('/');
            if (text.StartsWith("https://github.com/",StringComparison.OrdinalIgnoreCase)) text=text.Substring(19);
            if (text.EndsWith(".git")) text=text.Substring(0,text.Length-4);
            if (!Regex.IsMatch(text,@"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") || text.Contains("..")) throw new Exception("Enter a GitHub repository as owner/repository.");
            return text;
        }
        static HttpWebRequest Request(string url) {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var request=(HttpWebRequest)WebRequest.Create(url);
            request.UserAgent="KCCAutomate/"+AppVersion; request.Timeout=20000; request.ReadWriteTimeout=20000;
            request.Accept="application/vnd.github+json"; return request;
        }
        public static UpdateRow Check(string component,string repo,string installed) {
            repo=Repository(repo);
            try {
                using(var response=Request(ReleaseApiUrl(component,repo)).GetResponse())
                using(var reader=new StreamReader(response.GetResponseStream())) return Parse(component,repo,installed,reader.ReadToEnd());
            } catch(WebException ex) {
                var response=ex.Response as HttpWebResponse;
                if(response!=null && response.StatusCode==HttpStatusCode.NotFound) throw new Exception("No public stable release was found for "+repo+". Check repository visibility and publish a release with its Windows asset.");
                if(response!=null && response.StatusCode==HttpStatusCode.Forbidden) throw new Exception("GitHub declined the request. Its public API rate limit may have been reached; try again later.");
                throw;
            }
        }
        public static string ReleaseApiUrl(string component,string repo){return "https://api.github.com/repos/"+Repository(repo)+"/releases/latest";}
        public static UpdateRow Parse(string component,string repo,string installed,string text) {
            var data=json.Deserialize<Dictionary<string,object>>(text);
            var tag=Convert.ToString(data["tag_name"]);
            var row=new UpdateRow { Component=component, Repository=repo, Installed=installed, Latest=tag, Notes=data.ContainsKey("body") ? Convert.ToString(data["body"]) : "" };
            var assets=json.ConvertToType<List<Dictionary<string,object>>>(data["assets"]);
            foreach(var asset in assets) {
                var name=Convert.ToString(asset["name"]);
                bool match=component=="KCCAutomate" ? name.Equals("KCCAutomate-Windows.zip",StringComparison.OrdinalIgnoreCase) :
                    component=="KCC" ? Regex.IsMatch(name,@"^tool_cli_c2e_.*_AMD64\.exe$",RegexOptions.IgnoreCase) :
                    name.Equals("jxl-x64-windows-static.zip",StringComparison.OrdinalIgnoreCase);
                if (match) { row.Asset=new ReleaseAsset {Name=name,Url=Convert.ToString(asset["browser_download_url"]),Digest=asset.ContainsKey("digest") ? Convert.ToString(asset["digest"]) : "",Size=Convert.ToInt64(asset["size"])}; break; }
            }
            Version latest,current;
            if(!Version.TryParse(tag.Trim().TrimStart('v','V'),out latest))row.Status="Version needs review";
            else if(!Version.TryParse((installed??"").Trim().TrimStart('v','V'),out current))row.Status="Installed version unknown";
            else row.Status=latest>current?"Update available":"Up to date";
            if (row.Asset==null) row.Status="No matching Windows asset";
            if(component=="KCC") {
                row.Notes=KccUpdateInstructions(row)+"\n\n"+row.Notes;
            }
            return row;
        }
        public static string KccUpdateInstructions(UpdateRow row) {
            string file=row.Asset==null?"the Windows x64 tool_cli_c2e_VERSION_AMD64.exe":row.Asset.Name;
            return "Selected KCC: "+(String.IsNullOrWhiteSpace(row.Installed)?"Unknown":row.Installed)+". Latest release: "+row.Latest+".\n\n1. Click Open KCC releases and download "+file+" from the release's Assets list.\n2. Click Choose downloaded KCC and select that file.\n3. Setup opens at the KCC step. Wait for its green check, continue to Finish & save, and KCCAutomate will copy the validated tools into its own folder. Your folders and conversion settings are retained.\n\nKCCAutomate does not download KCC binaries or silently replace your selected converter. Its Windows CLI includes Python and its libraries.";
        }
        public static void ValidateKccHelp(string help) {
            if(String.IsNullOrWhiteSpace(help)||help.IndexOf("comic2ebook",StringComparison.OrdinalIgnoreCase)<0||!help.Contains("--profile")||!help.Contains("--format"))
                throw new Exception("Choose the Windows x64 c2e command-line converter from KCC's releases page. Its help must identify comic2ebook and include --profile and --format.");
        }
        public static string Hash(string file) { using(var sha=SHA256.Create()) using(var stream=File.OpenRead(file)) return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant(); }
        public static void Verify(string path,string digest) {
            if (!Regex.IsMatch(digest ?? "",@"^sha256:[0-9a-fA-F]{64}$")) throw new Exception("This release has no SHA-256 digest. Nothing will be installed.");
            if (!String.Equals(Hash(path),digest.Substring(7),StringComparison.OrdinalIgnoreCase)) throw new Exception("Download checksum failed. Nothing will be installed.");
        }
        public static string Download(UpdateRow row,string directory) {
            if(row.Component=="KCC")throw new Exception("KCC downloads are user-managed. Open KCC's GitHub releases page and choose the downloaded CLI in setup: "+KccReleasesPage);
            if (row.Asset==null) throw new Exception("No compatible Windows download is available.");
            if (!Regex.IsMatch(row.Asset.Digest ?? "",@"^sha256:[0-9a-fA-F]{64}$")) throw new Exception("GitHub supplied no SHA-256 digest for this asset. Installation is blocked.");
            var uri=new Uri(row.Asset.Url);
            if (uri.Scheme!="https" || uri.Host!="github.com" || !uri.AbsolutePath.StartsWith("/"+row.Repository+"/releases/download/",StringComparison.OrdinalIgnoreCase)) throw new Exception("Unexpected release download URL.");
            Directory.CreateDirectory(directory);
            var path=Path.Combine(directory,Path.GetFileName(row.Asset.Name));
            using(var response=Request(uri.AbsoluteUri).GetResponse()) using(var source=response.GetResponseStream()) using(var target=File.Create(path)) source.CopyTo(target);
            if (new FileInfo(path).Length!=row.Asset.Size) throw new Exception("Download size does not match the release.");
            Verify(path,row.Asset.Digest);
            if (path.EndsWith(".zip",StringComparison.OrdinalIgnoreCase)) {
                var extract=Path.Combine(directory,"payload"); SafeExtract(path,extract);
                if(row.Component=="KCCAutomate") {
                    var folder=Path.Combine(extract,"KCCAutomate");
                    foreach(var required in RequiredFiles) if(!File.Exists(Path.Combine(folder,required))) throw new Exception("The app release is incomplete: "+required);
                    return folder;
                }
                var candidates=Directory.GetFiles(extract,"djxl.exe",SearchOption.AllDirectories);
                if(candidates.Length!=1) throw new Exception("The tool package does not contain exactly one djxl.exe.");
                return candidates[0];
            }
            return path;
        }
        public static readonly string[] RequiredFiles={"KCCAutomate.exe","MainWindow.xaml","Convert-Manga.ps1","Workflow-Support.ps1","Manage-Schedule.ps1","Read-Log.ps1","Notify-Result.ps1","Apply-Update.ps1","Workspace-Info.ps1","README.md","license.txt"};
        public static void SafeExtract(string zipPath,string destination) {
            string prefix=Path.GetFullPath(destination).TrimEnd('\\')+"\\";
            Directory.CreateDirectory(destination);
            using(var zip=ZipFile.OpenRead(zipPath)) {
                foreach(var entry in zip.Entries) {
                    string target=Path.GetFullPath(Path.Combine(destination,entry.FullName.Replace('/',Path.DirectorySeparatorChar)));
                    if (!target.StartsWith(prefix,StringComparison.OrdinalIgnoreCase) || ((entry.ExternalAttributes >> 16) & 0xF000)==0xA000) throw new Exception("Unsafe path in release archive.");
                    if(String.IsNullOrEmpty(entry.Name)) { Directory.CreateDirectory(target); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(target)); entry.ExtractToFile(target,false);
                }
            }
        }
        public static string ToolHelp(string executable) {
            if(!File.Exists(executable)) throw new Exception("The executable was not found.");
            var info=new ProcessStartInfo(executable,"--help") { UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true };
            using(var p=Process.Start(info)) {
                var stdout=p.StandardOutput.ReadToEndAsync(); var stderr=p.StandardError.ReadToEndAsync();
                if(!p.WaitForExit(20000)) { p.Kill(); throw new Exception("The tool did not respond to its compatibility check."); }
                string text=stdout.Result+"\n"+stderr.Result;
                if(p.ExitCode!=0) throw new Exception("Tool compatibility check failed: "+text.Substring(0,Math.Min(text.Length,1200)));
                return text;
            }
        }
        public static string VersionFromHelp(string text){
            var match=Regex.Match(text??"",@"(?:comic2ebook|decoder|djxl)[^\r\n]*?\bv?(\d+\.\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?)(?=\s|$|[)\]])",RegexOptions.IgnoreCase);
            return match.Success?match.Groups[1].Value:"Unknown";
        }
        public static string InstalledVersion(string executable) {
            try {
                string text=ToolHelp(executable);
                // A frozen executable's file version can belong to its Python bootloader.
                return VersionFromHelp(text);
            } catch { return "Unavailable"; }
        }
    }
}
