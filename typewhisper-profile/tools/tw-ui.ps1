param(
  [string]$Click = '',      # ボタン/リンク名（部分一致）をクリック
  [string]$Shot = '',       # スクリーンショット保存名（拡張子なし）
  [switch]$Dump,            # 表示テキストを列挙
  [int]$Wait = 2
)
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
$src = @'
using System; using System.Runtime.InteropServices;
public static class PW { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags); [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; } }
'@
try { Add-Type -TypeDefinition $src -ErrorAction Stop } catch {}
$p = Get-Process TypeWhisper -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
if (-not $p) { Write-Output 'NO WINDOW'; Get-Process TypeWhisper* -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,MainWindowTitle | Format-Table | Out-String; exit }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
$true_ = [System.Windows.Automation.Condition]::TrueCondition
if ($Click) {
  $el = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $true_) | Where-Object { $_.Current.Name -like "*$Click*" -and ($_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -or $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Hyperlink -or $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::ListItem -or $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::RadioButton -or $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::CheckBox -or $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::ComboBox) } | Select-Object -First 1
  if (-not $el) { Write-Output "CLICK TARGET NOT FOUND: $Click" } else {
    $pat = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) { $pat.Invoke(); Write-Output "INVOKED: $($el.Current.Name)" }
    elseif ($el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pat)) { $pat.Select(); Write-Output "SELECTED: $($el.Current.Name)" }
    elseif ($el.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pat)) { $pat.Toggle(); Write-Output "TOGGLED: $($el.Current.Name)" }
    elseif ($el.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pat)) { $pat.Expand(); Write-Output "EXPANDED: $($el.Current.Name)" }
    else { Write-Output "NO PATTERN: $($el.Current.Name)" }
  }
  Start-Sleep -Seconds $Wait
}
if ($Dump) {
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $true_)
  Write-Output "== title: $($p.MainWindowTitle)  elements: $($all.Count) =="
  $all | ForEach-Object { $c=$_.Current; if ($c.Name -and $c.Name.Trim()) { "{0,-12} {1}" -f $c.ControlType.ProgrammaticName.Replace('ControlType.',''), $c.Name.Trim() } } | Select-Object -Unique
}
if ($Shot) {
  $h = $p.MainWindowHandle; $r = New-Object PW+RECT; [PW]::GetWindowRect($h, [ref]$r) | Out-Null
  $bmp = New-Object System.Drawing.Bitmap ($r.R-$r.L),($r.B-$r.T); $g=[System.Drawing.Graphics]::FromImage($bmp); $hdc=$g.GetHdc(); [PW]::PrintWindow($h,$hdc,2) | Out-Null; $g.ReleaseHdc($hdc)
  $out = Join-Path $env:TEMP "$Shot.png"; $bmp.Save($out,[System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose(); Write-Output "SHOT: $out"
}
