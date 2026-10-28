using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace KCCAutomate {
    public class InterfacePreferences {
        public string ViewMode { get; set; }
    }
    public partial class Desktop {
        string viewMode="Simple";
        bool interfaceReady;
        string interfacePath {get{return Path.Combine(userDir,"interface.json");}}
        static readonly string[] AdvancedOnly={"AdvancedWork","AdvancedToolsCard","AdvancedPresetManagement","AdvancedImageControls","AdvancedFileControls","AdvancedCleanupOptions","AdvancedQuietHours","AdvancedRulesCard","AdvancedRepository","AdvancedScheduleControls","RollbackUpdate"};
        static readonly string[] SimpleOnly={"SimpleWorkSummary","SimpleToolsCard","SimpleImageNote","SimpleFileSummary","SimpleSettingsCard","SimpleUpdateSource","SimpleScheduleSummary"};

        public static string LoadInterfaceMode(string path) {
            if(!File.Exists(path))return "Simple";
            try {var p=new JavaScriptSerializer().Deserialize<InterfacePreferences>(File.ReadAllText(path));return p!=null&&p.ViewMode=="Advanced"?"Advanced":"Simple";}
            catch(ArgumentException){return "Simple";}catch(IOException){return "Simple";}catch(UnauthorizedAccessException){return "Simple";}catch(InvalidOperationException){return "Simple";}
        }
        void InitializeInterfaceModes() {
            On("SimpleView",delegate{SetViewMode("Simple",true);});
            On("AdvancedView",delegate{SetViewMode("Advanced",true);});
            On("ShowAdvancedConversion",delegate{ShowAdvancedPage(1,"AdvancedImageControls");});
            On("ShowAdvancedSettings",delegate{ShowAdvancedPage(5,"AdvancedCleanupCard");});
            On("ShowAdvancedTools",delegate{ShowAdvancedPage(0,"AdvancedToolsCard");});
            interfaceReady=true;SetViewMode(LoadInterfaceMode(interfacePath),false);
        }
        void ShowAdvancedPage(int page,string section) {
            SetViewMode("Advanced",true);Navigate(page);Window.UpdateLayout();Find<FrameworkElement>(section).BringIntoView();
        }
        void SetViewMode(string mode,bool remember) {
            if(mode!="Simple"&&mode!="Advanced")throw new ArgumentException("Choose Simple or Advanced view.");
            viewMode=mode;bool advanced=mode=="Advanced";
            foreach(var name in AdvancedOnly)Find<FrameworkElement>(name).Visibility=advanced?Visibility.Visible:Visibility.Collapsed;
            foreach(var name in SimpleOnly)Find<FrameworkElement>(name).Visibility=advanced?Visibility.Collapsed:Visibility.Visible;
            foreach(var column in Find<DataGrid>("QueueGrid").Columns.Where(c=>Convert.ToString(c.Header)=="JXL pages"))column.Visibility=advanced?Visibility.Visible:Visibility.Collapsed;
            foreach(var name in new[]{"Simple","Advanced"}) {
                var button=Find<Button>(name+"View");bool selected=name==mode;
                if(selected){button.Background=new SolidColorBrush(Color.FromRgb(35,101,76));button.Foreground=Brushes.White;}
                else{button.SetResourceReference(Control.BackgroundProperty,"SurfaceBrush");button.SetResourceReference(Control.ForegroundProperty,"TextBrush");}
                System.Windows.Automation.AutomationProperties.SetHelpText(button,selected?"Selected view":"Switch view without changing conversion settings");
            }
            Find<TextBlock>("ViewDescription").Text=advanced?"All settings are available. Switching views keeps your current options.":"Everyday controls. Your saved advanced settings still apply.";
            RefreshSimpleSummaries();
            if(remember) {
                try {
                    Directory.CreateDirectory(userDir);string temp=interfacePath+".tmp";
                    File.WriteAllText(temp,json.Serialize(new InterfacePreferences{ViewMode=mode}),new UTF8Encoding(false));
                    if(File.Exists(interfacePath))File.Replace(temp,interfacePath,interfacePath+".bak");else File.Move(temp,interfacePath);
                } catch(Exception ex){throw new Exception("The view changed, but your choice could not be saved: "+ex.Message);}
            }
        }
        bool Checked(string name){return Find<CheckBox>(name).IsChecked==true;}
        static string ToolName(string path){try{return String.IsNullOrWhiteSpace(path)?"not selected":Path.GetFileName(path);}catch(ArgumentException){return "path needs checking";}}
        void RefreshSimpleSummaries() {
            if(!interfaceReady)return;
            Find<TextBlock>("SimpleWorkSummary").Text=Text("WorkFolder").Length>0?"Working folder: "+Text("WorkFolder"):"A separate working folder will be suggested beside incoming downloads.";
            Find<TextBlock>("SimpleToolsSummary").Text="Selected KCC: "+ToolName(Text("KccExe"))+"\nJPEG XL preparation: "+(Checked("ConvertJxl")?ToolName(Text("DjxlExe")):"off")+(ComboText("OutputFormat")=="MOBI"?"\nKindleGen: "+(Text("KindlegenExe").Length>0?ToolName(Text("KindlegenExe")):"let KCC find it"):"");
            var image=new List<string>{Checked("Stretch")?"Stretching enabled (changes proportions)":"Page proportions preserved"};
            image.Add(Checked("NoAutocontrast")?"automatic contrast off":"automatic contrast");
            if(Checked("Autolevel"))image.Add("stronger blacks");
            if(Checked("ForceColor"))image.Add("keep color");
            bool scribe=Checked("ScribeCompatibility")&&Convert.ToString(Find<ComboBox>("Profile").SelectedValue)=="KS"&&(ComboText("OutputFormat")=="MOBI"||ComboText("OutputFormat")=="EPUB");
            Find<FrameworkElement>("ScribeCompatibilityCard").Visibility=Convert.ToString(Find<ComboBox>("Profile").SelectedValue)=="KS"?Visibility.Visible:Visibility.Collapsed;
            if(scribe)image.Add("Scribe compatibility: JPEG, no cropping, 1860 × 1920 limit");else if(Checked("ForcePng"))image.Add("PNG output");
            if(Checked("Webtoon"))image.Add("webtoon mode");
            image.Add(Text("Gamma")=="0"?"automatic gamma":"gamma "+Text("Gamma"));
            Find<TextBlock>("SimpleImageSummary").Text=String.Join(" · ",image)+". These options also apply in Simple view.";
            string ruleText=rules.Count+" folder rule"+(rules.Count==1?"":"s")+" configured";
            Find<TextBlock>("DuplicateDescription").Text=DuplicateDescription();
            Find<TextBlock>("SimpleFileSummary").Text="Naming: "+Text("OutputNaming")+". "+ruleText+".";
            Find<TextBlock>("SimpleSettingsSummary").Text="Completed conversion scratch files: cleared automatically.\n"+(Checked("AutoCleanup")?"Diagnostic expiry: on (successful logs "+Text("SuccessRetentionDays")+" days; unsuccessful attempts "+Text("FailureRetentionDays")+" days).":"Diagnostic expiry: off; logs and unsuccessful attempts are retained.")+"\n"+ruleText+".\nNotification quiet hours: "+(Checked("QuietHoursEnabled")?Text("QuietHoursStart")+" to "+Text("QuietHoursEnd"):"off")+". These preferences keep applying in Simple view.";
            Find<TextBlock>("SimpleUpdateSource").Text="App update source: "+(Text("UpdateRepository").Length>0?Text("UpdateRepository"):"not set")+". KCC and JPEG XL checks use their latest official releases. Choose your downloaded KCC CLI in setup to validate it.";
            Find<TextBlock>("SimpleScheduleSummary").Text="Wait after files change: "+Text("QuietMinutes")+" minutes. Move completed downloads into the incoming folder.";
        }

        void RenderInterface(string path,int width,int height) {
            var root=(FrameworkElement)Window.Content;root.Measure(new Size(width,height));root.Arrange(new Rect(0,0,width,height));root.UpdateLayout();
            var bitmap=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32);bitmap.Render(root);
            var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(path))encoder.Save(stream);
        }
        void RenderSection(string name,string path) {
            RenderInterface(path,1180,850);
            var target=Find<FrameworkElement>(name);DependencyObject parent=target;
            while(parent!=null&&!(parent is ScrollViewer))parent=VisualTreeHelper.GetParent(parent);
            var scroll=parent as ScrollViewer;
            if(scroll!=null){var content=scroll.Content as UIElement;if(content!=null){scroll.ScrollToVerticalOffset(Math.Max(0,target.TranslatePoint(new Point(0,0),content).Y-12));scroll.UpdateLayout();}}
            RenderInterface(path,1180,850);
        }
        static object SortJson(object value) {
            var fields=value as IDictionary<string,object>;
            if(fields!=null){var sorted=new SortedDictionary<string,object>(StringComparer.Ordinal);foreach(var field in fields)sorted[field.Key]=SortJson(field.Value);return sorted;}
            var items=value as object[];return items==null?value:items.Select(SortJson).ToArray();
        }
        string ComparableSettings(Settings settings){return json.Serialize(SortJson(json.DeserializeObject(json.Serialize(settings))));}
        void TestInterfaceModes(List<string> results,string directory) {
            string root=Path.Combine(directory,"interface-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
            string fixture=Path.Combine(root,"interface.json");
            if(LoadInterfaceMode(fixture)!="Simple")throw new Exception("Missing view preferences did not default to Simple.");
            File.WriteAllText(fixture,"broken JSON");
            if(LoadInterfaceMode(fixture)!="Simple"||File.ReadAllText(fixture)!="broken JSON")throw new Exception("Damaged view preference was not preserved.");
            File.WriteAllText(fixture,"{\"ViewMode\":\"Unknown\"}");if(LoadInterfaceMode(fixture)!="Simple")throw new Exception("Unknown view was accepted.");

            var settings=new Settings{KccExe=@"C:\tools\kcc-c2e.exe",DjxlExe=@"C:\tools\djxl.exe",WatchFolder=@"C:\test\in",ConvertedFolder=@"C:\test\out",ArchiveFolder=@"C:\test\archive",WorkFolder=@"C:\test\work",Gamma=1.2,Stretch=true,Autolevel=true,ForcePng=true,OverwriteConverted=true,OutputNaming="{name} - {profile}",AutoCleanup=true,QuietHoursEnabled=true,QuietMinutes=45,InputExtensions=new[]{".cbz",".pdf"}};
            settings.BundleChapters=true;settings.BundleTargetPages=235;settings.ChapterPageThreshold=120;settings.BundleMaxMiB=300;settings.HoldShortBundles=false;
            settings.BookTitleStyle="NumberFirst";settings.CoverNumberBadge=true;settings.SeriesAliases.Add("A Long Series","Short");settings.BundleVolumes=true;settings.VolumeTargetPages=800;
            var preset=new Preset{Name="View preservation fixture",Options=Options(settings)};presets.Add(preset);
            settings.FolderRules.Add(new FolderRule{Pattern="Series\\*",PresetName=preset.Name});Fill(settings);Navigate(1);Find<ComboBox>("Presets").SelectedItem=preset;
            var chapterSettings=Read();if(!chapterSettings.BundleChapters||chapterSettings.BundleTargetPages!=235||chapterSettings.ChapterPageThreshold!=120||chapterSettings.BundleMaxMiB!=300||chapterSettings.HoldShortBundles)throw new Exception("Chapter grouping settings did not survive the UI round trip.");
            if(chapterSettings.BookTitleStyle!="NumberFirst"||!chapterSettings.CoverNumberBadge||chapterSettings.SeriesAliases["A Long Series"]!="Short"||!chapterSettings.BundleVolumes||chapterSettings.VolumeTargetPages!=800)throw new Exception("Readable labels or whole-volume settings did not survive the UI round trip.");
            Find<ComboBox>("BookTitleStyle").SelectedIndex=3;
            if(Read().BookTitleStyle!="Clean")throw new Exception("Clean filename style did not survive the UI round trip.");
            Find<ComboBox>("BookTitleStyle").SelectedIndex=2;
            string draft=ComparableSettings(Read()),savedHash=ReleaseClient.Hash(configPath),presetsHash=ReleaseClient.Hash(presetPath),dirty=Find<TextBlock>("SavedState").Text;
            var page=Find<TabControl>("Pages").SelectedItem;
            SetViewMode("Advanced",true);SetViewMode("Simple",true);
            if(viewMode!="Simple"||LoadInterfaceMode(interfacePath)!="Simple"||Find<TabControl>("Pages").SelectedItem!=page)throw new Exception("View choice or current page was lost.");
            if(Find<ComboBox>("Presets").SelectedItem!=preset||running!=null)throw new Exception("Switching views changed the selected preset or started a worker.");
            if(AdvancedOnly.Any(n=>Find<FrameworkElement>(n).Visibility!=Visibility.Collapsed)||SimpleOnly.Any(n=>Find<FrameworkElement>(n).Visibility!=Visibility.Visible))throw new Exception("Simple view exposes an advanced group or hides an everyday group.");
            string after=ComparableSettings(Read());
            if(after!=draft){File.WriteAllText(Path.Combine(root,"draft-before.json"),draft);File.WriteAllText(Path.Combine(root,"draft-after.json"),after);throw new Exception("Switching views changed conversion settings. Details: "+root);}
            if(ReleaseClient.Hash(configPath)!=savedHash)throw new Exception("Switching views saved the conversion file.");
            if(ReleaseClient.Hash(presetPath)!=presetsHash)throw new Exception("Switching views changed the preset file.");
            if(Find<TextBlock>("SavedState").Text!=dirty)throw new Exception("Switching views changed the unsaved-edit indicator: "+dirty+" -> "+Find<TextBlock>("SavedState").Text);
            if(!Find<TextBlock>("SimpleImageSummary").Text.Contains("Stretching enabled")||!Find<TextBlock>("SimpleImageSummary").Text.Contains("gamma 1.2")||!Find<TextBlock>("DuplicateDescription").Text.Contains("replaced")||!Find<TextBlock>("SimpleSettingsSummary").Text.Contains("1 folder rule"))throw new Exception("Simple view hid an active advanced setting without a summary.");
            var stored=Save();
            if(ComparableSettings(stored)!=draft)throw new Exception("Saving in Simple view changed advanced settings.");
            Find<TextBox>("Gamma").Text="unfinished";SetViewMode("Advanced",true);SetViewMode("Simple",true);
            if(Text("Gamma")!="unfinished")throw new Exception("View switching discarded an incomplete edit.");
            Find<TextBox>("Gamma").Text="1.2";
            SetViewMode("Advanced",true);
            if(AdvancedOnly.Any(n=>Find<FrameworkElement>(n).Visibility!=Visibility.Visible)||SimpleOnly.Any(n=>Find<FrameworkElement>(n).Visibility!=Visibility.Collapsed))throw new Exception("Advanced view did not restore all detailed controls.");
            if(LoadInterfaceMode(interfacePath)!="Advanced")throw new Exception("Advanced view preference was not remembered.");
            var reopened=new Desktop(true,userDir);
            if(reopened.viewMode!="Advanced")throw new Exception("Reopening did not restore the view preference.");
            reopened.closing=true;reopened.Window.Close();
            results.Add("PASS: Simple/Advanced switching and reopening preserve drafts, hidden settings, presets, page selection and conversion-file contents");
            results.Add("PASS: Simple-view save retains advanced options; incomplete edits survive switching; active settings are summarized");
            results.Add("PASS: view preference is independent, remembered and defaults safely when absent, damaged or unknown");

            Find<ComboBox>("OriginalsAction").SelectedIndex=1;
            if(Checked("DeleteOriginalsConfirmed")||Find<FrameworkElement>("DeleteOriginalsWarning").Visibility!=Visibility.Visible||Find<TextBox>("ArchiveFolder").IsEnabled)throw new Exception("Deletion choice did not show its warning and disable the unused archive folder.");
            bool rejected=false;try{Read();}catch(Exception){rejected=true;}if(!rejected)throw new Exception("Unacknowledged source deletion was accepted.");
            Find<CheckBox>("DeleteOriginalsConfirmed").IsChecked=true;
            var removal=Read();if(removal.OriginalsAction!="Delete"||!removal.DeleteOriginalsConfirmed)throw new Exception("Acknowledged removal settings were not preserved.");
            RenderSection("DeleteOriginalsWarning",Path.Combine(directory,"screen-originals-warning.png"));
            Find<ComboBox>("OriginalsAction").SelectedIndex=0;
            if(Checked("DeleteOriginalsConfirmed")||Find<FrameworkElement>("DeleteOriginalsWarning").Visibility!=Visibility.Collapsed||!Find<TextBox>("ArchiveFolder").IsEnabled)throw new Exception("Returning to Archive did not reset deletion consent.");
            results.Add("PASS: labels, aliases and whole-volume options survive both views; permanent deletion requires acknowledgement and resets consent when changed");
            TestSeriesAliasEditor(results,directory);

            Fill(new Settings{WatchFolder=@"\\server\share\manga_downloaded",ConvertedFolder=@"\\server\share\manga_kindle",ArchiveFolder=@"\\server\share\manga_sorted",WorkFolder=@"\\server\share\manga_work"});
            foreach(var mode in new[]{"Simple","Advanced"}) {
                SetViewMode(mode,false);
                Navigate(1);Find<CheckBox>("ScribeCompatibility").IsChecked=true;RefreshSimpleSummaries();
                if(Find<FrameworkElement>("ScribeCompatibilityCard").Visibility!=Visibility.Visible||!Checked("ScribeCompatibility")||!Find<TextBlock>("SimpleImageSummary").Text.Contains("1860"))throw new Exception("Scribe compatibility is unavailable or its effective settings are not explained.");
                RenderSection("ScribeCompatibilityCard",Path.Combine(directory,"screen-"+mode.ToLowerInvariant()+"-scribe.png"));
                Find<CheckBox>("ScribeCompatibility").IsChecked=false;RefreshSimpleSummaries();
                for(int pageNumber=0;pageNumber<6;pageNumber++){Navigate(pageNumber);RenderInterface(Path.Combine(directory,"screen-"+mode.ToLowerInvariant()+"-"+pageNumber+".png"),1180,850);}
                ApplyTheme("Dark");Navigate(1);RenderInterface(Path.Combine(directory,"screen-"+mode.ToLowerInvariant()+"-dark.png"),1180,850);ApplyTheme("Light");
                Navigate(5);RenderInterface(Path.Combine(directory,"screen-"+mode.ToLowerInvariant()+"-small.png"),1040,720);
                Navigate(1);Window.UpdateLayout();Find<ComboBox>("DuplicateAction").BringIntoView();RenderInterface(Path.Combine(directory,"screen-"+mode.ToLowerInvariant()+"-duplicates.png"),1180,850);
                Find<CheckBox>("BundleChapters").BringIntoView();RenderInterface(Path.Combine(directory,"screen-"+mode.ToLowerInvariant()+"-chapters.png"),1180,850);
                RenderSection("BookBundlesCard",Path.Combine(directory,"screen-"+mode.ToLowerInvariant()+"-volumes.png"));
                RenderSection("BookLabelsCard",Path.Combine(directory,"screen-"+mode.ToLowerInvariant()+"-labels.png"));
            }
            Find<FrameworkElement>("FolderErrorBanner").Visibility=Visibility.Visible;
            Find<TextBlock>("FolderErrorText").Text="Some saved folders are unavailable:\nArchive: C:\\Comics\\Archive - Folder is missing, disconnected, or not accessible.\nWorking: \\\\server\\share\\manga_work - Folder is missing, disconnected, or not accessible.";
            Navigate(0);RenderInterface(Path.Combine(directory,"screen-folder-error.png"),1040,720);
            Find<FrameworkElement>("FolderErrorBanner").Visibility=Visibility.Collapsed;
            SetViewMode("Simple",false);Navigate(4);
            results.Add("PASS: all six pages rendered in both views, with dark-theme and minimum-window checks");
        }
    }
}
