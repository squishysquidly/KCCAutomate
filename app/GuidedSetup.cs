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
        void ShowGuidedSetup() {
            if(running!=null||asyncBusy)throw new Exception("Finish the current operation before changing setup.");
            string books=File.Exists(Path.Combine(baseDir,"portable.flag"))?Path.Combine(userDir,"Books"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"KCCAutomate");
            var wizard=new SetupWizard(Window,saved,Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),userDir,books);
            if(wizard.Window.ShowDialog()!=true)return;
            Fill(wizard.Result);saved.SetupCompleted=true;var settings=Save();
            if(wizard.EnableSchedule)Start("Manage-Schedule.ps1","-Action Enable","Saving your automatic-check schedule...",false,settings);
            else Status("Setup saved. Preview the queue before your first full run. Existing schedules were not changed.");
        }
        void TestGuidedSetup(List<string> results,string directory) {
            string root=Path.Combine(directory,"setup-fixtures-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
            var settings=new Settings{WatchFolder=Path.Combine(root,"in"),ConvertedFolder=Path.Combine(root,"out"),ArchiveFolder=Path.Combine(root,"archive"),WorkFolder=Path.Combine(root,"work")};
            Directory.CreateDirectory(settings.WatchFolder);File.WriteAllText(Path.Combine(settings.WatchFolder,"keep.cbz"),"keep original");
            SetupChecks.ProbeFolders(settings);
            if(File.ReadAllText(Path.Combine(settings.WatchFolder,"keep.cbz"))!="keep original"||Directory.GetFiles(settings.WatchFolder).Length!=1)throw new Exception("Folder access probe changed user files or left a probe behind.");
            settings.ArchiveFolder=Path.Combine(settings.WatchFolder,"nested");
            try{SetupChecks.ProbeFolders(settings);throw new Exception("Nested wizard folder accepted");}catch(Exception ex){if(!ex.Message.Contains("four folders"))throw;}
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
            var wizard=new SetupWizard(Window,new Settings(),Find<System.Windows.Controls.ComboBox>("Profile").ItemsSource.Cast<Device>(),userDir,Path.Combine(root,"default-books"));
            wizard.TestToolControls(results);
            string fixtureSource=Path.Combine(root,"ToolFixtures.cs");
            File.WriteAllText(fixtureSource,@"using System;using System.IO;using System.Threading;class Fixture{static int Main(){string name=Path.GetFileName(Environment.GetCommandLineArgs()[0]);if(name==""kindlegen.exe""){Console.WriteLine(""Amazon kindlgen(Windows) V2.0 build 0000-kdevld\nA command line e-book compiler"");return 1;}if(name==""djxl.exe""){Console.WriteLine(""JPEG XL decoder djxl"");return 0;}Thread.Sleep(350);Console.WriteLine(""comic2ebook v12.0.0 --profile --format"");return 0;}}");
            string compiler=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"Microsoft.NET\Framework64\v4.0.30319\csc.exe");
            var compiled=SetupChecks.Run(compiler,"/nologo /target:exe /out:"+Quote(Path.Combine(tools,"kcc-c2e.exe"))+" "+Quote(fixtureSource),20000);
            if(compiled.Item1!=0)throw new Exception("Automatic-check fixture failed to compile: "+compiled.Item2);
            File.Copy(Path.Combine(tools,"kcc-c2e.exe"),Path.Combine(tools,"djxl.exe"),true);File.Copy(Path.Combine(tools,"kcc-c2e.exe"),Path.Combine(tools,@"Kindle Previewer 4\lib\fc\bin\kindlegen.exe"),true);
            var oldContext=System.Threading.SynchronizationContext.Current;System.Threading.SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Window.Dispatcher));
            var automatic=wizard.TestAutomaticTools(tools,results);var frame=new DispatcherFrame();
            var timeout=new DispatcherTimer{Interval=TimeSpan.FromSeconds(45)};bool timedOut=false;timeout.Tick+=delegate{timedOut=true;frame.Continue=false;};timeout.Start();
            automatic.ContinueWith(delegate{Window.Dispatcher.BeginInvoke(new Action(delegate{frame.Continue=false;}));});Dispatcher.PushFrame(frame);timeout.Stop();
            System.Threading.SynchronizationContext.SetSynchronizationContext(oldContext);if(timedOut)throw new Exception("Automatic setup validation timed out.");automatic.GetAwaiter().GetResult();
            var content=(FrameworkElement)wizard.Window.Content;content.Measure(new Size(960,700));content.Arrange(new Rect(0,0,960,700));
            for(int i=0;i<6;i++) {
                wizard.RenderStep(i);content.UpdateLayout();var bitmap=new RenderTargetBitmap(960,700,96,96,PixelFormats.Pbgra32);bitmap.Render(content);
                var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(Path.Combine(directory,"wizard-"+i+".png")))encoder.Save(stream);
            }
            wizard.RenderStep(2);var toolScroll=(System.Windows.Controls.ScrollViewer)wizard.Window.FindName("ToolScroll");toolScroll.ScrollToEnd();content.UpdateLayout();
            var bottom=new RenderTargetBitmap(960,700,96,96,PixelFormats.Pbgra32);bottom.Render(content);var bottomEncoder=new PngBitmapEncoder();bottomEncoder.Frames.Add(BitmapFrame.Create(bottom));using(var stream=File.Create(Path.Combine(directory,"wizard-tools-bottom.png")))bottomEncoder.Save(stream);
            results.Add("PASS: all six wizard pages load and render without launching a conversion or schedule");
        }
    }
}
