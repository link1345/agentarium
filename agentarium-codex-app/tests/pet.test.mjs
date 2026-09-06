import {test} from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {makePack,recipe} from '../pet-tools.mjs';
import {unzipSync} from 'fflate';

test('recipe specifies all real animation rows and native-generation boundary',()=>{
 const r=recipe('lavender fox','Lumi');
 assert.equal(r.rows.length,11);assert.equal(r.rows[7].state,'running');
 assert.match(r.generation,/not generated pixels/);
});
test('palette preserves alpha, neutrals and exact atlas dimensions',async()=>{
 const data=Buffer.alloc(1536*1872*4);
 for(let i=0;i<100;i++) {data.set([184,160,237,255],i*4);}
 data.set([255,255,255,129],400);data.set([25,25,25,255],404);
 const original=await sharp(data,{raw:{width:1536,height:1872,channels:4}}).png().toBuffer();
 const pack=await makePack(original,{palette:'mint',name:'Test'});
 const decoded=await sharp(pack.sheet).raw().toBuffer();
 assert.equal(pack.changedPixels,100);
 assert.notDeepEqual(decoded.subarray(0,3),data.subarray(0,3));
 assert.deepEqual(decoded.subarray(400,408),data.subarray(400,408));
 for(let i=3;i<data.length;i+=4) assert.equal(decoded[i],data[i]);
 assert.equal(pack.manifest.spriteVersionNumber,1);
 assert.deepEqual(Object.keys(unzipSync(pack.zip)).sort(),['palette.json','pet.json','spritesheet.webp']);
});
test('wrong dimensions rejected',async()=>{
 const input=await sharp({create:{width:10,height:10,channels:4,background:'#ffffff00'}}).png().toBuffer();
 await assert.rejects(makePack(input),/1536/);
});
