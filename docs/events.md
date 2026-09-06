# イベント契約 v1

アダプターは保存先の `inbox/` にUTF-8 JSONファイルを置きます。書き込み途中を読ませないため `.tmp` へ書いてから `.json` にatomic renameしてください。`scripts/send-event.ps1` がこの手順を実装しています。

```json
{
  "id": "unique-event-id",
  "task_id": "task-123",
  "type": "input.required",
  "title": "新しい機能を実装",
  "summary": "公開APIの名前を選んでください。",
  "pet": "fox",
  "url": "https://github.com/owner/repository/issues/1",
  "sequence": 12
}
```

- 必須：`id`, `task_id`, `type` は空でない文字列、最大160文字。
- 任意：`title`, `summary`, `url` は最大2048文字。省略すると以前の値を維持。
- `pet`：`fox`, `dog`, `bird`, `cat`。初期値fox。パック拡張点は `scripts/pet.gd`。
- `sequence`：タスク単位の単調増加整数。全プロデューサーが同じタスクの順序を協調すること。過去と同値または小さい値は拒否。未指定では受信順を採用。
- `id`：直近2000件で重複排除。長期間の厳密な一度だけ配送は保証しません。順序番号と併用してください。
- 最大16KiB/イベント、100タスク。0.5秒ごとに最大20ファイルを処理。

| type | 状態 |
| --- | --- |
| task.started / task.progress / task.resumed / tool.started / tool.completed | working |
| input.required | question |
| ci.failed / task.failed | failed |
| review.received | review |
| task.completed | completed |
| task.paused | idle |
| user.acknowledged | 確認済みにして休憩（idle）へ移行する |

質問・失敗・レビュー・完了は未確認状態で保持されます。時間で勝手に解決しません。`user.acknowledged` は質問への回答でも処理の再開でもありません。元のサービスで操作し、そのアダプターが次の実イベントを送る必要があります。

受理したイベントは `tasks.json.tmp` を経て `tasks.json` に保存してからinboxから削除します。保存失敗ならinboxを残し再試行。無効イベントは `rejected/` に移動し、画面にエラーを表示します。タスクログ本文の収集は行いません。

リンクはHTTPSと `codex://threads/<UUID>` のみ。リンクを開くのはユーザーが「作業を開く」を押したときだけです。外部からのイベントでコマンド実行はできません。

同じ保存先を複数のAgentariumで開かないでください。ファイル監視は小規模なローカル連携を目的とし、認証付きネットワークサービスや複数起動の排他は実装していません。受信ディレクトリを共有ネットワークやWeb公開フォルダーに設定しないでください。
