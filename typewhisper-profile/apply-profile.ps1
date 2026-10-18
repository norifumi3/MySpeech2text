# TypeWhisper 設定スナップショットを %LOCALAPPDATA%\TypeWhisper-WinUI に適用する。
# 前提: TypeWhisper を終了していること。既存ファイルは上書き前に backup-<日時>\ に退避する。
# API キー（.secret）は含まれないため、適用後に Soniox / Claude の API キーを UI で入力すること。
param(
  [string]$Source = (Join-Path $PSScriptRoot 'TypeWhisper-WinUI'),
  [string]$Target = (Join-Path $env:LOCALAPPDATA 'TypeWhisper-WinUI'),
  [switch]$Force   # TypeWhisper 実行中でも続行する（非推奨）
)
$ErrorActionPreference = 'Stop'
if (-not $Force -and (Get-Process TypeWhisper -ErrorAction SilentlyContinue)) {
  Write-Error 'TypeWhisper が実行中です。トレイアイコンから終了してから再実行してください（-Force で無視可）。'
}
if (-not (Test-Path $Source)) { Write-Error "スナップショットが見つかりません: $Source" }
New-Item -ItemType Directory -Force $Target | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $Target "backup-$stamp"
$files = Get-ChildItem $Source -Recurse -File
foreach ($f in $files) {
  $rel = $f.FullName.Substring($Source.Length).TrimStart('\')
  $dest = Join-Path $Target $rel
  if (Test-Path $dest) {
    $bk = Join-Path $backup $rel
    New-Item -ItemType Directory -Force (Split-Path $bk) | Out-Null
    Copy-Item $dest $bk -Force
  }
  New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
  Copy-Item $f.FullName $dest -Force
  Write-Output "applied: $rel"
}
Write-Output ''
Write-Output "完了: $($files.Count) ファイルを適用しました。退避先: $backup（既存ファイルがあった場合のみ）"
Write-Output '次の手順: TypeWhisper を起動 → Integrations で Soniox / Filler Words / Claude をインストール → Soniox と Claude の API キーを入力 → Claude の Refresh models → 設定を保存。'
