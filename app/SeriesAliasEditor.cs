using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace KCCAutomate {
    public partial class Desktop {
        sealed class SeriesAliasRow {
            public Grid Panel;
            public TextBox Original,Shortened;
            public Button Remove;
        }
        readonly List<SeriesAliasRow> seriesAliasRows=new List<SeriesAliasRow>();

        SeriesAliasRow AddSeriesAliasRow(string original,string shortened) {
            var row=new SeriesAliasRow{Panel=new Grid{Margin=new Thickness(0,0,0,10)},Original=new TextBox{Text=original,MinHeight=38},Shortened=new TextBox{Text=shortened,MinHeight=38},Remove=new Button{Content="Remove",Padding=new Thickness(10,8,10,8),Margin=new Thickness(12,0,0,0),VerticalAlignment=VerticalAlignment.Bottom}};
            row.Panel.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});
            row.Panel.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(12)});
            row.Panel.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});
            row.Panel.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});
            var left=new StackPanel();var right=new StackPanel();
            left.Children.Add(new TextBlock{Text="Original long name",FontWeight=FontWeights.SemiBold,Margin=new Thickness(0,0,0,6)});
            right.Children.Add(new TextBlock{Text="Shortened name",FontWeight=FontWeights.SemiBold,Margin=new Thickness(0,0,0,6)});
            left.Children.Add(row.Original);right.Children.Add(row.Shortened);
            Grid.SetColumn(right,2);Grid.SetColumn(row.Remove,3);
            row.Panel.Children.Add(left);row.Panel.Children.Add(right);row.Panel.Children.Add(row.Remove);
            AutomationProperties.SetName(row.Original,"Original long series name");
            AutomationProperties.SetName(row.Shortened,"Shortened series name");
            AutomationProperties.SetName(row.Remove,"Remove this series name pair");
            row.Original.ToolTip="Series title only, without a volume/chapter number or release tags.";
            row.Shortened.ToolTip="The shorter series title to use in converted books.";
            row.Original.TextChanged+=delegate{Dirty();};row.Shortened.TextChanged+=delegate{Dirty();};
            row.Remove.Click+=delegate{
                Find<StackPanel>("SeriesAliasRows").Children.Remove(row.Panel);seriesAliasRows.Remove(row);
                if(seriesAliasRows.Count==0)AddSeriesAliasRow("","");
                RefreshSeriesAliasButtons();Dirty();
            };
            seriesAliasRows.Add(row);Find<StackPanel>("SeriesAliasRows").Children.Add(row.Panel);
            RefreshSeriesAliasButtons();return row;
        }
        void RefreshSeriesAliasButtons(){foreach(var row in seriesAliasRows)row.Remove.Visibility=seriesAliasRows.Count>1?Visibility.Visible:Visibility.Collapsed;}
        void FillSeriesAliases(Dictionary<string,string> aliases) {
            seriesAliasRows.Clear();Find<StackPanel>("SeriesAliasRows").Children.Clear();
            if(aliases!=null)foreach(var pair in aliases)AddSeriesAliasRow(pair.Key,pair.Value);
            if(seriesAliasRows.Count==0)AddSeriesAliasRow("","");
        }
        Dictionary<string,string> ReadSeriesAliases() {
            var aliases=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            foreach(var row in seriesAliasRows){
                string original=row.Original.Text.Trim(),shortened=row.Shortened.Text.Trim();
                if(original.Length==0&&shortened.Length==0)continue;
                if(original.Length==0||shortened.Length==0)throw new Exception("Enter both the original long name and its shortened name, or clear both boxes.");
                if(aliases.ContainsKey(original))throw new Exception("Each original series name can have only one shortened name. Remove the duplicate pair.");
                if(shortened.IndexOfAny(Path.GetInvalidFileNameChars())>=0)throw new Exception("The shortened name contains a character that cannot be used in a book filename.");
                aliases.Add(original,shortened);
            }
            return aliases;
        }
        void TestSeriesAliasEditor(List<string> results,string directory) {
            FillSeriesAliases(null);
            if(seriesAliasRows.Count!=1||seriesAliasRows[0].Original.Text!=""||seriesAliasRows[0].Shortened.Text!=""||ReadSeriesAliases().Count!=0||seriesAliasRows[0].Remove.Visibility!=Visibility.Collapsed)throw new Exception("An unused series editor did not start with exactly one empty pair.");
            Find<Button>("AddSeriesAlias").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if(seriesAliasRows.Count!=2)throw new Exception("Add another series did not add a pair.");
            seriesAliasRows[0].Original.Text="A Very Long Series";seriesAliasRows[0].Shortened.Text="Short One";
            seriesAliasRows[1].Original.Text="Another Long Series";seriesAliasRows[1].Shortened.Text="Short Two";
            Save();
            var reopened=new Desktop(true,userDir);
            // Test-mode construction deliberately skips user settings. Replay
            // the production load explicitly without enabling timers or setup.
            reopened.Fill(json.Deserialize<Settings>(File.ReadAllText(configPath)));
            if(reopened.seriesAliasRows.Count!=2||reopened.ReadSeriesAliases()["A Very Long Series"]!="Short One"||reopened.ReadSeriesAliases()["Another Long Series"]!="Short Two")throw new Exception("Existing saved name pairs were not restored into the row editor.");
            reopened.closing=true;reopened.Window.Close();
            RenderSection("SeriesAliasEditor",Path.Combine(directory,"screen-series-pairs.png"));
            ApplyTheme("Dark");RenderSection("SeriesAliasEditor",Path.Combine(directory,"screen-series-pairs-dark.png"));RenderInterface(Path.Combine(directory,"screen-series-pairs-dark-small.png"),1040,720);ApplyTheme("Light");
            Find<Button>("AddSeriesAlias").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if(ReadSeriesAliases().Count!=2)throw new Exception("An unused extra row was saved as a series name.");
            seriesAliasRows[0].Remove.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if(ReadSeriesAliases().Count!=1||ReadSeriesAliases()["Another Long Series"]!="Short Two")throw new Exception("Removing a pair changed the remaining mapping.");
            string savedHash=ReleaseClient.Hash(configPath);
            seriesAliasRows[1].Original.Text="Incomplete";
            bool rejected=false;try{Save();}catch(Exception){rejected=true;}
            if(!rejected||ReleaseClient.Hash(configPath)!=savedHash)throw new Exception("An incomplete pair changed saved settings.");
            seriesAliasRows[1].Original.Text="ANOTHER LONG SERIES";seriesAliasRows[1].Shortened.Text="Duplicate";
            rejected=false;try{ReadSeriesAliases();}catch(Exception){rejected=true;}if(!rejected)throw new Exception("Duplicate original names were accepted.");
            seriesAliasRows[1].Original.Text="Other";seriesAliasRows[1].Shortened.Text="Invalid/name";
            rejected=false;try{ReadSeriesAliases();}catch(Exception){rejected=true;}if(!rejected)throw new Exception("An invalid shortened filename was accepted.");
            seriesAliasRows[1].Original.Text="  Other  ";seriesAliasRows[1].Shortened.Text="  Tiny  ";
            if(ReadSeriesAliases()["Other"]!="Tiny")throw new Exception("Space around a name was not trimmed.");
            FillSeriesAliases(null);
            RenderSection("SeriesAliasEditor",Path.Combine(directory,"screen-series-pair-empty.png"));
            results.Add("PASS: paired series-name fields start empty, add/remove independently, restore saved aliases, ignore blank rows and reject incomplete/duplicate/invalid pairs without changing saved settings");
        }
    }
}
