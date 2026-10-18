# 改変版 Soniox プラグイン（辞書の「用語」を context.terms として送る）を、インストール済みの Soniox プラグインの DLL と差し替える。
# 既定では、非公開 fork norifumi3/typewhisper-win のリリースからビルド済み DLL をダウンロードし、SHA256 を照合して差し替える。
# 元の DLL は plugin-backup\ に退避する。元に戻すときは -Restore、ソースからビルドするときは -Build。
# 前提: Integrations で Soniox 1.3.3 をインストール済み。ダウンロードには gh（gh auth login 済み）、-Build には .NET 10 SDK と submodule が必要。
param(
  [string]$Source = (Join-Path $PSScriptRoot '..\..\external\typewhisper-win\plugins\TypeWhisper.Plugin.Soniox'),
  [string]$Data = (Join-Path $env:LOCALAPPDATA 'TypeWhisper-WinUI'),
  [string]$Repo = 'norifumi3/typewhisper-win',
  [string]$Tag = 'soniox-terms-1.3.3-1',
  # リリースに添付した DLL（2026-10-18 に実際の音声入力で動作確認したもの）の SHA256
  [string]$Sha256 = '8B5C3423703C4E3A2CAB3FCAD0B50BB5E1C144C536DC2AC5D79D509DA39B2635',
  [switch]$Build,
  [switch]$Restore,
  [switch]$Force   # TypeWhisper 実行中でも続行する（非推奨）
)
$ErrorActionPreference = 'Stop'
$dllName = 'TypeWhisper.Plugin.Soniox.dll'
if (-not $Force -and (Get-Process TypeWhisper -ErrorAction SilentlyContinue)) {
  Write-Error 'TypeWhisper が実行中です。トレイアイコンから終了してから再実行してください（-Force で無視可）。'
}
$installed = Get-Content (Join-Path $Data 'PluginPackages\installed.json') -Raw | ConvertFrom-Json
$entry = $installed.'com.typewhisper.soniox'
if (-not $entry) { Write-Error 'Soniox プラグインが未インストールです。先に Integrations からインストールしてください。' }
if ($entry.version -ne '1.3.3') { Write-Warning "インストール済みの Soniox は $($entry.version) です。改変は 1.3.3（v1.1.0 ホスト）向けに作っています。" }
$pkg = Join-Path $Data "PluginPackages\packages\$($entry.directory)"
$backup = Join-Path $Data "plugin-backup\soniox-$($entry.version)-original"

if ($Restore) {
  Copy-Item (Join-Path $backup $dllName) $pkg -Force
  Write-Output "元の DLL に戻しました: $pkg"
  return
}

if ($Build) {
  if (-not (Test-Path (Join-Path $Source 'TypeWhisper.Plugin.Soniox.csproj'))) {
    Write-Error "プラグインのソースが見つかりません: $Source（git submodule update --init を実行してください）"
  }
  dotnet build (Join-Path $Source 'TypeWhisper.Plugin.Soniox.csproj') -c Release --nologo -v q
  if ($LASTEXITCODE -ne 0) { Write-Error 'ビルドに失敗しました。' }
  $built = Join-Path $Source "bin\Release\net10.0\$dllName"
} else {
  $download = Join-Path ([IO.Path]::GetTempPath()) ("soniox-terms-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force $download | Out-Null
  gh release download $Tag --repo $Repo --pattern $dllName --dir $download
  if ($LASTEXITCODE -ne 0) { Write-Error "ダウンロードに失敗しました（$Repo $Tag）。gh auth login 済みか確認してください。" }
  $built = Join-Path $download $dllName
  $actual = (Get-FileHash $built -Algorithm SHA256).Hash
  if ($actual -ne $Sha256) { Write-Error "SHA256 が一致しません。期待値 $Sha256、実際 $actual" }
  Write-Output "ダウンロードして SHA256 を照合しました: $Repo $Tag"
}

New-Item -ItemType Directory -Force $backup | Out-Null
# 2 回目以降の実行で改変版を「元の DLL」として退避しないよう、最初の 1 回だけ退避する
if (-not (Test-Path (Join-Path $backup $dllName))) { Copy-Item (Join-Path $pkg $dllName) $backup }
Copy-Item $built $pkg -Force
Write-Output "差し替えました: $pkg"
Write-Output "  改変版 SHA256: $((Get-FileHash (Join-Path $pkg $dllName)).Hash)"
Write-Output "  元の DLL の退避先: $backup"
Write-Output '注意: アプリ内で Soniox プラグインを更新すると、この差し替えは上書きされます。'
