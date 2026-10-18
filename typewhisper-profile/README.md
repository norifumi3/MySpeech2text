# TypeWhisper セットアップ再現手順（2026-10-18 時点の構成）

このフォルダは、2026-10-18 に検証した TypeWhisper for Windows v1.1.0（公式 Portable 版。Soniox プラグインの DLL だけ改変版に差し替え）の設定を、
別の PC で同じ状態に再現するための手順書と設定スナップショットです。

- `README.md` … この手順書
- `plugins-required.json` … インストールするプラグインの一覧（ID・版・導入後の設定）。**プラグインの正式な一覧はこのファイル**
- `TypeWhisper-WinUI/` … `%LOCALAPPDATA%\TypeWhisper-WinUI` から取り出した設定ファイル（API キー・履歴・端末固有情報は除外）
- `apply-profile.ps1` … スナップショットを新 PC の `%LOCALAPPDATA%\TypeWhisper-WinUI` に適用するスクリプト
- `tools/tw-ui.ps1` … Claude Code が設定画面を自動操作するための UI Automation ヘルパー
- `tools/soniox-ws-probe.ps1` … Soniox の疎通テスト（残高・リージョンの問題を確定させる）。`-Terms` で context.terms の効果も試せる
- `tools/install-soniox-terms.ps1` … 改変版 Soniox プラグイン（辞書の用語を context.terms として送る）をビルドして DLL を差し替える

## 0. TypeWhisper 標準機能では再現できない理由

| 機能 | 含まれるもの | 含まれないもの |
|---|---|---|
| 設定 → 同期とバックアップ → ローカルバックアップ（JSON） | 辞書、スニペット、ワークフロー、履歴（テキスト） | API キー、プラグインの導入状態、音声設定、録音モード、ショートカット、プラグイン個別設定 |
| 設定 → 同期とバックアップ → すべてのデータを書き出す（zip） | 上記＋端末設定の JSON（と推測。中身は未検証） | API キー、ライセンス、モデル、インストール済みプラグイン |
| クラウドフォルダ同期 | 辞書・スニペット | 商用ライセンスが必要 |

したがって「プラグインの再インストール」「API キーの再入力」は必ず手作業になります。それ以外はこのフォルダのファイルコピーで再現できます。

## 1. 目標の構成

| 項目 | 値 |
|---|---|
| アプリ | TypeWhisper for Windows **v1.1.0** Portable（`TypeWhisper-win-x64-Portable.zip`、GitHub Releases タグ `v1.1.0`） |
| 配置先 | `C:\Users\<user>\Tools\TypeWhisper-1.1.0-portable\app\`（任意。Velopack 形式で `TypeWhisper.exe` と `current\` が並ぶ） |
| 前提ランタイム | .NET 10 ランタイム（Portable 版は同梱しない。`winget install Microsoft.DotNet.SDK.10` または .NET 10 Desktop Runtime） |
| 文字起こし | Soniox プラグイン v1.3.3、Region = **United States**、モデル既定（stt-rt-v5）。**DLL を改変版に差し替え**（辞書の「用語」を Soniox の `context.terms` として送る。§3.3 手順 2） |
| 後処理 | Filler Words プラグイン v1.1.0、既定 26 語＋「あー」「えー」、連続語の折り畳み ON |
| LLM 整形 | Claude プラグイン v1.1.1、Default text model = **claude-haiku-5-5**、Temperature = Provider default |
| ワークフロー | 「スマートフォーマット (Haiku 5.5)」: テンプレート CleanedText、起動方法 = グローバルフォールバック、有効、出力 = テキストを挿入。微調整指示（Fine-tuning）: Azure／Microsoft の用語がカタカナの音写で出たら公式の英語表記に直し、「仮想マシン」のような漢字の和訳は残す |
| デフォルト LLM | Claude / claude-haiku-5-5 |
| ショートカット | ALT+WIN と CTRL+ALT+SHIFT+COMMA（録音モード = ハイブリッド） |
| 音声 | 無音で停止 ON、10 秒。音のフィードバック ON、ダッキング OFF、プリロール OFF |
| ディクテーション | 第 1 優先言語 = 日本語、数字正規化 ON、アプリベースの書式 ON、直接挿入、元の入力欄にのみ貼り付け ON |
| 辞書 | 修正 1 件（正規表現）: `(タイプ\|パイプ)ウィスパー\|Type\s*Whisper` →「TypeWhisper」。表記ゆれ（パイプウィスパー、Type Whisper）もまとめて置き換える（表中の `\|` は `|` のこと）。用語 6 件: Azure、Application Gateway、Key Vault、Virtual Network、Storage Account、Log Analytics（改変版 Soniox プラグインで認識時に英語表記になる） |
| オーバーレイ | 表示モード = 標準、インジケーター = 画面上・中央、ライブテキスト = フローティング表示（位置と大きさは PC ごとに自分でドラッグして調整） |

## 2. 前提条件（新 PC 側で用意するもの）

- Windows 11 x64（最小ビルド 19041）
- Soniox の API キー（**US リージョンのプロジェクト**で発行したもの。Region を Japan にするなら JP プロジェクトのキーが必要）
- Soniox の残高（新規アカウントに無料枠は無い。2025-10-27 に廃止。残高 0 だと 402 で失敗する）
- Anthropic の API キー
- `winget` と `gh`（GitHub CLI）が使えること。`gh` は `gh auth login` 済み

## 3. 手順

### 3.1 ランタイムとアプリ

```powershell
winget install --id Microsoft.DotNet.SDK.10 --exact --silent --accept-package-agreements --accept-source-agreements
# 実行だけなら SDK ではなく Microsoft.DotNet.DesktopRuntime.10 でも可（未検証）

