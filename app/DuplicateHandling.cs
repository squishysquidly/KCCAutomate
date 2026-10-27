using System;
using System.IO;
using System.Linq;
using System.Windows.Controls;

namespace KCCAutomate {
    public partial class Settings {
        public string DuplicateAction {get;set;}
    }
    public partial class Desktop {
        static readonly string[] DuplicatePolicies={"Review","Replace","KeepBoth","Skip"};
        public static string DuplicatePolicy(Settings settings) {
            string policy=String.IsNullOrWhiteSpace(settings.DuplicateAction)?(settings.OverwriteConverted?"Replace":"Review"):settings.DuplicateAction;
            if(!DuplicatePolicies.Contains(policy))throw new Exception("Choose a supported action for existing output.");
            return policy;
        }
        void FillDuplicatePolicy(Settings settings){Find<ComboBox>("DuplicateAction").SelectedIndex=Array.IndexOf(DuplicatePolicies,DuplicatePolicy(settings));}
        void ReadDuplicatePolicy(Settings settings) {
            int index=Find<ComboBox>("DuplicateAction").SelectedIndex;
            if(index<0||index>=DuplicatePolicies.Length)throw new Exception("Choose what to do when output already exists.");
            settings.DuplicateAction=DuplicatePolicies[index];settings.OverwriteConverted=settings.DuplicateAction=="Replace";
        }
        string DuplicateDescription() {
            switch(Find<ComboBox>("DuplicateAction").SelectedIndex) {
                case 1:return "Existing converted books are replaced only after conversion. Original handling follows your chosen policy after output verification.";
                case 2:return "Keep different existing output and publish the new book as Name (2), (3), and so on. Identical verified output is reused. Split parts share one number.";
                case 3:return "Keep existing output and leave incoming originals in place. Other books continue; a folder stays incoming until all selected books have verified conversions.";
                default:return "Keep conflicting output and incoming originals for review. Matching output can be reused after verification. Choose a one-run action in the queue to resolve a conflict.";
            }
        }
        public static bool IsOutputConflict(QueueRow row) {
            if(row.ConflictKind=="MultipleInputs")return false;
            return row.ConflictKind=="ExistingOutput"||row.Status=="Skipped existing output"||row.Status=="Review existing output"||
                ((row.Status=="Failed"||row.Status=="Conflict")&&((row.Detail??"").Contains("Different output already exists")||(row.Detail??"").Contains("Previously published output")));
        }
        void RetryQueuedBooks() {
            var selected=Find<DataGrid>("QueueGrid").SelectedItems.Cast<QueueRow>().Where(r=>r.Status=="Failed"||r.Status=="Conflict"||r.Status=="Skipped existing output"||r.Status=="Review existing output").ToArray();
            if(selected.Length==0)throw new Exception("Select failed, conflicting or skipped books in the queue first.");
            int action=Find<ComboBox>("RetryAction").SelectedIndex;
            if(action<0||action>3)throw new Exception("Choose an action for this retry.");
            if(action>0&&selected.Any(r=>!IsOutputConflict(r)))throw new Exception("A one-run output action applies only to existing-output conflicts. Select those rows, or use Saved default to retry other failures. Two incoming files targeting one name must be renamed or separated.");
            var settings=Save();Directory.CreateDirectory(userDir);
            string selection=Path.Combine(userDir,"retry-"+Guid.NewGuid().ToString("N")+".json");File.WriteAllText(selection,json.Serialize(selected.Select(r=>r.SourcePath).ToArray()));
            string extra="-SelectionPath "+Quote(selection);
            if(action>0)extra+=" -ExistingOutputAction "+new[]{"","Replace","KeepBoth","Skip"}[action];
            Start("Convert-Manga.ps1",extra,"Retrying selected books"+(action>0?" using "+ComboText("RetryAction"):" using the saved default")+". The one-run choice does not change your default policy.",true,settings);
            Find<ComboBox>("RetryAction").SelectedIndex=0;
        }
    }
}
