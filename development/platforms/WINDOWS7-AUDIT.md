# Windows 7 compatibility audit

Phase-one source audit, 2026-10-24. Status: not certified, repairs deferred to
the Windows 7 phase after the first complete Linux x86_64 delivery.

| Area | Observed current behavior | Required resolution |
| --- | --- | --- |
| GUI/build | WPF with .NET Framework references taken from the build machine's Framework64 directory. | Retain the interface; build against explicit compatible references and verify on Windows 7 SP1 with the selected .NET Framework, proposed 4.8 rather than 4.8.1. |
| Worker | Windows PowerShell 5.1 constructs such as Get-FileHash and JSON commands. | Check/install prerequisites through clear setup guidance; the original Windows 7 PowerShell is insufficient. Later shared-worker migration must replace all runtime helpers before removing this prerequisite. |
| Scheduler | Manage-Schedule.ps1 uses the ScheduledTasks module introduced with Windows 8. | Provide Task Scheduler 2.0 COM/XML registration/status/disable and verify equivalent triggers, account context and overlap behavior. |
| KCC | ToolManagement.cs and Services.cs select the approved modern AMD64 CLI; the Win7 upstream download is a separately packaged GUI. | Identify and approve a legacy c2e path from documented package/source entry points. Do not substitute the GUI or assume the modern CLI runs on Win7. |
| Helpers | Current checks recognize Windows executable names and startup replies; no Win7 certification matrix exists. | Verify KindleGen, djxl and 7-Zip architecture/OS minimum and real conversions. |
| Install/update | Current manifest declares the modern Windows compatibility GUID; installer and updater use the current Windows package family. | Audit manifest/prerequisite messages, API use, runtime compatibility and legacy-specific asset selection. Never install a modern-only update on a legacy host. |
| HTTPS | GitHub checks depend on the system's TLS/certificate capabilities. | Test on the intended updated Win7 environment; do not weaken certificate verification. |

The [Microsoft scheduler change log](https://learn.microsoft.com/en-us/windows/win32/taskschd/what-s-new-in-task-scheduler)
documents the module's Windows 8 introduction. [Task Scheduler 2.0](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)
is available on Windows Vista and later. Microsoft lists [.NET Framework 4.8
as installable on Windows 7 SP1](https://learn.microsoft.com/en-us/dotnet/framework/get-started/system-requirements).

Required evidence before claiming support: native/VM startup, setup prerequisite
checks, approved legacy CLI and all required helpers, a real conversion for
each promised format, local and network folders, scheduler operation with the
GUI closed, stop/retry, install/uninstall and update/rollback. The fixture-based
tests do not replace these checks. No 32-bit Windows claim is made until KCC
and every required helper have corresponding verified support.

Any repair is a new app version. Published 0.1.18 downloads remain unchanged.
