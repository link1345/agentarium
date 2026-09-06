import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
from rollout_state import RolloutReader

class Questions(unittest.TestCase):
    def test_async_question_survives_output_and_completion_then_resumes(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'rollout.jsonl';reader=RolloutReader()
            records=[('event_msg',{'type':'task_started','turn_id':'t'}),
                     ('response_item',{'type':'function_call','name':'request_user_input_async','call_id':'q','arguments':'PRIVATE QUESTION'}),
                     ('response_item',{'type':'function_call_output','call_id':'q','output':'{"accepted":true}'}),
                     ('event_msg',{'type':'task_complete','turn_id':'t'})]
            p.write_text(''.join(json.dumps({'type':kind,'payload':payload})+'\n' for kind,payload in records))
            self.assertEqual(reader.read(p)['state'],'question')
            self.assertNotIn('PRIVATE',str(reader.cache))
            with p.open('a') as f:f.write(json.dumps({'type':'response_item','payload':{'type':'message','role':'user','content':'PRIVATE ANSWER'}})+'\n')
            self.assertEqual(reader.read(p)['state'],'working')
            self.assertEqual(RolloutReader().read(p)['state'],'working')

    def test_sync_output_and_partial_call(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'rollout.jsonl';reader=RolloutReader()
            def row(kind,payload):return (json.dumps({'type':kind,'payload':payload})+'\n').encode()
            start=row('event_msg',{'type':'task_started'})
            call=row('response_item',{'type':'function_call','name':'functions.request_user_input','call_id':'q'})
            p.write_bytes(start+call[:20]);self.assertEqual(reader.read(p)['state'],'working')
            with p.open('ab') as f:f.write(call[20:])
            self.assertEqual(reader.read(p)['state'],'question')
            with p.open('ab') as f:f.write(row('response_item',{'type':'function_call_output','call_id':'q'}))
            self.assertEqual(reader.read(p)['state'],'working')

if __name__=='__main__':unittest.main()
