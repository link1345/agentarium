import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

script = Path(__file__).parents[1]/'agentarium-codex-app/skills/create-agentarium-pet/scripts/assemble_native_alpha.py'
spec = importlib.util.spec_from_file_location('native',script)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)

class NativeAlphaTests(unittest.TestCase):
    def test_reject_opaque_and_clipped(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder)/'frame.png'
            Image.new('RGB',(32,32),'white').save(p)
            with self.assertRaisesRegex(ValueError,'native alpha'): native.read_frame(p)
            image=Image.new('RGBA',(32,32))
            image.paste((128,64,192,255),(0,10,20,20));image.save(p)
            with self.assertRaisesRegex(ValueError,'canvas edge'): native.read_frame(p)

    def test_assembly_keeps_alpha_and_unused_cells(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder)
            image=Image.new('RGBA',(32,32))
            image.paste((184,160,237,128),(8,8,24,24));image.save(folder/'frame.png')
            # Synthetic repeats test geometry only, never deliverable animation.
            manifest={'rows':[['frame.png']*n for n in native.COUNTS],'neutral':'frame.png'}
            (folder/'manifest.json').write_text(json.dumps(manifest))
            native.assemble(folder/'manifest.json',folder/'atlas.webp')
            atlas=Image.open(folder/'atlas.webp')
            self.assertEqual(atlas.size,(1536,2288))
            self.assertEqual(atlas.getpixel((96,100))[3],128)
            self.assertIsNone(atlas.crop((7*192,0,8*192,208)).getbbox())

if __name__=='__main__': unittest.main()
