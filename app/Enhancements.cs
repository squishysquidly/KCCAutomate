using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace MangaFlow {
    public partial class Desktop {
        public static void MigrateUpdateSource(Settings settings) {
            // Only migrate the former built-in source; preserve custom sources.
            string value=(settings.UpdateRepository??"").Trim().TrimEnd('/');
            if(value.StartsWith("https://github.com/",StringComparison.OrdinalIgnoreCase)) value=value.Substring(19);
            if(value.EndsWith(".git",StringComparison.OrdinalIgnoreCase)) value=value.Substring(0,value.Length-4);
            if(value.Equals("squidlysquishy/KCCautomated",StringComparison.OrdinalIgnoreCase)) settings.UpdateRepository="squishysquidly/KCCAutomate";
        }
        readonly Dictionary<string,QueueRow> queue=new Dictionary<string,QueueRow>(StringComparer.OrdinalIgnoreCase);
        readonly ObservableCollection<Preset> presets=new ObservableCollection<Preset>();
        readonly ObservableCollection<FolderRule> rules=new ObservableCollection<FolderRule>();
        readonly ObservableCollection<UpdateRow> updates=new ObservableCollection<UpdateRow>();
        static readonly string[] OptionFields={"Profile","Format","Cropping","Splitter","MangaStyle","Upscale","Stretch","Autolevel","NoAutocontrast","ForceColor","ForcePng","Webtoon","Gamma","OutputNaming"};
        bool asyncBusy,historyBusy;
        DateTime nextPoll=DateTime.MinValue;
        string queueReport;
        Action<int> afterWorker;
        string presetPath { get { return Path.Combine(userDir,"presets.json"); } }
        void InitializeEnhancements(bool testing) {
            if(!testing && File.Exists(presetPath)) {
                foreach(var preset in json.Deserialize<List<Preset>>(File.ReadAllText(presetPath))) presets.Add(preset);
            }
            Find<ComboBox>("Presets").ItemsSource=presets;
            Find<DataGrid>("RulesGrid").ItemsSource=rules;
            Find<DataGrid>("UpdatesGrid").ItemsSource=updates;
            On("QueueNav",delegate {Navigate(4);}); On("PreferencesNav",delegate {Navigate(5);});
            On("RefreshQueue",delegate {RefreshQueue();});
            On("RetrySelected",delegate {
                var selected=Find<DataGrid>("QueueGrid").SelectedItems.Cast<QueueRow>().Where(r=>r.Status=="Failed" || r.Status=="Conflict").Select(r=>r.SourcePath).ToArray();
                if(selected.Length==0) throw new Exception("Select one or more failed books in the queue first.");
                var s=Save(); Directory.CreateDirectory(userDir);
                var selection=Path.Combine(userDir,"retry-"+Guid.NewGuid().ToString("N")+".json");
                File.WriteAllText(selection,json.Serialize(selected));
                Start("Convert-Manga.ps1","-SelectionPath "+Quote(selection),"Retrying selected books. Other pending inputs remain in place.",true,s);
            });
            Find<ComboBox>("QueueFilter").SelectionChanged+=delegate {UpdateQueueView();};
            Find<DataGrid>("QueueGrid").SelectionChanged+=delegate {
                var row=Find<DataGrid>("QueueGrid").SelectedItem as QueueRow;
                if(row==null) return;
                Find<TextBlock>("QueueDetail").Text=row.Name+" · "+row.Status+"\n"+row.Detail+(String.IsNullOrEmpty(row.OutputPath)?"":"\nOutput: "+row.OutputPath);
                Find<TextBlock>("QueueAdvice").Text=row.Advice;
            };
            On("SavePreset",SaveCurrentPreset); On("ApplyPreset",delegate {var p=Find<ComboBox>("Presets").SelectedItem as Preset; if(p==null) throw new Exception("Select a preset first."); ApplyOptions(p.Options); Dirty();});
            On("DeletePreset",delegate {var p=Find<ComboBox>("Presets").SelectedItem as Preset; if(p==null) return; if(rules.Any(r=>r.PresetName==p.Name)) throw new Exception("Remove rules referring to this preset first."); presets.Remove(p); SavePresets();});
            On("ExportPresets",delegate {
                var dialog=new Microsoft.Win32.SaveFileDialog {Filter="MangaFlow presets (*.json)|*.json",FileName="MangaFlow-presets.json"};
                if(dialog.ShowDialog(Window)==true) File.WriteAllText(dialog.FileName,json.Serialize(presets));
            });
            On("ImportPresets",delegate {
                var dialog=new Microsoft.Win32.OpenFileDialog {Filter="MangaFlow presets (*.json)|*.json"};
                if(dialog.ShowDialog(Window)!=true) return;
                if(new FileInfo(dialog.FileName).Length>1000000) throw new Exception("Preset file is too large.");
                var imported=json.Deserialize<List<Preset>>(File.ReadAllText(dialog.FileName));
                foreach(var p in imported) ValidatePreset(p);
                foreach(var p in imported) {
                    var existing=presets.FirstOrDefault(x=>x.Name==p.Name);
                    if(existing!=null) { p.Name=p.Name+" (imported "+DateTime.Now.ToString("HHmmss")+")"; }
                    presets.Add(p);
                }
                SavePresets(); Status("Presets imported. Apply one to review it before saving settings.");
            });
            On("AddRule",delegate {rules.Add(new FolderRule {Pattern="Series name\\*",PresetName=presets.Count>0 ? presets[0].Name : ""}); Dirty();});
            On("DeleteRule",delegate {var r=Find<DataGrid>("RulesGrid").SelectedItem as FolderRule; if(r!=null) {rules.Remove(r); Dirty();}});
            On("WorkspaceUsage",delegate {Start("Workspace-Info.ps1","","Checking working-folder usage...",false,Save());});
            On("CleanupNow",delegate {
                var s=Save();
                if(!s.AutoCleanup) throw new Exception("Enable temporary-attempt cleanup first, then save your retention periods.");
                Start("Convert-Manga.ps1","-CleanupOnly","Cleaning expired attempts; originals and receipts are preserved.",false,s);
            });
            OnAsync("CheckUpdates",CheckUpdatesAsync); OnAsync("DownloadUpdate",DownloadUpdateAsync);
            On("InstallUpdate",InstallSelected); On("RollbackUpdate",RollbackSelected);
            foreach(var name in new[]{"RefreshQueue","RetrySelected","CleanupNow","WorkspaceUsage","CheckUpdates","DownloadUpdate","InstallUpdate","RollbackUpdate","SavePreset","ApplyPreset","DeletePreset","ImportPresets","ExportPresets"}) actionButtons.Add(Find<Button>(name));
            foreach(var name in new[]{"OutputNaming","SuccessRetentionDays","FailureRetentionDays","QuietHoursStart","QuietHoursEnd","UpdateRepository"}) Find<TextBox>(name).TextChanged+=delegate {Dirty();};
            foreach(var name in new[]{"AutoCleanup","QuietHoursEnabled"}) {Find<CheckBox>(name).Checked+=delegate {Dirty();};Find<CheckBox>(name).Unchecked+=delegate {Dirty();};}
            Find<ComboBox>("Theme").SelectionChanged+=delegate {ApplyTheme(ComboText("Theme"));Dirty();};
            Find<ComboBox>("NotificationMode").SelectionChanged+=delegate {Dirty();};
            Find<DataGrid>("UpdatesGrid").SelectionChanged+=delegate {var r=Find<DataGrid>("UpdatesGrid").SelectedItem as UpdateRow; Find<TextBox>("ReleaseNotes").Text=r==null?"":r.Notes;};
            ApplyTheme(saved.Theme);
            var result=Path.Combine(userDir,"last-update.txt");
            if(!testing && File.Exists(result)) {Status(File.ReadAllText(result)); Append(File.ReadAllText(result));}
        }
        void OnAsync(string name,Func<Task> action) {
            Find<Button>(name).Click+=async delegate {
                if(running!=null || asyncBusy) return;
                asyncBusy=true; foreach(var b in actionButtons) b.IsEnabled=false;
                try {await action();} catch(Exception ex) {Find<TextBlock>("UpdateStatus").Text=ex.Message;Status(ex.Message);}
                finally {asyncBusy=false;foreach(var b in actionButtons) b.IsEnabled=true;}
            };
        }
        string ComboText(string name) {var item=Find<ComboBox>(name).SelectedItem as ComboBoxItem;return item==null?"":Convert.ToString(item.Content);}
        void SelectCombo(string name,string text) {var c=Find<ComboBox>(name);c.SelectedItem=c.Items.Cast<ComboBoxItem>().FirstOrDefault(i=>Convert.ToString(i.Content)==text);}
        void FillExtras(Settings s) {
            Find<TextBox>("OutputNaming").Text=s.OutputNaming??"{name}";
            Find<CheckBox>("AutoCleanup").IsChecked=s.AutoCleanup;
            Find<TextBox>("SuccessRetentionDays").Text=s.SuccessRetentionDays.ToString();
            Find<TextBox>("FailureRetentionDays").Text=s.FailureRetentionDays.ToString();
            Find<CheckBox>("QuietHoursEnabled").IsChecked=s.QuietHoursEnabled;
            Find<TextBox>("QuietHoursStart").Text=s.QuietHoursStart;Find<TextBox>("QuietHoursEnd").Text=s.QuietHoursEnd;
            Find<TextBox>("UpdateRepository").Text=s.UpdateRepository;
            SelectCombo("Theme",s.Theme??"Light");SelectCombo("NotificationMode",s.NotificationMode??"Off");
            rules.Clear();foreach(var r in s.FolderRules??new List<FolderRule>()) rules.Add(r);
        }
        void ReadExtras(Settings s) {
            s.OutputNaming=Text("OutputNaming");
            var testName=s.OutputNaming.Replace("{name}","Book").Replace("{format}","mobi").Replace("{profile}","KS");
            if(String.IsNullOrWhiteSpace(testName) || testName.IndexOfAny(Path.GetInvalidFileNameChars())>=0 || testName.Contains("{") || testName.Contains("}") || testName.EndsWith(".") || testName.EndsWith(" ")) throw new Exception("Use a filename template with {name}, {format} and {profile}, without folders or other braces.");
            int successful,failed;
            if(!Int32.TryParse(Text("SuccessRetentionDays"),out successful) || successful<1 || successful>3650 || !Int32.TryParse(Text("FailureRetentionDays"),out failed) || failed<1 || failed>3650) throw new Exception("Retention periods must be between 1 and 3650 days.");
            s.SuccessRetentionDays=successful;s.FailureRetentionDays=failed;s.AutoCleanup=Find<CheckBox>("AutoCleanup").IsChecked==true;
            s.QuietHoursEnabled=Find<CheckBox>("QuietHoursEnabled").IsChecked==true;
            s.QuietHoursStart=NormalizeTimes(Text("QuietHoursStart"));s.QuietHoursEnd=NormalizeTimes(Text("QuietHoursEnd"));
            if(s.QuietHoursStart.Contains(",") || s.QuietHoursEnd.Contains(",")) throw new Exception("Quiet hours need one start time and one end time.");
            s.NotificationMode=ComboText("NotificationMode");s.Theme=ComboText("Theme");
            s.UpdateRepository=Text("UpdateRepository").Length==0?"":ReleaseClient.Repository(Text("UpdateRepository"));
            s.PreviousKccExe=saved.PreviousKccExe;s.PreviousDjxlExe=saved.PreviousDjxlExe;
            Find<DataGrid>("RulesGrid").CommitEdit(DataGridEditingUnit.Cell,true);Find<DataGrid>("RulesGrid").CommitEdit(DataGridEditingUnit.Row,true);
            foreach(var rule in rules) {
                var preset=presets.FirstOrDefault(p=>p.Name==rule.PresetName);
                if(String.IsNullOrWhiteSpace(rule.Pattern) || preset==null) throw new Exception("Every folder rule needs a pattern and an existing preset name.");
                rule.Options=new Dictionary<string,object>(preset.Options);
            }
            s.FolderRules=rules.ToList();
        }
        public static Dictionary<string,object> Options(Settings s) {
            var result=new Dictionary<string,object>();foreach(var field in OptionFields) result[field]=typeof(Settings).GetProperty(field).GetValue(s,null);return result;
        }
        public static void ValidatePreset(Preset p) {
            if(p==null || String.IsNullOrWhiteSpace(p.Name) || p.Name.Length>100 || p.Options==null || p.Options.Keys.Any(k=>!OptionFields.Contains(k))) throw new Exception("Invalid preset file; only conversion settings are accepted.");
            var serializer=new System.Web.Script.Serialization.JavaScriptSerializer();
            var s=serializer.Deserialize<Settings>(serializer.Serialize(p.Options));ValidateConversion(s);
        }
        void SaveCurrentPreset() {
            var name=Text("PresetName");var p=new Preset{Name=name,Options=Options(Read(false))};ValidatePreset(p);
            var old=presets.FirstOrDefault(x=>x.Name==name);
            if(old!=null) {if(MessageBox.Show(Window,"Replace preset '"+name+"'?","Save preset",MessageBoxButton.OKCancel)!=MessageBoxResult.OK)return;presets.Remove(old);}
            presets.Add(p);SavePresets();Find<ComboBox>("Presets").SelectedItem=p;Status("Preset saved. Folder paths and tool locations were not included.");
        }
        void SavePresets() {Directory.CreateDirectory(userDir);var temp=presetPath+".tmp";File.WriteAllText(temp,json.Serialize(presets));if(File.Exists(presetPath))File.Replace(temp,presetPath,presetPath+".bak");else File.Move(temp,presetPath);}
        void ApplyOptions(Dictionary<string,object> options) {
            var s=json.Deserialize<Settings>(json.Serialize(options));
            Find<ComboBox>("Profile").SelectedValue=s.Profile;SelectCombo("OutputFormat",s.Format);
            Find<ComboBox>("Cropping").SelectedIndex=s.Cropping;Find<ComboBox>("Splitter").SelectedIndex=s.Splitter;
            foreach(var field in OptionFields.Where(f=>typeof(Settings).GetProperty(f).PropertyType==typeof(bool))) Find<CheckBox>(field).IsChecked=(bool)typeof(Settings).GetProperty(field).GetValue(s,null);
            Find<TextBox>("Gamma").Text=s.Gamma.ToString(CultureInfo.InvariantCulture);Find<TextBox>("OutputNaming").Text=s.OutputNaming;
        }
        bool HandleStructured(string line) {
            if(line.StartsWith("@@MF:")) {
                try {var row=json.Deserialize<QueueRow>(line.Substring(5));queue[row.SourcePath]=row;UpdateQueueView();} catch(Exception ex) {Append("Queue record could not be displayed: "+ex.Message);} return true;
            }
            if(line.StartsWith("@@SPACE:")) {Find<TextBlock>("SpaceUsage").Text=line.Substring(8);return true;}
            if(line.StartsWith("@@FOLDERS:")) {Find<TextBlock>("QueueNetwork").Text=line.Substring(10);return true;}
            if(line.StartsWith("Schedule:") || line.StartsWith("No MangaFlow schedule") || line.StartsWith("Automatic checks")) Find<TextBlock>("QueueSchedule").Text=line;
            return false;
        }
        void UpdateQueueView() {
            string selected=(Find<DataGrid>("QueueGrid").SelectedItem as QueueRow)==null?null:((QueueRow)Find<DataGrid>("QueueGrid").SelectedItem).SourcePath;
            IEnumerable<QueueRow> rows=queue.Values;
            switch(ComboText("QueueFilter")) {
                case "Needs attention":rows=rows.Where(r=>r.Status=="Failed" || r.Status=="Conflict" || r.Status=="Review existing output");break;
                case "Waiting":rows=rows.Where(r=>r.Status.StartsWith("Waiting"));break;
                case "Completed":rows=rows.Where(r=>r.Status=="Converted" || r.Status=="Archived");break;
            }
            var items=rows.OrderBy(r=>r.Batch).ThenBy(r=>r.Name).ToList();
            Find<DataGrid>("QueueGrid").ItemsSource=items;
            if(selected!=null) Find<DataGrid>("QueueGrid").SelectedItem=items.FirstOrDefault(r=>r.SourcePath==selected);
            Find<TextBlock>("QueueSummary").Text=String.Format("{0} books / files · {1} need attention · {2} completed · refreshed {3:t}",queue.Count,queue.Values.Count(r=>r.Status=="Failed" || r.Status=="Conflict"),queue.Values.Count(r=>r.Status=="Archived" || r.Status=="Converted"),DateTime.Now);
        }
        void RefreshQueue() {
            var s=Save();Start("Convert-Manga.ps1","-Preview","Inspecting filenames, JXL pages and archive companions. No books are changed.",false,s);
            afterWorker=delegate(int code) {if(code==0) {Start("Manage-Schedule.ps1","-Action Status","Reading the next scheduled check...",false,s);Navigate(4);} else Find<TextBlock>("QueueSummary").Text="Watch folder inspection failed. Check Activity for network or file errors.";};
        }
        void FinishEnhancements(int code) {
            if(queueReport!=null) {
                if(code==0 && File.Exists(queueReport)) {var items=json.Deserialize<List<QueueRow>>(File.ReadAllText(queueReport));queue.Clear();foreach(var r in items)queue[r.SourcePath]=r;UpdateQueueView();}
                queueReport=null;
            }
            if(afterWorker!=null) {var callback=afterWorker;afterWorker=null;callback(code);}
        }
        async void PollQueueHistory() {
            if(historyBusy || running!=null || asyncBusy || DateTime.UtcNow<nextPoll || String.IsNullOrWhiteSpace(saved.WorkFolder)) return;
            nextPoll=DateTime.UtcNow.AddSeconds(20);historyBusy=true;
            try {
                string path=Path.Combine(saved.WorkFolder,"queue.json");
                string text=await Task.Run(delegate {return File.Exists(path)?File.ReadAllText(path):null;});
                if(text!=null) {foreach(var row in json.Deserialize<List<QueueRow>>(text)) queue[row.SourcePath]=row;UpdateQueueView();Find<TextBlock>("QueueNetwork").Text="Working folder is reachable. Refresh the queue to check incoming files.";}
            } catch {Find<TextBlock>("QueueNetwork").Text="Queue history is temporarily unavailable. Check network connectivity or refresh manually.";}
            finally {historyBusy=false;}
        }
        void ApplyTheme(string theme) {
            bool dark=theme=="Dark";
            var colors=new Dictionary<string,string>{{"CanvasBrush",dark?"#17231E":"#F4F5F1"},{"SurfaceBrush",dark?"#23372D":"#FFFFFF"},{"TextBrush",dark?"#E2EDDF":"#27372F"},{"HintBrush",dark?"#B4C7B9":"#647168"},{"LineBrush",dark?"#486150":"#D5DDD5"},{"SoftBrush",dark?"#304B39":"#E5ECDF"}};
            foreach(var c in colors) Window.Resources[c.Key]=new SolidColorBrush((Color)ColorConverter.ConvertFromString(c.Value));
        }
        async Task CheckUpdatesAsync() {
            string repo=Text("UpdateRepository").Length==0?"":ReleaseClient.Repository(Text("UpdateRepository"));
            string kcc=Text("KccExe"),jxl=Text("DjxlExe");updates.Clear();Find<TextBlock>("UpdateStatus").Text="Checking published stable releases...";
            foreach(var component in new[]{"MangaFlow","KCC","JPEG XL"}) {
                if(component=="MangaFlow" && repo.Length==0) {updates.Add(new UpdateRow{Component=component,Installed=ReleaseClient.AppVersion,Latest="—",Status="Set repository first"});continue;}
                string owner=component=="MangaFlow"?repo:component=="KCC"?"ciromattia/kcc":"libjxl/libjxl";
                try {var row=await Task.Run(delegate {return ReleaseClient.Check(component,owner,component=="MangaFlow"?ReleaseClient.AppVersion:ReleaseClient.InstalledVersion(component=="KCC"?kcc:jxl));});updates.Add(row);}
                catch(Exception ex) {updates.Add(new UpdateRow{Component=component,Installed="Unknown",Latest="—",Status="Check failed",Notes=ex.Message});}
            }
            Find<TextBlock>("UpdateStatus").Text="Checks finished. Select a component to read its release notes. Updates are never applied automatically.";
        }
        async Task DownloadUpdateAsync() {
            var row=Find<DataGrid>("UpdatesGrid").SelectedItem as UpdateRow;if(row==null || row.Asset==null) throw new Exception("Select an available release first.");
            Find<TextBlock>("UpdateStatus").Text="Downloading and checking SHA-256...";
            string directory=Path.Combine(userDir,"Updates",Guid.NewGuid().ToString("N"));
            string path=await Task.Run(delegate {return ReleaseClient.Download(row,directory);});
            if(row.Component!="MangaFlow") {
                await Task.Run(delegate {ReleaseClient.ToolHelp(path);});
                var files=row.Component=="KCC"?new[]{path}:Directory.GetFiles(Path.GetDirectoryName(path),"*",SearchOption.AllDirectories);
                row.VerifiedToolFiles=files.ToDictionary(file=>file,file=>ReleaseClient.Hash(file));
            }
            else {
                var manifest=ReleaseClient.RequiredFiles.Select(name=>new{ Name=name,Hash=ReleaseClient.Hash(Path.Combine(path,name)) }).ToArray();
                File.WriteAllText(Path.Combine(path,"verified-files.json"),json.Serialize(manifest));
                row.VerifiedManifestHash=ReleaseClient.Hash(Path.Combine(path,"verified-files.json"));
            }
            row.VerifiedPath=path;row.Status=row.Component=="MangaFlow"?"Verified; ready to install":"Verified; tool check passed";
            Find<DataGrid>("UpdatesGrid").Items.Refresh();Find<TextBlock>("UpdateStatus").Text=row.Status+". Existing installed versions have not changed.";
        }
        void InstallSelected() {
            var row=Find<DataGrid>("UpdatesGrid").SelectedItem as UpdateRow;if(row==null || String.IsNullOrEmpty(row.VerifiedPath)) throw new Exception("Download and verify a release first.");
            if(running!=null || asyncBusy) throw new Exception("Wait until the current operation finishes.");
            if(row.Component=="MangaFlow") {
                Save();if(MessageBox.Show(Window,"Close MangaFlow, back up this installation and apply the verified update? Settings and scheduled paths will be retained.","Install update",MessageBoxButton.OKCancel)!=MessageBoxResult.OK)return;
                LaunchInstaller(row.VerifiedPath,null,row.VerifiedManifestHash);return;
            }
            if(row.VerifiedToolFiles==null || row.VerifiedToolFiles.Any(file=>!File.Exists(file.Key) || !String.Equals(ReleaseClient.Hash(file.Key),file.Value,StringComparison.OrdinalIgnoreCase))) throw new Exception("The staged tool files changed after verification. Download them again.");
            if(row.Component=="KCC") {saved.PreviousKccExe=Text("KccExe");Find<TextBox>("KccExe").Text=row.VerifiedPath;} else {saved.PreviousDjxlExe=Text("DjxlExe");Find<TextBox>("DjxlExe").Text=row.VerifiedPath;}
            Save();Status("Verified tool selected. The previous path is retained for rollback. Test a small book before relying on the new tool.");
        }
        void RollbackSelected() {
            var row=Find<DataGrid>("UpdatesGrid").SelectedItem as UpdateRow;if(row==null) throw new Exception("Select the component to restore first.");
            if(row.Component=="MangaFlow") {
                string backups=Path.Combine(userDir,"Backups");
                var previous=Directory.Exists(backups)?Directory.GetDirectories(backups).OrderByDescending(p=>p).FirstOrDefault(p=>File.Exists(Path.Combine(p,"backup-info.json"))):null;
                if(previous==null) throw new Exception("There is no previous app installation to restore.");
                Save();if(MessageBox.Show(Window,"Close MangaFlow and restore the previous app installation? Settings stay unchanged.","Restore app",MessageBoxButton.OKCancel)==MessageBoxResult.OK)LaunchInstaller(null,previous,null);
                return;
            }
            bool kcc=row.Component=="KCC";string previousTool=kcc?saved.PreviousKccExe:saved.PreviousDjxlExe;
            if(String.IsNullOrEmpty(previousTool)) throw new Exception("No previous tool path was recorded.");
            if(kcc) {saved.PreviousKccExe=Text("KccExe");Find<TextBox>("KccExe").Text=previousTool;} else {saved.PreviousDjxlExe=Text("DjxlExe");Find<TextBox>("DjxlExe").Text=previousTool;}
            Save();Status("Previous tool path restored.");
        }
        void LaunchInstaller(string stage,string rollback,string manifestHash) {
            string helperDir=Path.Combine(userDir,"Updates","helper-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(helperDir);
            string helper=Path.Combine(helperDir,"Apply-Update.ps1");File.Copy(Path.Combine(baseDir,"Apply-Update.ps1"),helper);
            string backup=rollback??Path.Combine(userDir,"Backups",DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N").Substring(0,6));
            string options=" -TargetDirectory "+Quote(baseDir.TrimEnd('\\'))+" -ConfigPath "+Quote(configPath)+" -BackupDirectory "+Quote(backup)+" -WaitProcessId "+Process.GetCurrentProcess().Id;
            if(stage!=null) options+=" -StageDirectory "+Quote(stage)+" -ManifestHash "+Quote(manifestHash);else options+=" -Rollback";
            var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"),"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "+Quote(helper)+options){UseShellExecute=false,CreateNoWindow=true};
            Process.Start(info);closing=true;Window.Close();
        }
        void TestEnhancements(List<string> results,string directory) {
            var legacy=new Settings {UpdateRepository="https://github.com/squidlysquishy/KCCautomated"};
            MigrateUpdateSource(legacy);
            if(legacy.UpdateRepository!="squishysquidly/KCCAutomate") throw new Exception("Legacy update source was not migrated.");
            legacy.UpdateRepository="example/custom";MigrateUpdateSource(legacy);
            if(legacy.UpdateRepository!="example/custom") throw new Exception("Custom update source was changed.");
            results.Add("PASS: old update source migration and custom source preservation");
            var settings=new Settings {WatchFolder=@"C:\test\in",ConvertedFolder=@"C:\test\out",ArchiveFolder=@"C:\test\archive",WorkFolder=@"C:\test\work"};
            Fill(settings);Save();
            var stored=json.Deserialize<Settings>(File.ReadAllText(configPath));
            if(stored.SuccessRetentionDays!=7 || stored.OutputNaming!="{name}" || stored.UpdateRepository!="squishysquidly/KCCAutomate") throw new Exception("Enhanced settings did not persist.");
            var preset=new Preset{Name="Scribe manga",Options=Options(settings)};ValidatePreset(preset);presets.Add(preset);SavePresets();
            if(preset.Options.ContainsKey("WatchFolder") || json.Deserialize<List<Preset>>(File.ReadAllText(presetPath)).Count<1) throw new Exception("Preset isolation or persistence failed.");
            var unsafePreset=new Preset{Name="Unsafe",Options=new Dictionary<string,object>{{"KccExe","bad.exe"}}};
            try {ValidatePreset(unsafePreset);throw new Exception("Unsafe preset accepted");}catch(Exception ex){if(!ex.Message.Contains("Invalid preset"))throw;}
            results.Add("PASS: preset isolation, persistence, unsafe import rejection and enhanced settings");
            var release="{\"tag_name\":\"v0.3.0\",\"body\":\"Release notes\",\"assets\":[{\"name\":\"MangaFlow-Windows.zip\",\"size\":12,\"browser_download_url\":\"https://github.com/squishysquidly/KCCAutomate/releases/download/v0.3.0/MangaFlow-Windows.zip\",\"digest\":\"sha256:"+new string('0',64)+"\"}]}";
            var row=ReleaseClient.Parse("MangaFlow","squishysquidly/KCCAutomate","0.2.0",release);
            if(row.Status!="Update available" || row.Asset==null)throw new Exception("Release parsing failed.");
            if(ReleaseClient.Repository("https://github.com/squishysquidly/KCCAutomate")!="squishysquidly/KCCAutomate")throw new Exception("Repository normalization failed.");
            try{ReleaseClient.Repository("https://evil.example/repo");throw new Exception("Invalid repository accepted");}catch(Exception ex){if(!ex.Message.Contains("owner/repository"))throw;}
            string checkFile=Path.Combine(directory,"checksum-fixture.txt");File.WriteAllText(checkFile,"fixture");ReleaseClient.Verify(checkFile,"sha256:"+ReleaseClient.Hash(checkFile));
            try{ReleaseClient.Verify(checkFile,"sha256:"+new string('0',64));throw new Exception("Tampered download accepted");}catch(Exception ex){if(!ex.Message.Contains("checksum failed"))throw;}
            string zipPath=Path.Combine(directory,"unsafe-"+Guid.NewGuid().ToString("N")+".zip");
            using(var z=System.IO.Compression.ZipFile.Open(zipPath,System.IO.Compression.ZipArchiveMode.Create)){z.CreateEntry("../escape.txt");}
            try{ReleaseClient.SafeExtract(zipPath,Path.Combine(directory,"extract-"+Guid.NewGuid().ToString("N")));throw new Exception("Unsafe ZIP accepted");}catch(Exception ex){if(!ex.Message.Contains("Unsafe path"))throw;}
            results.Add("PASS: release selection, repository validation, SHA-256 verification and ZIP traversal rejection");
            queue[@"C:\test\in\Example.cbz"]=new QueueRow{SourcePath=@"C:\test\in\Example.cbz",Name="Example manga.cbz",Batch="Example series",Status="Failed",Detail="Example decoder failure",Advice="Check the decoder path, then retry.",JxlPages=24};
            UpdateQueueView();
        }
    }
}
