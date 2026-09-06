"""Package built Windows app, source, and ChatGPT app without local conversation data."""
from pathlib import Path
import os
import zipfile

root=Path(__file__).resolve().parents[1]
ignored={'node_modules','__pycache__','.godot','.git','artifacts','dist','runtime'}

def add_tree(archive,folder,prefix):
    for current,dirs,files in os.walk(folder):
        dirs[:]=[name for name in dirs if name not in ignored]
        for name in files:
            if name.endswith(('.import','.pyc')) or name.startswith('.env'): continue
            file=Path(current)/name
            archive.write(file,str(Path(prefix)/file.relative_to(folder)))

out=root/'artifacts';out.mkdir(exist_ok=True)
with zipfile.ZipFile(out/'Agentarium-0.4.3-windows-x64.zip','w',zipfile.ZIP_DEFLATED) as archive:
    # Runtime is required in the Windows distribution, unlike source packages.
    for file in (root/'dist').rglob('*'):
        if file.is_file() and file.name!='.gdignore': archive.write(file,str(file.relative_to(root/'dist')))
with zipfile.ZipFile(out/'Agentarium-0.4.3-source.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for name in ['README.md','LICENSE','THIRD_PARTY_NOTICES.md','project.godot','Main.tscn','export_presets.cfg','.gitignore']:
        archive.write(root/name,name)
    for folder in ['core','scripts','assets','addons','tests','docs','agentarium-codex-app']:
        add_tree(archive,root/folder,folder)
with zipfile.ZipFile(out/'agentarium-codex-app-0.3.0.zip','w',zipfile.ZIP_DEFLATED) as archive:
    add_tree(archive,root/'agentarium-codex-app','agentarium-codex-app')
    archive.write(root/'LICENSE','agentarium-codex-app/LICENSE')
with zipfile.ZipFile(out/'create-agentarium-pet-0.3.0.zip','w',zipfile.ZIP_DEFLATED) as archive:
    add_tree(archive,root/'agentarium-codex-app/skills/create-agentarium-pet','create-agentarium-pet')
for file in out.glob('*0.3.0*.zip'): print(file.name,file.stat().st_size)




