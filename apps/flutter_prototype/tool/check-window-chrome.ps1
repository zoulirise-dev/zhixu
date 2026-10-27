param([Parameter(Mandatory=$true)][System.Diagnostics.Process]$AppProcess)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ChromeProbe {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int n);
 [DllImport("user32.dll")] public static extern int GetSystemMetricsForDpi(int n,uint d);
 [StructLayout(LayoutKind.Sequential)] public struct CursorInfo { public int cbSize; public int flags; public IntPtr cursor; public int x,y; }
 [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CursorInfo info);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 public static IntPtr DesktopCursor() { var i=new CursorInfo(); i.cbSize=Marshal.SizeOf<CursorInfo>(); if(!GetCursorInfo(ref i)) throw new Exception("GetCursorInfo failed"); return i.cursor; }
 [DllImport("user32.dll")] public static extern IntPtr LoadCursor(IntPtr h,IntPtr id);
 public static int Hit(IntPtr h,int x,int y) {return (int)SendMessage(h,0x84,IntPtr.Zero,(IntPtr)((y<<16)|(x&0xffff)));}
}
'@
$AppProcess.Refresh()
$h=$AppProcess.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw 'No visible app window' }
$r=New-Object ChromeProbe+Rect
[ChromeProbe]::GetWindowRect($h,[ref]$r) | Out-Null
$dpi=[ChromeProbe]::GetDpiForWindow($h)
$s=$dpi/96.0
$edge=[ChromeProbe]::GetSystemMetricsForDpi(32,$dpi)+[ChromeProbe]::GetSystemMetricsForDpi(92,$dpi)
$y=[int]($r.Top+$edge+18*$s)
$checks=@(
 @([int](($r.Left+$r.Right)/2),$y,2,'drag caption'),
 @([int]($r.Right-$edge-23*$s),$y,20,'close'),
 @([int]($r.Right-$edge-69*$s),$y,9,'maximize / Snap Layouts'),
 @([int]($r.Right-$edge-115*$s),$y,8,'minimize'),
 @(($r.Left+1),[int](($r.Top+$r.Bottom)/2),10,'left resize'),
 @([int](($r.Left+$r.Right)/2),($r.Top+1),12,'top resize'),
 @(($r.Right-1),($r.Bottom-1),17,'bottom-right resize')
)
foreach($c in $checks) {
 $actual=[ChromeProbe]::Hit($h,$c[0],$c[1])
 if($actual -ne $c[2]) {throw "Hit test $($c[3]): expected $($c[2]), got $actual"}
 if ($c[2] -in @(8,9,20)) {
   [ChromeProbe]::SetCursorPos($c[0],$c[1]) | Out-Null
   Start-Sleep -Milliseconds 100
   [ChromeProbe]::SendMessage($h,0x20,$h,[IntPtr]((0x200 -shl 16) -bor $c[2])) | Out-Null
   if ([ChromeProbe]::DesktopCursor() -ne [ChromeProbe]::LoadCursor([IntPtr]::Zero,[IntPtr]32512)) {throw "Caption button cursor is not the default arrow"}
 }
 Write-Host "PASS $($c[3])"
}
[ChromeProbe]::SendMessage($h,0x112,[IntPtr]0xF030,[IntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 500
if(![ChromeProbe]::IsZoomed($h)){throw 'Maximize failed'}
[ChromeProbe]::SendMessage($h,0x112,[IntPtr]0xF120,[IntPtr]::Zero) | Out-Null
[ChromeProbe]::SendMessage($h,0x112,[IntPtr]0xF020,[IntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 300
if(![ChromeProbe]::IsIconic($h)){throw 'Minimize failed'}
[ChromeProbe]::ShowWindow($h,9) | Out-Null
Write-Host 'PASS native maximize, restore and minimize'
