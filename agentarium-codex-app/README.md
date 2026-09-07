# Agentarium Pet Studio (`agentarium-codex-app`)

ChatGPT用のApps SDK / MCPアプリ。内蔵スキルでペット互換のアニメーション画像を生成し、色違いパックをAgentariumへ渡します。形は **tool-only**：ChatGPTの会話から操作し、独自ウィジェットは持ちません。

## できること

- `get_pet_recipe`：キャラクター案から、v2の行順・セル寸法・パレット契約・画像生成手順を取得。
- `swap_pet_palette`：ChatGPTで選択した完成済み画像を受け取り、選択色のWebPと`pet.json`をZIPで返す。v1/v2両対応。
- `skills/list` / `skills/get` / `resources/read`：内蔵スキルと全補助スクリプトを、SHA-256付きで提供。ChatGPTのScan Toolsでスキルを取り込むための形式。

画像の新規生成は、**ChatGPT／Codexのネイティブ画像生成機能を内蔵スキルが使う**構成です。MCPサーバー自体が画像生成APIを呼び出すわけではありません。APIキーは不要。画像生成とファイル処理を使えるホストで実行してください。機能がないホストでは、レシピだけを生成済み画像と偽って返しません。

## 起動・検証

Node.js 22以上とBunを使用します。

```powershell
bun install --frozen-lockfile
bun run start
# http://127.0.0.1:8788/mcp
# http://127.0.0.1:8788/health
```

```powershell
bun run test
node tests/mcp-smoke.mjs # 起動中サーバーを検証。Agentariumリポジトリ内で実行
```

ローカルMCPの初期化、ツール一覧、レシピ取得、スキル全リソースのハッシュ、拒否するURL、画像の寸法・アルファ・白／暗色保持をテストしています。ChatGPTの実アカウントでの接続・生成ループは未検証です。

## AIエージェントに追加を依頼する

[APEX Coach Pluginの「Ask an AI agent」](https://github.com/link1345/apex-coach-plugin#ask-an-ai-agent)と同様に、リポジトリURLをAIエージェントへ渡して導入を依頼できます。ChatGPTデスクトップアプリのWorkモード、またはCodexで新しいタスクを作り、次の文を貼り付けてください。

```text
https://github.com/link1345/agentarium
このリポジトリの agentarium-codex-app をローカルプラグインとして追加してください。
agentarium-codex-app/README.md と .codex-plugin/plugin.json、.mcp.json を確認し、
Node.js 22以上とBunの確認、依存関係のインストール、MCPサーバーの起動を行ってください。
既存の個人用マーケットプレイスを維持して、このプラグインのエントリを追加し、
Plugins Directoryからインストールできる状態にしてください。
サーバーのヘルスチェックとMCPツール一覧を確認し、
アプリの再起動・インストール操作など、利用者に必要な残りの手順を案内してください。
```

このリポジトリはプラグイン本体を`agentarium-codex-app/`に同梱していますが、マーケットプレイス定義は同梱していません。AIエージェントがローカルに取得したプラグインを個人用マーケットプレイスへ登録する形になります。APEX Coachのマーケットプレイス追加コマンドのURLだけを置き換える方法には対応していません。

登録後はデスクトップアプリを再起動し、Plugins Directoryで追加先のマーケットプレイスから **Agentarium Pet Studio** をインストールして、新しいタスクで使用します。`.mcp.json`は`http://127.0.0.1:8788/mcp`に接続する設定なので、利用中はMCPサーバーを起動しておいてください。サーバーはプラグインの追加だけでは自動起動しません。

ローカルプラグインの追加方法は [OpenAI公式のパッケージ手順](https://developers.openai.com/plugins/build/plugins)に基づきます。この導入経路の実アカウントでの通し確認は未実施です。

## ChatGPTへHTTPSで接続

ChatGPTからリモートMCPサーバーへ接続する場合は、次の手順を使用します。AIエージェントにこの準備を依頼することもできます。

1. このサーバーをHTTPSで到達できる環境へ配置するか、開発用トンネルにつなぐ。
2. `PUBLIC_BASE_URL`をそのHTTPSオリジンに設定して再起動する。ダウンロードURLにも使います。
3. ChatGPTの開発者モードで、HTTPSの`/mcp`を登録する。
4. 内蔵スキルをパッケージから追加するか、提出ポータルのScan Toolsで取り込む。スキルの取り込みはスナップショットです。

このリポジトリには、ローカル接続用`.mcp.json`と`.codex-plugin/plugin.json`を同梱します。ChatGPT登録後の接続IDは未発行なので、架空の`.app.json`は作っていません。公開ディレクトリへの提出も行っていません。

## 使い方

「Agentarium用にラベンダーの小さな猫キツネを作って。ミントの色違いもほしい」と依頼します。スキルは基準絵、各アニメーション、視線方向、組み立て、検査の順に進めます。完成シートを`swap_pet_palette`へ渡すと、1時間有効なZIPを返します。ダウンロードしてAgentariumの **設定 → ペットを取り込む** で選んでください。

毛色はHSV色相の範囲だけを交換します。透明度・彩度・明度を保持し、低彩度と暗部を除外します。標準設定は彩度0.12以上・明度0.45以上。生成絵ごとの`sourceHue`を指定してください。元画像の行順・寸法は変えません。

## データと運用

入力はChatGPTの認可済みファイルURLに限定し、20 MiB・400万画素まで。リダイレクトは禁止。追加のファイルホストが必要な場合だけ、運用者が`ALLOWED_FILE_HOSTS`へ完全なホスト名を設定します。出力はメモリー内に最大16件・1時間保持し、推測困難なダウンロードURLを発行します。端末の任意ファイルやCodexの会話DBへはアクセスしません。

既定はループバック待受。`HOST`、`PORT`で変更可能です。個人用のHTTP認証として`MCP_AUTH_TOKEN`によるBearer認証を選択できます。複数ユーザー向けOAuth・ユーザー別永続ストレージは未実装です。一般公開運用には、その構成を追加してください。

## 実装の根拠

[公式MCPクイックスタート](https://developers.openai.com/plugins/build/app-quickstart)を最小構成の出発点にし、[ファイル入力の契約](https://developers.openai.com/plugins/reference#file-apis)、[MCP経由のスキル取り込み](https://developers.openai.com/plugins/build/mcp-server#import-skills-from-the-mcp-server)、[スキルの構成](https://developers.openai.com/plugins/build/skills)に合わせています。

同梱ワークフローのライセンスは`skills/create-agentarium-pet/LICENSE.txt`（Apache-2.0）を参照してください。自作サーバー部分は親プロジェクトと同じMITです。

0.3では生成時に透過RGBAを直接指定します。内蔵スキルのnative-alpha-workflow.mdとassemble_native_alpha.pyで生成アルファを保持し、基準色のアトラスを組み立てます。Agentariumでは色違いは表示時のシェーダーで適用します。色違いZIPの書き出しは他アプリ向けの任意機能です。
