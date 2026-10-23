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
using Forms=System.Windows.Forms;

namespace KCCAutomate {
    public class SetupWizard {
        public Window Window {get;private set;}
        public Settings Result {get;private set;}
        public bool EnableSchedule {get;private set;}
        readonly Settings draft;
        readonly string appDirectory;
        bool busy,foldersPassed,toolsPassed,testPassed;
        int step;
        string testOutput;
        public SetupWizard(Window owner,Settings settings,IEnumerable<Device> devices,string storage) {
            draft=new JavaScriptSerializer().Deserialize<Settings>(new JavaScriptSerializer().Serialize(settings));
            appDirectory=AppDomain.CurrentDomain.BaseDirectory;
            using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("KCCAutomate.SetupWizard.xaml"))Window=(Window)XamlReader.Load(stream);
            if(owner.IsVisible)Window.Owner=owner;Window.Resources.MergedDictionaries.Add(owner.Resources);
            Get<ComboBox>("Device").ItemsSource=devices;Get<ComboBox>("Device").SelectedValue=draft.Profile;
            Select("Format",draft.Format);Get<CheckBox>("Manga").IsChecked=draft.MangaStyle;
            Set("Watch",draft.WatchFolder);Set("Output",draft.ConvertedFolder);Set("Archive",draft.ArchiveFolder);Set("Work",draft.WorkFolder);
            Set("Kcc",draft.KccExe);Set("Jxl",draft.DjxlExe);Set("Kindle",draft.KindlegenExe);
            Get<CheckBox>("JxlEnabled").IsChecked=draft.ConvertJxl;
            Set("Times",draft.ScheduleTimes);Set("QuietMinutes",draft.QuietMinutes.ToString());Get<CheckBox>("Wake").IsChecked=draft.WakeComputer;
            Get<TextBlock>("StorageInfo").Text="Settings location: "+storage;
            Get<TextBlock>("ScheduleInfo").Text="Checks run as "+WindowsIdentity.GetCurrent().Name+" while signed in, including when the screen is locked. The app may be closed. The PC and network share must be available.";
            foreach(var pair in new[]{new[]{"WatchBrowse","Watch"},new[]{"OutputBrowse","Output"},new[]{"ArchiveBrowse","Archive"},new[]{"WorkBrowse","Work"}}){string field=pair[1];Click(pair[0],delegate{BrowseFolder(field);});}
            foreach(var pair in new[]{new[]{"KccBrowse","Kcc"},new[]{"JxlBrowse","Jxl"},new[]{"KindleBrowse","Kindle"}}){string field=pair[1];Click(pair[0],delegate{BrowseFile(field,"Windows programs (*.exe)|*.exe");});}
            Click("TestBrowse",delegate{BrowseFile("TestBook","Comic files|*.cbz;*.pdf;*.epub;*.cbr;*.cb7");});
            Click("GetKcc",delegate{Open("https://github.com/ciromattia/kcc/releases");});Click("GetJxl",delegate{Open("https://github.com/libjxl/libjxl/releases");});Click("GetKindle",delegate{Open("https://github.com/ciromattia/kcc/wiki/Installation#kindlegen");});
            Click("OpenTest",delegate{if(testOutput!=null)Open(testOutput);});
            Async("FindTools",Discover);Async("CheckFolders",CheckFolders);Async("CheckTools",CheckTools);Async("RunTest",RunTest);Async("Next",Next);
            Click("Back",delegate{if(step>0){step--;ShowStep();}});
            Click("CancelSetup",delegate{Window.DialogResult=false;});
            foreach(var name in new[]{"Watch","Output","Archive","Work"})Get<TextBox>(name).TextChanged+=delegate{foldersPassed=false;testPassed=false;};
            foreach(var name in new[]{"Kcc","Jxl","Kindle"})Get<TextBox>(name).TextChanged+=delegate{toolsPassed=false;testPassed=false;};
            Get<CheckBox>("JxlEnabled").Checked+=delegate{toolsPassed=false;testPassed=false;};Get<CheckBox>("JxlEnabled").Unchecked+=delegate{toolsPassed=false;testPassed=false;};
            Get<TextBox>("TestBook").TextChanged+=delegate{testPassed=false;};
            Get<ComboBox>("Device").SelectionChanged+=delegate{testPassed=false;};Get<ComboBox>("Format").SelectionChanged+=delegate{testPassed=false;toolsPassed=false;};Get<CheckBox>("Manga").Checked+=delegate{testPassed=false;};Get<CheckBox>("Manga").Unchecked+=delegate{testPassed=false;};
            Window.Closing+=delegate(object sender,System.ComponentModel.CancelEventArgs e){if(busy){e.Cancel=true;Feedback("Please let the current check or test finish before closing.");}};
            ShowStep();
        }
        T Get<T>(string name)where T:class{var result=Window.FindName(name)as T;if(result==null)throw new Exception("Setup control missing: "+name);return result;}
        string Text(string name){return Get<TextBox>(name).Text.Trim();}
        void Set(string name,string text){Get<TextBox>(name).Text=text??"";}
        void Select(string name,string text){Get<ComboBox>(name).SelectedItem=Get<ComboBox>(name).Items.Cast<ComboBoxItem>().FirstOrDefault(i=>Convert.ToString(i.Content)==text);}
        void Feedback(string text){Get<TextBlock>("Feedback").Text=text;}
        void Click(string name,Action action){Get<Button>(name).Click+=delegate{if(busy)return;try{action();}catch(Exception ex){Feedback(ex.Message);}};}
        void Async(string name,Func<Task> action){Get<Button>(name).Click+=async delegate{if(busy)return;busy=true;Buttons(false);try{await action();}catch(Exception ex){Feedback(ex.Message);}finally{busy=false;Buttons(true);ShowStep(false);}};}
        void Buttons(bool enabled){Get<TabControl>("Steps").IsEnabled=enabled;foreach(var name in new[]{"Next","Back","CancelSetup","FindTools","CheckFolders","CheckTools","RunTest","WatchBrowse","OutputBrowse","ArchiveBrowse","WorkBrowse","KccBrowse","JxlBrowse","KindleBrowse","TestBrowse","OpenTest"})Get<Button>(name).IsEnabled=enabled;Get<Button>("OpenTest").IsEnabled=enabled&&testOutput!=null;}
        void ShowStep(bool resetFeedback=true){
            Get<TabControl>("Steps").SelectedIndex=step;Get<TextBlock>("StepTitle").Text="Step "+(step+1)+" of 6 · "+new[]{"Your reader","Folders","Tools","Try a book","Schedule","Review"}[step];
            Get<Button>("Back").IsEnabled=!busy&&step>0;Get<Button>("Next").Content=step==5?"Finish & save":"Continue";
            if(resetFeedback)Feedback(step==3?"Choose a small completed comic, or continue to test later.":"Your normal queue is not converted during setup.");
            if(step==5)Get<TextBlock>("Summary").Text="Device: "+draft.Profile+" · "+draft.Format+"\n\nIncoming: "+draft.WatchFolder+"\nConverted: "+draft.ConvertedFolder+"\nArchive: "+draft.ArchiveFolder+"\nWorking: "+draft.WorkFolder+"\n\nFolder access: "+(foldersPassed?"verified":"needs checking")+"\nTools: "+(toolsPassed?"startup checks passed":"needs checking")+"\nTest conversion: "+(testPassed?"passed":"not verified yet")+"\n\nAutomatic checks: "+(Get<CheckBox>("EnableSchedule").IsChecked==true?draft.ScheduleTimes:"off; existing schedules are left unchanged");
        }
        void Capture(){
            draft.Profile=Get<ComboBox>("Device").SelectedValue as string;
            var format=Get<ComboBox>("Format").SelectedItem as ComboBoxItem;if(format==null)throw new Exception("Choose an output format.");draft.Format=Convert.ToString(format.Content);
            draft.MangaStyle=Get<CheckBox>("Manga").IsChecked==true;
            draft.WatchFolder=Text("Watch");draft.ConvertedFolder=Text("Output");draft.ArchiveFolder=Text("Archive");draft.WorkFolder=Text("Work");
            if(String.IsNullOrEmpty(draft.WorkFolder)&&!String.IsNullOrEmpty(draft.WatchFolder)){var parent=Path.GetDirectoryName(draft.WatchFolder.TrimEnd('\\'));if(parent!=null){draft.WorkFolder=Path.Combine(parent,"manga_automation_work");Set("Work",draft.WorkFolder);}}
            draft.KccExe=Text("Kcc");draft.DjxlExe=Text("Jxl");draft.KindlegenExe=Text("Kindle");draft.ConvertJxl=Get<CheckBox>("JxlEnabled").IsChecked==true;
        }
        async Task Next(){
            Capture();
            if(step==0)Desktop.ValidateConversion(draft);
            if(step==1&&!foldersPassed)await CheckFolders();
            if(step==2&&!toolsPassed)await CheckTools();
            if(step==4){draft.ScheduleTimes=Desktop.NormalizeTimes(Text("Times"));int quiet;if(!Int32.TryParse(Text("QuietMinutes"),out quiet)||quiet<0||quiet>1440)throw new Exception("Choose a wait time between 0 and 1440 minutes.");draft.QuietMinutes=quiet;draft.WakeComputer=Get<CheckBox>("Wake").IsChecked==true;}
            if(step==5){draft.SetupCompleted=true;Result=draft;EnableSchedule=Get<CheckBox>("EnableSchedule").IsChecked==true;busy=false;Window.DialogResult=true;return;}
            step++;ShowStep();
        }
        async Task CheckFolders(){Capture();Feedback("Checking folder access. Network folders may take a moment...");string report=await Task.Run(delegate{return SetupChecks.ProbeFolders(draft);});foldersPassed=true;Feedback(report);}
        async Task CheckTools(){Capture();Feedback("Checking that the selected tools can start...");string report=await Task.Run(delegate{return SetupChecks.CheckTools(draft);});toolsPassed=true;Feedback(report);}
        async Task Discover(){
            Capture();Feedback("Looking in common app locations. Nothing will be downloaded or installed...");
            string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var roots=new[]{(String.IsNullOrWhiteSpace(draft.KccExe)?null:Path.GetDirectoryName(draft.KccExe)),appDirectory,@"C:\kindletomanga",Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"KindleComicConverter"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Amazon"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Amazon"),Path.Combine(local,"Amazon"),Path.Combine(local,"Programs","Kindle Previewer 3"),Path.Combine(local,"Programs","Kindle Previewer 4"),Path.Combine(local,"KCCAutomate","Updates")};
            var found=await Task.Run(delegate{return SetupChecks.Discover(roots);});
            if(!File.Exists(Text("Kcc"))&&found.Kcc!=null)Set("Kcc",found.Kcc);if(!File.Exists(Text("Jxl"))&&found.Jxl!=null)Set("Jxl",found.Jxl);if(!File.Exists(Text("Kindle"))&&found.Kindlegen!=null)Set("Kindle",found.Kindlegen);
            Feedback("Search finished. Review the paths, then Check tools. If a tool was not found, select it manually or use its download link.");
        }
        async Task RunTest(){Capture();Desktop.Validate(draft);string book=Text("TestBook");Feedback("Testing a copy of the selected book. The original stays in place...");Get<TextBox>("TestLog").Text="Preparing a verified test copy...";var result=await Task.Run(delegate{return SetupChecks.ConvertTest(draft,book,appDirectory);});testOutput=result.Output;testPassed=result.Passed;Get<TextBox>("TestLog").Text=result.Log;Feedback(result.Passed?"Test conversion passed. Open the results and inspect the book on your reader.":"Test conversion failed. Review the log above and the test working folder; the selected original was retained.");}
        void BrowseFolder(string field){using(var d=new Forms.FolderBrowserDialog{Description="Choose "+field+" folder",ShowNewFolderButton=true}){if(d.ShowDialog()==Forms.DialogResult.OK)Set(field,d.SelectedPath);}}
        void BrowseFile(string field,string filter){var d=new Microsoft.Win32.OpenFileDialog{Filter=filter};if(d.ShowDialog(Window)==true)Set(field,d.FileName);}
        static void Open(string path){Process.Start(new ProcessStartInfo(path){UseShellExecute=true});}
        public void RenderStep(int index){step=index;ShowStep();}
    }
}
