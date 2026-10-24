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
        public const int PageCount=8;
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
            foreach(var pair in new[]{new[]{"KccBrowse","Kcc"},new[]{"KindleBrowse","Kindle"},new[]{"SevenZipBrowse","SevenZip"}}){string field=pair[1];Click(pair[0],delegate{BrowseFile(field,"Windows programs (*.exe)|*.exe");});}
            Click("JxlBrowse",delegate{BrowseFile("Jxl","JPEG XL decoder or Windows package|*.exe;*.zip;*.7z");});
            Click("TestBrowse",delegate{BrowseFile("TestBook","Comic files|*.cbz;*.pdf;*.epub;*.cbr;*.cb7");});
            Click("GetKcc",delegate{Open(ReleaseClient.ApprovedKccDownload);});Click("GetJxl",delegate{Open("https://github.com/libjxl/libjxl/releases");});Click("GetKindle",delegate{Open("https://github.com/ciromattia/kcc/wiki/Installation#kindlegen");});
            Click("GetKccFallback",delegate{Open(ReleaseClient.ApprovedKccPage);});Click("GetDependencies",delegate{Open("https://github.com/ciromattia/kcc/wiki/Installation");});Click("GetSevenZip",delegate{Open("https://www.7-zip.org/");});
            Click("ShowKindleGuide",delegate{KindleGenGuide.Create(Window,delegate{return Text("Kindle");}).ShowDialog();});
            Click("OpenKindleFolder",delegate{Feedback(KindleGenGuide.OpenFolder(Text("Kindle")));});
            Click("OpenTest",delegate{if(testOutput!=null)Open(testOutput);});
            Async("FindTools",Discover);Async("CheckFolders",CheckFolders);Async("CheckTools",delegate{return CheckPageTool(CurrentTool());});Async("RunTest",RunTest);Async("Next",Next);
            Click("Back",delegate{if(step>0){step--;ShowStep();}});
            Click("BackToSevenZip",delegate{step=1;ShowStep();});
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
        Brush StatusBrush(bool passed,bool optional){var canvas=Window.TryFindResource("CanvasBrush") as SolidColorBrush;bool dark=canvas!=null&&canvas.Color.R<100;return passed?(dark?Brushes.LightGreen:Brushes.ForestGreen):optional?(dark?Brushes.LightGray:Brushes.Gray):(dark?Brushes.LightSalmon:Brushes.Firebrick);}
        void InvalidateTools(){foreach(var name in new[]{"Kcc","Jxl","Kindle","SevenZip"})InvalidateTool(name);}
        void InvalidateTool(string name){
            toolsPassed=false;testPassed=false;toolChecks.Remove(name);toolRevisions[name]=toolRevisions.ContainsKey(name)?toolRevisions[name]+1:1;
            bool optional=(name=="Jxl"&&Get<CheckBox>("JxlEnabled").IsChecked!=true)||(name=="Kindle"&&Value((ComboBoxItem)Get<ComboBox>("Format").SelectedItem)!="MOBI")||(name=="SevenZip"&&!(Get<CheckBox>("JxlEnabled").IsChecked==true&&Text("Jxl").EndsWith(".7z",StringComparison.OrdinalIgnoreCase)));
            var text=Get<TextBlock>(name+"Status");text.Text=(optional?"○ ":"✗ ")+new Dictionary<string,string>{{"Kcc","KCC c2e"},{"Jxl","JPEG XL decoder"},{"Kindle","KindleGen"},{"SevenZip","7-Zip"}}[name]+(autoEnabled?" · checking automatically...":optional?" · optional / not checked":" · missing or not checked");text.Foreground=StatusBrush(false,optional);
        }
        void ToolChanged(string key){
            InvalidateTool(key);pendingTools.Add(key);
            if(key=="SevenZip"){sevenSearchComplete=false;if(Text("Jxl").EndsWith(".7z",StringComparison.OrdinalIgnoreCase)){InvalidateTool("Jxl");pendingTools.Add("Jxl");}}
            if(key=="Jxl"&&String.IsNullOrWhiteSpace(Text("SevenZip"))){sevenSearchComplete=false;InvalidateTool("SevenZip");pendingTools.Add("SevenZip");}
            if(autoEnabled&&!busy&&pendingTools.Any(ActiveTool)){autoTimer.Stop();autoTimer.Start();}
        }
        string CurrentTool(){return step==1?"SevenZip":step==2?"Kcc":step==3?"Kindle":step==4?"Jxl":null;}
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
                ToolCheck check;
                try{
                    if(key=="Jxl"&&!snapshot.ConvertJxl){ShowChecks(new[]{ToolValidation.Check(snapshot,key)});continue;}
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
            if(pendingTools.Any(ActiveTool)&&!closed&&!busy)autoTimer.Start();
        }
        void ShowChecks(IEnumerable<ToolCheck> checks){foreach(var check in checks){toolChecks[check.Key]=check;pendingTools.Remove(check.Key);var text=Get<TextBlock>(check.Key+"Status");text.Text=(check.Passed?"✓ ":check.Optional?"○ ":"✗ ")+check.Message;text.Foreground=StatusBrush(check.Passed,check.Optional);}toolsPassed=toolChecks.Count==4&&ToolValidation.Passed(toolChecks.Values);}
        void Feedback(string text){Get<TextBlock>("Feedback").Text=text;}
        void Click(string name,Action action){Get<Button>(name).Click+=delegate{if(busy)return;try{action();}catch(Exception ex){Feedback(ex.Message);}};}
        void Async(string name,Func<Task> action){Get<Button>(name).Click+=async delegate{if(busy)return;busy=true;autoTimer.Stop();Buttons(false);try{await activeAutoCheck;await action();}catch(Exception ex){Feedback(ex.Message);}finally{busy=false;Buttons(true);ShowStep(false);if(autoEnabled&&pendingTools.Any(ActiveTool))autoTimer.Start();}};}
        void Buttons(bool enabled){Get<TabControl>("Steps").IsEnabled=enabled;foreach(var name in new[]{"Next","Back","CancelSetup","FindTools","CheckFolders","CheckTools","RunTest","KccBrowse","JxlBrowse","KindleBrowse","SevenZipBrowse","TestBrowse","OpenTest"})Get<Button>(name).IsEnabled=enabled;Get<Button>("OpenTest").IsEnabled=enabled&&testOutput!=null;}
        void ShowStep(bool resetFeedback=true){
            Get<TabControl>("Steps").SelectedIndex=step;Get<TextBlock>("StepTitle").Text="Step "+(step+1)+" of "+PageCount+" · "+new[]{"Your reader","7-Zip","KCC converter","KindleGen","JPEG XL","Try a book","Schedule","Your folders"}[step];
            Get<Button>("Back").IsEnabled=!busy&&step>0;Get<Button>("Next").Content=step==7?"Finish & save":step==5&&!testPassed?"Skip test for now":"Continue";
            Get<Button>("FindTools").Visibility=CurrentTool()!=null?Visibility.Visible:Visibility.Collapsed;Get<Button>("CheckTools").Visibility=CurrentTool()!=null?Visibility.Visible:Visibility.Collapsed;
            Get<TextBlock>("KindleNeed").Text=Value((ComboBoxItem)Get<ComboBox>("Format").SelectedItem)=="MOBI"?"KindleGen is Amazon's compiler. KCC uses it to build the final MOBI file for your Kindle.":"Your selected format does not require KindleGen. You can leave this entry empty and continue. Add it later if you switch to MOBI.";
            if(resetFeedback)Feedback(step==5?"Try a small completed comic, or skip this optional test.":CurrentTool()!=null?"This page checks only the current tool. A green check means you can continue.":"Your normal queue is not converted during setup.");
            if(step==7)Get<TextBlock>("Summary").Text="Reader: "+draft.Profile+" · "+draft.Format+". Folder access: "+(foldersPassed?"verified":"needs checking")+". Sample conversion: "+(testPassed?"passed":"not tested yet")+".\nAutomatic checks: "+(Get<CheckBox>("EnableSchedule").IsChecked==true?draft.ScheduleTimes:"off; existing schedules are left unchanged")+".";
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
            if(step==4){
                Feedback("Copying and verifying tools in KCCAutomate's tools folder...");
                var copied=await Task.Run(delegate{return ManagedTools.Import(draft,toolsRoot);});
                Set("Kcc",copied.KccExe);Set("Jxl",copied.DjxlExe);Set("Kindle",copied.KindlegenExe);Set("SevenZip",copied.SevenZipExe);Capture();
                var checks=await Task.Run(delegate{return ToolValidation.Check(draft);});ShowChecks(checks);toolsPassed=ToolValidation.Passed(checks);
                if(!toolsPassed)throw new Exception("The copied tools need checking.\n"+ToolValidation.Report(checks));
            }
            if(step==6){draft.ScheduleTimes=Desktop.NormalizeTimes(Text("Times"));int quiet;if(!Int32.TryParse(Text("QuietMinutes"),out quiet)||quiet<0||quiet>1440)throw new Exception("Choose a wait time between 0 and 1440 minutes.");draft.QuietMinutes=quiet;draft.WakeComputer=Get<CheckBox>("Wake").IsChecked==true;}
            if(step==7){if(!foldersPassed&&Get<CheckBox>("OpenFolderSettings").IsChecked!=true)await CheckFolders();PrepareResult();busy=false;Window.DialogResult=true;return;}
            step++;ShowStep();if(step==7){try{await CheckFolders();}catch(Exception ex){Get<CheckBox>("OpenFolderSettings").IsChecked=true;Feedback("Your folders need attention. Finish setup to choose accessible locations in Folders & tools. Setup will not enable a schedule yet.\n"+ex.Message);}ShowStep(false);}
        }
        void PrepareResult(){draft.SetupCompleted=true;Result=draft;EnableSchedule=Get<CheckBox>("EnableSchedule").IsChecked==true&&foldersPassed;OpenFolderSettings=Get<CheckBox>("OpenFolderSettings").IsChecked==true;}
        async Task CheckFolders(){Capture();Feedback("Preparing and checking your folders. Network folders may take a moment...");await Task.Run(delegate{return SetupChecks.ProbeFolders(draft);});foldersPassed=true;Feedback("All four folders are ready. Finish setup, then add completed comics to Incoming.");}
        async Task CheckPageTool(string key){
            if(key==null)return;InvalidateTool(key);Feedback("Checking "+key+"...");var selection=Snapshot();
            try {
            if(key=="Jxl"&&!selection.ConvertJxl){ShowChecks(new[]{ToolValidation.Check(selection,key)});Feedback("JPEG XL preparation is off. You can continue.");return;}
            string selected=key=="Kcc"?selection.KccExe:key=="Jxl"?selection.DjxlExe:key=="Kindle"?selection.KindlegenExe:selection.SevenZipExe;
            string resolved=await Task.Run(delegate{return key=="SevenZip"&&String.IsNullOrWhiteSpace(selected)?SetupChecks.FindUsableSevenZip(null):SetupChecks.ResolveToolPath(key,selected);});
            if(key=="Jxl"&&selection.ConvertJxl){resolved=await Task.Run(delegate{return ManagedTools.PrepareJxl(resolved,selection.SevenZipExe,toolsRoot);});}
            SetToolSilently(key,resolved);selection=Snapshot();var check=await Task.Run(delegate{return ToolValidation.Check(selection,key);});ShowChecks(new[]{check});
            if(key=="SevenZip"){Get<TextBlock>("SevenZipLocation").Text=check.Passed?"Detected and tested: "+Text("SevenZip"):"No working 7-Zip CLI was found. Install it, choose its location, or continue if it is not needed.";Get<Expander>("SevenZipDetails").IsExpanded=!check.Passed;}
            if(!check.Passed&&!check.Optional)throw new Exception(check.Message);
            Feedback(check.Passed?"This tool is ready. Continue when you are ready.":"This tool is optional for your current choices. You can continue.");
            }catch(Exception ex){ShowChecks(new[]{new ToolCheck{Key=key,Required=true,Message=ex.Message}});throw;}
        }
        async Task Discover(){
            string key=CurrentTool();if(key==null)return;if(key=="SevenZip"){await CheckPageTool(key);return;}Capture();Feedback("Looking for this tool in common app locations...");
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
            results.Add("PASS: one page per tool follows 7-Zip, KCC, KindleGen and JXL order; inactive tools wait; imports precede the optional test; the final page creates and explains book folders");
            string originalWatch=draft.WatchFolder,blocked=Path.Combine(fixtures,"blocked-folder");File.WriteAllText(blocked,"keep file");Set("Watch",blocked);Get<CheckBox>("EnableSchedule").IsChecked=true;step=6;await TestNextPage();
            if(step!=7||Get<CheckBox>("OpenFolderSettings").IsChecked!=true||foldersPassed)throw new Exception("Unavailable folders did not offer a route to app settings.");PrepareResult();
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
