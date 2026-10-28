using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;

namespace KCCAutomate {
    public class ActiveConversion {
        public int Version{get;set;}
        public string RunId{get;set;}
        public string Host{get;set;}
        public int ProcessId{get;set;}
        public string StartedUtc{get;set;}
    }
    public static class ConversionControl {
        static string Root(string folder){
            if(String.IsNullOrWhiteSpace(folder)||!Path.IsPathRooted(folder))return null;
            string root=Path.GetFullPath(folder).TrimEnd('\\');return root==Path.GetPathRoot(root).TrimEnd('\\')?null:root;
        }
        public static ActiveConversion Read(string folder){
            try{
                string root=Root(folder);if(root==null)return null;
                string path=Path.Combine(root,"active-run.json");
                if(!File.Exists(path)||new FileInfo(path).Length>8192||(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)return null;
                var run=new JavaScriptSerializer().Deserialize<ActiveConversion>(File.ReadAllText(path));
                if(run==null||run.Version!=1||!Regex.IsMatch(run.RunId??"",@"^[a-f0-9]{32}$"))return null;
                try{using(var check=File.Open(Path.Combine(root,"running.lock"),FileMode.Open,FileAccess.ReadWrite,FileShare.None))return null;}
                catch(IOException ex){int error=ex.HResult&65535;if(error!=32&&error!=33)return null;}
                return run;
            }catch{return null;}
        }
        public static bool Request(string folder,string runId,bool immediately){
            string root=Root(folder);var current=Read(root);
            if(current==null||current.RunId!=runId)return false;
            string path=Path.Combine(root,"stop-"+current.RunId+".request");
            if(File.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new IOException("The stop request must not be a link.");
            if(File.Exists(path)&&File.ReadAllText(path).Trim()=="now")immediately=true;
            File.WriteAllText(path,immediately?"now":"after");
            var after=Read(root);if(after!=null&&after.RunId==runId)return true;
            File.Delete(path);return false;
        }
    }
    public partial class Desktop {
        ActiveConversion activeConversion;
        bool runCheckBusy,stopRequested;
        DateTime nextRunCheck=DateTime.MinValue;
        string requestedRunId;
        void RefreshStopButton(){
            bool owned=running!=null&&!String.IsNullOrEmpty(stopPath);
            Find<Button>("StopNow").IsEnabled=(owned||activeConversion!=null)&&!stopRequested;
            Find<Button>("StopAfter").IsEnabled=(owned||activeConversion!=null)&&!stopRequested;
            Find<Button>("StopNow").ToolTip="Stop the active converter and keep unconverted originals. A file-copy or publishing step already in progress finishes safely.";
        }
        async void PollConversionControl(){
            RefreshStopButton();
            if(runCheckBusy||DateTime.UtcNow<nextRunCheck||String.IsNullOrWhiteSpace(saved.WorkFolder))return;
            runCheckBusy=true;nextRunCheck=DateTime.UtcNow.AddSeconds(2);string folder=saved.WorkFolder;
            try{
                var run=await Task.Run(delegate{return ConversionControl.Read(folder);});if(folder!=saved.WorkFolder)return;
                activeConversion=run;
                if(stopRequested&&!String.IsNullOrEmpty(requestedRunId)&&running==null&&(run==null||run.RunId!=requestedRunId)){Status("Stop request sent. The run is no longer reported as active; refresh the queue for its results.");nextPoll=DateTime.MinValue;}
                if(run==null||(!String.IsNullOrEmpty(requestedRunId)&&run.RunId!=requestedRunId)){if(running==null)stopRequested=false;requestedRunId=null;}
                Find<TextBlock>("QueueRunStatus").Text=run==null?"":("Conversion running on "+run.Host+". Stop is available below.");
            }finally{runCheckBusy=false;RefreshStopButton();}
        }
        async void RequestConversionStop(bool immediately){
            try{
                if(running!=null&&!String.IsNullOrEmpty(stopPath))File.WriteAllText(stopPath,immediately?"now":"after");
                else{
                    var run=activeConversion;if(run==null)return;string folder=saved.WorkFolder;
                    bool sent=await Task.Run(delegate{return ConversionControl.Request(folder,run.RunId,immediately);});
                    if(!sent){Status("That conversion has already finished or changed. Refresh the queue and try again if another run is active.");nextRunCheck=DateTime.MinValue;return;}
                    requestedRunId=run.RunId;
                }
                stopRequested=true;Find<Button>("StopAfter").IsEnabled=false;RefreshStopButton();
                Status(immediately?"Stopping the converter. Unconverted originals stay in place; a file operation already in progress finishes safely.":"Stop requested. The current book will finish; remaining originals stay in place.");
            }catch(Exception ex){Status("Could not request a stop. "+ex.Message);}
        }
        void TestConversionControls(System.Collections.Generic.List<string> results,string directory){
            string root=Path.Combine(directory,"run-control");Directory.CreateDirectory(root);
            string path=Path.Combine(root,"active-run.json");var run=new ActiveConversion{Version=1,RunId=Guid.NewGuid().ToString("N"),Host="fixture",ProcessId=123};
            File.WriteAllText(path,json.Serialize(run));
            using(var held=File.Open(Path.Combine(root,"running.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)){
                if(ConversionControl.Read(root)==null||!ConversionControl.Request(root,run.RunId,true)||File.ReadAllText(Path.Combine(root,"stop-"+run.RunId+".request"))!="now")throw new Exception("A running background worker could not be signalled.");
                if(!ConversionControl.Request(root,run.RunId,false)||File.ReadAllText(Path.Combine(root,"stop-"+run.RunId+".request"))!="now")throw new Exception("A later graceful request downgraded an immediate stop.");
                if(ConversionControl.Request(root,Guid.NewGuid().ToString("N"),true))throw new Exception("A stale run identifier stopped another run.");
                File.WriteAllText(path,"{\"Version\":1,\"RunId\":\"../outside\"}");if(ConversionControl.Read(root)!=null)throw new Exception("An invalid run record was accepted.");
            }
            File.WriteAllText(path,json.Serialize(run));if(ConversionControl.Read(root)!=null)throw new Exception("A stale record without an active lock enabled Stop.");
            activeConversion=run;RefreshStopButton();if(!Find<Button>("StopNow").IsEnabled)throw new Exception("Background conversion Stop was unavailable.");activeConversion=null;RefreshStopButton();if(Find<Button>("StopNow").IsEnabled)throw new Exception("Stop remained enabled without a conversion.");
            results.Add("PASS: visible Stop supports an active background run, rejects stale/unsafe records and never selects a process to kill from UI metadata");
        }
    }
}
