# Agentarium

**AIの仕事が、ひと目で生きて見える。**

1つのタスクが1匹のペットになる、Godot製のデスクトップマスコット。質問待ち、CI失敗、レビュー、完了を、表情とイベント劇場で知らせます。

Windows x64向け **0.4.3 プレビュー**。チャットやログは元の作業画面に任せます。

## 起動

配布フォルダーの `Agentarium.exe` を実行してください。同梱のDLL・`runtime/`・`scripts/desktop_sync.py`も同じ場所に置いてください。Pythonの別途インストールは不要です。標準は透明マスコット。下の「劇場を開く」で展開します。終了は劇場右上またはトレイメニューから。

起動すると、この端末のCodexスレッドを2秒間隔で自動同期します。初回起動は空の一覧から開始し、その後に作成されたタスクだけを自動追加します。過去のタスクは編集モードの＋からディープリンクで追加できます。既存ユーザーの登録済みタスクは維持します。「デモを試す」で実接続とサンプルを切り替えられます。

作業中・質問待ち・失敗・レビュー・完了・待機を、ペットのポーズと色で表現します。自動同期が取得するのはターンの実行状態です。質問ツールによる入力待ちとGitHubのCI失敗・レビューにも対応します。

「確認した」を押すとペットが休憩（おやすみ・zzz）に入ります。元のサービスへの回答やCI操作は行いません。次の新しいイベントを受けると表示を更新します。「スレッドを開く」はイベントに含まれるリンクを開きます。

## マスコットと設定

キャラをドラッグして移動、ダブルクリックで劇場へ。透明な外側はクリックを透過します。「次のペット」でタスクを切り替えられます。劇場はサイズ変更できます。左一覧を除く表示領域が900px以上なら2列、1450px以上なら3列。高さ850px以上で項目が多い場合は2段になります。狭いときは選択した1件を表示し、一覧または前後ボタンで切り替えます。タブはありません。カード内にも元のスレッド名を表示します。「☰ 一覧」で左一覧を開閉できます。編集モード中に一覧項目をドラッグ＆ドロップすると、移動先の線の位置へ並べ替えられます。並び順は保存されます。「編集」で＋と×を表示し、「完了」で隠します。上下移動ボタンはありません。左一覧の状態は名前の左の画像スタンプで表示します。編集時の×は名前の右に表示し、一覧の幅は変わりません。×はAgentariumの表示から外す操作で、Codex本体は削除しません。編集モードの＋から、codex://threads/UUID 形式のディープリンクで表示スレッドを追加できます。同じリンクは重複せず、非表示なら復元します。追加したスレッドは直近24件から外れても同期します。名前と状態の取得にはこの端末のCodexデータが必要です。新しいCodexタスクは名前確定前から仮名で取得し、起動中の新規タスクは一覧の先頭に自動追加して表示します。名前の確定後はCodexの表示名に更新します。既存項目の相対順は維持し、非表示の既存タスクは更新だけでは復活しません。ページ送りで残りを確認できます。

設定から、自動同期・毛色・ペット取り込み・集中モード・動きを減らす・最前面（通常 / 常に / 未確認の重要イベント時）を選べます。標準は重要イベント時のみ最前面。マスコットはキーボードのフォーカスを奪わず、音は鳴らしません。トレイからいつでも表示を戻せます。

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

標準キャラクターLumiは、この内蔵スキルによるネイティブ画像生成で制作し、アプリと同じ書き出し処理を経て組み込みました。画像形式はペット互換の192×208pxセル、8列。既存v1（9行・1536×1872）も、新規v2（11行・1536×2288）もそのまま読み込めます。色替えは毛色の色相だけに適用し、透明度・白い顔・暗い輪郭を保ちます。スレッドごとに色を分け、設定の「毛色」で組み合わせを切り替えます。

「ペットを取り込む」で、ルート直下に`pet.json`、`spritesheet.webp`（またはPNG）、任意の`palette.json`があるZIPを選べます。アプリが作成するZIPはそのまま取り込めます。ZIPの任意パスは展開せず、検証した画像だけを保存します。元のCodexペットフォルダーは変更しません。

現状は同時100タスクまで、マスコットは選択した1匹。Windows以外、複数インスタンス、署名・インストーラー・Store提出は未対応です。

MIT License。[第三者ライセンス](THIRD_PARTY_NOTICES.md)も参照してください。


## 0.3の状態演出と透過生成

背景の光は連続した放射グラデーションです。質問イベント `input.required` が届くと「質問が来ました！」を約4.5秒間、ウィンドウ全体に表示します。クリックで即座に閉じられます。その後も質問状態が続く間、該当カードには赤い警告枠と動く警告帯を表示します。「動きを減らす」「集中モード」ではアニメーションを止めます。Codexの質問ツールを検出した場合も、このアラートを表示します。

キャラクターの右上には生成した透過アイテムを表示します。CI失敗 (`ci.failed`) は爆弾、通常の失敗 (`task.failed`) はたらい、作業中はフラスコ、質問ははてな、レビューは風船、完了はプレゼント、休憩はzzzです。標準Lumiは完了・休憩時に専用の寝姿になります。外部ペットには互換アトラスの伏せた静止ポーズを使います。

今後のキャラ生成は生成時から透過RGBAを指定し、そのアルファを保持して組み立てます。背景色の除去やクロマキーは使いません。基準色の画像を1組作り、毛色は表示シェーダーで変更します。0.3の寝姿と7アイテムはこの方法で新規生成しました。既存の通常アニメーションは0.2のLumiを継続利用しています。生成プロンプトは `docs/art-v0.3.md`、新しい生成手順は内蔵スキルの `references/native-alpha-workflow.md` にあります。



