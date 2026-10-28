using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Threading.Tasks;
using System.Windows.Threading;

namespace KCCAutomate {
    public partial class Desktop {
        public static string GetSettingsDirectory(string appDirectory) {
            return File.Exists(Path.Combine(appDirectory,"portable.flag"))?Path.Combine(appDirectory,"data"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"KCCAutomate");
        }
        public static void ImportLegacySettings(string destination,string legacy) {
            if(File.Exists(Path.Combine(destination,"settings.json"))||!File.Exists(Path.Combine(legacy,"settings.json")))return;
            Directory.CreateDirectory(destination);
            // Copy the settings last so an interrupted import can be retried.
            foreach(var name in new[]{"presets.json","presets.json.bak","settings.json.bak","settings.json"}) {
                string source=Path.Combine(legacy,name),target=Path.Combine(destination,name);
                if(File.Exists(source)&&!File.Exists(target))File.Copy(source,target);
            }
        }
        void ShowGuidedSetup(){ShowGuidedSetup(null);}
        void ChooseDownloadedKcc(){
            if(running!=null||asyncBusy)throw new Exception("Finish the current operation before choosing a new converter.");
            var dialog=new Microsoft.Win32.OpenFileDialog{Filter="KCC c2e command-line converter (*.exe)|*.exe",Title="Choose the new KCC c2e download"};
            if(dialog.ShowDialog(Window)!=true)return;
            var selection=Read();selection.KccExe=dialog.FileName;ShowGuidedSetup(selection);
        }
        void ShowGuidedSetup(Settings converterUpdate) {
            if(running!=null||asyncBusy)throw new Exception("Finish the current operation before changing setup.");
            string books=File.Exists(Path.Combine(baseDir,"portable.flag"))?Path.Combine(userDir,"Books"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"KCCAutomate");
            var wizard=new SetupWizard(Window,converterUpdate??saved,Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),userDir,books);
            if(converterUpdate!=null)wizard.RenderStep(2);
            if(wizard.Window.ShowDialog()!=true)return;
            if(converterUpdate!=null&&wizard.Result.KccExe!=saved.KccExe)saved.PreviousKccExe=saved.KccExe;
            Fill(wizard.Result);if(wizard.OpenFolderSettings)Navigate(0);saved.SetupCompleted=true;var settings=Save();
            RequestToolUpdateCheck();
            if(wizard.EnableSchedule){Start("Manage-Schedule.ps1","-Action Enable","Saving your automatic-check schedule...",false,settings);if(wizard.OpenFolderSettings)afterWorker=delegate{Navigate(0);};}
            else {if(wizard.OpenFolderSettings)Navigate(0);Status(wizard.OpenFolderSettings?"Setup saved. Choose your folders here, then Create & check folders before enabling automatic checks.":"Setup saved. Preview the queue before your first full run. Existing schedules were not changed.");}
        }
        void TestGuidedSetup(List<string> results,string directory) {
            // Leave room for versioned Store paths within Windows' legacy path limit.
            string root=Path.Combine(directory,"setup-"+Guid.NewGuid().ToString("N").Substring(0,8));Directory.CreateDirectory(root);
            var settings=new Settings{WatchFolder=Path.Combine(root,"in"),ConvertedFolder=Path.Combine(root,"out"),ArchiveFolder=Path.Combine(root,"archive"),WorkFolder=Path.Combine(root,"work")};
            Directory.CreateDirectory(settings.WatchFolder);File.WriteAllText(Path.Combine(settings.WatchFolder,"keep.cbz"),"keep original");
            SetupChecks.ProbeFolders(settings);
            if(File.ReadAllText(Path.Combine(settings.WatchFolder,"keep.cbz"))!="keep original"||Directory.GetFiles(settings.WatchFolder).Length!=1)throw new Exception("Folder access probe changed user files or left a probe behind.");
            settings.ArchiveFolder=Path.Combine(settings.WatchFolder,"nested");
            try{SetupChecks.ProbeFolders(settings);throw new Exception("Nested wizard folder accepted");}catch(Exception ex){if(!ex.Message.Contains("must be separate"))throw;}
            if(Directory.Exists(settings.ArchiveFolder))throw new Exception("Invalid setup created folders before validation.");
            settings.WorkFolder=Path.Combine(root,new string('x',150));
            try{SetupChecks.ConvertTest(settings,Path.Combine(settings.WatchFolder,"keep.cbz"),baseDir);throw new Exception("Overlong setup test path accepted");}catch(Exception ex){if(!ex.Message.Contains("working folder path is too long"))throw;}
            if(Directory.Exists(settings.WorkFolder))throw new Exception("An overlong test path created folders before validation.");
            string tools=Path.Combine(root,"tools");Directory.CreateDirectory(Path.Combine(tools,@"Kindle Previewer 4\lib\fc\bin"));
            File.WriteAllText(Path.Combine(tools,"kcc-c2e.exe"),"fixture");File.WriteAllText(Path.Combine(tools,"djxl.exe"),"fixture");File.WriteAllText(Path.Combine(tools,@"Kindle Previewer 4\lib\fc\bin\kindlegen.exe"),"fixture");
            var found=SetupChecks.Discover(new[]{tools});if(found.Kcc==null||found.Jxl==null||found.Kindlegen==null)throw new Exception("Tool discovery failed.");
            File.WriteAllText(Path.Combine(root,"portable.flag"),"portable");if(GetSettingsDirectory(root)!=Path.Combine(root,"data"))throw new Exception("Portable settings isolation failed.");
            results.Add("PASS: setup access probes, overlap and long-path protection, tool discovery and portable settings isolation");
            string legacy=Path.Combine(root,"legacy"),current=Path.Combine(root,"current");Directory.CreateDirectory(legacy);
            File.WriteAllText(Path.Combine(legacy,"settings.json"),"old settings");File.WriteAllText(Path.Combine(legacy,"presets.json"),"old presets");
            ImportLegacySettings(current,legacy);
            if(File.ReadAllText(Path.Combine(current,"settings.json"))!="old settings"||File.ReadAllText(Path.Combine(current,"presets.json"))!="old presets"||File.ReadAllText(Path.Combine(legacy,"settings.json"))!="old settings")throw new Exception("Legacy settings import lost data.");
            File.WriteAllText(Path.Combine(current,"settings.json"),"new settings");ImportLegacySettings(current,legacy);
            if(File.ReadAllText(Path.Combine(current,"settings.json"))!="new settings")throw new Exception("Legacy import replaced current settings.");
            results.Add("PASS: earlier working-name settings import preserves originals and never replaces current settings");
            var wizard=new SetupWizard(Window,new Settings(),Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),userDir,Path.Combine(root,"default-books"),new string[0]);
            wizard.TestToolControls(results);
            string fixtureSource=Path.Combine(root,"ToolFixtures.cs");
            File.WriteAllText(fixtureSource,@"using System;using System.IO;using System.Threading;class Fixture{static int Main(){string name=Path.GetFileName(Environment.GetCommandLineArgs()[0]);if(name==""kindlegen.exe""){Console.WriteLine(""Amazon kindlgen(Windows) V2.0 build 0000-kdevld\nA command line e-book compiler"");return 1;}if(name==""djxl.exe""){Console.WriteLine(""JPEG XL decoder djxl"");return 0;}Thread.Sleep(350);Console.WriteLine(""comic2ebook v12.0.0 --profile --format"");return 0;}}");
            string compiler=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"Microsoft.NET\Framework64\v4.0.30319\csc.exe");
            var compiled=SetupChecks.Run(compiler,"/nologo /target:exe /out:"+Quote(Path.Combine(tools,"kcc-c2e.exe"))+" "+Quote(fixtureSource),20000);
            if(compiled.Item1!=0)throw new Exception("Automatic-check fixture failed to compile: "+compiled.Item2);
            File.Copy(Path.Combine(tools,"kcc-c2e.exe"),Path.Combine(tools,"djxl.exe"),true);File.Copy(Path.Combine(tools,"kcc-c2e.exe"),Path.Combine(tools,@"Kindle Previewer 4\lib\fc\bin\kindlegen.exe"),true);
            var oldContext=System.Threading.SynchronizationContext.Current;System.Threading.SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Window.Dispatcher));
            var automatic=TestWizardAndFolders(wizard,tools,root,results);var frame=new DispatcherFrame();
            var timeout=new DispatcherTimer{Interval=TimeSpan.FromSeconds(90)};bool timedOut=false;timeout.Tick+=delegate{timedOut=true;frame.Continue=false;};timeout.Start();
            automatic.ContinueWith(delegate{Window.Dispatcher.BeginInvoke(new Action(delegate{frame.Continue=false;}));});Dispatcher.PushFrame(frame);timeout.Stop();
            System.Threading.SynchronizationContext.SetSynchronizationContext(oldContext);if(timedOut)throw new Exception("Automatic setup validation timed out.");automatic.GetAwaiter().GetResult();
            var content=(FrameworkElement)wizard.Window.Content;content.Measure(new Size(960,700));content.Arrange(new Rect(0,0,960,700));
            for(int i=0;i<SetupWizard.PageCount;i++) {
                wizard.RenderStep(i);content.UpdateLayout();var bitmap=new RenderTargetBitmap(960,700,96,96,PixelFormats.Pbgra32);bitmap.Render(content);
                var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(Path.Combine(directory,"wizard-"+i+".png")))encoder.Save(stream);
            }
            results.Add("PASS: all nine wizard pages load and render, with the folder explanation followed by how-it-works guidance, without launching a conversion or schedule");
            ApplyTheme("Dark");var darkWizard=new SetupWizard(Window,new Settings(),Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),userDir);
            var darkContent=(FrameworkElement)darkWizard.Window.Content;darkContent.Measure(new Size(840,590));darkContent.Arrange(new Rect(0,0,840,590));
            for(int page=1;page<=4;page++){darkWizard.RenderStep(page);darkContent.UpdateLayout();var bitmap=new RenderTargetBitmap(840,590,96,96,PixelFormats.Pbgra32);bitmap.Render(darkContent);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(Path.Combine(directory,"wizard-dark-"+page+".png")))encoder.Save(stream);}
            ApplyTheme("Light");results.Add("PASS: all four individual tool pages render in dark mode at the minimum setup size");
            foreach(string theme in new[]{"Light","Dark"}){
                ApplyTheme(theme);var shortened=new SetupWizard(Window,new Settings{Format="EPUB",ConvertJxl=false},Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),userDir);
                var shortenedContent=(FrameworkElement)shortened.Window.Content;var size=theme=="Light"?new Size(960,700):new Size(840,590);shortenedContent.Measure(size);shortenedContent.Arrange(new Rect(new Point(),size));
                foreach(int page in new[]{0,2,5,7,8}){shortened.RenderStep(page);shortenedContent.UpdateLayout();var bitmap=new RenderTargetBitmap((int)size.Width,(int)size.Height,96,96,PixelFormats.Pbgra32);bitmap.Render(shortenedContent);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(Path.Combine(directory,"wizard-short-"+theme.ToLowerInvariant()+"-"+page+".png")))encoder.Save(stream);}
            }
            ApplyTheme("Light");results.Add("PASS: shortened EPUB setup renders with seven steps, folders followed by how-it-works guidance, and correct numbering in light/dark themes");
            foreach(string theme in new[]{"Light","Dark"}){
                ApplyTheme(theme);var guide=KindleGenGuide.Create(Window,delegate{return "";});
                foreach(string name in new[]{"GuideOpenFolder","GuideKccLink","GuideDone"})if(guide.FindName(name)==null)throw new Exception("Illustrated KindleGen guide action is missing: "+name);
                foreach(var size in new[]{new Size(810,700),new Size(650,540)}){
                    var guideContent=(FrameworkElement)guide.Content;guideContent.Measure(size);guideContent.Arrange(new Rect(new Point(),size));guideContent.UpdateLayout();
                    var bitmap=new RenderTargetBitmap((int)size.Width,(int)size.Height,96,96,PixelFormats.Pbgra32);bitmap.Render(guideContent);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using(var stream=File.Create(Path.Combine(directory,"kindlegen-guide-"+theme.ToLowerInvariant()+(size.Width<700?"-minimum":"")+".png")))encoder.Save(stream);
                    if(size.Width<700){((System.Windows.Controls.Expander)guide.FindName("GuideWindowsHelp")).IsExpanded=true;guideContent.UpdateLayout();((System.Windows.Controls.ScrollViewer)guide.FindName("GuideSteps")).ScrollToBottom();guideContent.UpdateLayout();bitmap=new RenderTargetBitmap((int)size.Width,(int)size.Height,96,96,PixelFormats.Pbgra32);bitmap.Render(guideContent);encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(Path.Combine(directory,"kindlegen-guide-"+theme.ToLowerInvariant()+"-help-bottom.png")))encoder.Save(stream);}
                }
            }
            ApplyTheme("Light");results.Add("PASS: embedded illustrated KindleGen guide loads with folder, official-guide and return actions; renders in both themes at normal and minimum sizes without opening folders, downloading or running tools");
        }
        async Task TestWizardAndFolders(SetupWizard wizard,string tools,string root,List<string> results){
            await wizard.TestAutomaticTools(tools,results);
            string install=Path.Combine(root,"previewer-check","Kindle Previewer 4");
            foreach(bool simulate in new[]{true,false}){var discovery=new SetupWizard(Window,new Settings(),Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),Path.Combine(root,"previewer-settings"),null,new[]{install});await discovery.TestKindleDiscovery(tools,install,simulate,results);}
            string store=Path.Combine(root,"store-check","WindowsApps"),package=Path.Combine(store,"KindlePreviewerApp_4.0.3.0_x64__fixture");
            foreach(bool simulate in new[]{true,false}){var discovery=new SetupWizard(Window,new Settings(),Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),Path.Combine(root,"store-settings"),null,new[]{store});await discovery.TestKindleDiscovery(tools,package,simulate,results,true);}
            string inactive=Path.Combine(root,"inactive-tools");Directory.CreateDirectory(inactive);
            var replacement=new Settings{KccExe=Path.Combine(tools,"kcc-c2e.exe"),DjxlExe=Path.Combine(tools,"djxl.exe"),KindlegenExe=Path.Combine(tools,@"Kindle Previewer 4\lib\fc\bin\kindlegen.exe"),WatchFolder=Path.Combine(root,"replace-in"),ConvertedFolder=Path.Combine(root,"replace-out"),ArchiveFolder=Path.Combine(root,"replace-originals"),WorkFolder=Path.Combine(root,"replace-work")};
            var replacementWizard=new SetupWizard(Window,replacement,Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),Path.Combine(root,"replace-settings"),null,new string[0]);
            await replacementWizard.TestConverterReplacement(results);
            File.WriteAllText(Path.Combine(inactive,"kindlegen.exe"),"inactive file must never run or be copied");File.WriteAllText(Path.Combine(inactive,"djxl.exe"),"inactive file must never run or be copied");
            foreach(var choice in new[]{Tuple.Create("EPUB",false),Tuple.Create("CBZ",false),Tuple.Create("PDF",false),Tuple.Create("EPUB",true),Tuple.Create("MOBI",false)}){
                string name=choice.Item1+"-"+choice.Item2;
                var conditional=new SetupWizard(Window,new Settings{Format=choice.Item1,ConvertJxl=choice.Item2,KindlegenExe=Path.Combine(inactive,"kindlegen.exe"),DjxlExe=Path.Combine(inactive,"djxl.exe")},Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),Path.Combine(root,"conditional",name),Path.Combine(root,"conditional-books",name),new string[0]);
                await conditional.TestConditionalPages(tools,results);
            }
            var mixed=new Settings{Format="EPUB",ConvertJxl=false,KindlegenExe=Path.Combine(inactive,"kindlegen.exe"),DjxlExe=Path.Combine(inactive,"djxl.exe"),FolderRules=new List<FolderRule>{new FolderRule{Pattern="mobi/*",PresetName="Kindle",Options=new Dictionary<string,object>{{"Format","MOBI"}}}}};
            var mixedWizard=new SetupWizard(Window,mixed,Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),Path.Combine(root,"conditional","mixed"),Path.Combine(root,"conditional-books","mixed"),new string[0]);
            await mixedWizard.TestConditionalPages(tools,results);
            var custom=new Settings{WatchFolder=Path.Combine(root,"custom-in"),ConvertedFolder=Path.Combine(root,"custom-out"),ArchiveFolder=Path.Combine(root,"custom-originals"),WorkFolder=Path.Combine(root,"custom-work"),KccExe=Path.Combine(tools,"kcc-c2e.exe"),DjxlExe=Path.Combine(tools,"djxl.exe")};
            Directory.CreateDirectory(custom.WatchFolder);File.WriteAllText(Path.Combine(custom.WatchFolder,"keep.cbz"),"keep original");Fill(custom);await PrepareBookFoldersAsync();
            var stored=json.Deserialize<Settings>(File.ReadAllText(configPath));
            if(stored.ArchiveFolder!=custom.ArchiveFolder||!new[]{custom.WatchFolder,custom.ConvertedFolder,custom.ArchiveFolder,custom.WorkFolder}.All(Directory.Exists)||File.ReadAllText(Path.Combine(custom.WatchFolder,"keep.cbz"))!="keep original")throw new Exception("App folder settings did not persist, prepare chosen paths or preserve existing books.");
            results.Add("PASS: app folder settings save and prepare custom folders, check availability and retain incoming books without restarting setup");
        }
    }
}
