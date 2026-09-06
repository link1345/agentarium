# Agentarium

**AIの仕事が、ひと目で生きて見える。**

1つのタスクが1匹のペットになる、Godot製のデスクトップマスコット。質問待ち、CI失敗、レビュー、完了を、表情とイベント劇場で知らせます。

Windows x64向け **0.4.3 プレビュー**。チャットやログは元の作業画面に任せます。

## 起動

配布フォルダーの `Agentarium.exe` を実行してください。同梱のDLL・`runtime/`・`scripts/desktop_sync.py`も同じ場所に置いてください。Pythonの別途インストールは不要です。標準は透明マスコット。下の「劇場を開く」で展開します。終了は劇場右上またはトレイメニューから。

起動すると、この端末のCodexスレッドを2秒間隔で自動同期します。初回起動は空の一覧から開始し、その後に作成されたタスクだけを自動追加します。過去のタスクは編集モードの＋からディープリンクで追加できます。既存ユーザーの登録済みタスクは維持します。「デモを試す」で実接続とサンプルを切り替えられます。

作業中・質問待ち・失敗・レビュー・完了・待機を、ペットのポーズと色で表現します。自動同期が取得するのはターンの実行状態です。質問ツールによる入力待ちとGitHubのCI失敗・レビューにも対応します。

## 本物の作業をつなぐ

**Codexデスクトップの自動同期**に加えて、ローカルJSON、Codex CLI JSONL、プロセス実行結果に対応しています。APIキーは使いません。

自動同期は `%USERPROFILE%\.codex`（`CODEX_HOME`指定時はその場所）のSQLiteデータを読み取り専用で参照します。最近の非アーカイブのスレッドを最大24件取得し、内部サブエージェントは除きます。表示名はCodexの`name`そのものです。実行状態はローカル履歴JSONLの開始・完了・中断イベントから取得します。履歴レコードを読みますが、会話本文は保存・表示・送信しません。認証情報は読みません。

これはCodex内部保存形式向けの互換アダプターで、公式の購読APIではありません。現行の`state_5.sqlite` / 履歴JSONL形式を検証済みです。履歴が取得できない場合は`thread_history_1.sqlite`にフォールバックし、キャッシュの遅延可能性を表示します。形式変更や読み取り失敗は接続状態に表示し、同期が10秒以上止まった場合は最終取得時点の表示であることを明示します。質問ツールの呼び出しを検出して質問待ちを表示します。詳細は [質問同期](docs/question-sync.md) を参照してください。初回に取得した過去の完了は確認済みとして扱います。GitHubのCI失敗・提出済みレビューを自動取得します。Gitとログイン済みGitHub CLIが必要です。詳細は [GitHub同期](docs/github-sync.md) を参照してください。

PowerShellで：

```powershell
.\scripts\send-event.ps1 -TaskId my-task -Type task.started -Title 'テストを実行' -Pet dog -Sequence 1
.\scripts\send-event.ps1 -TaskId my-task -Type input.required -Summary '実装方針を選んでください' -Sequence 2
.\scripts\send-event.ps1 -TaskId my-task -Type task.resumed -Summary '回答を受けて再開しました' -Sequence 3
.\scripts\send-event.ps1 -TaskId my-task -Type task.completed -Summary '成果物を用意しました' -Sequence 4
```

`-Url 'codex://threads/実際のタスクUUID'` またはHTTPSの成果物URLを付けると、作業画面へ移動できます。イベントからURLを自動で開くことはありません。

ローカルプロセスの実行結果を自動通知するには：

```powershell
.\scripts\watch-process.ps1 -Executable git -ArgumentList @('status','--short') -Title 'リポジトリの確認'
```

入力仕様、重複・順序・保存の契約は [イベント仕様](docs/events.md) にあります。同時起動は1インスタンスで使用してください。

### Codex CLI

既存の `codex exec --json` 出力をパイプで受け取れます。PowerShell 7で、利用者自身のCodex実行につなぎます：

