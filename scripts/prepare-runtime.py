"""Package the current Windows Python 3.12 runtime for the read-only sync worker."""
from pathlib import Path
import shutil
import sys
import zipfile

source=Path(sys.base_prefix)
target=Path(__file__).resolve().parents[1]/'runtime/python'
if sys.platform!='win32' or sys.version_info[:2]!=(3,12):
    raise SystemExit('Run with a Windows CPython 3.12 installation.')
target.mkdir(parents=True,exist_ok=True)
shutil.copy2(Path(__file__).resolve().parents[1]/'docs/licenses/libffi.txt',target/'LICENSE-libffi.txt')
for name in ['python.exe','pythonw.exe','python312.dll','python3.dll','vcruntime140.dll','vcruntime140_1.dll','LICENSE.txt']:
    if (source/name).exists(): shutil.copy2(source/name,target/name)
(target/'DLLs').mkdir(exist_ok=True)
for name in ['_sqlite3.pyd','sqlite3.dll','_ctypes.pyd','libffi-8.dll','_socket.pyd','select.pyd','_decimal.pyd']:
    if (source/'DLLs'/name).exists(): shutil.copy2(source/'DLLs'/name,target/'DLLs'/name)
with zipfile.ZipFile(target/'python312.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for file in (source/'Lib').rglob('*.py'):
        relative=file.relative_to(source/'Lib')
        if not any(x in relative.parts for x in ['site-packages','test','tests','idlelib','tkinter','ensurepip','venv','__pycache__']):
            archive.write(file,str(relative))
(target/'python312._pth').write_text('python312.zip\nDLLs\n.\n',encoding='utf-8')
print(target)