$dir = "$env:USERPROFILE\Tools\TypeWhisper-1.1.0-portable"
New-Item -ItemType Directory -Force "$dir\zip" | Out-Null
gh release download v1.1.0 -R TypeWhisper/typewhisper-win -p "TypeWhisper-win-x64-Portable.zip" -D "$dir\zip" --clobber
Expand-Archive "$dir\zip\TypeWhisper-win-x64-Portable.zip" -DestinationPath "$dir\app" -Force
```

公式は Portable.zip の sha256 を公開していない。2026-10-18 取得分の SHA256 は
`4817492A997A03D11C9FE1990B15B933859EDB17D1967498AC83FD55D584F2C0`。

### 3.2 設定スナップショットの適用（アプリ起動前）

```powershell
powershell -ExecutionPolicy Bypass -File .\typewhisper-profile\apply-profile.ps1
```

`%LOCALAPPDATA%\TypeWhisper-WinUI` に設定 JSON を配置する。既存ファイルがあれば `backup-<日時>\` に退避する。
これで音声設定・ディクテーション設定・ショートカット・ワークフロー・デフォルト LLM・辞書・各プラグインの設定値が入る。

### 3.3 起動とプラグイン導入（Claude Code が自動で行う。人手でも可）

**インストールするプラグインは 3 つ。正式な一覧は `plugins-required.json`**。Soniox はインストール後に改変版 DLL へ差し替える（下の手順 2）（ID、版、導入後の設定、確認手順を機械可読で記載）。

| 順 | プラグイン | ID | 版 | API キー | 導入後にやること |
|---|---|---|---|---|---|
| 1 | Soniox | `com.typewhisper.soniox` | 1.3.3 | 必要（ユーザー入力） | Region = United States を確認 → 設定を保存 → 接続を確認 → 選択したモデルを使用 |
| 2 | Filler Words | `com.typewhisper.filler-words` | 1.1.0 | 不要 | 語リストに「あー」「えー」があることを確認 |
| 3 | Claude | `com.typewhisper.claude` | 1.1.1 | 必要（ユーザー入力） | **Refresh models** → Default text model = claude-haiku-5-5 → 設定を保存 |

手順:
1. `TypeWhisper.exe` を起動。スナップショットの `setup.json` はウィザード完了済み（`Completed: true`）なので、初回ウィザードは通常出ない。出た場合は「セットアップをスキップ」でよい（設定ウィンドウが閉じたら再度 exe を起動すると戻る）。
2. 設定 → 「プラグインを見つける」から上の表の順にインストールし、導入後の設定を行う。
   Soniox をインストールしたら、TypeWhisper を終了して `tools/install-soniox-terms.ps1` を実行し、改変版 DLL に差し替えてから再起動する。
   前提は submodule の取得（非公開 fork なので `gh auth login` 済みであること）と .NET 10 SDK。元に戻すときは `-Restore`。
   アプリ内で Soniox プラグインを更新すると差し替えは上書きされるので、そのときは再実行する。
3. 設定 → ワークフロー で「スマートフォーマット (Haiku 5.5)」が存在し、右上「デフォルトLLM」が Claude / claude-haiku-5-5 になっていることを確認。
4. 設定 → 音声 で「無音で停止」が ON・10 秒になっていることを確認。

Claude Code による自動化の範囲（2026-10-18 に実際にこの方法で導入した）:
- 起動、（出た場合は）ウィザードのスキップ、Integrations でのプラグイン検索とインストール、各プラグインの設定変更と保存、Refresh models とモデル選択、
  デフォルト LLM の設定、ワークフロー作成、音声設定の変更は、すべて `tools/tw-ui.ps1`（UI Automation）で代行できる。
- **止まるのは API キーの入力 2 回だけ**（Soniox と Claude）。ユーザーが開いている設定画面に貼り付ける。キーはチャットに貼らない。
- 導入済みかどうかは `%LOCALAPPDATA%\TypeWhisper-WinUI\PluginPackages\installed.json` で確認できる（ID と版が載る）。

### 3.4 検証

1. メモ帳で ALT+WIN → 話す → ALT+WIN。整形済みテキストが挿入されること。
2. `%LOCALAPPDATA%\TypeWhisper-WinUI\diagnostics.jsonl` の末尾に `dictation.transcribed` → `delivery.completed` が並ぶこと。
   `dictation.failed` が出る場合は §5 を参照。
3. 停止から挿入までの目安: 整形なし約 0.5 秒、Haiku 整形ありで約 1.4〜2.5 秒。

## 4. Claude Code への指示文（コピーして使う）

> このリポジトリの `typewhisper-profile/README.md` の手順で、この PC に TypeWhisper をセットアップして。
> §3.1 と §3.2 は実行してよい。§3.3 のプラグインのインストールと設定は UI Automation で代行してよいが、
> API キーの入力は私が行うので、入力待ちの箇所で止めて教えて。最後に §3.4 の検証をして、診断ログの結果を報告して。

Claude 側の補足:
- `tools/tw-ui.ps1` … 設定ウィンドウの UI Automation ヘルパー。`-Click '<名前の部分一致>'` でボタン／リスト項目を押し、`-Dump` で表示テキストを列挙、`-Shot <名前>` で `PrintWindow` によるスクリーンショットを保存する（`CopyFromScreen` はこの実行環境では失敗する）。
  - インストールボタンの UIA 名は「マーケットプレイスの主要な操作」（表示は「インストール」）。
  - サイドバーは「設定カテゴリ: 音声」「設定の統合: Soniox」のような名前。
  - ComboBox は ExpandCollapsePattern で開き ListItem を SelectionItemPattern で選ぶ。フライアウト型ドロップダウン（起動方法、デフォルト LLM）は開いた後に Text 要素の親 Button を Invoke する。
  - 複数行テキスト欄は ValuePattern.SetValue で一括設定できる（Filler Words の語リストはカンマ区切り 1 行でよい）。
  - 「保存されていない変更を破棄しますか？」が出たら「編集を続ける」を押してから「設定を保存」。
- `tools/soniox-ws-probe.ps1` … 保存済み Soniox キーを DPAPI で復号し（出力はしない）、Windows TTS の日本語音声を WebSocket に流してサーバー応答を記録する疎通テスト。
  `/v1/models` の接続確認は残高 0 でも成功するため、402（残高切れ）や 401（リージョン不一致）はこのプローブで確定させる。
- 診断ログは `%LOCALAPPDATA%\TypeWhisper-WinUI\diagnostics.jsonl`。失敗は `dictation.failed` に例外型のみ記録される（メッセージは無い）。

## 5. 既知の落とし穴（今回実際に踏んだもの）

| 症状 | 原因 | 対処 |
|---|---|---|
| Soniox 設定で「プラグインの操作を完了できませんでした (InvalidOperationException)」、ディクテーションが HttpRequestException | Region=Japan だがキーが US プロジェクトのもの（`api.jp.soniox.com` が 401） | Region を United States に戻す。JP を使うなら Soniox コンソールで Region access 申請 → JP プロジェクト → 新キー |
| 接続確認は成功するのにディクテーションが InvalidOperationException で失敗（停止の約 2 秒後） | Soniox 残高 0（WebSocket が 402 organization_balance_exhausted） | コンソールで入金。支払い方法登録だけでは残高は増えない |
| Claude のモデル一覧に Haiku 5.5 が無い | 初期表示はプラグイン内蔵のフォールバック 4 件 | Refresh models → 選択 → 設定を保存 |
| Portable 版が起動しない | .NET 10 ランタイム未導入 | §3.1 |
| `dotnet build` が全パッケージ NU1100 | NuGet.Config にソースが無い PC だった | `dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org`（開発する場合のみ） |
| ショートカット開始直後に `shortcut.cancel` | 連打・押し直し | トグル式なので「押す→話す→押す」。ハイブリッドでは 300 ms 以上の長押しは離すと停止 |
| 長い組み合わせを押すと `shortcut.start` の数 ms 後に `shortcut.cancel` | 修飾キーだけの短いショートカット（例: CTRL+SHIFT）が、長い組み合わせを押す途中で先に反応している | 長い組み合わせの途中の形になる修飾キーだけのショートカットを登録しない（CTRL+SHIFT はこれで削除した）。Win を含む長い組み合わせを追加すると、ALT+WIN が同じ問題を起こす |

## 6. スナップショットに含めたファイルと除外したもの

含めたもの（`TypeWhisper-WinUI/` 配下、相対パスそのまま）:
`audio.json`, `dictation-output.json`, `dictation-text.json`, `dictionary.json`, `setup.json`, `workflow-llm-default.json`,
`workflows.json`, `dictation-hotkeys.txt`, `Dictation\settings.json`,
`PluginData\com.typewhisper.claude\settings.json`, `PluginData\com.typewhisper.filler-words\settings.json`, `PluginData\com.typewhisper.soniox\settings.json`, `overlay.json`

除外したもの:
- `PluginData\*\*.secret` … API キー（DPAPI でユーザー・PC に紐づくため移行不可）
- `history.json` … 文字起こし履歴（個人データ）
- `diagnostics.jsonl`, `PluginData\com.typewhisper.parakeet-ctc\ctc-diagnostics.jsonl` … ログ
- `microphone.json` … マイクのデバイス ID（端末固有）
- `premium-account-device.txt` … デバイス ID
- `PluginPackages\` … プラグイン本体（Integrations から再インストールする）
- `live-text-position.json` … フローティング表示の位置と大きさ（画面座標なので解像度が違う PC ではずれる）
- `plugin-backup\` … 差し替え前の Soniox DLL の退避先（PC ごとに作られる）
- `*.bak-*` … 設定を手で書き換えたときのバックアップ

注意: `PluginData\com.typewhisper.claude\settings.json` の `SecretName` は旧 PC の秘密ファイル名への参照。新 PC で API キーを入力すると上書きされる想定だが、未検証。
問題が出たら Claude 設定で「保存したキーを削除」→ 再入力。

## 7. 開発環境（ソースを改変する場合のみ）

- .NET 10 SDK 10.0.402 と Windows SDK 10.0.26100（`winget install Microsoft.WindowsSDK.10.0.26100`）
- NuGet ソースに nuget.org を登録
- `external/typewhisper-win` は非公開 fork `norifumi3/typewhisper-win` の `soniox-context-terms` ブランチ（v1.1.0 + Soniox の context.terms 対応）。取得には GitHub の認証が必要
- 上流の v1.1.0 で `dotnet build TypeWhisper.slnx` が 0 エラーで通ることを確認済み（約 1 分 20 秒）。Soniox プラグイン単体は `tools/install-soniox-terms.ps1` がビルドする
