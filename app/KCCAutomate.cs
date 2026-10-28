using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace KCCAutomate {
    public partial class Settings {
        public int Version { get; set; }
        public string WatchFolder { get; set; }
        public string ConvertedFolder { get; set; }
        public string ArchiveFolder { get; set; }
        public string WorkFolder { get; set; }
        public string KccExe { get; set; }
        public string DjxlExe { get; set; }
        public string Profile { get; set; }
        public string Format { get; set; }
        public int Cropping { get; set; }
        public int Splitter { get; set; }
        public bool MangaStyle { get; set; }
        public bool Upscale { get; set; }
        public bool Stretch { get; set; }
        public bool Autolevel { get; set; }
        public bool NoAutocontrast { get; set; }
        public bool ForceColor { get; set; }
        public bool ForcePng { get; set; }
        public bool ScribeCompatibility {get;set;}
        public bool Webtoon { get; set; }
        public double Gamma { get; set; }
        public bool ConvertJxl { get; set; }
        public bool OverwriteConverted { get; set; }
        public int QuietMinutes { get; set; }
        public string[] InputExtensions { get; set; }
        public string ScheduleTimes { get; set; }
        public bool WakeComputer { get; set; }
        public Settings() {
            NewDefaults();
            Version = 1;
            WatchFolder = ConvertedFolder = ArchiveFolder = WorkFolder = "";
            KccExe = "";
            DjxlExe = "";
            Profile = "KS"; Format = "MOBI"; MangaStyle = Upscale = ConvertJxl = true;
            QuietMinutes = 30; InputExtensions = new[] { ".cbz" };
            ScheduleTimes = "08:00, 14:00, 20:00";
        }
    }
    public class Device {
        public string Code { get; set; }
        public string Label { get; set; }
        public Device(string code, string label) { Code = code; Label = label; }
    }
    public static class Program {
        [STAThread]
        public static void Main(string[] args) {
            try {
                if (args.Length == 2 && args[0] == "--self-test") {
                    try { Desktop.SelfTest(args[1]); }
                    catch (Exception ex) { File.WriteAllText(args[1], ex.ToString()); Environment.ExitCode = 1; }
                    return;
                }
                if(args.Length==4&&args[0]=="--test-setup") {
                    try{var settings=new JavaScriptSerializer().Deserialize<Settings>(File.ReadAllText(args[1]));var result=SetupChecks.ConvertTest(settings,args[2],AppDomain.CurrentDomain.BaseDirectory);File.WriteAllText(args[3],new JavaScriptSerializer().Serialize(result));Environment.ExitCode=result.Passed?0:1;}
                    catch(Exception ex){File.WriteAllText(args[3],new JavaScriptSerializer().Serialize(new{Passed=false,Log=ex.ToString()}));Environment.ExitCode=1;}
                    return;
                }
                bool created;
                using (var mutex = new Mutex(true, @"Local\KCCAutomate-Desktop", out created)) {
                    if (!created) { MessageBox.Show("KCCAutomate is already open.", "KCCAutomate"); return; }
                    // Also covers portable replacements and updates applied by older updaters.
                    ShellIcons.Refresh(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"KCCAutomate.exe"));
                    var app = new Application();
                    var desktop = new Desktop();
                    app.Run(desktop.Window);
                }
            } catch (Exception ex) { MessageBox.Show(ex.Message, "KCCAutomate couldn't start", MessageBoxButton.OK, MessageBoxImage.Error); }
        }
    }
    public partial class Desktop {
        public Window Window { get; private set; }
        readonly string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        readonly string userDir;
        readonly string configPath;
        readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 64000000 };
        readonly List<Button> actionButtons = new List<Button>();
        Process running;
        string stopPath;
        DispatcherTimer timer;
        readonly object outputGate = new object();
        readonly Queue<string> outputQueue = new Queue<string>();
        Settings saved;
        bool closing;
        bool constructing = true;
        static readonly string[] BooleanFields = { "MangaStyle", "Upscale", "Stretch", "Autolevel", "NoAutocontrast", "ForceColor", "ForcePng", "Webtoon", "ConvertJxl", "WakeComputer", "ScribeCompatibility" };
        static readonly string[] PathFields = { "WatchFolder", "ConvertedFolder", "ArchiveFolder", "WorkFolder", "KccExe", "DjxlExe", "KindlegenExe", "SevenZipExe" };
        public Desktop(bool testing = false, string testDirectory = null) {
            userDir = testing ? (testDirectory ?? Path.Combine(baseDir,"test-settings")) : GetSettingsDirectory(baseDir);
            configPath = Path.Combine(userDir, "settings.json");
            if(!testing&&!File.Exists(Path.Combine(baseDir,"portable.flag")))ImportLegacySettings(userDir,Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"MangaFlow"));
            using (var reader = new StreamReader(Path.Combine(baseDir, "MainWindow.xaml"))) Window = (Window)XamlReader.Load(reader.BaseStream);
            Window.Icon=AppBranding.Icon;
            var devices = new[] {
                new Device("KS","Kindle Scribe 2022 / 2024"), new Device("KS3","Kindle Scribe 2025"),
                new Device("KPW5","Kindle Paperwhite 5 / Signature"), new Device("KPW6","Kindle Paperwhite 6"),
                new Device("KPW34","Kindle Paperwhite 3 / 4"), new Device("KPW","Kindle Paperwhite 1 / 2"),
                new Device("K11","Kindle 11"), new Device("K810","Kindle 8 / 10"),
                new Device("KO","Kindle Oasis 2 / 3"), new Device("KV","Kindle Voyage"), new Device("KCS","Kindle Colorsoft"),
                new Device("K34","Kindle Keyboard / Touch"), new Device("KDX","Kindle DX"),
                new Device("KoLC","Kobo Libra Colour"), new Device("KoL","Kobo Libra H2O / 2"),
                new Device("KoCC","Kobo Clara Colour"), new Device("KoC","Kobo Clara HD / 2E / BW"),
                new Device("KoS","Kobo Sage"), new Device("KoF","Kobo Forma"), new Device("KoE","Kobo Elipsa"),
                new Device("Rmk1","reMarkable 1"), new Device("Rmk2","reMarkable 2")
            };
            Find<ComboBox>("Profile").ItemsSource = devices;
            saved = new Settings();
            if (!testing && File.Exists(configPath)) {
                try { saved = json.Deserialize<Settings>(File.ReadAllText(configPath)); if (saved == null) throw new Exception("Empty settings file."); MigrateUpdateSource(saved); }
                catch (Exception ex) { throw new Exception("Cannot read your saved settings. Your file is preserved at " + configPath + ". " + ex.Message); }
            }
            Fill(saved);
            Wire();
            InitializeEnhancements(testing);
            InitializeInterfaceModes();
            InitializeFolderAvailability();
            Navigate(viewMode=="Simple"&&!String.IsNullOrWhiteSpace(saved.WatchFolder)?4:0);
            constructing = false;
            if (!String.IsNullOrWhiteSpace(saved.WatchFolder)) Status("Your settings are ready. Preview the queue or run a conversion.");
            if (!testing) {
                timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
                timer.Tick += Tick; timer.Start();
                Window.ContentRendered+=async delegate {if(!saved.SetupCompleted)ShowGuidedSetup();RequestToolUpdateCheck();await CheckSavedFolders();};
            }
        }
        T Find<T>(string name) where T : class {
            var control = Window.FindName(name) as T;
            if (control == null) throw new Exception("Missing interface element: " + name);
            return control;
        }
        string Text(string name) { return Find<TextBox>(name).Text.Trim(); }
        void Status(string message) { Find<TextBlock>("Status").Text = message; }
        void Append(string line) {
            if (HandleStructured(line)) return;
            var box = Find<TextBox>("Activity");
            if (box.Text.Length > 200000) box.Text = box.Text.Substring(box.Text.Length - 100000);
            box.AppendText(line + Environment.NewLine); box.ScrollToEnd();
        }
        void On(string name, Action action) {
            Find<Button>(name).Click += delegate { try { action(); } catch (Exception ex) { Status(ex.Message); MessageBox.Show(Window, ex.Message, "KCCAutomate", MessageBoxButton.OK, MessageBoxImage.Information); } };
        }
        void Wire() {
            On("GuidedSetup",ShowGuidedSetup);
            On("FoldersNav", delegate { Navigate(0); }); On("ConversionNav", delegate { Navigate(1); });
            On("ScheduleNav", delegate { Navigate(2); }); On("ActivityNav", delegate { Navigate(3); });
            On("WatchBrowse", delegate { Folder("WatchFolder"); }); On("ConvertedBrowse", delegate { Folder("ConvertedFolder"); });
            On("ArchiveBrowse", delegate { Folder("ArchiveFolder"); }); On("WorkBrowse", delegate { Folder("WorkFolder"); });
            On("KccBrowse", delegate { Executable("KccExe"); }); On("DjxlBrowse", delegate { Executable("DjxlExe"); });
            On("KindlegenBrowse",delegate {Executable("KindlegenExe");});
            On("SevenZipBrowse",delegate {Executable("SevenZipExe");});
            On("KccLink", delegate { Open(ReleaseClient.KccReleasesPage); });
            On("JxlLink", delegate { Open("https://github.com/libjxl/libjxl/releases"); });
            On("SaveSettings", delegate { Save(); Status("Conversion settings saved. To change scheduled times, use Save & enable schedule."); });
            On("RunNow", delegate {
                var settings = Save();
                string message=settings.OriginalsAction=="Delete"?"Convert selected files, then permanently delete their originals after the entire batch is verified? Deleted originals will not go to the Recycle Bin.":"Convert selected files, then move successful batches to Originals? Matching archived originals will be replaced.";
                if (MessageBox.Show(Window, message, "Run conversion", MessageBoxButton.OKCancel, MessageBoxImage.Question) == MessageBoxResult.OK)
                    Start("Convert-Manga.ps1", "", "Converting. You can request a stop after the current file.", true, settings);
            });
            On("Preview", delegate { var s = Save(); Start("Convert-Manga.ps1", "-Preview", "Reading the queue. No books will be changed.", false, s); });
            On("CheckTools", delegate { var s = Save(); Start("Convert-Manga.ps1", "-CheckSetup", "Checking folders and converter tools...", false, s); });
            On("EnableSchedule", delegate { var s = Save(); Start("Manage-Schedule.ps1", "-Action Enable", "Registering automatic checks...", false, s); });
            On("DisableSchedule", delegate { Start("Manage-Schedule.ps1", "-Action Disable", "Disabling automatic checks...", false, saved); });
            On("ScheduleStatus", delegate { Start("Manage-Schedule.ps1", "-Action Status", "Reading the Windows schedule...", false, saved); });
            On("OpenLog", delegate {
                var path = Path.Combine(Text("WorkFolder"),"automation.log");
                if (Text("WorkFolder").Length == 0) { Status("Choose your working folder first."); return; }
                // Load via the worker so an unavailable share never freezes the window.
                Start("Read-Log.ps1", "-LogPath " + Quote(path), "Loading the latest conversion log...", false, saved);
            });
            On("OpenWork", delegate { if (Text("WorkFolder").Length == 0) throw new Exception("Choose a working folder first."); Open(Text("WorkFolder")); });
            On("ClearActivity", delegate { Find<TextBox>("Activity").Clear(); });
            On("StopAfter",delegate{RequestConversionStop(false);});On("StopNow",delegate{RequestConversionStop(true);});
            foreach (var name in new[] {"SaveSettings","RunNow","Preview","CheckTools","EnableSchedule","DisableSchedule","ScheduleStatus","OpenLog"}) actionButtons.Add(Find<Button>(name));
            foreach (var name in PathFields.Concat(new[] {"Gamma","QuietMinutes","ScheduleTimes"})) Find<TextBox>(name).TextChanged += delegate { Dirty(); };
            foreach (var name in BooleanFields.Concat(new[] {"InputCbz","InputPdf","InputEpub","InputCbr","InputCb7"})) {
                Find<CheckBox>(name).Checked += delegate { Dirty(); }; Find<CheckBox>(name).Unchecked += delegate { Dirty(); };
            }
            foreach (var name in new[] {"Profile","OutputFormat","Splitter","Cropping","DuplicateAction"}) Find<ComboBox>(name).SelectionChanged += delegate { Dirty(); };
            Window.Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e) {
                if (!closing && (running != null || asyncBusy)) { e.Cancel = true; MessageBox.Show(Window,"An operation is still running. Let it finish before closing. For conversions, use Stop after this file.","KCCAutomate"); }
            };
        }
        void Dirty() { if (!constructing) Find<TextBlock>("SavedState").Text = "Unsaved changes"; RefreshSimpleSummaries(); }
        void Navigate(int page) {
            string[] headers={"Folders","Conversion","Schedule","Activity","Queue","Preferences"};
            var pages=Find<TabControl>("Pages");
            pages.SelectedItem=pages.Items.Cast<TabItem>().First(t=>Convert.ToString(t.Header)==headers[page]);
            string[] buttons = {"FoldersNav","ConversionNav","ScheduleNav","ActivityNav","QueueNav","PreferencesNav"};
            for (int i = 0; i < buttons.Length; i++) Find<Button>(buttons[i]).Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(i == page ? "#3D634B" : "#203D32"));
        }
        void Folder(string field) {
            using (var dialog = new Forms.FolderBrowserDialog { Description = "Choose " + field.Replace("Folder", " folder"), ShowNewFolderButton = true }) {
                if (Directory.Exists(Text(field))) dialog.SelectedPath = Text(field);
                if (dialog.ShowDialog() == Forms.DialogResult.OK) {
                    Find<TextBox>(field).Text = dialog.SelectedPath;
                    if (field == "WatchFolder" && Text("WorkFolder").Length == 0) {
                        var parent = Directory.GetParent(dialog.SelectedPath.TrimEnd('\\'));
                        if (parent != null) Find<TextBox>("WorkFolder").Text = Path.Combine(parent.FullName, "manga_automation_work");
                    }
                }
            }
        }
        void Executable(string field) {
            var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "Windows programs (*.exe)|*.exe", Title = field == "KccExe" ? "Choose KCC c2e converter" : field=="KindlegenExe"?"Choose KindleGen":"Choose djxl decoder" };
            if (dialog.ShowDialog(Window) == true) Find<TextBox>(field).Text = dialog.FileName;
        }
        static void Open(string path) { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        void Fill(Settings s) {
            foreach (var field in PathFields) Find<TextBox>(field).Text = (string)typeof(Settings).GetProperty(field).GetValue(s, null) ?? "";
            foreach (var field in BooleanFields) Find<CheckBox>(field).IsChecked = (bool)typeof(Settings).GetProperty(field).GetValue(s, null);
            Find<ComboBox>("Profile").SelectedValue = s.Profile;
            var formats = new[] {"MOBI","EPUB","CBZ","PDF"}; Find<ComboBox>("OutputFormat").SelectedIndex = Array.IndexOf(formats, s.Format);
            Find<ComboBox>("Cropping").SelectedIndex = s.Cropping; Find<ComboBox>("Splitter").SelectedIndex = s.Splitter;
            Find<TextBox>("Gamma").Text = s.Gamma.ToString(CultureInfo.InvariantCulture);
            Find<TextBox>("QuietMinutes").Text = s.QuietMinutes.ToString();
            Find<TextBox>("ScheduleTimes").Text = s.ScheduleTimes;
            string[] controls = {"InputCbz","InputPdf","InputEpub","InputCbr","InputCb7"};
            string[] extensions = {".cbz",".pdf",".epub",".cbr",".cb7"};
            for (int i = 0; i < controls.Length; i++) Find<CheckBox>(controls[i]).IsChecked = (s.InputExtensions ?? new string[0]).Contains(extensions[i]);
            FillExtras(s);
            RefreshSimpleSummaries();
        }
        Settings Read(bool validateFolders = true) {
            var s = new Settings();
            foreach (var field in PathFields) typeof(Settings).GetProperty(field).SetValue(s, Text(field), null);
            foreach (var field in BooleanFields) typeof(Settings).GetProperty(field).SetValue(s, Find<CheckBox>(field).IsChecked == true, null);
            if (String.IsNullOrWhiteSpace(s.WorkFolder) && !String.IsNullOrWhiteSpace(s.WatchFolder)) {
                var parent = Path.GetDirectoryName(s.WatchFolder.TrimEnd('\\'));
                if (!String.IsNullOrWhiteSpace(parent)) {
                    s.WorkFolder = Path.Combine(parent, "manga_automation_work");
                    Find<TextBox>("WorkFolder").Text = s.WorkFolder;
                }
            }
            s.Profile = Find<ComboBox>("Profile").SelectedValue as string;
            s.Format = (Find<ComboBox>("OutputFormat").SelectedItem as ComboBoxItem) == null ? "" : (string)((ComboBoxItem)Find<ComboBox>("OutputFormat").SelectedItem).Content;
            s.Cropping = Find<ComboBox>("Cropping").SelectedIndex; s.Splitter = Find<ComboBox>("Splitter").SelectedIndex;
            if (!Int32.TryParse(Text("QuietMinutes"), out varQuiet) || varQuiet < 0 || varQuiet > 1440) throw new Exception("Wait time must be a whole number between 0 and 1440 minutes.");
            s.QuietMinutes = varQuiet;
            double gamma;
            if (!Double.TryParse(Text("Gamma"), NumberStyles.Float, CultureInfo.InvariantCulture, out gamma) || Double.IsNaN(gamma) || Double.IsInfinity(gamma) || gamma < 0 || gamma > 5) throw new Exception("Gamma must be between 0 and 5. Use 0 for automatic.");
            s.Gamma = gamma;
            var extensions = new List<string>();
            string[] controls = {"InputCbz","InputPdf","InputEpub","InputCbr","InputCb7"};
            string[] values = {".cbz",".pdf",".epub",".cbr",".cb7"};
            for (int i = 0; i < controls.Length; i++) if (Find<CheckBox>(controls[i]).IsChecked == true) extensions.Add(values[i]);
            s.InputExtensions = extensions.ToArray();
            s.ScheduleTimes = NormalizeTimes(Text("ScheduleTimes"));
            ReadExtras(s);
            if (validateFolders) Validate(s); else ValidateConversion(s);
            return s;
        }
        int varQuiet;
        public static string NormalizeTimes(string text) {
            var times = new SortedSet<string>();
            foreach (var part in text.Split(',')) {
                DateTime time;
                if (!DateTime.TryParseExact(part.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out time)) throw new Exception("Use 24-hour schedule times, such as 08:00, 14:00, 20:00.");
                times.Add(time.ToString("HH:mm"));
            }
            if (times.Count > 12) throw new Exception("Choose up to 12 daily check times.");
            return String.Join(", ", times);
        }
        public static void Validate(Settings s) {
            ValidateFolders(s);
            if (String.IsNullOrEmpty(s.KccExe) || !Path.IsPathRooted(s.KccExe) || !s.KccExe.EndsWith(".exe",StringComparison.OrdinalIgnoreCase)) throw new Exception("Choose the KCC command-line .exe in Folders & tools.");
            if (s.ConvertJxl && (String.IsNullOrEmpty(s.DjxlExe) || !Path.IsPathRooted(s.DjxlExe) || !s.DjxlExe.EndsWith(".exe",StringComparison.OrdinalIgnoreCase))) throw new Exception("Choose djxl.exe, or turn off JPEG XL preprocessing.");
            if (!String.IsNullOrWhiteSpace(s.SevenZipExe) && (!Path.IsPathRooted(s.SevenZipExe) || !Path.GetFileName(s.SevenZipExe).Equals("7z.exe",StringComparison.OrdinalIgnoreCase))) throw new Exception("Choose 7z.exe using its full path, or clear the optional 7-Zip path.");
            ValidateConversion(s);
        }
        public static void ValidateFolders(Settings s) {
            var paths = s.OriginalsAction=="Delete"?new[]{s.WatchFolder,s.ConvertedFolder,s.WorkFolder}:new[] {s.WatchFolder,s.ConvertedFolder,s.ArchiveFolder,s.WorkFolder};
            foreach (var path in paths) {
                if (String.IsNullOrWhiteSpace(path) || !Path.IsPathRooted(path)) throw new Exception("Choose all required folders using full paths.");
                var full = Path.GetFullPath(path).TrimEnd('\\');
                if (full == Path.GetPathRoot(full).TrimEnd('\\')) throw new Exception("Choose a subfolder, rather than the root of a drive or network share.");
            }
            for (int i = 0; i < paths.Length; i++) for (int j = i + 1; j < paths.Length; j++) {
                var a = Path.GetFullPath(paths[i]).TrimEnd('\\') + "\\";
                var b = Path.GetFullPath(paths[j]).TrimEnd('\\') + "\\";
                if (a.StartsWith(b, StringComparison.OrdinalIgnoreCase) || b.StartsWith(a, StringComparison.OrdinalIgnoreCase)) throw new Exception("The required folders must be separate. None can be inside another.");
            }
        }
        public static void ValidateConversion(Settings s) {
            if(s.OriginalsAction!="Archive"&&s.OriginalsAction!="Delete")throw new Exception("Choose how to handle original files.");
            if(s.OriginalsAction=="Delete"&&!s.DeleteOriginalsConfirmed)throw new Exception("Read the deletion warning and acknowledge permanent removal before saving or running this mode.");
            if(s.VolumeTargetPages<100||s.VolumeTargetPages>5000)throw new Exception("Combined volumes need a target between 100 and 5000 source pages.");
            if(!new[]{"Original","SeriesFirst","NumberFirst","Clean"}.Contains(s.BookTitleStyle))throw new Exception("Choose a supported book title style.");
            if(s.BundleTargetPages<50||s.BundleTargetPages>1000||s.ChapterPageThreshold<1||s.ChapterPageThreshold>s.BundleTargetPages||s.BundleMaxMiB<10||s.BundleMaxMiB>390)throw new Exception("Chapter grouping needs a 50-1000 page target, a chapter threshold no higher than the target, and a 10-390 MiB budget.");
            if (String.IsNullOrEmpty(s.Profile)) throw new Exception("Choose a device profile.");
            if (!new[] {"MOBI","EPUB","CBZ","PDF"}.Contains(s.Format)) throw new Exception("Choose an output format.");
            if (s.Format == "MOBI" && (!s.Profile.StartsWith("K") || s.Profile.StartsWith("Ko"))) throw new Exception("MOBI requires a Kindle profile. Choose EPUB, CBZ or PDF for this device.");
            if (s.Cropping < 0 || s.Splitter < 0 || s.InputExtensions.Length == 0) throw new Exception("Choose cropping, spread handling and at least one input format.");
            if (s.Cropping>2 || s.Splitter>2 || Double.IsNaN(s.Gamma) || Double.IsInfinity(s.Gamma) || s.Gamma<0 || s.Gamma>5) throw new Exception("Invalid conversion parameter in this preset.");
            var naming=(s.OutputNaming??"").Replace("{name}","Book").Replace("{format}","mobi").Replace("{profile}","KS");
            if(String.IsNullOrWhiteSpace(naming) || naming.IndexOfAny(Path.GetInvalidFileNameChars())>=0 || naming.Contains("{") || naming.Contains("}") || naming.EndsWith(".") || naming.EndsWith(" ")) throw new Exception("Invalid output naming in this preset.");
        }
        Settings Save() {
            var s = Read();
            bool toolsChanged=saved.KccExe!=s.KccExe||saved.DjxlExe!=s.DjxlExe||saved.ConvertJxl!=s.ConvertJxl;
            Directory.CreateDirectory(userDir);
            string temp = configPath + ".tmp";
            File.WriteAllText(temp, json.Serialize(s), new UTF8Encoding(false));
            if (File.Exists(configPath)) File.Replace(temp, configPath, configPath + ".bak"); else File.Move(temp, configPath);
            saved = s; Find<TextBlock>("SavedState").Text = "Saved at " + DateTime.Now.ToString("t");
            if(toolsChanged)RequestToolUpdateCheck();
            return s;
        }
        public static string Quote(string value) {
            // Windows command-line quoting, including trailing backslashes.
            var result = new StringBuilder("\""); int slashes = 0;
            foreach (char c in value) {
                if (c == '\\') { slashes++; continue; }
                if (c == '"') result.Append('\\', slashes * 2 + 1); else result.Append('\\', slashes);
                slashes = 0; result.Append(c);
            }
            result.Append('\\', slashes * 2); result.Append('"'); return result.ToString();
        }
        void Start(string script, string extra, string message, bool conversion, Settings s) {
            if (running != null || asyncBusy) throw new Exception("Wait for the current operation to finish.");
            Directory.CreateDirectory(userDir);
            if (script=="Convert-Manga.ps1" && extra.Contains("-Preview")) {
                queueReport=Path.Combine(userDir,"queue-"+Guid.NewGuid().ToString("N")+".json");
                extra+=" -ReportPath "+Quote(queueReport);
            }
            stopPath = conversion ? Path.Combine(userDir, "stop-" + Guid.NewGuid().ToString("N")) : null;
            stopRequested=false;requestedRunId=null;
            var info = new ProcessStartInfo {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(Path.Combine(baseDir, script)) + " -ConfigPath " + Quote(configPath) + " " + extra + (conversion ? " -StopFile " + Quote(stopPath) : ""),
                WorkingDirectory = baseDir, UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
            };
            info.StandardOutputEncoding = Encoding.UTF8; info.StandardErrorEncoding = Encoding.UTF8;
            var process = new Process { StartInfo = info };
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) lock (outputGate) outputQueue.Enqueue(e.Data); };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) lock (outputGate) outputQueue.Enqueue(e.Data); };
            if (!process.Start()) throw new Exception("Could not start the conversion worker.");
            running = process; running.BeginOutputReadLine(); running.BeginErrorReadLine();
            foreach (var button in actionButtons) button.IsEnabled = false;
            Find<Button>("StopAfter").IsEnabled = conversion;
            RefreshStopButton();
            Navigate(script=="Convert-Manga.ps1" && !extra.Contains("-CheckSetup") && !extra.Contains("-CleanupOnly") ? 4 : 3);
            Append("--- " + DateTime.Now.ToString("g") + " ---"); Status(message);
        }
        void Tick(object sender, EventArgs e) {
            PollQueueHistory();
            PollConversionControl();
            PollToolUpdates();
            lock (outputGate) while (outputQueue.Count > 0) Append(outputQueue.Dequeue());
            if (running == null || !running.HasExited) return;
            running.WaitForExit();
            lock (outputGate) while (outputQueue.Count > 0) Append(outputQueue.Dequeue());
            int code = running.ExitCode; running.Dispose(); running = null;
            foreach (var button in actionButtons) button.IsEnabled = true;
            Find<Button>("StopAfter").IsEnabled = false;
            if(stopPath!=null){try{File.Delete(stopPath);}catch{}stopPath=null;}stopRequested=false;nextRunCheck=DateTime.MinValue;RefreshStopButton();
            Status(code == 0 ? "Finished. Review the activity below for results." : code == 2 ? "Stopped. Completed output was kept; unconverted originals remain in Incoming." : "Finished with an error. Details are in Activity; failed originals stay in place.");
            Append("--- " + (code == 0 ? "Finished" : "Exit code " + code) + " ---");
            FinishEnhancements(code);
        }
        public static void SelfTest(string report) {
            var results = new List<string>();
            var desktop = new Desktop(true,Path.Combine(Path.GetDirectoryName(report),"desktop-settings"));
            var s = new Settings { WatchFolder = @"C:\test\in", ConvertedFolder = @"C:\test\out", ArchiveFolder = @"C:\test\archive", WorkFolder = @"C:\test\work", KccExe=@"C:\tools\kcc-c2e.exe",DjxlExe=@"C:\tools\djxl.exe" };
            Validate(s); results.Add("PASS: separate folders accepted");
            s.ArchiveFolder = @"C:\test\in\archive";
            try { Validate(s); throw new Exception("Nested path accepted"); } catch (Exception ex) { if (!ex.Message.Contains("must be separate")) throw; }
            results.Add("PASS: nested folder rejected");
            s.ArchiveFolder = @"C:\test\archive"; s.Profile = "KoL";
            try { Validate(s); throw new Exception("Non-Kindle MOBI accepted"); } catch (Exception ex) { if (!ex.Message.Contains("MOBI requires")) throw; }
            results.Add("PASS: device and output compatibility");
            if (NormalizeTimes("20:00,08:00,08:00,14:00") != "08:00, 14:00, 20:00") throw new Exception("Schedule normalization failed");
            try { NormalizeTimes("28:00"); throw new Exception("Invalid time accepted"); } catch (Exception ex) { if (!ex.Message.Contains("24-hour")) throw; }
            results.Add("PASS: schedule validation and deduplication");
            var roundTrip = desktop.json.Deserialize<Settings>(desktop.json.Serialize(new Settings()));
            if (roundTrip.Profile != "KS" || !roundTrip.ConvertJxl || roundTrip.Autolevel||roundTrip.ScribeCompatibility) throw new Exception("Settings round trip failed");
            results.Add("PASS: settings round trip and user defaults");
            desktop.TestEnhancements(results,Path.GetDirectoryName(report));
            desktop.TestConversionControls(results,Path.GetDirectoryName(report));
            desktop.TestToolUpdateChecks(results,Path.GetDirectoryName(report));
            desktop.TestGuidedSetup(results,Path.GetDirectoryName(report));
            desktop.TestInterfaceModes(results,Path.GetDirectoryName(report));
            results.Add("PASS: XAML loaded and named controls wired");
            desktop.closing = true; desktop.Window.Close();
            File.WriteAllLines(report, results);
        }
    }
}
