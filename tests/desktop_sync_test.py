from contextlib import closing
import hashlib
import json
import os
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('desktop_sync',Path(__file__).parents[1]/'scripts/desktop_sync.py')
sync=importlib.util.module_from_spec(spec);spec.loader.exec_module(sync)

class SyncTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.home=Path(self.temp.name)
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db:
            db.execute('CREATE TABLE threads(id TEXT,name TEXT,title TEXT,updated_at INT,recency_at INT,archived INT,source TEXT)')
            db.executemany('INSERT INTO threads VALUES(?,?,?,?,?,?,?)',[
                ('user','正確な画面名','PRIVATE PROMPT',100,100,0,'vscode'),
                ('archived','古い','PRIVATE',99,99,1,'vscode'),
                ('agent','内部','PRIVATE',110,110,0,'{"subagent":{}}'),
                ('nameless',None,'PRIVATE',111,111,0,'vscode')])
        with closing(sqlite3.connect(self.home/'thread_history_1.sqlite',isolation_level=None)) as db:
            db.execute('CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,status TEXT,started_at INT,completed_at INT,rollout_ordinal INT)')
            db.execute("INSERT INTO thread_turns VALUES('user','turn','inProgress',100,NULL,0)")
    def tearDown(self): self.temp.cleanup()
    def test_exact_name_filter_and_readonly(self):
        paths=list(self.home.glob('*.sqlite'));before=[hashlib.sha256(p.read_bytes()).digest() for p in paths]
        data=sync.snapshot(self.home,200)
        self.assertEqual(len(data['threads']),2)
        task=next(t for t in data['threads'] if t['id']=='user')
        self.assertEqual(task['title'],'正確な画面名')
        self.assertEqual(task['state'],'working')
        self.assertEqual(data['threads'][0]['title'],'新しいタスク · nameless')
        self.assertNotIn('PRIVATE',str(data))
        self.assertEqual(before,[hashlib.sha256(p.read_bytes()).digest() for p in paths])
    def test_updates_and_unknown(self):
        for status,expected in [('completed','completed'),('failed','failed'),('interrupted','idle'),('futureStatus','idle')]:
            with closing(sqlite3.connect(self.home/'thread_history_1.sqlite',isolation_level=None)) as db: db.execute('UPDATE thread_turns SET status=?',(status,))
            self.assertEqual(next(t for t in sync.snapshot(self.home)['threads'] if t['id']=='user')['state'],expected)
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db: db.execute("UPDATE threads SET name='変更した名前' WHERE id='user'")
        self.assertEqual(next(t for t in sync.snapshot(self.home)['threads'] if t['id']=='user')['title'],'変更した名前')
    def test_missing_database_fails_without_creating(self):
        other=self.home/'missing';other.mkdir()
        with self.assertRaises(sqlite3.OperationalError): sync.snapshot(other)
        self.assertEqual(list(other.iterdir()),[])
    def test_query_only(self):
        with sync.connect(self.home/'state_5.sqlite') as db:
            with self.assertRaises(sqlite3.OperationalError): db.execute('DELETE FROM threads')

    def test_first_launch_boundary_and_explicit_old_task(self):
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db:
            db.execute('ALTER TABLE threads ADD COLUMN created_at INT DEFAULT 50')
        self.assertEqual(sync.snapshot(self.home,since=200)['threads'],[])
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db:
            db.execute("UPDATE threads SET updated_at=400,recency_at=400 WHERE id='user'")
        self.assertEqual(sync.snapshot(self.home,since=200)['threads'],[])
        self.assertEqual(sync.snapshot(self.home,since=200,watched=['user'])['threads'][0]['id'],'user')
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db:
            db.execute("INSERT INTO threads VALUES('new',NULL,'PRIVATE',300,300,0,'vscode',300)")
        self.assertEqual([t['id'] for t in sync.snapshot(self.home,since=200)['threads']],['new'])

    def test_new_task_before_name_and_later_rename(self):
        before={t['id'] for t in sync.snapshot(self.home)['threads']}
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db:
            db.execute("INSERT INTO threads VALUES('new','', 'PRIVATE PROMPT',300,300,0,'vscode')")
        task=sync.snapshot(self.home)['threads'][0]
        self.assertNotIn(task['id'],before)
        self.assertEqual(task['title'],'新しいタスク · new')
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db:
            db.execute("UPDATE threads SET name='確定した名前' WHERE id='new'")
        self.assertEqual(sync.snapshot(self.home)['threads'][0]['title'],'確定した名前')
        self.assertNotIn('PRIVATE',str(sync.snapshot(self.home)))

    def test_live_rollout_overrides_stale_projection(self):
        path=self.home/'live.jsonl'
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db:
            db.execute('ALTER TABLE threads ADD COLUMN rollout_path TEXT')
            stored=('\\\\?\\'+str(path)) if os.name=='nt' else str(path)
            db.execute("UPDATE threads SET rollout_path=? WHERE id='user'",(stored,))
        with closing(sqlite3.connect(self.home/'thread_history_1.sqlite',isolation_level=None)) as db:
            db.execute("UPDATE thread_turns SET status='interrupted'")
        for kind,expected in [('task_started','working'),('task_complete','completed'),('task_started','working'),('turn_aborted','idle')]:
            with path.open('a') as out:
                out.write(json.dumps({'type':'event_msg','payload':{'type':kind,'turn_id':'new','last_agent_message':'SECRET BODY'}})+'\n')
            task=next(t for t in sync.snapshot(self.home)['threads'] if t['id']=='user')
            self.assertEqual(task['state'],expected)
            self.assertEqual(task['status_source'],'rollout')
            self.assertNotIn('SECRET',str(task))

    def test_partial_rollout_and_truncation(self):
        path=self.home/'partial.jsonl';reader=sync.RolloutReader()
        def record(kind): return json.dumps({'type':'event_msg','payload':{'type':kind}}).encode()+b'\n'
        start=record('task_started');done=record('task_complete')
        path.write_bytes(start+done[:20])
        self.assertEqual(reader.read(path)['state'],'working')
        with path.open('ab') as out: out.write(done[20:])
        self.assertEqual(reader.read(path)['state'],'completed')
        path.write_bytes(start)
        self.assertEqual(reader.read(path)['state'],'working')
        with path.open('ab') as out:
            out.write(b'invalid\n'+json.dumps({'type':'response_item','payload':{'type':'task_complete'}}).encode()+b'\n')
        self.assertEqual(reader.read(path)['state'],'working')

    def test_linked_thread_outside_recent_window(self):
        with closing(sqlite3.connect(self.home/'state_5.sqlite',isolation_level=None)) as db:
            db.executemany('INSERT INTO threads VALUES(?,?,?,?,?,?,?)',[(f'recent-{i}',f'Recent {i}','PRIVATE',200+i,200+i,0,'vscode') for i in range(25)])
        self.assertNotIn('user',[t['id'] for t in sync.snapshot(self.home)['threads']])
        linked=sync.snapshot(self.home,watched=['user','user','missing',"' OR 1=1 --"])
        self.assertEqual(len([t for t in linked['threads'] if t['id']=='user']),1)
        self.assertEqual(next(t for t in linked['threads'] if t['id']=='user')['title'],'正確な画面名')
        self.assertNotIn('PRIVATE',str(linked))

if __name__=='__main__': unittest.main()
