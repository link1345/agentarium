"""Incremental lifecycle extraction; never retain conversation content."""
import json
from pathlib import Path

LIFECYCLE = {'task_started': 'working', 'task_complete': 'completed',
             'turn_aborted': 'idle', 'task_aborted': 'idle', 'task_failed': 'failed'}

def lifecycle(raw):
    try:
        record = json.loads(raw)
        event = record.get('payload', {})
        kind = event.get('type')
        stamp = str(record.get('timestamp',''))
        if record.get('type') == 'event_msg' and kind in LIFECYCLE:
            return {'op':kind, 'state': LIFECYCLE[kind], 'revision': 'rollout:' + str(event.get('turn_id','')) + ':' + kind + ':' + stamp}
        if record.get('type') != 'response_item': return None
        if kind == 'function_call' and event.get('name','').split('.')[-1] in ('request_user_input','request_user_input_async'):
            return {'op':'question', 'call_id':event.get('call_id',''), 'async':event['name'].endswith('_async'),
                    'state':'question', 'revision':'question:'+str(event.get('call_id',''))}
        if kind == 'function_call_output':
            return {'op':'answer', 'call_id':event.get('call_id',''), 'revision':'answer:'+stamp}
        if kind == 'message' and event.get('role') == 'user':
            return {'op':'user', 'revision':'user:'+stamp}
        return None
    except (ValueError, AttributeError, TypeError):
        return None


def advance(previous, event):
    if not event: return previous
    previous = previous or {}
    pending = dict(previous.get('_pending', {}))
    op = event['op']
    if op == 'question':
        pending[event['call_id']] = event['async']
        return dict(event, _pending=pending)
    if op == 'answer':
        # Async output only acknowledges that the question was displayed.
        if event['call_id'] not in pending or pending[event['call_id']]: return previous or None
        del pending[event['call_id']]
        if pending: return dict(previous, _pending=pending)
        return dict(event, state='working', _pending={})
    if op == 'user':
        if not pending: return previous or None
        return dict(event, state='working', _pending={})
    if op == 'task_complete' and pending: return previous
    return dict(event, _pending={})

class RolloutReader:
    def __init__(self): self.cache = {}

    def read(self, path):
        path = Path(path)
        stat = path.stat()
        cached = self.cache.get(str(path))
        if cached and cached['size'] == stat.st_size and cached['mtime'] == stat.st_mtime_ns:
            return cached['event']
        if not cached or stat.st_size < cached['size'] or (stat.st_size == cached['size'] and stat.st_mtime_ns != cached['mtime']):
            event, offset = self._latest(path)
        else:
            event, offset = cached['event'], cached['offset']
            with path.open('rb') as source:
                source.seek(offset)
                while True:
                    start = source.tell()
                    raw = source.readline()
                    if not raw: break
                    if not raw.endswith(b'\n'):
                        offset = start
                        break
                    offset = source.tell()
                    event = advance(event, lifecycle(raw))
        self.cache[str(path)] = {'size': stat.st_size, 'mtime': stat.st_mtime_ns, 'offset': offset, 'event': event}
        return event

    def _latest(self, path):
        with path.open('rb') as source:
            source.seek(0, 2)
            end = source.tell()
            position, buffer, offset = end, b'', end
            first = True
            events = []
            while position:
                size = min(position, 65536)
                position -= size
                source.seek(position)
                buffer = source.read(size) + buffer
                if first:
                    boundary = buffer.rfind(b'\n')
                    if boundary < 0: continue
                    offset = position + boundary + 1
                    buffer = buffer[:boundary]
                    first = False
                lines = buffer.split(b'\n')
                buffer = lines.pop(0)
                for raw in reversed(lines):
                    found = lifecycle(raw)
                    if found:
                        events.append(found)
                        if found['op'] == 'task_started':
                            result = None
                            for item in reversed(events): result = advance(result,item)
                            return result, offset
            if first: return None, 0
            found = lifecycle(buffer)
            if found: events.append(found)
            result = None
            for item in reversed(events): result = advance(result,item)
            return result, offset
