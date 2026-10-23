using System;
using System.IO;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;

namespace KCCAutomate {
    public class FolderAvailability {
        public bool Ready {get;set;}
        public string Message {get;set;}
    }
    public partial class Desktop {
        bool checkingFolders;
        void InitializeFolderAvailability() {
            Find<Button>("RecheckFolders").Click+=async delegate{await CheckSavedFolders();};
            On("OpenFoldersFromError",delegate{Navigate(0);});
        }
        async Task CheckSavedFolders() {
            if(checkingFolders||!File.Exists(configPath))return;
            checkingFolders=true;Find<Button>("RecheckFolders").IsEnabled=false;
            try {
                string script=Path.Combine(baseDir,"Workspace-Info.ps1");
                var result=await Task.Run(delegate{
                    string powershell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");
                    return SetupChecks.Run(powershell,"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "+Quote(script)+" -ConfigPath "+Quote(configPath)+" -AvailabilityOnly",10000);
                });
                if(result.Item1!=0)throw new Exception("The folder check could not finish. Review the saved paths in Folders & tools.");
                var report=new JavaScriptSerializer().Deserialize<FolderAvailability>(result.Item2);
                if(report==null)throw new Exception("The folder check returned no result.");
                Find<FrameworkElement>("FolderErrorBanner").Visibility=report.Ready?Visibility.Collapsed:Visibility.Visible;
                Find<TextBlock>("FolderErrorText").Text="Some saved folders are unavailable:\n"+report.Message;
                Find<TextBlock>("QueueNetwork").Text=report.Ready?"All saved folders are accessible. Local and remote folders use the same check.":"Some saved folders are unavailable. See the folder error above.";
            } catch(Exception ex) {
                Find<FrameworkElement>("FolderErrorBanner").Visibility=Visibility.Visible;
                Find<TextBlock>("FolderErrorText").Text="Folder availability could not be confirmed: "+ex.Message+" Check the local drive or remote connection, then check saved folders again.";
            } finally {checkingFolders=false;Find<Button>("RecheckFolders").IsEnabled=true;}
        }
    }
}
