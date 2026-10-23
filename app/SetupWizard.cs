using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Principal;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;
using Forms=System.Windows.Forms;

namespace KCCAutomate {
    public class SetupWizard {
        public Window Window {get;private set;}
        public Settings Result {get;private set;}
        public bool EnableSchedule {get;private set;}
        readonly Settings draft;
        readonly string appDirectory;
        readonly string toolsRoot;
        readonly DispatcherTimer autoTimer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(600)};
        readonly HashSet<string> pendingTools=new HashSet<string>();
        readonly Dictionary<string,int> toolRevisions=new Dictionary<string,int>();
        readonly Dictionary<string,ToolCheck> toolChecks=new Dictionary<string,ToolCheck>();
        Task activeAutoCheck=Task.FromResult(0);
        bool autoEnabled,closed,suppressToolEvents,sevenSearchComplete;
        bool busy,foldersPassed,toolsPassed,testPassed;
        int step;
        string testOutput;
        public SetupWizard(Window owner,Settings settings,IEnumerable<Device> devices,string storage,string bookRoot=null) {
            draft=new JavaScriptSerializer().Deserialize<Settings>(new JavaScriptSerializer().Serialize(settings));
            SetupChecks.DefaultFolders(draft,bookRoot??Path.Combine(storage,"Books"));
            appDirectory=AppDomain.CurrentDomain.BaseDirectory;
            toolsRoot=Path.Combine(storage,"Tools");
            using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("KCCAutomate.SetupWizard.xaml"))Window=(Window)XamlReader.Load(stream);
            if(owner.IsVisible)Window.Owner=owner;Window.Resources.MergedDictionaries.Add(owner.Resources);
            Get<ComboBox>("Device").ItemsSource=devices;Get<ComboBox>("Device").SelectedValue=draft.Profile;
            Select("Format",draft.Format);Get<CheckBox>("Manga").IsChecked=draft.MangaStyle;
            Set("Watch",draft.WatchFolder);Set("Output",draft.ConvertedFolder);Set("Archive",draft.ArchiveFolder);Set("Work",draft.WorkFolder);
            Set("Kcc",draft.KccExe);Set("Jxl",draft.DjxlExe);Set("Kindle",draft.KindlegenExe);Set("SevenZip",draft.SevenZipExe);
            Get<CheckBox>("JxlEnabled").IsChecked=draft.ConvertJxl;
            Set("Times",draft.ScheduleTimes);Set("QuietMinutes",draft.QuietMinutes.ToString());Get<CheckBox>("Wake").IsChecked=draft.WakeComputer;
            Get<TextBlock>("StorageInfo").Text="Settings location: "+storage;
            Get<TextBlock>("ManagedToolsInfo").Text="Tools will be kept in: "+toolsRoot;
            Get<TextBlock>("ScheduleInfo").Text="Checks run as "+WindowsIdentity.GetCurrent().Name+" while signed in, including when the screen is locked. The app may be closed. The PC and network share must be available.";
            foreach(var pair in new[]{new[]{"WatchBrowse","Watch"},new[]{"OutputBrowse","Output"},new[]{"ArchiveBrowse","Archive"},new[]{"WorkBrowse","Work"}}){string field=pair[1];Click(pair[0],delegate{BrowseFolder(field);});}
            foreach(var pair in new[]{new[]{"KccBrowse","Kcc"},new[]{"KindleBrowse","Kindle"},new[]{"SevenZipBrowse","SevenZip"}}){string field=pair[1];Click(pair[0],delegate{BrowseFile(field,"Windows programs (*.exe)|*.exe");});}
            Click("JxlBrowse",delegate{BrowseFile("Jxl","JPEG XL decoder or Windows package|*.exe;*.zip;*.7z");});
            Click("TestBrowse",delegate{BrowseFile("TestBook","Comic files|*.cbz;*.pdf;*.epub;*.cbr;*.cb7");});
            Click("GetKcc",delegate{Open(ReleaseClient.ApprovedKccDownload);});Click("GetJxl",delegate{Open("https://github.com/libjxl/libjxl/releases");});Click("GetKindle",delegate{Open("https://github.com/ciromattia/kcc/wiki/Installation#kindlegen");});
            Click("GetKccFallback",delegate{Open(ReleaseClient.ApprovedKccPage);});Click("GetDependencies",delegate{Open("https://github.com/ciromattia/kcc/wiki/Installation");});Click("GetSevenZip",delegate{Open("https://www.7-zip.org/");});
            Click("OpenTest",delegate{if(testOutput!=null)Open(testOutput);});
            Async("FindTools",Discover);Async("CheckFolders",CheckFolders);Async("CheckTools",CheckTools);Async("RunTest",RunTest);Async("Next",Next);
            Click("Back",delegate{if(step>0){step--;ShowStep();}});
            Click("CancelSetup",delegate{Window.DialogResult=false;});
            foreach(var name in new[]{"Watch","Output","Archive","Work"})Get<TextBox>(name).TextChanged+=delegate{foldersPassed=false;testPassed=false;};
            foreach(var name in new[]{"Kcc","Jxl","Kindle","SevenZip"}){string key=name;Get<TextBox>(name).TextChanged+=delegate{if(!suppressToolEvents)ToolChanged(key);};}
            Get<CheckBox>("JxlEnabled").Checked+=delegate{ToolChanged("Jxl");ToolChanged("SevenZip");};Get<CheckBox>("JxlEnabled").Unchecked+=delegate{ToolChanged("Jxl");ToolChanged("SevenZip");};
            Get<TextBox>("TestBook").TextChanged+=delegate{testPassed=false;};
            Get<ComboBox>("Device").SelectionChanged+=delegate{testPassed=false;};Get<ComboBox>("Format").SelectionChanged+=delegate{ToolChanged("Kindle");};Get<CheckBox>("Manga").Checked+=delegate{testPassed=false;};Get<CheckBox>("Manga").Unchecked+=delegate{testPassed=false;};
            Window.Closing+=delegate(object sender,System.ComponentModel.CancelEventArgs e){if(busy){e.Cancel=true;Feedback("Please let the current check or test finish before closing.");}};
            autoTimer.Tick+=async delegate {autoTimer.Stop();if(!closed&&!busy&&activeAutoCheck.IsCompleted){try{activeAutoCheck=AutoCheckPending();await activeAutoCheck;}catch(Exception ex){if(!closed)Feedback(ex.Message);}}};
            Window.Loaded+=delegate{StartAutomaticChecks();};
            Window.Closed+=delegate{closed=true;autoTimer.Stop();};
            InvalidateTools();ShowStep();
        }
        T Get<T>(string name)where T:class{var result=Window.FindName(name)as T;if(result==null)throw new Exception("Setup control missing: "+name);return result;}
        string Text(string name){return Get<TextBox>(name).Text.Trim().Trim('"');}
        void Set(string name,string text){Get<TextBox>(name).Text=text??"";}
        static string Value(ComboBoxItem item){return item==null?"":Convert.ToString(item.Tag??item.Content);}
        void Select(string name,string text){Get<ComboBox>(name).SelectedItem=Get<ComboBox>(name).Items.Cast<ComboBoxItem>().FirstOrDefault(i=>Value(i)==text);}
        void InvalidateTools(){foreach(var name in new[]{"Kcc","Jxl","Kindle","SevenZip"})InvalidateTool(name);}
        void InvalidateTool(string name){
            toolsPassed=false;testPassed=false;toolChecks.Remove(name);toolRevisions[name]=toolRevisions.ContainsKey(name)?toolRevisions[name]+1:1;
            bool optional=(name=="Jxl"&&Get<CheckBox>("JxlEnabled").IsChecked!=true)||(name=="Kindle"&&Value((ComboBoxItem)Get<ComboBox>("Format").SelectedItem)!="MOBI")||(name=="SevenZip"&&!(Get<CheckBox>("JxlEnabled").IsChecked==true&&Text("Jxl").EndsWith(".7z",StringComparison.OrdinalIgnoreCase)));
            var text=Get<TextBlock>(name+"Status");text.Text=(optional?"○ ":"✗ ")+new Dictionary<string,string>{{"Kcc","KCC c2e"},{"Jxl","JPEG XL decoder"},{"Kindle","KindleGen"},{"SevenZip","7-Zip"}}[name]+(autoEnabled?" · checking automatically...":optional?" · optional / not checked":" · missing or not checked");text.Foreground=optional?Brushes.Gray:Brushes.Firebrick;
        }
        void ToolChanged(string key){
            InvalidateTool(key);pendingTools.Add(key);
            if(key=="SevenZip"){sevenSearchComplete=false;if(Text("Jxl").EndsWith(".7z",StringComparison.OrdinalIgnoreCase)){InvalidateTool("Jxl");pendingTools.Add("Jxl");}}
            if(key=="Jxl"&&String.IsNullOrWhiteSpace(Text("SevenZip"))){sevenSearchComplete=false;InvalidateTool("SevenZip");pendingTools.Add("SevenZip");}
            if(autoEnabled&&!busy){autoTimer.Stop();autoTimer.Start();}
        }
        void StartAutomaticChecks(){if(autoEnabled||closed)return;autoEnabled=true;foreach(var key in new[]{"SevenZip","Kcc","Jxl","Kindle"}){InvalidateTool(key);pendingTools.Add(key);}autoTimer.Start();}
        void SetToolSilently(string key,string path){suppressToolEvents=true;try{Set(key,path);}finally{suppressToolEvents=false;}}
        Settings Snapshot(){var copy=new JavaScriptSerializer().Deserialize<Settings>(new JavaScriptSerializer().Serialize(draft));copy.KccExe=Text("Kcc");copy.DjxlExe=Text("Jxl");copy.KindlegenExe=Text("Kindle");copy.SevenZipExe=Text("SevenZip");copy.ConvertJxl=Get<CheckBox>("JxlEnabled").IsChecked==true;copy.Format=Value((ComboBoxItem)Get<ComboBox>("Format").SelectedItem);return copy;}
        async Task AutoCheckPending(){
            if(!autoEnabled||closed||busy)return;
            var keys=new[]{"SevenZip","Jxl","Kindle","Kcc"}.Where(k=>pendingTools.Contains(k)).ToArray();
            foreach(string key in keys){
                if(closed||busy)break;pendingTools.Remove(key);int revision=toolRevisions[key];var snapshot=Snapshot();string resolved=null;bool searchedSeven=false;
                ToolCheck check;
                try{
                    if(key=="SevenZip"&&String.IsNullOrWhiteSpace(snapshot.SevenZipExe)&&!sevenSearchComplete){
                        Get<TextBlock>("SevenZipLocation").Text="Checking standard Windows locations and command-line archive support...";
                        resolved=await Task.Run(delegate{return SetupChecks.FindUsableSevenZip(null);});snapshot.SevenZipExe=resolved;searchedSeven=true;
                    }
                    else {string selected=key=="Kcc"?snapshot.KccExe:key=="Jxl"?snapshot.DjxlExe:key=="Kindle"?snapshot.KindlegenExe:snapshot.SevenZipExe;resolved=await Task.Run(delegate{return SetupChecks.ResolveToolPath(key,selected);});if(key=="Kcc")snapshot.KccExe=resolved;else if(key=="Jxl")snapshot.DjxlExe=resolved;else if(key=="Kindle")snapshot.KindlegenExe=resolved;else snapshot.SevenZipExe=resolved;}
                    if(key=="Jxl"&&snapshot.ConvertJxl){resolved=await Task.Run(delegate{return ManagedTools.PrepareJxl(snapshot.DjxlExe,snapshot.SevenZipExe,toolsRoot);});snapshot.DjxlExe=resolved;}
                    check=await Task.Run(delegate{return ToolValidation.Check(snapshot,key);});
                }catch(Exception ex){check=new ToolCheck{Key=key,Required=true,Message=ex.Message};}
                if(closed)return;
                if(revision!=toolRevisions[key])continue;
                if(resolved!=null)SetToolSilently(key,resolved);if(searchedSeven)sevenSearchComplete=true;
                ShowChecks(new[]{check});
                if(key=="SevenZip"){
                    Get<TextBlock>("SevenZipLocation").Text=check.Passed?"Detected and tested: "+Text("SevenZip"):"No usable 7-Zip CLI was found. Install 7-Zip or choose its 7z.exe below.";
                    Get<Expander>("SevenZipDetails").IsExpanded=!check.Passed;
                }
            }
            if(pendingTools.Count>0&&!closed&&!busy)autoTimer.Start();
        }
        void ShowChecks(IEnumerable<ToolCheck> checks){foreach(var check in checks){toolChecks[check.Key]=check;pendingTools.Remove(check.Key);var text=Get<TextBlock>(check.Key+"Status");text.Text=(check.Passed?"✓ ":check.Optional?"○ ":"✗ ")+check.Message;text.Foreground=check.Passed?Brushes.ForestGreen:check.Optional?Brushes.Gray:Brushes.Firebrick;}toolsPassed=toolChecks.Count==4&&ToolValidation.Passed(toolChecks.Values);}
        void Feedback(string text){Get<TextBlock>("Feedback").Text=text;}
        void Click(string name,Action action){Get<Button>(name).Click+=delegate{if(busy)return;try{action();}catch(Exception ex){Feedback(ex.Message);}};}
        void Async(string name,Func<Task> action){Get<Button>(name).Click+=async delegate{if(busy)return;busy=true;autoTimer.Stop();Buttons(false);try{await activeAutoCheck;await action();}catch(Exception ex){Feedback(ex.Message);}finally{busy=false;Buttons(true);ShowStep(false);if(autoEnabled&&pendingTools.Count>0)autoTimer.Start();}};}
        void Buttons(bool enabled){Get<TabControl>("Steps").IsEnabled=enabled;foreach(var name in new[]{"Next","Back","CancelSetup","FindTools","CheckFolders","CheckTools","RunTest","WatchBrowse","OutputBrowse","ArchiveBrowse","WorkBrowse","KccBrowse","JxlBrowse","KindleBrowse","SevenZipBrowse","TestBrowse","OpenTest"})Get<Button>(name).IsEnabled=enabled;Get<Button>("OpenTest").IsEnabled=enabled&&testOutput!=null;}
        void ShowStep(bool resetFeedback=true){
            Get<TabControl>("Steps").SelectedIndex=step;Get<TextBlock>("StepTitle").Text="Step "+(step+1)+" of 6 · "+new[]{"Your reader","Folders","Tools","Try a book","Schedule","Review"}[step];
            Get<Button>("Back").IsEnabled=!busy&&step>0;Get<Button>("Next").Content=step==5?"Finish & save":"Continue";
            if(resetFeedback)Feedback(step==3?"Choose a small completed comic, or continue to test later.":"Your normal queue is not converted during setup.");
            if(step==5)Get<TextBlock>("Summary").Text="Device: "+draft.Profile+" · "+draft.Format+"\n\nIncoming: "+draft.WatchFolder+"\nConverted: "+draft.ConvertedFolder+"\nArchive: "+draft.ArchiveFolder+"\nWorking: "+draft.WorkFolder+"\n\nFolder access: "+(foldersPassed?"verified":"needs checking")+"\nTools: "+(toolsPassed?"startup checks passed":"needs checking")+"\nTest conversion: "+(testPassed?"passed":"not verified yet")+"\n\nAutomatic checks: "+(Get<CheckBox>("EnableSchedule").IsChecked==true?draft.ScheduleTimes:"off; existing schedules are left unchanged");
        }
        void Capture(){
            draft.Profile=Get<ComboBox>("Device").SelectedValue as string;
            var format=Get<ComboBox>("Format").SelectedItem as ComboBoxItem;if(format==null)throw new Exception("Choose an output format.");draft.Format=Value(format);
            draft.MangaStyle=Get<CheckBox>("Manga").IsChecked==true;
            draft.WatchFolder=Text("Watch");draft.ConvertedFolder=Text("Output");draft.ArchiveFolder=Text("Archive");draft.WorkFolder=Text("Work");
            if(String.IsNullOrEmpty(draft.WorkFolder)&&!String.IsNullOrEmpty(draft.WatchFolder)){var parent=Path.GetDirectoryName(draft.WatchFolder.TrimEnd('\\'));if(parent!=null){draft.WorkFolder=Path.Combine(parent,"manga_automation_work");Set("Work",draft.WorkFolder);}}
            draft.KccExe=Text("Kcc");draft.DjxlExe=Text("Jxl");draft.KindlegenExe=Text("Kindle");draft.SevenZipExe=Text("SevenZip");draft.ConvertJxl=Get<CheckBox>("JxlEnabled").IsChecked==true;
        }
        async Task Next(){
            Capture();
            if(step==0)Desktop.ValidateConversion(draft);
            if(step==1&&!foldersPassed)await CheckFolders();
            if(step==2&&!toolsPassed)await CheckTools();
            if(step==2){
                Feedback("Copying and verifying tools in KCCAutomate's tools folder...");
                var copied=await Task.Run(delegate{return ManagedTools.Import(draft,toolsRoot);});
                Set("Kcc",copied.KccExe);Set("Jxl",copied.DjxlExe);Set("Kindle",copied.KindlegenExe);Set("SevenZip",copied.SevenZipExe);Capture();
                var checks=await Task.Run(delegate{return ToolValidation.Check(draft);});ShowChecks(checks);toolsPassed=ToolValidation.Passed(checks);
                if(!toolsPassed)throw new Exception("The copied tools need checking.\n"+ToolValidation.Report(checks));
            }
            if(step==4){draft.ScheduleTimes=Desktop.NormalizeTimes(Text("Times"));int quiet;if(!Int32.TryParse(Text("QuietMinutes"),out quiet)||quiet<0||quiet>1440)throw new Exception("Choose a wait time between 0 and 1440 minutes.");draft.QuietMinutes=quiet;draft.WakeComputer=Get<CheckBox>("Wake").IsChecked==true;}
            if(step==5){draft.SetupCompleted=true;Result=draft;EnableSchedule=Get<CheckBox>("EnableSchedule").IsChecked==true;busy=false;Window.DialogResult=true;return;}
            step++;ShowStep();if(step==1)await CheckFolders();
        }
        async Task CheckFolders(){Capture();Feedback("Checking folder access. Network folders may take a moment...");string report=await Task.Run(delegate{return SetupChecks.ProbeFolders(draft);});foldersPassed=true;Feedback(report);}
        async Task CheckTools(){
            Capture();InvalidateTools();Feedback("Checking selected tools and importing any JXL package...");
            var selection=Snapshot();
            selection=await Task.Run(delegate{
                selection.KccExe=SetupChecks.ResolveToolPath("Kcc",selection.KccExe);selection.DjxlExe=SetupChecks.ResolveToolPath("Jxl",selection.DjxlExe);selection.KindlegenExe=SetupChecks.ResolveToolPath("Kindle",selection.KindlegenExe);selection.SevenZipExe=SetupChecks.ResolveToolPath("SevenZip",selection.SevenZipExe);
                if(String.IsNullOrWhiteSpace(selection.SevenZipExe))selection.SevenZipExe=SetupChecks.FindUsableSevenZip(null);return selection;
            });
            SetToolSilently("Kcc",selection.KccExe);SetToolSilently("Jxl",selection.DjxlExe);SetToolSilently("Kindle",selection.KindlegenExe);SetToolSilently("SevenZip",selection.SevenZipExe);Capture();
            string packageError=null;
            if(draft.ConvertJxl){try{string decoder=await Task.Run(delegate{return ManagedTools.PrepareJxl(draft.DjxlExe,draft.SevenZipExe,toolsRoot);});Set("Jxl",decoder);Capture();}catch(Exception ex){packageError=ex.Message;}}
            var checks=await Task.Run(delegate{return ToolValidation.Check(draft);});
            if(packageError!=null){var jxl=checks.Single(c=>c.Key=="Jxl");jxl.Passed=false;jxl.Message=packageError;}
            ShowChecks(checks);toolsPassed=ToolValidation.Passed(checks);
            var seven=checks.Single(c=>c.Key=="SevenZip");Get<TextBlock>("SevenZipLocation").Text=seven.Passed?"Ready: "+Text("SevenZip"):"7-Zip was not detected. Install it or choose its executable if needed.";Get<Expander>("SevenZipDetails").IsExpanded=!seven.Passed;
            Feedback(toolsPassed?"Selected tools passed startup checks. Continue will copy and recheck them in KCCAutomate's tools folder.":"Resolve the red items above, then Check tools again.");
            if(!toolsPassed)throw new Exception("Resolve the red items above, then Check tools again.");
        }
        async Task Discover(){
            Capture();Feedback("Looking in common app locations. Nothing will be downloaded or installed...");
            string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var roots=new[]{(String.IsNullOrWhiteSpace(draft.KccExe)?null:Path.GetDirectoryName(draft.KccExe)),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"7-Zip"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"7-Zip"),toolsRoot,appDirectory,@"C:\kindletomanga",Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"KindleComicConverter"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Amazon"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Amazon"),Path.Combine(local,"Amazon"),Path.Combine(local,"Programs","Kindle Previewer 3"),Path.Combine(local,"Programs","Kindle Previewer 4"),Path.Combine(local,"KCCAutomate","Updates")};
            var found=await Task.Run(delegate{return SetupChecks.Discover(roots);});
            if(!File.Exists(Text("Kcc"))&&found.Kcc!=null)Set("Kcc",found.Kcc);if(!File.Exists(Text("Jxl"))&&found.Jxl!=null)Set("Jxl",found.Jxl);if(!File.Exists(Text("Kindle"))&&found.Kindlegen!=null)Set("Kindle",found.Kindlegen);
            if(!File.Exists(Text("SevenZip"))&&found.SevenZip!=null)Set("SevenZip",found.SevenZip);
            Feedback("Search finished. Review the paths, then Check tools. If a tool was not found, select it manually or use its download link.");
        }
        async Task RunTest(){Capture();Desktop.Validate(draft);string book=Text("TestBook");Feedback("Testing a copy of the selected book. The original stays in place...");Get<TextBox>("TestLog").Text="Preparing a verified test copy...";var result=await Task.Run(delegate{return SetupChecks.ConvertTest(draft,book,appDirectory);});testOutput=result.Output;testPassed=result.Passed;Get<TextBox>("TestLog").Text=result.Log;Feedback(result.Passed?"Test conversion passed. Open the results and inspect the book on your reader.":"Test conversion failed. Review the log above and the test working folder; the selected original was retained.");}
        void BrowseFolder(string field){using(var d=new Forms.FolderBrowserDialog{Description="Choose "+field+" folder",ShowNewFolderButton=true}){if(d.ShowDialog()==Forms.DialogResult.OK)Set(field,d.SelectedPath);}}
        void BrowseFile(string field,string filter){var d=new Microsoft.Win32.OpenFileDialog{Filter=filter};if(d.ShowDialog(Window)==true)Set(field,d.FileName);}
        static void Open(string path){Process.Start(new ProcessStartInfo(path){UseShellExecute=true});}
        public void RenderStep(int index){step=index;ShowStep();}
        public async Task TestAutomaticTools(string fixtures,List<string> results){
            if(Directory.Exists(draft.WatchFolder))throw new Exception("Default book folders were created before setup reached its folder step.");
            await Next();
            if(!new[]{draft.WatchFolder,draft.ConvertedFolder,draft.ArchiveFolder,draft.WorkFolder}.All(Directory.Exists)||!foldersPassed)throw new Exception("Setup did not create and check its default folders automatically.");
            results.Add("PASS: setup supplies separate default folders and creates all four, including incoming, on reaching the folder page");
            StartAutomaticChecks();Set("Kcc",fixtures);Set("Jxl",Path.Combine(fixtures,"djxl.exe"));Set("Kindle",Path.Combine(fixtures,"Kindle Previewer 4"));autoTimer.Stop();
            activeAutoCheck=AutoCheckPending();await activeAutoCheck;
            if(!toolsPassed||!Get<TextBlock>("KindleStatus").Text.StartsWith("✓")||!Get<TextBlock>("SevenZipStatus").Text.StartsWith("✓")||Get<Expander>("SevenZipDetails").IsExpanded)throw new Exception("Automatic folder resolution, KindleGen validation or installed 7-Zip detection failed.");
            string readyKindle=Get<TextBlock>("KindleStatus").Text;Set("Kcc",Path.Combine(fixtures,"missing.exe"));autoTimer.Stop();
            if(Get<TextBlock>("KindleStatus").Text!=readyKindle)throw new Exception("Editing one tool cleared another tool's completed check.");
            Set("Kcc",Path.Combine(fixtures,"kcc-c2e.exe"));autoTimer.Stop();activeAutoCheck=AutoCheckPending();await Task.Delay(75);Set("Kcc",Path.Combine(fixtures,"missing.exe"));autoTimer.Stop();await activeAutoCheck;
            if(Get<TextBlock>("KccStatus").Text.StartsWith("✓"))throw new Exception("A stale automatic result validated a changed path.");
            activeAutoCheck=AutoCheckPending();await activeAutoCheck;
            if(toolsPassed||!Get<TextBlock>("KccStatus").Text.StartsWith("✗"))throw new Exception("A missing changed tool was not marked red.");
            autoEnabled=false;autoTimer.Stop();foreach(string key in new[]{"Kcc","Jxl","Kindle","SevenZip"})SetToolSilently(key,"");pendingTools.Clear();InvalidateTools();
            results.Add("PASS: tool paths/folders check automatically, installed 7-Zip CLI is tested before prompting, unrelated green checks survive edits and stale results cannot validate a changed path");
        }
        public void TestToolControls(List<string> results){
            if(Text("Kcc")!=""||Text("Jxl")!="")throw new Exception("Fresh setup pre-populated an unselected tool.");
            var mobi=Get<ComboBox>("Format").SelectedItem as ComboBoxItem;
            if(mobi==null||Convert.ToString(mobi.Content)!="MOBI (AZW3/kindle compatible)")throw new Exception("MOBI setup explanation missing.");
            Capture();if(draft.Format!="MOBI")throw new Exception("MOBI display text leaked into converter settings.");
            ShowChecks(new[]{new ToolCheck{Key="Kcc",Passed=true,Message="KCC validated"},new ToolCheck{Key="Jxl",Message="Decoder missing"}});
            if(!Get<TextBlock>("KccStatus").Text.StartsWith("✓")||Get<TextBlock>("KccStatus").Foreground!=Brushes.ForestGreen||!Get<TextBlock>("JxlStatus").Text.StartsWith("✗"))throw new Exception("Tool checklist did not reflect independent pass/failure states.");
            Set("Kcc",@"C:\changed\kcc-c2e.exe");if(Get<TextBlock>("KccStatus").Text.StartsWith("✓")||toolsPassed)throw new Exception("Editing a tool retained a stale green check.");
            Set("Kcc","");Set("Jxl",@"C:\downloads\jxl.7z");if(!Get<TextBlock>("SevenZipStatus").Text.StartsWith("✗"))throw new Exception("7-Zip import dependency was not marked required.");Set("Jxl","");
            Select("Format","EPUB");Capture();if(draft.Format!="EPUB")throw new Exception("EPUB format mapping failed.");Select("Format","MOBI");Capture();
            results.Add("PASS: setup explains MOBI while storing MOBI, leaves unselected tools empty, displays independent red/green checks and invalidates stale checks after edits");
        }
    }
}
