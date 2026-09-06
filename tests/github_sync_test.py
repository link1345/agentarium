import sys
import json
import unittest
from pathlib import Path
from contextlib import contextmanager

@contextmanager
def patched(obj, name, return_value=None, side_effect=None):
    old=getattr(obj,name)
    def replacement(*args):
        if isinstance(side_effect,Exception): raise side_effect
        return side_effect(*args) if side_effect else return_value
    setattr(obj,name,replacement)
    try: yield
    finally: setattr(obj,name,old)
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
import github_sync as gh

def pr():
    return dict(number=12,url='https://github.com/acme/app/pull/12',headRefName='feature',headRefOid='abc',
                headRepositoryOwner={'login':'acme'},headRepository={'name':'app'},
                statusCheckRollup=[],reviews=[])

class GitHubTests(unittest.TestCase):
    def test_remotes(self):
        for url in ['https://github.com/acme/app.git','git@github.com:acme/app.git','ssh://git@github.com/acme/app']:
            self.assertEqual(gh.repository(url),'acme/app')
        for url in ['https://github.com.evil/acme/app','https://token@github.com/acme/app','https://gitlab.com/acme/app']:
            self.assertIsNone(gh.repository(url))

    def test_ci_review_and_recovery(self):
        p=pr();p['reviews']=[dict(id='r1',state='APPROVED',submittedAt='2026-09-06')]
        p['statusCheckRollup']=[dict(name='test',conclusion='FAILURE')]
        self.assertEqual(gh.classify(p)['event_type'],'ci.failed')
        p['statusCheckRollup'][0]['conclusion']='SUCCESS'
        self.assertEqual(gh.classify(p)['event_type'],'review.received')
        p['reviews'][0]['state']='DISMISSED'
        self.assertEqual(gh.classify(p),{})

    def test_pending_cancelled_and_legacy_status(self):
        p=pr();p['reviews']=[dict(state='PENDING',submittedAt=None)]
        p['statusCheckRollup']=[dict(conclusion='CANCELLED')]
        self.assertEqual(gh.classify(p),{})
        p['statusCheckRollup']=[dict(context='ci',state='ERROR')]
        self.assertEqual(gh.classify(p)['event_type'],'ci.failed')

    def fake_run(self,args):
        if args[0]=='git':
            if 'origin' in args:return 'git@github.com:acme/app.git'
            if 'upstream' in args:return 'git@github.com:acme/app.git'
            return 'feature'
        if args[1]=='pr':return json.dumps(self.prs)
        return '[]'

    def test_exact_head_and_ambiguous_pr(self):
        self.prs=[pr()]
        with patched(gh,'run',side_effect=self.fake_run):
            self.assertIn('#12',gh.fetch(('repo','feature','abc'))['status'])
            self.prs.append(pr())
            self.assertIn('複数',gh.fetch(('repo','feature','abc'))['status'])
            self.prs=[pr()];self.prs[0]['headRepositoryOwner']['login']='someone-else'
            self.assertNotIn('#12',gh.fetch(('repo','feature','abc'))['status'])

    def test_missing_cli(self):
        with patched(gh,'run',side_effect=FileNotFoundError()):
            self.assertIn('必要',gh.fetch(('repo','',''))['status'])

    def test_async_overlay_stable_revision_and_recovery(self):
        poller=gh.GitHubPoller();context=('repo','','')
        data={'status':'GitHub: acme/app #12','event_type':'ci.failed','state':'failed','summary':'CI失敗','key':'k'}
        with patched(gh,'fetch',return_value=data):
            task={'state':'working','revision':'turn1'};poller.apply(task,context)
            future=poller.cache[context]['future'];future.result(timeout=2)
            poller.apply(task,context)
            revision=task['revision'];self.assertEqual(task['event_type'],'ci.failed')
            other={'state':'completed','revision':'turn2'};poller.apply(other,context)
            self.assertEqual(other['revision'],revision)
            poller.cache[context]['data']={'status':'GitHub: CI失敗なし'}
            recovered={'state':'completed','revision':'turn2'};poller.apply(recovered,context)
            self.assertEqual(recovered['state'],'completed')
        poller.pool.shutdown()

if __name__=='__main__':unittest.main()
