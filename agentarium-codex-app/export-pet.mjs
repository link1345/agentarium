// Local counterpart of swap_pet_palette, using the exact same app implementation.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {makePack,PALETTES} from './pet-tools.mjs';

const [source,output,hue='0.72',name='Pet']=process.argv.slice(2);
if(!source||!output) throw new Error('Usage: node export-pet.mjs <atlas> <output-dir> [source-hue] [name]');
const bytes=await readFile(resolve(source));
const folder=resolve(output);await mkdir(folder,{recursive:true});
const report={app:'agentarium-codex-app',sourceHash:createHash('sha256').update(bytes).digest('hex'),outputs:[]};
for(const palette of Object.keys(PALETTES)) {
  const result=await makePack(bytes,{name,palette,sourceHue:Number(hue)});
  await writeFile(join(folder,`${palette}.zip`),result.zip);
  await writeFile(join(folder,`${palette}.webp`),result.sheet);
  report.outputs.push({palette,changedPixels:result.changedPixels,alphaPreserved:result.alphaPreserved,spriteVersionNumber:result.manifest.spriteVersionNumber,sha256:createHash('sha256').update(result.sheet).digest('hex')});
}
await writeFile(join(folder,'app-export-report.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
