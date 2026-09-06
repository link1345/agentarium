"""Read-only compatibility adapter for Codex desktop's local SQLite projection.

Only task metadata and lifecycle records are extracted. Conversation content is
not retained, displayed or transmitted.
This is an internal-format adapter, not an official Codex subscription API.
"""
import argparse
from contextlib import contextmanager
import ctypes
import json
import os
from pathlib import Path
import sqlite3
import time
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from rollout_state import RolloutReader
from github_sync import GitHubPoller
ROLLOUTS = RolloutReader()


@contextmanager
def connect(path):
    db = sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True, timeout=2)
    db.execute('PRAGMA query_only=ON')
    db.row_factory = sqlite3.Row
    try:
        yield db
    finally:
        db.close()


def snapshot(home, now=None, watched=(), since=None, github=None):
    now = int(time.time()) if now is None else now
    with connect(home / 'state_5.sqlite') as state, connect(home / 'thread_history_1.sqlite') as history:
        # Names can arrive after creation. Never substitute the first prompt/title.
        has_rollout = any(row[1] == 'rollout_path' for row in state.execute('PRAGMA table_info(threads)'))
        rollout_column = ',rollout_path' if has_rollout else ''
        columns = {r[1] for r in state.execute('PRAGMA table_info(threads)')}
        has_git = {'cwd','git_branch','git_sha'} <= columns
        if has_git: rollout_column += ',cwd,git_branch,git_sha'
        new_only = ' AND created_at > ?' if since is not None else ''
        rows = state.execute('''SELECT id,name,updated_at''' + rollout_column + ''' FROM threads
            WHERE archived=0 AND source IN ('vscode','cli','appServer')
            ''' + new_only + ''' ORDER BY COALESCE(recency_at,updated_at) DESC LIMIT 24''', (since,) if since is not None else ()).fetchall()
        result = []
        known = {row['id'] for row in rows}
        for thread_id in list(watched)[:100]:
            if not isinstance(thread_id, str) or thread_id in known: continue
            row = state.execute("SELECT id,name,updated_at" + rollout_column + " FROM threads WHERE id=?", (thread_id,)).fetchone()
            if row:
                rows.append(row)
                known.add(thread_id)
        for row in rows:
            turn = history.execute('''SELECT turn_id,status,started_at,completed_at
                FROM thread_turns WHERE thread_id=? ORDER BY rollout_ordinal DESC LIMIT 1''', (row['id'],)).fetchone()
            status = turn['status'] if turn else 'unknown'
            # An active turn may be waiting for input: without a reliable pending-request
            # projection, report execution generically instead of inventing a wait reason.
            mapped = {'inProgress':'working', 'completed':'completed', 'failed':'failed',
                      'interrupted':'idle'}.get(status, 'idle')
            summary = {'working':'Codexで実行中（入力待ちを含む）', 'completed':'直近のターンが完了',
                       'failed':'直近のターンでエラー', 'idle':'実行状態を確認できません' if status == 'unknown' else '中断・待機中'}[mapped]
            revision = (turn['turn_id'] + ':' + status) if turn else 'unknown'
            origin = 'projection'
            if has_rollout and row['rollout_path']:
                try:
                    raw_path = row['rollout_path']
                    # Codex stores Windows extended-length paths; compare equivalent
                    # ordinary paths so the home containment check does not reject them.
                    if os.name == 'nt' and raw_path.startswith('\\\\?\\'):
                        raw_path = ('\\\\' + raw_path[8:]) if raw_path.startswith('\\\\?\\UNC\\') else raw_path[4:]
                    path = Path(raw_path).resolve()
                    if path.is_relative_to(home.resolve()) and path.suffix == '.jsonl':
                        current = ROLLOUTS.read(path)
                        if current:
                            mapped, revision = current['state'], current['revision']
                            origin = 'rollout'
                            summary = {'question':'Codexから質問が届いています。元のタスクで回答してください。','working':'Codexが応答を生成中','completed':'Codexの応答が完了しました','idle':'Codexの実行が中断されました','failed':'Codexの実行が失敗しました'}[mapped]
                except OSError:
                    pass
            if origin == 'projection': summary += '（履歴キャッシュ・遅延の可能性）'
            result.append(dict(id=row['id'], title=row['name'] or '新しいタスク · ' + row['id'][:8], state=mapped, summary=summary,
                               revision=revision, status_source=origin))
            if github and has_git:
                github.apply(result[-1], (row['cwd'] or '', row['git_branch'] or '', row['git_sha'] or ''))
            if mapped == 'question':
                result[-1].update(state='question',event_type='input.required',summary=summary,revision=revision)
        return dict(ok=True, generated_at=now, threads=result)


def parent_alive(pid):
    if os.name != 'nt':
        try: os.kill(pid, 0); return True
        except OSError: return False
    kernel = ctypes.windll.kernel32
    kernel.OpenProcess.restype = ctypes.c_void_p
    handle = kernel.OpenProcess(0x100000, False, pid)
    if not handle: return False
    kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    alive = kernel.WaitForSingleObject(handle, 0) == 258
    kernel.CloseHandle(handle)
    return alive


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--home', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--parent', type=int)
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--watch-file', type=Path)
    parser.add_argument('--since', type=int)
    args = parser.parse_args()
    github = GitHubPoller()
    while not args.parent or parent_alive(args.parent):
        try:
            watched = []
            if args.watch_file and args.watch_file.exists():
                try:
                    saved = json.loads(args.watch_file.read_text(encoding='utf-8-sig'))
                    watched = [key for key,value in saved.get('tasks',{}).items() if isinstance(value,dict)]
                except (ValueError, AttributeError, OSError): pass
            data = snapshot(args.home, watched=watched, since=args.since, github=github)
        except (sqlite3.Error, OSError):
            data = dict(ok=False, generated_at=int(time.time()), error='Codexのローカルデータを読めません（未起動・形式変更の可能性）')
        temporary = args.output.with_suffix('.tmp')
        try:
            temporary.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
            os.replace(temporary, args.output)
        except OSError:
            # A short Windows sharing lock must not kill the background adapter.
            if args.once: raise
        if args.once: break
        time.sleep(2)
    github.pool.shutdown(wait=False, cancel_futures=True)


if __name__ == '__main__': main()
