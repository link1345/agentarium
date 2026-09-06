"""Create/update only the test databases under artifacts/sync-fixture."""
from pathlib import Path
import sqlite3
import sys
from contextlib import closing

home=Path(__file__).resolve().parents[1]/'artifacts/sync-fixture'
home.mkdir(parents=True,exist_ok=True)
with closing(sqlite3.connect(home/'state_5.sqlite',isolation_level=None)) as db:
    db.execute('CREATE TABLE IF NOT EXISTS threads(id TEXT PRIMARY KEY,name TEXT,updated_at INT,recency_at INT,archived INT,source TEXT)')
    for number,label in [(1,'同期テストA：名前をそのまま表示'),(2,'同期テストB：並列実行'),(3,'同期テストC：過去の完了')]:
        db.execute('INSERT OR IGNORE INTO threads VALUES(?,?,?,?,?,?)',(f'10000000-0000-0000-0000-{number:012d}',label,400-number,400-number,0,'vscode'))
    if sys.argv[-1]=='rename': db.execute("UPDATE threads SET name='同期テストA：改名後も確認済み' WHERE id LIKE '%000000000001'")
with closing(sqlite3.connect(home/'thread_history_1.sqlite',isolation_level=None)) as db:
    db.execute('CREATE TABLE IF NOT EXISTS thread_turns(thread_id TEXT PRIMARY KEY,turn_id TEXT,status TEXT,started_at INT,completed_at INT,rollout_ordinal INT)')
    for number in [1,2,3]:
        db.execute('INSERT OR IGNORE INTO thread_turns VALUES(?,?,?,?,?,?)',(f'10000000-0000-0000-0000-{number:012d}',f'turn-{number}','completed' if number==3 else 'inProgress',100,None,0))
    if sys.argv[-1]=='finish': db.execute("UPDATE thread_turns SET status='completed',completed_at=500 WHERE thread_id LIKE '%000000000001'")
print(home)
