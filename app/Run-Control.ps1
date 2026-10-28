# Per-run stop requests. No process is selected by name or supplied by the UI.
$script:runControlId=$null
$script:runStopFile=$null
$script:cancelRequested=$false
function Get-StopMode {
    if($script:cancelRequested){return 'now'}
    $found=$false
    foreach($path in @($StopFile,$script:runStopFile)){
        if($path -and [IO.File]::Exists($path)){
            $found=$true
            try{if([IO.File]::ReadAllText($path).Trim() -eq 'now'){$script:cancelRequested=$true;return 'now'}}catch{}
        }
    }
    if($found){return 'after'}
    return ''
}
function Assert-NotCancelled {
    if((Get-StopMode) -eq 'now'){throw [OperationCanceledException]::new('Conversion stopped by the user. Unconverted originals were retained.')}
}
function Initialize-RunControl {
    $script:runControlId=[guid]::NewGuid().ToString('N')
    $script:runStopFile=Join-Path $work ('stop-'+$script:runControlId+'.request')
    $path=Join-Path $work 'active-run.json'
    if([IO.File]::Exists($path)-and([IO.File]::GetAttributes($path)-band[IO.FileAttributes]::ReparsePoint)){throw 'The active-run record must not be a link.'}
    $record=@{Version=1;RunId=$script:runControlId;Host=[Environment]::MachineName;ProcessId=$PID;StartedUtc=[DateTime]::UtcNow.ToString('o')}
    # This small informational record is written under the run lock. Readers
    # ignore incomplete JSON and retry; no process is killed from its contents.
    [IO.File]::WriteAllText($path,($record|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}
function Close-RunControl {
    if(-not$script:runControlId){return}
    $path=Join-Path $work 'active-run.json'
    try{if([IO.File]::Exists($path)){$record=[IO.File]::ReadAllText($path)|ConvertFrom-Json;if($record.RunId -eq $script:runControlId){[IO.File]::Delete($path)}}}catch{}
    try{if($script:runStopFile-and[IO.File]::Exists($script:runStopFile)){[IO.File]::Delete($script:runStopFile)}}catch{}
}
function Initialize-ConverterJobType {
    if(-not('KCCAutomate.WorkerProcessJob' -as [type])){
        Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
namespace KCCAutomate {
 public sealed class WorkerProcessJob:IDisposable {
  [StructLayout(LayoutKind.Sequential)]struct Basic {public long ProcessTime,JobTime;public uint Flags;public UIntPtr Minimum,Maximum;public uint Active;public UIntPtr Affinity;public uint Priority,Scheduling;}
  [StructLayout(LayoutKind.Sequential)]struct Io {public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes;}
  [StructLayout(LayoutKind.Sequential)]struct Extended {public Basic Basic;public Io Io;public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern IntPtr CreateJobObject(IntPtr attributes,string name);
  [DllImport("kernel32.dll")]static extern bool SetInformationJobObject(IntPtr job,int kind,IntPtr info,uint length);
  [DllImport("kernel32.dll")]static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
  [DllImport("kernel32.dll")]static extern bool TerminateJobObject(IntPtr job,uint code);
  [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr handle);
  IntPtr handle;public bool Assigned{get;private set;}
  public WorkerProcessJob(IntPtr process){
   handle=CreateJobObject(IntPtr.Zero,null);if(handle==IntPtr.Zero)return;
   var limits=new Extended();limits.Basic.Flags=0x2000;
   int size=Marshal.SizeOf(typeof(Extended));IntPtr data=Marshal.AllocHGlobal(size);
   try{Marshal.StructureToPtr(limits,data,false);Assigned=SetInformationJobObject(handle,9,data,(uint)size)&&AssignProcessToJobObject(handle,process);}finally{Marshal.FreeHGlobal(data);}
   if(!Assigned)Dispose();
  }
  public bool Stop(){return Assigned&&handle!=IntPtr.Zero&&TerminateJobObject(handle,2);}
  public void Dispose(){if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;}}
 }
}
'@
    }
}
function New-ConverterJob($Process){
    Initialize-ConverterJobType
    return [KCCAutomate.WorkerProcessJob]::new($Process.Handle)
}
function Stop-ConverterProcess($Process,$Job){
    if($Process.HasExited){return $true}
    if($Job-and$Job.Assigned){[void]$Job.Stop()}
    else{
        # Windows 7 / hosts that do not allow nested job objects: target only
        # the process we started and its descendants, never all KCC processes.
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=Join-Path $env:WINDIR 'System32\taskkill.exe';$info.Arguments='/PID '+$Process.Id+' /T /F'
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        try{$killer=[Diagnostics.Process]::Start($info);$out=$killer.StandardOutput.ReadToEndAsync();$err=$killer.StandardError.ReadToEndAsync();if(-not$killer.WaitForExit(5000)){$killer.Kill()};$killer.Dispose()}catch{}
    }
    return $Process.WaitForExit(5000)
}
