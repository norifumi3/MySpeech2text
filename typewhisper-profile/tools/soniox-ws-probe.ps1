# Soniox リアルタイム WebSocket の再現プローブ。TypeWhisper プラグインと同じ設定で接続し、
# Windows TTS で生成した日本語音声（16kHz mono PCM16）を送って、サーバーの全応答 JSON を記録する。
# API キーは DPAPI から復号してメモリ上でのみ使用し、出力には含めない。
param(
  [string]$Region = 'us',
  [string[]]$Languages = @('ja','en'),
  [string]$Text = 'こんにちは。これはタイプウィスパーの動作確認です。今日はいい天気ですね。',
  [string[]]$Terms = @()   # 指定すると context.terms として送る
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security, System.Speech

# --- API key (DPAPI, same entropy as TypeWhisper.WinUI) ---
$secret = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'TypeWhisper-WinUI\PluginData\com.typewhisper.soniox\*.secret') | Select-Object -First 1
$ent = [Text.Encoding]::UTF8.GetBytes('TypeWhisper.WinUI.PluginSecrets.v1')
$key = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($secret.FullName), $ent, 'CurrentUser'))

# --- TTS -> 16kHz mono PCM16 WAV ---
$wav = Join-Path $env:TEMP 'probe_ja_16k.wav'
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voices = $synth.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo } | Where-Object { $_.Culture.Name -like 'ja*' }
if ($voices) { $synth.SelectVoice($voices[0].Name) }
"voice: $($synth.Voice.Name) ($($synth.Voice.Culture))"
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$synth.SetOutputToWaveFile($wav, $fmt)
$synth.Speak($Text)
$synth.Dispose()
$bytes = [IO.File]::ReadAllBytes($wav)
# WAV ヘッダー(44 byte 想定)を飛ばして data チャンクを探す
$idx = [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(200, $bytes.Length)).IndexOf('data')
$pcm = $bytes[($idx + 8)..($bytes.Length - 1)]
"pcm bytes: $($pcm.Length) (~$([math]::Round($pcm.Length / 32000.0, 1)) s)"

# --- WebSocket ---
$uri = switch ($Region) { 'us' { 'wss://stt-rt.soniox.com/transcribe-websocket' } 'eu' { 'wss://stt-rt.eu.soniox.com/transcribe-websocket' } 'jp' { 'wss://stt-rt.jp.soniox.com/transcribe-websocket' } }
$ws = [Net.WebSockets.ClientWebSocket]::new()
$ws.Options.SetRequestHeader('Authorization', "Bearer $key")
$cts = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(60))
$ws.ConnectAsync([Uri]$uri, $cts.Token).Wait()
"connected: $($ws.State)"
$cfgObj = @{ model = 'stt-rt-v5'; audio_format = 'pcm_s16le'; sample_rate = 16000; num_channels = 1; language_hints = $Languages; enable_language_identification = $true; enable_endpoint_detection = $true }
if ($Terms.Count -gt 0) { $cfgObj.context = @{ terms = $Terms } }
$cfg = $cfgObj | ConvertTo-Json -Compress -Depth 5
"config: $cfg"
$cfgBytes = [Text.Encoding]::UTF8.GetBytes($cfg)
$ws.SendAsync([ArraySegment[byte]]::new($cfgBytes), 'Text', $true, $cts.Token).Wait()

# 受信ループ（別スレッド）
$log = [Collections.Concurrent.ConcurrentQueue[string]]::new()
$recv = [PowerShell]::Create().AddScript({
  param($ws, $log, $ct)
  $buf = New-Object byte[] 65536
  $ms = New-Object IO.MemoryStream
  try {
    while ($ws.State -eq 'Open') {
      $ms.SetLength(0)
      do { $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).Result; $ms.Write($buf, 0, $r.Count) } while (-not $r.EndOfMessage)
      if ($r.MessageType -eq 'Close') { $log.Enqueue("<<CLOSE status=$($ws.CloseStatus) desc=$($ws.CloseStatusDescription)>>"); break }
      $log.Enqueue([Text.Encoding]::UTF8.GetString($ms.ToArray()))
    }
  } catch { $log.Enqueue("<<RECV EXC: $($_.Exception.InnerException.Message ?? $_.Exception.Message)>>") }
  $log.Enqueue('<<RECV END state=' + $ws.State + '>>')
}).AddArgument($ws).AddArgument($log).AddArgument($cts.Token)
$handle = $recv.BeginInvoke()

# 音声送信（プラグインと同じ最大 32000 byte チャンク、実時間に近いペース）
$off = 0
while ($off -lt $pcm.Length) {
  $n = [Math]::Min(32000, $pcm.Length - $off)
  $ws.SendAsync([ArraySegment[byte]]::new($pcm, $off, $n), 'Binary', $true, $cts.Token).Wait()
  $off += $n
  Start-Sleep -Milliseconds 200
}
"audio sent"
# end-of-audio: 空テキストフレーム（プラグインと同じ）
$ws.SendAsync([ArraySegment[byte]]::new([byte[]]@()), 'Text', $true, $cts.Token).Wait()
"end-of-audio (empty text frame) sent"
$sw = [Diagnostics.Stopwatch]::StartNew()
while (-not $handle.IsCompleted -and $sw.Elapsed.TotalSeconds -lt 20) { Start-Sleep -Milliseconds 200 }
"receiver done=$($handle.IsCompleted) after $([int]$sw.Elapsed.TotalSeconds)s ws.State=$($ws.State)"
try { $ws.Abort() } catch {}
"==== server messages ($($log.Count)) ===="
$i = 0
foreach ($m in $log) { $i++; if ($m.Length -gt 600) { "[$i] " + $m.Substring(0, 600) + " ...(" + $m.Length + " chars)" } else { "[$i] $m" } }
# 確定トークンを連結した最終テキスト
$final = foreach ($m in $log) { if ($m.StartsWith('{')) { try { (ConvertFrom-Json $m).tokens | Where-Object { $_.is_final -and $_.text -notmatch '^<.+>$' } | ForEach-Object { $_.text } } catch {} } }
"==== final text ===="
-join $final
$key = $null