```powershell
codex exec --json 'このリポジトリを要約してください' | .\scripts\import-codex.ps1 -Title 'リポジトリの調査'
```

保存済みJSONLにも対応します：

```powershell
Get-Content .\events.jsonl | .\scripts\import-codex.ps1 -TaskId my-codex-task -RunId unique-run-id
```

開始・ツール使用・完了・失敗を変換し、ログ本文・コマンド・思考内容はコピーしません。未完了で入力が途切れた場合は「完了未確認」で停止扱いにします。CLIの終了状態だけでは質問待ちを推測しません。質問待ちは共通イベントで送ってください。`RunId` は1回のCLIストリームごとに固有にし、同じストリームの再投入時だけ再利用してください。

対応形式は [OpenAI公式のnon-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode) に基づきます。JSONLフィクスチャによる検証済みですが、この開発中に実API呼び出しは実施していません。

## ソースから開発

Godot **4.7 standard / Windows x64** と PowerShell 7を使用。Godotで `project.godot` を開くか：

```powershell
.\scripts\run.ps1 -Theater
# UI操作・テスト用のGuaを有効にする
.\scripts\run.ps1 -Theater -Gua -GuaPort 18765
```

ビルド用テンプレートを用意して書き出す：

```powershell
.\scripts\setup.ps1 # 公式Godotテンプレートは約1.2GB。既存ZIPのパスを引数で渡すことも可能
python scripts/prepare-runtime.py # Windows CPython 3.12から同期ランタイムを用意
.\scripts\build.ps1
```

成果物は `dist/` フォルダー全体。署名・Microsoft Store公開は行っていません。

## テスト

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/event_store_test.gd

# 別ターミナルで、上記のGua有効版を起動してから
$env:GUA_SOURCE = 'C:\path\to\gua' # Guaリポジトリで bun install 済み
$env:GUA_BRIDGE_URL = 'ws://127.0.0.1:18765'
bun tests/gua-driver.ts tree
# テスト用起動時は $env:AGENTARIUM_DISABLE_SYNC="1" を設定。DEMOモードで実行。UI操作はすべてGua公式クライアント経由
bun tests/gua-driver.ts suite
```

検証結果は [0.3の検証記録](docs/validation-v0.3.md)（[0.1の記録](docs/validation.md)）。スクリーンショット・操作レシートは `artifacts/` に保存されます。Gua無効時は撮影・テスト用状態出力・ブリッジ起動を行いません。

## 保存とプライバシー

標準保存先は `%APPDATA%\Godot\app_userdata\Agentarium`。`AGENTARIUM_DATA_DIR` または送信スクリプトの `-DataDir` で変更できます。タスクの短い題名・要約・URL、確認状態、設定を平文でこの端末に保存します。テレメトリー、クラウド送信、自動起動登録はありません。秘密情報を要約に入れないでください。

## ペット画像とChatGPT用アプリ

`agentarium-codex-app/` はChatGPT Apps SDK / MCPアプリです。画像生成スキルを同梱し、生成レシピと色違いZIPの作成ツールを提供します。詳細は [アプリのREADME](agentarium-codex-app/README.md)。ChatGPT上の接続登録・公開は別途必要です。

標準キャラクターLumiは、この内蔵スキルによるネイティブ画像生成で制作し、アプリと同じ書き出し処理を経て組み込みました。画像形式はペット互換の192×208pxセル、8列。色替えは毛色の色相だけに適用し、透明度・白い顔・暗い輪郭を保ちます。スレッドごとに色を分け、設定の「毛色」で組み合わせを切り替えます。

「ペットを取り込む」で、ルート直下に`pet.json`、`spritesheet.webp`（またはPNG）、任意の`palette.json`があるZIPを選べます。アプリが作成するZIPはそのまま取り込めます。ZIPの任意パスは展開せず、検証した画像だけを保存します。元のCodexペットフォルダーは変更しません。

現状は同時100タスクまで。Windows以外、複数インスタンスは未対応です。

MIT License。[第三者ライセンス](THIRD_PARTY_NOTICES.md)も参照してください。


