using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace KCCAutomate {
    public partial class Desktop {
        bool automaticToolChecks,toolUpdateCheckPending,releaseCheckRunning;
        Task toolUpdateTask=Task.FromResult(0);
        Func<string,string,string,UpdateRow> releaseLookup=ReleaseClient.Check;
        Func<string,string> versionLookup=ReleaseClient.InstalledVersion;

        void RequestToolUpdateCheck(){
            if(automaticToolChecks&&(saved.SetupCompleted||!String.IsNullOrWhiteSpace(saved.KccExe)))toolUpdateCheckPending=true;
        }
        void PollToolUpdates(){
            if(!automaticToolChecks||!toolUpdateCheckPending||releaseCheckRunning||running!=null||activeConversion!=null||asyncBusy)return;
            toolUpdateCheckPending=false;toolUpdateTask=SafeToolUpdateCheckAsync();
        }
        async Task SafeToolUpdateCheckAsync(){
            try{await CheckToolUpdatesAsync(true);}
            catch(Exception ex){
                Find<TextBlock>("UpdateStatus").Text="Update check could not finish. "+ex.Message;
                Find<TextBlock>("ToolUpdateMessage").Text="Could not check for updates right now. Your selected tools have not changed. View updates for details or try Check GitHub for updates again.";
                Find<FrameworkElement>("NoticeKccReleases").Visibility=Visibility.Collapsed;
                Find<FrameworkElement>("NoticeChooseKcc").Visibility=Visibility.Collapsed;
                Find<FrameworkElement>("ToolUpdateNotice").Visibility=Visibility.Visible;
            }
        }
        async Task CheckToolUpdatesAsync(bool background=false){
            if(releaseCheckRunning)return;
            releaseCheckRunning=true;toolUpdateCheckPending=false;
            var checkButton=Find<Button>("CheckUpdates");checkButton.IsEnabled=false;
            string repo=Text("UpdateRepository"),kcc=Text("KccExe"),jxl=Text("DjxlExe");bool jxlEnabled=Checked("ConvertJxl");
            Find<TextBlock>("UpdateStatus").Text="Checking the latest app, KCC and JPEG XL releases. Your selected tools will stay in place...";
            try{
                var rows=new List<UpdateRow>();
                foreach(string component in new[]{"KCCAutomate","KCC","JPEG XL"}){
                    if(component=="KCCAutomate"&&String.IsNullOrWhiteSpace(repo)){rows.Add(new UpdateRow{Component=component,Installed=ReleaseClient.AppVersion,Latest="—",Status="Set repository first"});continue;}
                    if(component=="JPEG XL"&&!jxlEnabled){rows.Add(new UpdateRow{Component=component,Installed="Not in use",Latest="—",Status="Not in use",Notes="JPEG XL preparation is disabled. Enable it before checking or updating its decoder."});continue;}
                    string owner=component=="KCCAutomate"?repo:component=="KCC"?"ciromattia/kcc":"libjxl/libjxl";
                    string installed=component=="KCCAutomate"?ReleaseClient.AppVersion:"Unknown";
                    try{
                        if(component!="KCCAutomate")installed=await Task.Run(delegate{return versionLookup(component=="KCC"?kcc:jxl);});
                        rows.Add(await Task.Run(delegate{return releaseLookup(component,owner,installed);}));
                    }catch(Exception ex){rows.Add(new UpdateRow{Component=component,Repository=owner,Installed=installed,Latest="—",Status="Check failed",Notes="Could not check the latest release. Your selected tool was not changed.\n\n"+ex.Message});}
                }
                // Leave an active download/conversion's UI alone; retry after it finishes.
                if(background&&(asyncBusy||running!=null||activeConversion!=null)){RequestToolUpdateCheck();return;}
                // Do not present results for a converter the user changed during the request.
                if(kcc!=Text("KccExe")||jxl!=Text("DjxlExe")||repo!=Text("UpdateRepository")||jxlEnabled!=Checked("ConvertJxl")){
                    RequestToolUpdateCheck();Find<TextBlock>("UpdateStatus").Text="Your tool choices changed during the check. Checking the current choices next...";return;
                }
                foreach(var row in rows)KeepVerifiedRelease(row,updates.FirstOrDefault(r=>r.Component==row.Component));
                updates.Clear();foreach(var row in rows)updates.Add(row);
                UpdateToolNotice();
                Find<TextBlock>("UpdateStatus").Text="Checked "+DateTime.Now.ToString("g")+". App updates preserve your tools; tool updates are selected separately. Select a component for its results and instructions.";
                var first=updates.FirstOrDefault(NeedsUpdateAttention);if(first!=null)Find<DataGrid>("UpdatesGrid").SelectedItem=first;
            }finally{releaseCheckRunning=false;checkButton.IsEnabled=running==null&&!asyncBusy;}
        }
        static void KeepVerifiedRelease(UpdateRow current,UpdateRow previous){
            if(previous==null||String.IsNullOrWhiteSpace(previous.VerifiedPath)||current.Asset==null||previous.Asset==null||current.Latest!=previous.Latest||current.Asset.Name!=previous.Asset.Name||current.Asset.Url!=previous.Asset.Url||current.Asset.Digest!=previous.Asset.Digest||current.Asset.Size!=previous.Asset.Size||current.Status!="Update available")return;
            current.VerifiedPath=previous.VerifiedPath;current.VerifiedManifestHash=previous.VerifiedManifestHash;current.VerifiedToolFiles=previous.VerifiedToolFiles;current.Status=previous.Status;
        }
        static bool NeedsUpdateAttention(UpdateRow row){
            return row.Status=="Update available"||row.Status=="Check failed"||row.Status=="Installed version unknown"||row.Status=="Version needs review"||row.Status=="No matching Windows asset"||row.Status=="Verified; ready to install"||row.Status=="Verified; tool check passed";
        }
        void UpdateToolNotice(){
            var attention=updates.Where(NeedsUpdateAttention).ToList();
            var kcc=attention.FirstOrDefault(r=>r.Component=="KCC"&&r.Asset!=null&&(r.Status=="Update available"||r.Status=="Installed version unknown"));
            var lines=attention.Select(r=>r.Status=="Update available"?r.Component+" update available: selected "+r.Installed+"; latest "+r.Latest+".":r.Status=="Check failed"?r.Component+": could not check for updates. Your selected tool has not changed.":r.Component+": "+r.Status.ToLowerInvariant()+". Selected "+r.Installed+"; latest "+r.Latest+".").ToList();
            if(kcc!=null)lines.Add("Use Open KCC releases to download the latest Windows x64 c2e file, then Choose downloaded KCC. Continue through validation to Finish & save. Your folders and conversion settings are kept.");
            else if(attention.Count>0)lines.Add("View updates for details, instructions, or to check again. Conversions can continue with your current working tools.");
            Find<TextBlock>("ToolUpdateMessage").Text=String.Join("\n",lines);
            Find<FrameworkElement>("ToolUpdateNotice").Visibility=attention.Count>0?Visibility.Visible:Visibility.Collapsed;
            foreach(string name in new[]{"NoticeKccReleases","NoticeChooseKcc"})Find<FrameworkElement>(name).Visibility=kcc!=null?Visibility.Visible:Visibility.Collapsed;
        }
        void ShowUpdateDetails(){
            Navigate(5);var row=updates.FirstOrDefault(r=>r.Component=="KCC"&&NeedsUpdateAttention(r))??updates.FirstOrDefault(NeedsUpdateAttention);
            if(row!=null)Find<DataGrid>("UpdatesGrid").SelectedItem=row;
        }
        void TestToolUpdateChecks(List<string> results,string directory){
            var previousContext=SynchronizationContext.Current;SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Window.Dispatcher));
            try{
                var task=TestToolUpdateChecksAsync(results,directory);var frame=new DispatcherFrame();bool expired=false;
                var timer=new DispatcherTimer{Interval=TimeSpan.FromSeconds(30)};timer.Tick+=delegate{expired=true;frame.Continue=false;};timer.Start();
                task.ContinueWith(delegate{Window.Dispatcher.BeginInvoke(new Action(delegate{frame.Continue=false;}));});Dispatcher.PushFrame(frame);timer.Stop();
                if(expired)throw new Exception("Automatic update tests timed out.");task.GetAwaiter().GetResult();
            }finally{SynchronizationContext.SetSynchronizationContext(previousContext);}
        }
        async Task TestToolUpdateChecksAsync(List<string> results,string directory){
            var original=Read();var originalSaved=saved;var originalLookup=releaseLookup;var originalVersion=versionLookup;string originalMode=viewMode;int originalPage=Find<TabControl>("Pages").SelectedIndex;
            string settingsBefore=File.ReadAllText(configPath);bool originalAutomatic=automaticToolChecks;
            try{
                automaticToolChecks=true;saved=json.Deserialize<Settings>(json.Serialize(saved));saved.SetupCompleted=true;Find<CheckBox>("ConvertJxl").IsChecked=true;int calls=0;
                versionLookup=delegate{return "21.0.0";};
                releaseLookup=delegate(string component,string repo,string installed){calls++;return new UpdateRow{Component=component,Repository=repo,Installed=installed,Latest=component=="KCC"?"v22.0.0":installed,Status=component=="KCC"?"Update available":"Up to date",Asset=new ReleaseAsset{Name="tool_cli_c2e_22.0.0_AMD64.exe"}};};
                RequestToolUpdateCheck();asyncBusy=true;PollToolUpdates();if(!toolUpdateCheckPending||calls!=0)throw new Exception("Automatic checks interrupted another operation.");asyncBusy=false;
                PollToolUpdates();await toolUpdateTask;
                if(calls!=3||updates.Count!=3||Find<FrameworkElement>("ToolUpdateNotice").Visibility!=Visibility.Visible||!Find<TextBlock>("ToolUpdateMessage").Text.Contains("v22.0.0")||Find<FrameworkElement>("NoticeChooseKcc").Visibility!=Visibility.Visible)throw new Exception("Startup update checks did not show an actionable KCC notice.");
                if(File.ReadAllText(configPath)!=settingsBefore||saved.KccExe!=originalSaved.KccExe)throw new Exception("Checking releases changed settings or the selected tool.");
                ShowUpdateDetails();if((Find<DataGrid>("UpdatesGrid").SelectedItem as UpdateRow).Component!="KCC")throw new Exception("The notice did not select KCC update instructions.");
                var sample=updates.First(r=>r.Component=="KCC");string instructions=ReleaseClient.KccUpdateInstructions(sample);
                if(!instructions.Contains(sample.Asset.Name)||!instructions.Contains("Finish & save")||!instructions.Contains("Choose downloaded KCC"))throw new Exception("KCC replacement instructions are incomplete.");
                results.Add("PASS: startup/post-setup update requests wait for idle, compare selected/latest versions and show KCC download/selection instructions without changing settings or tools");
                releaseLookup=delegate(string component,string repo,string installed){return new UpdateRow{Component=component,Installed=installed,Latest=installed,Status="Up to date"};};
                await CheckToolUpdatesAsync();if(Find<FrameworkElement>("ToolUpdateNotice").Visibility!=Visibility.Collapsed)throw new Exception("An up-to-date tool still showed an update notice.");
                releaseLookup=delegate(string component,string repo,string installed){throw new IOException("Offline fixture");};await CheckToolUpdatesAsync();
                if(updates.Any(r=>r.Status!="Check failed")||Find<FrameworkElement>("ToolUpdateNotice").Visibility!=Visibility.Visible||Find<FrameworkElement>("NoticeChooseKcc").Visibility!=Visibility.Collapsed)throw new Exception("Offline checks claimed tools were current or offered an unverified update.");
                results.Add("PASS: current tools clear update notices; offline checks remain visible without claiming success or blocking conversions");
                Find<CheckBox>("ConvertJxl").IsChecked=false;calls=0;
                releaseLookup=delegate(string component,string repo,string installed){calls++;return new UpdateRow{Component=component,Installed=installed,Latest=installed,Status="Up to date"};};
                await CheckToolUpdatesAsync();if(calls!=2||updates.First(r=>r.Component=="JPEG XL").Status!="Not in use")throw new Exception("Disabled JPEG XL support still requested updates.");
                results.Add("PASS: inactive JPEG XL tools do not trigger update requests or unnecessary notices");
                var previousRows=updates.ToArray();string previousKcc=Text("KccExe");
                versionLookup=delegate{Thread.Sleep(40);return "21.0.0";};
                var stale=CheckToolUpdatesAsync();Find<TextBox>("KccExe").Text=previousKcc+".changed";await stale;
                if(!toolUpdateCheckPending||!updates.SequenceEqual(previousRows))throw new Exception("Stale update results replaced the current selection's state.");
                PollToolUpdates();await toolUpdateTask;if(toolUpdateCheckPending)throw new Exception("Changed tool choices were not checked again.");
                Find<TextBox>("KccExe").Text=previousKcc;
                results.Add("PASS: changing a tool during a release request discards stale results and schedules a check of the current selection");
                previousRows=updates.ToArray();var background=CheckToolUpdatesAsync(true);asyncBusy=true;await background;
                if(!toolUpdateCheckPending||!updates.SequenceEqual(previousRows))throw new Exception("A background check replaced rows during another operation.");
                asyncBusy=false;PollToolUpdates();await toolUpdateTask;
                var asset=new ReleaseAsset{Name="jxl.zip",Url="https://github.com/libjxl/libjxl/releases/download/v2/jxl.zip",Digest="sha256:fixture",Size=10};
                var downloaded=new UpdateRow{Component="JPEG XL",Latest="v2",Asset=asset,VerifiedPath="fixture-path",Status="Verified; tool check passed"};
                var refreshed=new UpdateRow{Component="JPEG XL",Latest="v2",Asset=asset,Status="Update available"};KeepVerifiedRelease(refreshed,downloaded);
                if(refreshed.VerifiedPath!=downloaded.VerifiedPath)throw new Exception("Refreshing release metadata lost a verified staged download.");
                var changed=new UpdateRow{Component="JPEG XL",Latest="v3",Asset=asset,Status="Update available"};KeepVerifiedRelease(changed,downloaded);
                if(changed.VerifiedPath!=null)throw new Exception("Verification was carried over to a different release.");
                results.Add("PASS: background results wait for active work and matching release refreshes preserve verified downloads without trusting a different release");
                UpdateToolNotice();Find<CheckBox>("ConvertJxl").IsChecked=original.ConvertJxl;
                foreach(string mode in new[]{"Simple","Advanced"}){
                    updates.Clear();updates.Add(sample);UpdateToolNotice();SetViewMode(mode,false);ApplyTheme("Dark");
                    RenderInterface(Path.Combine(directory,"updates-"+mode.ToLowerInvariant()+".png"),1040,720);
                    if(Find<FrameworkElement>("NoticeChooseKcc").ActualWidth<=0)throw new Exception("The KCC update action was hidden in a view mode.");
                }
                results.Add("PASS: the tool-update notice and actions render in Simple/Advanced views at the minimum window size");
            }finally{
                automaticToolChecks=originalAutomatic;toolUpdateCheckPending=false;releaseLookup=originalLookup;versionLookup=originalVersion;asyncBusy=false;updates.Clear();UpdateToolNotice();Fill(original);saved=originalSaved;SetViewMode(originalMode,false);ApplyTheme(original.Theme);Navigate(originalPage);
            }
        }
    }
}
