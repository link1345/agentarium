"""Read-only GitHub polling. Uses the user's gh login; never stores credentials."""
import hashlib
import json
import os
import re
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor


def run(args):
    env = dict(os.environ, GH_PROMPT_DISABLED='1', GIT_TERMINAL_PROMPT='0')
    return subprocess.run(args, capture_output=True, text=True, encoding='utf-8',
                          errors='replace', timeout=15, check=True, env=env,
                          creationflags=0x08000000 if os.name == 'nt' else 0).stdout.strip()


def repository(url):
    match = re.fullmatch(r'(?:https://github\.com/|ssh://git@github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?/?', url)
    return match.group(1) if match else None


def classify(pr):
    checks = pr.get('statusCheckRollup') or []
    failed = [c for c in checks if (c.get('conclusion') or c.get('state')) in
              ('FAILURE', 'ERROR', 'TIMED_OUT', 'STARTUP_FAILURE', 'ACTION_REQUIRED')]
    reviews = [r for r in pr.get('reviews', []) if r.get('state') in
               ('APPROVED', 'CHANGES_REQUESTED', 'COMMENTED') and r.get('submittedAt')]
    if failed:
        key = json.dumps(sorted((c.get('name', c.get('context', 'CI')), c.get('detailsUrl', c.get('targetUrl', '')), c.get('completedAt', '')) for c in failed))
        return {'event_type': 'ci.failed', 'state': 'failed', 'key': key,
                'summary': 'GitHub CI失敗 · PR #' + str(pr['number'])}
    if reviews:
        latest = max(reviews, key=lambda r: r['submittedAt'])
        return {'event_type': 'review.received', 'state': 'review',
                'key': str(latest.get('id', latest['submittedAt'])) + latest['state'],
                'summary': 'GitHubレビュー到着 · PR #' + str(pr['number']) + ' · ' + latest['state']}
    return {}


def fetch(context):
    cwd, recorded_branch, recorded_sha = context
    try:
        local_branch = run(['git', '-C', cwd, 'branch', '--show-current'])
        branch = recorded_branch or local_branch
        if not branch: return {'status': 'GitHub: ブランチ未特定'}
        origin = repository(run(['git', '-C', cwd, 'remote', 'get-url', 'origin']))
        if not origin: return {'status': 'GitHub: 対象外のリモート'}
        repos = [origin]
        try:
            upstream = repository(run(['git', '-C', cwd, 'remote', 'get-url', 'upstream']))
            if upstream and upstream not in repos: repos.append(upstream)
        except subprocess.CalledProcessError: pass
        fields = 'number,url,headRefName,headRefOid,headRepository,headRepositoryOwner,statusCheckRollup,reviews'
        matches = []
        for repo in repos:
            prs = json.loads(run(['gh', 'pr', 'list', '--repo', 'github.com/' + repo,
                                  '--head', branch, '--state', 'open', '--limit', '100', '--json', fields]))
            for pr in prs:
                owner = (pr.get('headRepositoryOwner') or {}).get('login', '')
                name = (pr.get('headRepository') or {}).get('name', '')
                if (owner + '/' + name).lower() == origin.lower() and pr.get('headRefName') == branch:
                    matches.append((repo, pr))
        if len(matches) > 1: return {'status': 'GitHub: PRが複数あり特定できません'}
        if matches:
            repo, pr = matches[0]
            event = classify(pr)
            event.update(status='GitHub: ' + repo + ' #' + str(pr['number']), url=pr['url'])
            if event.get('key'):
                event['key'] = repo + ':' + str(pr['number']) + ':' + pr['headRefOid'] + ':' + event['key']
            return event
        sha = run(['git', '-C', cwd, 'rev-parse', 'HEAD']) if branch == local_branch else recorded_sha
        if not sha: return {'status': 'GitHub: PRなし・コミット未特定'}
        runs = json.loads(run(['gh', 'run', 'list', '--repo', 'github.com/' + origin,
                              '--branch', branch, '--commit', sha, '--limit', '100',
                              '--json', 'databaseId,workflowName,conclusion,status,url,createdAt']))
        latest = {}
        for item in sorted(runs, key=lambda r: r['createdAt'], reverse=True):
            latest.setdefault(item['workflowName'], item)
        failed = [r for r in latest.values() if r['conclusion'] in ('failure', 'timed_out', 'startup_failure', 'action_required')]
        if failed:
            return {'status': 'GitHub: ' + origin + ' / ' + branch, 'state': 'failed', 'event_type': 'ci.failed',
                    'summary': 'GitHub Actions失敗 · ' + branch, 'url': failed[0]['url'],
                    'key': origin + ':' + sha + ':' + str(sorted(r['databaseId'] for r in failed))}
        return {'status': 'GitHub: ' + origin + ' / ' + branch + ' · CI失敗なし'}
    except FileNotFoundError:
        return {'status': 'GitHub: Git / GitHub CLI (gh) が必要です'}
    except (subprocess.SubprocessError, ValueError, KeyError, TypeError, OSError):
        return {'status': 'GitHub: 取得失敗（ghのログイン・権限・接続を確認）'}


class GitHubPoller:
    def __init__(self):
        self.pool = ThreadPoolExecutor(max_workers=2)
        self.cache = {}

    def apply(self, task, context):
        if not context[0]: return
        now = time.monotonic()
        entry = self.cache.setdefault(context, {'at': 0, 'future': None, 'data': {}})
        future = entry['future']
        if future and future.done():
            entry.update(data=future.result(), future=None, at=now)
        if entry['future'] is None and (entry['at'] == 0 or now-entry['at'] >= 60):
            entry['future'] = self.pool.submit(fetch, context)
        data = entry['data']
        task['github_status'] = data.get('status', 'GitHub: 確認中')
        task['github_url'] = data.get('url', '')
        if data.get('event_type'):
            task.update(state=data['state'], event_type=data['event_type'], summary=data['summary'])
            task['revision'] = 'github:' + hashlib.sha256(data['key'].encode()).hexdigest()
