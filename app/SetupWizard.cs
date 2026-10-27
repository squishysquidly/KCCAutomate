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
        public bool OpenFolderSettings {get;private set;}
        public const int PageCount=9;
        readonly Settings draft;
        readonly string appDirectory;
        readonly string toolsRoot;
        readonly string[] kindleRoots;
        readonly DispatcherTimer autoTimer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(600)};
        readonly HashSet<string> pendingTools=new HashSet<string>();
        readonly Dictionary<string,int> toolRevisions=new Dictionary<string,int>();
        readonly Dictionary<string,ToolCheck> toolChecks=new Dictionary<string,ToolCheck>();
        Task activeAutoCheck=Task.FromResult(0);
        bool autoEnabled,closed,suppressToolEvents,sevenSearchComplete;
        bool busy,foldersPassed,toolsPassed,testPassed;
        int step;
        string testOutput;
        public SetupWizard(Window owner,Settings settings,IEnumerable<Device> devices,string storage,string bookRoot=null,IEnumerable<string> kindleLocations=null) {
            draft=new JavaScriptSerializer().Deserialize<Settings>(new JavaScriptSerializer().Serialize(settings));
            SetupChecks.DefaultFolders(draft,bookRoot??Path.Combine(storage,"Books"));
            appDirectory=AppDomain.CurrentDomain.BaseDirectory;
            toolsRoot=Path.Combine(storage,"Tools");
            kindleRoots=(kindleLocations??KindleGenGuide.InstallationRoots()).ToArray();
            using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("KCCAutomate.SetupWizard.xaml"))Window=(Window)XamlReader.Load(stream);
            Window.Icon=AppBranding.Icon;
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
            foreach(var pair in new[]{new[]{"KccBrowse","Kcc"},new[]{"KindleBrowse","Kindle"},new[]{"SevenZipBrowse","SevenZip"}}){string field=pair[1];Click(pair[0],delegate{BrowseFile(field,"Windows programs (*.exe)|*.exe");});}
            Click("JxlBrowse",delegate{BrowseFile("Jxl","JPEG XL decoder or Windows package|*.exe;*.zip;*.7z");});
            Click("TestBrowse",delegate{BrowseFile("TestBook","Comic files|*.cbz;*.pdf;*.epub;*.cbr;*.cb7");});
            Click("GetKcc",delegate{Open(ReleaseClient.KccReleasesPage);});Click("GetJxl",delegate{Open("https://github.com/libjxl/libjxl/releases");});Click("GetKindle",delegate{Open(KindleGenGuide.GuideUrl);});
            Click("GetPreviewer",delegate{Open(KindleGenGuide.PreviewerUrl);});Async("RecheckKindle",RecheckKindle);
            Click("GetKccFallback",delegate{Open(ReleaseClient.ApprovedKccPage);});Click("GetDependencies",delegate{Open("https://github.com/ciromattia/kcc/wiki/Installation");});Click("GetSevenZip",delegate{Open("https://www.7-zip.org/");});
            Click("ShowKindleGuide",delegate{KindleGenGuide.Create(Window,delegate{return Text("Kindle");}).ShowDialog();});
            Click("OpenKindleFolder",delegate{Feedback(KindleGenGuide.OpenFolder(Text("Kindle")));});
            Click("OpenTest",delegate{if(testOutput!=null)Open(testOutput);});
            Async("FindTools",Discover);Async("CheckFolders",CheckFolders);Async("CheckTools",delegate{return CheckPageTool(CurrentTool());});Async("RunTest",RunTest);Async("Next",Next);
            Click("Back",Back);
            Click("BackToSevenZip",delegate{step=1;ShowStep();});
            Click("ChangeJxlChoice",delegate{step=0;ShowStep();});
            Click("CancelSetup",delegate{Window.DialogResult=false;});
            // Tab headers are hidden; navigation must still pass through Next/Back checks.
            Get<TabControl>("Steps").SelectionChanged+=delegate(object sender,SelectionChangedEventArgs e){var tabs=Get<TabControl>("Steps");if(e.Source==tabs&&tabs.SelectedIndex!=step)tabs.SelectedIndex=step;};
            foreach(var name in new[]{"Watch","Output","Archive","Work"})Get<TextBox>(name).TextChanged+=delegate{foldersPassed=false;testPassed=false;};
            foreach(var name in new[]{"Kcc","Jxl","Kindle","SevenZip"}){string key=name;Get<TextBox>(name).TextChanged+=delegate{if(!suppressToolEvents)ToolChanged(key);};}
            Get<CheckBox>("JxlEnabled").Checked+=delegate{ToolChanged("Jxl");ToolChanged("SevenZip");ShowStep();};Get<CheckBox>("JxlEnabled").Unchecked+=delegate{ToolChanged("Jxl");ToolChanged("SevenZip");ShowStep();};
            Get<TextBox>("TestBook").TextChanged+=delegate{testPassed=false;};
            Get<ComboBox>("Device").SelectionChanged+=delegate{testPassed=false;};Get<ComboBox>("Format").SelectionChanged+=delegate{ToolChanged("Kindle");ShowStep();};Get<CheckBox>("Manga").Checked+=delegate{testPassed=false;};Get<CheckBox>("Manga").Unchecked+=delegate{testPassed=false;};
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
        Brush StatusBrush(bool passed,bool optional){var canvas=Window.TryFindResource("CanvasBrush") as SolidColorBrush;bool dark=canvas!=null&&canvas.Color.R<100;return passed?(dark?Brushes.LightGreen:Brushes.ForestGreen):optional?(dark?Brushes.LightGray:Brushes.Gray):(dark?Brushes.LightSalmon:Brushes.Firebrick);}
        void InvalidateTools(){foreach(var name in new[]{"Kcc","Jxl","Kindle","SevenZip"})InvalidateTool(name);}
        void InvalidateTool(string name){
            toolsPassed=false;testPassed=false;toolChecks.Remove(name);toolRevisions[name]=toolRevisions.ContainsKey(name)?toolRevisions[name]+1:1;
            bool optional=(name=="Jxl"&&Get<CheckBox>("JxlEnabled").IsChecked!=true)||(name=="Kindle"&&!ToolValidation.RequiresKindlegen(Snapshot()))||(name=="SevenZip"&&!(Get<CheckBox>("JxlEnabled").IsChecked==true&&Text("Jxl").EndsWith(".7z",StringComparison.OrdinalIgnoreCase)));
            var text=Get<TextBlock>(name+"Status");text.Text=(optional?"○ ":"✗ ")+new Dictionary<string,string>{{"Kcc","KCC c2e"},{"Jxl","JPEG XL decoder"},{"Kindle","KindleGen"},{"SevenZip","7-Zip"}}[name]+(autoEnabled?" · checking automatically...":optional?" · optional / not checked":" · missing or not checked");text.Foreground=StatusBrush(false,optional);
            if(name=="Kindle"){Get<TextBlock>("KindleDiscovery").Text="We check your selection and the usual Kindle Previewer folders automatically on this page.";Get<FrameworkElement>("KindleInstall").Visibility=optional?Visibility.Collapsed:Visibility.Visible;}
        }
        void ToolChanged(string key){
            InvalidateTool(key);pendingTools.Add(key);
            if(key=="SevenZip"){sevenSearchComplete=false;if(Text("Jxl").EndsWith(".7z",StringComparison.OrdinalIgnoreCase)){InvalidateTool("Jxl");pendingTools.Add("Jxl");}}
            if(key=="Jxl"&&String.IsNullOrWhiteSpace(Text("SevenZip"))){sevenSearchComplete=false;InvalidateTool("SevenZip");pendingTools.Add("SevenZip");}
            if(autoEnabled&&!busy&&pendingTools.Any(ActiveTool)){autoTimer.Stop();autoTimer.Start();}
        }
        string CurrentTool(){return step==1?"SevenZip":step==2?"Kcc":step==3?"Kindle":step==4?"Jxl":null;}
        int[] VisiblePages(){bool kindle=ToolValidation.RequiresKindlegen(Snapshot()),jxl=Get<CheckBox>("JxlEnabled").IsChecked==true;return Enumerable.Range(0,PageCount).Where(p=>(p!=3||kindle)&&(p!=4||jxl)).ToArray();}
        void Back(){if(step>0){step=VisiblePages().Last(p=>p<step);ShowStep();}}
        bool ActiveTool(string key){return key==CurrentTool()||(step==4&&key=="SevenZip"&&Text("Jxl").EndsWith(".7z",StringComparison.OrdinalIgnoreCase)&&String.IsNullOrWhiteSpace(Text("SevenZip")));}
        void QueueCurrentTool(){string key=CurrentTool();if(key==null||toolChecks.ContainsKey(key))return;pendingTools.Add(key);if(autoEnabled&&!busy){autoTimer.Stop();autoTimer.Start();}}
        void StartAutomaticChecks(){if(autoEnabled||closed)return;autoEnabled=true;QueueCurrentTool();}
        void SetToolSilently(string key,string path){suppressToolEvents=true;try{Set(key,path);}finally{suppressToolEvents=false;}}
        Settings Snapshot(){var copy=new JavaScriptSerializer().Deserialize<Settings>(new JavaScriptSerializer().Serialize(draft));copy.KccExe=Text("Kcc");copy.DjxlExe=Text("Jxl");copy.KindlegenExe=Text("Kindle");copy.SevenZipExe=Text("SevenZip");copy.ConvertJxl=Get<CheckBox>("JxlEnabled").IsChecked==true;copy.Format=Value((ComboBoxItem)Get<ComboBox>("Format").SelectedItem);return copy;}
        async Task AutoCheckPending(){
            if(!autoEnabled||closed||busy)return;
            var keys=new[]{"SevenZip","Jxl","Kindle","Kcc"}.Where(k=>pendingTools.Contains(k)&&ActiveTool(k)).ToArray();
            foreach(string key in keys){
                if(closed||busy)break;if(!ActiveTool(key))continue;pendingTools.Remove(key);int revision=toolRevisions[key];var snapshot=Snapshot();string resolved=null;bool searchedSeven=false;
                ToolCheck check;KindleGenLocation kindle=null;
                try{
                    if(key=="Jxl"&&!snapshot.ConvertJxl){ShowChecks(new[]{ToolValidation.Check(snapshot,key)});continue;}
                    if(key=="SevenZip"&&String.IsNullOrWhiteSpace(snapshot.SevenZipExe)&&!sevenSearchComplete){
                        Get<TextBlock>("SevenZipLocation").Text="Checking standard Windows locations and command-line archive support...";
                        resolved=await Task.Run(delegate{return SetupChecks.FindUsableSevenZip(null);});snapshot.SevenZipExe=resolved;searchedSeven=true;
                    }
                    else if(key=="Kindle"){kindle=await Task.Run(delegate{return File.Exists(snapshot.KindlegenExe)?new KindleGenLocation{Compiler=snapshot.KindlegenExe}:KindleGenGuide.Locate(snapshot.KindlegenExe,kindleRoots);});resolved=kindle.Compiler??snapshot.KindlegenExe;snapshot.KindlegenExe=resolved;}
                    else {string selected=key=="Kcc"?snapshot.KccExe:key=="Jxl"?snapshot.DjxlExe:snapshot.SevenZipExe;resolved=await Task.Run(delegate{return SetupChecks.ResolveToolPath(key,selected);});if(key=="Kcc")snapshot.KccExe=resolved;else if(key=="Jxl")snapshot.DjxlExe=resolved;else snapshot.SevenZipExe=resolved;}
                    if(key=="Jxl"&&snapshot.ConvertJxl){Get<TextBlock>("JxlStatus").Text="Preparing and checking the JPEG XL decoder. This may take a minute or two...";resolved=await Task.Run(delegate{return ManagedTools.PrepareJxl(snapshot.DjxlExe,snapshot.SevenZipExe,toolsRoot);});snapshot.DjxlExe=resolved;}
                    check=await Task.Run(delegate{return ToolValidation.Check(snapshot,key);});
                }catch(Exception ex){check=new ToolCheck{Key=key,Required=true,Message=ex.Message};}
                if(closed)return;
                if(revision!=toolRevisions[key])continue;
                if(resolved!=null)SetToolSilently(key,resolved);if(searchedSeven)sevenSearchComplete=true;
                ShowChecks(new[]{check});
                if(key=="Kindle")ShowKindleDiscovery(check,kindle);
                if(key=="SevenZip"){
                    Get<TextBlock>("SevenZipLocation").Text=check.Passed?"Detected and tested: "+Text("SevenZip"):"No usable 7-Zip CLI was found. Install 7-Zip or choose its 7z.exe below.";
                    Get<Expander>("SevenZipDetails").IsExpanded=!check.Passed;
                }
            }
            if(pendingTools.Any(ActiveTool)&&!closed&&!busy)autoTimer.Start();
        }
        void ShowChecks(IEnumerable<ToolCheck> checks){foreach(var check in checks){toolChecks[check.Key]=check;pendingTools.Remove(check.Key);var text=Get<TextBlock>(check.Key+"Status");text.Text=(check.Passed?"✓ ":check.Optional?"○ ":"✗ ")+check.Message;text.Foreground=StatusBrush(check.Passed,check.Optional);if(check.Key=="Kindle")ShowKindleDiscovery(check,null);}toolsPassed=toolChecks.Count==4&&ToolValidation.Passed(toolChecks.Values);}
        void ShowKindleDiscovery(ToolCheck check,KindleGenLocation location){
            Get<FrameworkElement>("KindleInstall").Visibility=check.Passed||check.Optional?Visibility.Collapsed:Visibility.Visible;
            if(check.Passed)Get<Expander>("KindleHelp").IsExpanded=false;
            Get<TextBlock>("KindleDiscovery").Text=check.Passed?"KindleGen was found and validated. You can continue.":check.Optional?"KindleGen is not needed for these choices.":location!=null&&location.PreviewerFolderFound?"A Kindle Previewer folder was found, but KindleGen is missing or could not start. Install or reinstall Previewer, then press the button below. You can also select an existing working copy.":"KindleGen was not found in the usual locations or has not passed its check. Download and install Kindle Previewer from Amazon, then check again.";
        }
        async Task RecheckKindle(){try{await CheckPageTool("Kindle");}catch(Exception ex){Get<Expander>("KindleHelp").IsExpanded=true;Feedback("KindleGen still needs attention. Use the instructions below to select an existing copy or locate a custom installation.\n"+ex.Message);}}
        void Feedback(string text){Get<TextBlock>("Feedback").Text=text;}
        void Click(string name,Action action){Get<Button>(name).Click+=delegate{if(busy)return;try{action();}catch(Exception ex){Feedback(ex.Message);}};}
        void Async(string name,Func<Task> action){Get<Button>(name).Click+=async delegate{if(busy)return;busy=true;autoTimer.Stop();Buttons(false);try{await activeAutoCheck;await action();}catch(Exception ex){Feedback(ex.Message);}finally{busy=false;Buttons(true);ShowStep(false);if(autoEnabled&&pendingTools.Any(ActiveTool))autoTimer.Start();}};}
        void Buttons(bool enabled){Get<TabControl>("Steps").IsEnabled=enabled;foreach(var name in new[]{"Next","Back","CancelSetup","FindTools","CheckFolders","CheckTools","RunTest","KccBrowse","JxlBrowse","KindleBrowse","SevenZipBrowse","TestBrowse","OpenTest"})Get<Button>(name).IsEnabled=enabled;Get<Button>("OpenTest").IsEnabled=enabled&&testOutput!=null;}
        void ShowStep(bool resetFeedback=true){
            var pages=VisiblePages();var tabs=Get<TabControl>("Steps");for(int i=0;i<PageCount;i++)((TabItem)tabs.Items[i]).Visibility=pages.Contains(i)?Visibility.Visible:Visibility.Collapsed;tabs.SelectedIndex=step;Get<TextBlock>("StepTitle").Text="Step "+(Array.IndexOf(pages,step)+1)+" of "+pages.Length+" · "+new[]{"Your reader","7-Zip","KCC converter","KindleGen","JPEG XL","Try a book","Schedule","Your folders","How it works"}[step];
            Get<TextBlock>("ReaderPlan").Text="Setup includes: 7-Zip check, KCC"+(pages.Contains(3)?", KindleGen":"")+(pages.Contains(4)?", JPEG XL decoder":"")+", optional test, schedule and folders. "+(!pages.Contains(3)?"KindleGen is skipped for this format. ":"")+(!pages.Contains(4)?"JPEG XL setup is skipped. ":"")+"You can change these choices later.";
            Get<Button>("Back").IsEnabled=!busy&&step>0;Get<Button>("Next").Content=step==8?"Finish & save":step==5&&!testPassed?"Skip test for now":"Continue";
            Get<Button>("FindTools").Visibility=CurrentTool()!=null?Visibility.Visible:Visibility.Collapsed;Get<Button>("CheckTools").Visibility=CurrentTool()!=null?Visibility.Visible:Visibility.Collapsed;
            Get<TextBlock>("KindleNeed").Text=Value((ComboBoxItem)Get<ComboBox>("Format").SelectedItem)=="MOBI"?"KindleGen is Amazon's compiler. KCC uses it to build the final MOBI file for your Kindle.":pages.Contains(3)?"A saved folder preset uses MOBI, so KindleGen is still needed for those books.":"Your selected format does not require KindleGen. This page is skipped during setup. Add it later if you switch to MOBI.";
            if(resetFeedback)Feedback(step==5?"Try a small completed comic, or skip this optional test.":CurrentTool()!=null?"This page checks only the current tool. A green check means you can continue.":"Your normal queue is not converted during setup.");
            if(step==7)Get<TextBlock>("Summary").Text="Reader: "+draft.Profile+" · "+draft.Format+". Folder access: "+(foldersPassed?"verified":"needs checking")+". Sample conversion: "+(testPassed?"passed":"not tested yet")+".\nAutomatic checks: "+(Get<CheckBox>("EnableSchedule").IsChecked==true?draft.ScheduleTimes:"off; existing schedules are left unchanged")+".";
            if(step==8){Get<TextBlock>("HowSchedule").Text=Get<CheckBox>("EnableSchedule").IsChecked==true?(foldersPassed?"After Finish & save, setup will ask Windows to check daily at "+draft.ScheduleTimes+". You can then close this app.":"Your folders need attention, so setup will not enable automatic checks yet. Finish, choose accessible folders in Folders & tools, then enable checks in Schedule."):"Setup will not enable a new schedule. Use Run now yourself, or enable automatic checks in Schedule later. An existing Windows schedule is left unchanged.";Get<TextBlock>("HowIncoming").Text="Place completed comics or manga in your Incoming/Watch folder. Selected input formats: "+String.Join(", ",draft.InputExtensions)+". Before processing a batch, files must have stopped changing for "+draft.QuietMinutes+" minutes. Newly added books may wait until the next scheduled check after that quiet period.";}
            QueueCurrentTool();
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
            string key=CurrentTool();
            if(key!=null&&(!toolChecks.ContainsKey(key)||(!toolChecks[key].Passed&&!toolChecks[key].Optional)))await CheckPageTool(key);
            int next=step<8?VisiblePages().First(p=>p>step):8;
            if(step<5&&next==5){
                Feedback("Copying and verifying tools in KCCAutomate's tools folder. This may take a minute or two; please keep setup open...");
                var copied=await Task.Run(delegate{return ManagedTools.Import(draft,toolsRoot);});
                Set("Kcc",copied.KccExe);Set("Jxl",copied.DjxlExe);Set("Kindle",copied.KindlegenExe);Set("SevenZip",copied.SevenZipExe);Capture();
                var checks=await Task.Run(delegate{return ToolValidation.Check(draft);});ShowChecks(checks);toolsPassed=ToolValidation.Passed(checks);
                if(!toolsPassed)throw new Exception("The copied tools need checking.\n"+ToolValidation.Report(checks));
            }
            if(step==6){draft.ScheduleTimes=Desktop.NormalizeTimes(Text("Times"));int quiet;if(!Int32.TryParse(Text("QuietMinutes"),out quiet)||quiet<0||quiet>1440)throw new Exception("Choose a wait time between 0 and 1440 minutes.");draft.QuietMinutes=quiet;draft.WakeComputer=Get<CheckBox>("Wake").IsChecked==true;}
            if(step==7&&!foldersPassed&&Get<CheckBox>("OpenFolderSettings").IsChecked!=true)await CheckFolders();
            if(step==8){if(!foldersPassed&&Get<CheckBox>("OpenFolderSettings").IsChecked!=true)await CheckFolders();PrepareResult();busy=false;Window.DialogResult=true;return;}
            step=next;ShowStep();if(step==7){try{await CheckFolders();}catch(Exception ex){Get<CheckBox>("OpenFolderSettings").IsChecked=true;Feedback("Your folders need attention. Finish setup to choose accessible locations in Folders & tools. Setup will not enable a schedule yet.\n"+ex.Message);}ShowStep(false);}
        }
        void PrepareResult(){draft.SetupCompleted=true;Result=draft;EnableSchedule=Get<CheckBox>("EnableSchedule").IsChecked==true&&foldersPassed;OpenFolderSettings=Get<CheckBox>("OpenFolderSettings").IsChecked==true;}
        async Task CheckFolders(){Capture();Feedback("Preparing and checking your folders. Network folders may take a moment...");await Task.Run(delegate{return SetupChecks.ProbeFolders(draft);});foldersPassed=true;Feedback("All four folders are ready. Continue for a short guide to using the app.");}
        async Task CheckPageTool(string key){
            if(key==null)return;InvalidateTool(key);Feedback(key=="Jxl"?"Preparing and checking the JPEG XL decoder. This may take a minute or two...":"Checking "+key+"...");var selection=Snapshot();KindleGenLocation kindle=null;
            try {
            if(key=="Jxl"&&!selection.ConvertJxl){ShowChecks(new[]{ToolValidation.Check(selection,key)});Feedback("JPEG XL preparation is off. You can continue.");return;}
            string selected=key=="Kcc"?selection.KccExe:key=="Jxl"?selection.DjxlExe:key=="Kindle"?selection.KindlegenExe:selection.SevenZipExe;
            string resolved;
            if(key=="Kindle"){kindle=await Task.Run(delegate{return File.Exists(selected)?new KindleGenLocation{Compiler=selected}:KindleGenGuide.Locate(selected,kindleRoots);});resolved=kindle.Compiler??selected;}
            else resolved=await Task.Run(delegate{return key=="SevenZip"&&String.IsNullOrWhiteSpace(selected)?SetupChecks.FindUsableSevenZip(null):SetupChecks.ResolveToolPath(key,selected);});
            if(key=="Jxl"&&selection.ConvertJxl){resolved=await Task.Run(delegate{return ManagedTools.PrepareJxl(resolved,selection.SevenZipExe,toolsRoot);});}
            SetToolSilently(key,resolved);selection=Snapshot();var check=await Task.Run(delegate{return ToolValidation.Check(selection,key);});ShowChecks(new[]{check});
            if(key=="Kindle")ShowKindleDiscovery(check,kindle);
            if(key=="SevenZip"){Get<TextBlock>("SevenZipLocation").Text=check.Passed?"Detected and tested: "+Text("SevenZip"):"No working 7-Zip CLI was found. Install it, choose its location, or continue if it is not needed.";Get<Expander>("SevenZipDetails").IsExpanded=!check.Passed;}
            if(!check.Passed&&!check.Optional)throw new Exception(check.Message);
            Feedback(check.Passed?"This tool is ready. Continue when you are ready.":"This tool is optional for your current choices. You can continue.");
            }catch(Exception ex){var failed=new ToolCheck{Key=key,Required=true,Message=ex.Message};ShowChecks(new[]{failed});if(key=="Kindle")ShowKindleDiscovery(failed,kindle);throw;}
        }
        async Task Discover(){
            string key=CurrentTool();if(key==null)return;if(key=="SevenZip"||key=="Kindle"){await CheckPageTool(key);return;}Capture();Feedback("Looking for this tool in common app locations...");
            string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var roots=new[]{(String.IsNullOrWhiteSpace(draft.KccExe)?null:Path.GetDirectoryName(draft.KccExe)),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"7-Zip"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"7-Zip"),toolsRoot,appDirectory,@"C:\kindletomanga",Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"KindleComicConverter"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Amazon"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Amazon"),Path.Combine(local,"Amazon"),Path.Combine(local,"Programs","Kindle Previewer 3"),Path.Combine(local,"Programs","Kindle Previewer 4"),Path.Combine(local,"KCCAutomate","Updates")}.Concat(key=="Kindle"?KindleGenGuide.InstallationRoots():new string[0]);
            var found=await Task.Run(delegate{return SetupChecks.Discover(roots);});
            string selected=key=="Kcc"?found.Kcc:key=="Jxl"?found.Jxl:found.Kindlegen;
            if(selected!=null&&!File.Exists(Text(key)))Set(key,selected);
            await CheckPageTool(key);
        }
        async Task RunTest(){Capture();Desktop.Validate(draft);string book=Text("TestBook");Feedback("Testing a copy of the selected book. The original stays in place...");Get<TextBox>("TestLog").Text="Preparing a verified test copy...";var result=await Task.Run(delegate{return SetupChecks.ConvertTest(draft,book,appDirectory);});testOutput=result.Output;testPassed=result.Passed;Get<TextBox>("TestLog").Text=result.Log;Feedback(result.Passed?"Test conversion passed. Open the results and inspect the book on your reader.":"Test conversion failed. Review the log above and the test working folder; the selected original was retained.");}
        void BrowseFolder(string field){using(var d=new Forms.FolderBrowserDialog{Description="Choose "+field+" folder",ShowNewFolderButton=true}){if(d.ShowDialog()==Forms.DialogResult.OK)Set(field,d.SelectedPath);}}
        void BrowseFile(string field,string filter){var d=new Microsoft.Win32.OpenFileDialog{Filter=filter};if(d.ShowDialog(Window)==true)Set(field,d.FileName);}
        static void Open(string path){Process.Start(new ProcessStartInfo(path){UseShellExecute=true});}
        public void RenderStep(int index){step=index;ShowStep();}
        async Task TestNextPage(){busy=true;autoTimer.Stop();try{await activeAutoCheck;await Next();}finally{busy=false;autoTimer.Stop();}}
        public async Task TestKindleDiscovery(string fixtures,string installation,bool simulateInstall,List<string> results){
            step=3;ShowStep();StartAutomaticChecks();activeAutoCheck=AutoCheckPending();await activeAutoCheck;autoTimer.Stop();
            if(simulateInstall){
                if(Get<TextBlock>("KindleStatus").Text.StartsWith("✓")||Get<FrameworkElement>("KindleInstall").Visibility!=Visibility.Visible||Directory.Exists(installation))throw new Exception("Missing Kindle Previewer did not offer manual installation or the scan created an installation folder.");
                await RecheckKindle();if(!Get<Expander>("KindleHelp").IsExpanded)throw new Exception("A failed post-install check did not reveal the existing illustrated/manual instructions.");
                string bin=Path.Combine(installation,@"lib\fc\bin");Directory.CreateDirectory(bin);await RecheckKindle();
                if(!Get<TextBlock>("KindleDiscovery").Text.Contains("Previewer folder was found")||Get<TextBlock>("KindleStatus").Text.StartsWith("✓"))throw new Exception("An empty Previewer folder was mistaken for a validated compiler.");
                File.Copy(Path.Combine(fixtures,@"Kindle Previewer 4\lib\fc\bin\kindlegen.exe"),Path.Combine(bin,"kindlegen.exe"));await RecheckKindle();
            }
            if(!Get<TextBlock>("KindleStatus").Text.StartsWith("✓")||Text("Kindle")!=Path.Combine(installation,@"lib\fc\bin\kindlegen.exe")||Get<FrameworkElement>("KindleInstall").Visibility!=Visibility.Collapsed)throw new Exception("KindleGen was not found, selected and validated automatically in the likely installation folder.");
            autoEnabled=false;autoTimer.Stop();results.Add("PASS: "+(simulateInstall?"missing Previewer offers its official page; repeated missing/empty-folder checks reveal manual help; post-install recheck finds and validates KindleGen":"existing Previewer KindleGen is found and validated automatically without asking for a path"));
        }
        public async Task TestConditionalPages(string fixtures,List<string> results){
            string format=draft.Format,unusedKindle=Text("Kindle"),unusedJxl=Text("Jxl");bool jxl=draft.ConvertJxl,kindle=ToolValidation.RequiresKindlegen(draft);
            int[] expected=Enumerable.Range(0,PageCount).Where(p=>(p!=3||kindle)&&(p!=4||jxl)).ToArray();
            if(!VisiblePages().SequenceEqual(expected)||!Get<TextBlock>("StepTitle").Text.StartsWith("Step 1 of "+expected.Length))throw new Exception("Conditional setup has the wrong initial route or step count.");
            var tabs=Get<TabControl>("Steps");for(int p=0;p<PageCount;p++)if((((TabItem)tabs.Items[p]).Visibility==Visibility.Visible)!=expected.Contains(p))throw new Exception("An inactive setup page remained available to tab navigation.");
            tabs.SelectedIndex=5;if(tabs.SelectedIndex!=step)throw new Exception("Direct tab navigation bypassed required setup checks.");
            Set("Kcc",Path.Combine(fixtures,"kcc-c2e.exe"));
            for(int i=1;i<expected.Length;i++){
                await TestNextPage();if(step!=expected[i]||!Get<TextBlock>("StepTitle").Text.StartsWith("Step "+(i+1)+" of "+expected.Length))throw new Exception("Conditional navigation visited a skipped page or used the wrong step count.");
                if(step==3||step==4){
                    string key=CurrentTool();Set(key,Path.Combine(fixtures,"missing-"+key+".exe"));bool rejected=false;try{await TestNextPage();}catch{rejected=true;}if(!rejected||step!=expected[i])throw new Exception("A required tool was bypassed on the conditional route.");
                    Set(key,key=="Kindle"?Path.Combine(fixtures,@"Kindle Previewer 4\lib\fc\bin\kindlegen.exe"):Path.Combine(fixtures,"djxl.exe"));
                }
            }
            if(!foldersPassed||!toolsPassed||!Text("Kcc").StartsWith(toolsRoot,StringComparison.OrdinalIgnoreCase))throw new Exception("The shortened route did not import tools before the test or prepare final folders.");
            string bundle=Path.GetDirectoryName(Path.GetDirectoryName(Text("Kcc")));
            if(!kindle&&(Text("Kindle")!=unusedKindle||Directory.Exists(Path.Combine(bundle,"kindlegen"))||File.Exists(Path.Combine(Path.GetDirectoryName(Text("Kcc")),"kindlegen.exe"))))throw new Exception("An inactive KindleGen path was erased or copied into the bundle.");
            if(!jxl&&(Text("Jxl")!=unusedJxl||Directory.Exists(Path.Combine(bundle,"jxl"))))throw new Exception("An inactive JPEG XL path was erased or copied into the bundle.");
            PrepareResult();if(Result.Format!=format||Result.ConvertJxl!=jxl||EnableSchedule)throw new Exception("Conditional setup saved different choices or enabled scheduling.");
            for(int i=expected.Length-2;i>=0;i--){Back();if(step!=expected[i])throw new Exception("Back visited a skipped setup page.");}
            if(format=="EPUB"&&!jxl&&!kindle){
                Set("Kindle",Path.Combine(fixtures,"missing-kindlegen.exe"));Set("Jxl",Path.Combine(fixtures,"missing-djxl.exe"));
                Select("Format","MOBI");Get<CheckBox>("JxlEnabled").IsChecked=true;
                if(VisiblePages().Length!=PageCount)throw new Exception("Changing choices did not restore required tool pages.");
                await TestNextPage();await TestNextPage();await TestNextPage();if(step!=3)throw new Exception("MOBI did not restore KindleGen setup.");
                bool rejected=false;try{await TestNextPage();}catch{rejected=true;}if(!rejected||step!=3)throw new Exception("Re-enabling MOBI accepted a stale inactive KindleGen selection.");
                Set("Kindle",Path.Combine(fixtures,@"Kindle Previewer 4\lib\fc\bin\kindlegen.exe"));await TestNextPage();if(step!=4)throw new Exception("Re-enabling JPEG XL did not restore its page.");
                rejected=false;try{await TestNextPage();}catch{rejected=true;}if(!rejected||step!=4)throw new Exception("Re-enabling JPEG XL accepted its previously inactive decoder.");
            }
            autoTimer.Stop();results.Add("PASS: "+format+(format!="MOBI"&&kindle?" with MOBI folder preset":"")+" / JPEG XL "+(jxl?"on":"off")+" uses "+expected.Length+" correctly numbered steps; Back skips inactive pages; required tools still gate; imports and final folders complete while inactive paths are retained");
        }
        public async Task TestAutomaticTools(string fixtures,List<string> results){
            if(Directory.Exists(draft.WatchFolder))throw new Exception("Default book folders were created before setup reached its folder step.");
            await TestNextPage();if(step!=1||Directory.Exists(draft.WatchFolder))throw new Exception("The first tool page is not 7-Zip, or book folders were created before the final step.");
            StartAutomaticChecks();Set("Kcc",fixtures);Set("Jxl",Path.Combine(fixtures,"djxl.exe"));Set("Kindle",Path.Combine(fixtures,"Kindle Previewer 4"));autoTimer.Stop();
            activeAutoCheck=AutoCheckPending();await activeAutoCheck;autoTimer.Stop();
            if(toolChecks.ContainsKey("Kcc")||toolChecks.ContainsKey("Kindle")||toolChecks.ContainsKey("Jxl")||!Get<TextBlock>("SevenZipStatus").Text.StartsWith("✓"))throw new Exception("Dependency setup checked unrelated tools or did not validate installed 7-Zip first.");
            foreach(var expected in new[]{Tuple.Create(2,"Kcc"),Tuple.Create(3,"Kindle"),Tuple.Create(4,"Jxl")}){
                await TestNextPage();if(step!=expected.Item1)throw new Exception("Tool pages are out of dependency order.");
                activeAutoCheck=AutoCheckPending();await activeAutoCheck;autoTimer.Stop();
                if(!Get<TextBlock>(expected.Item2+"Status").Text.StartsWith("✓"))throw new Exception("The current tool did not validate on its own page.");
            }
            if(!toolsPassed)throw new Exception("The four individual tool pages did not produce complete validation.");
            await TestNextPage();if(step!=5||!Text("Kcc").StartsWith(toolsRoot,StringComparison.OrdinalIgnoreCase)||Directory.Exists(draft.WatchFolder))throw new Exception("Tools were not imported before the optional test, or book folders were prepared before the final page.");
            await TestNextPage();if(step!=6)throw new Exception("The optional test cannot be skipped.");await TestNextPage();
            if(step!=7||!new[]{draft.WatchFolder,draft.ConvertedFolder,draft.ArchiveFolder,draft.WorkFolder}.All(Directory.Exists)||!foldersPassed||!Get<TextBox>("Watch").IsReadOnly)throw new Exception("The final folder page did not create folders and explain them without an initial path-editing burden.");
            await TestNextPage();if(step!=8||Convert.ToString(Get<Button>("Next").Content)!="Finish & save"||!Get<TextBlock>("HowSchedule").Text.Contains("existing Windows schedule"))throw new Exception("The final how-it-works page was missing or did not explain inactive/existing scheduling.");
            Get<CheckBox>("EnableSchedule").IsChecked=true;ShowStep();if(!Get<TextBlock>("HowSchedule").Text.Contains(draft.ScheduleTimes))throw new Exception("The final page did not show the chosen automatic-check times.");Get<CheckBox>("EnableSchedule").IsChecked=false;
            results.Add("PASS: tool pages follow dependency order; imports precede the optional test; folders are prepared before a final how-it-works page with scheduling, quiet-period and file-flow guidance");
            string originalWatch=draft.WatchFolder,blocked=Path.Combine(fixtures,"blocked-folder");File.WriteAllText(blocked,"keep file");Set("Watch",blocked);Get<CheckBox>("EnableSchedule").IsChecked=true;step=6;await TestNextPage();
            if(step!=7||Get<CheckBox>("OpenFolderSettings").IsChecked!=true||foldersPassed)throw new Exception("Unavailable folders did not offer a route to app settings.");await TestNextPage();if(step!=8||!Get<TextBlock>("HowSchedule").Text.Contains("will not enable automatic checks"))throw new Exception("The final page promised scheduling despite unavailable folders.");PrepareResult();
            if(EnableSchedule||!OpenFolderSettings||File.ReadAllText(blocked)!="keep file")throw new Exception("Unavailable folders enabled scheduling or replaced an existing file.");
            Set("Watch",originalWatch);Get<CheckBox>("EnableSchedule").IsChecked=false;Get<CheckBox>("OpenFolderSettings").IsChecked=false;await CheckFolders();Result=null;OpenFolderSettings=false;draft.SetupCompleted=false;
            results.Add("PASS: unavailable final folders route to app settings and suppress new scheduling without replacing existing files");
            step=2;ShowStep();string readyKindle=Get<TextBlock>("KindleStatus").Text;Set("Kcc",Path.Combine(fixtures,"missing.exe"));autoTimer.Stop();
            if(Get<TextBlock>("KindleStatus").Text!=readyKindle)throw new Exception("Editing one tool cleared another tool's completed check.");
            Set("Kcc",Path.Combine(fixtures,"kcc-c2e.exe"));autoTimer.Stop();activeAutoCheck=AutoCheckPending();await Task.Delay(75);Set("Kcc",Path.Combine(fixtures,"missing.exe"));autoTimer.Stop();await activeAutoCheck;
            if(Get<TextBlock>("KccStatus").Text.StartsWith("✓"))throw new Exception("A stale automatic result validated a changed path.");
            activeAutoCheck=AutoCheckPending();await activeAutoCheck;
            if(toolsPassed||!Get<TextBlock>("KccStatus").Text.StartsWith("✗"))throw new Exception("A missing changed tool was not marked red.");
            bool rejected=false;try{await TestNextPage();}catch{rejected=true;}if(!rejected||step!=2)throw new Exception("A required tool page allowed an unvalidated tool to continue.");
            autoEnabled=false;autoTimer.Stop();foreach(string key in new[]{"Kcc","Jxl","Kindle","SevenZip"})SetToolSilently(key,"");pendingTools.Clear();InvalidateTools();
            Get<TextBlock>("SevenZipLocation").Text="We check Program Files and PATH, then test creating and extracting an archive.";
            results.Add("PASS: tool paths/folders check automatically on their own pages; unrelated green checks survive edits and stale results cannot validate a changed path");
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
