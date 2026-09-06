import sharp from 'sharp';
import { zipSync, strToU8 } from 'fflate';

export const ROWS = [
  ['idle',6],['running-right',8],['running-left',8],['waving',4],['jumping',5],
  ['failed',8],['waiting',6],['running',6],['review',6],['look-upper',8],['look-lower',8]
];
export const PALETTES = { lavender:'#b8a0ed', mint:'#79cbb8', peach:'#e9aa80', rose:'#e9a0bc' };

export function recipe(description, name) {
  return {name, description, width:1536, height:2288, cellWidth:192, cellHeight:208,
    spriteVersionNumber:2, neutralLookCell:{row:0,column:6}, rows:ROWS.map(([state,frames],row)=>({row,state,frames})),
    palettes:PALETTES, sourceHue:0.72, hueTolerance:0.11, background:'native-transparent-alpha', paletteApplication:'runtime-shader',
    prompt:`Create an original ${description} named ${name}. Full body, neutral white face, dark ink outlines, predominantly lavender fur, clean separated color regions. Use the bundled create-agentarium-pet skill: generate a canonical base, then independent animation strips grounded in that base, extract real frames, assemble the exact 8×11 v2 atlas, and inspect every row. Do not generate a decorative grid or duplicate still images to fake animation. Generate a genuinely transparent RGBA background directly in the image tool for every source. Never use chroma-key backgrounds or background removal. Keep one canonical palette and apply palette swaps only at display time.`,
    generation:'Generate genuine transparent RGBA in the host image tool, never chroma-key or background removal. Generate one canonical palette; swap colors at display time. This MCP tool returns a recipe, not generated pixels.'};
}

function hsv(r,g,b) {
  r/=255;g/=255;b/=255;
  const max=Math.max(r,g,b),min=Math.min(r,g,b),d=max-min;
  let h=0;
  if(d) h=(max===r?(g-b)/d+(g<b?6:0):max===g?(b-r)/d+2:(r-g)/d+4)/6;
  return [h,max?d/max:0,max];
}
function rgb(h,s,v) {
  h=((h%1)+1)%1;
  const i=Math.floor(h*6), f=h*6-i,p=v*(1-s),q=v*(1-f*s),t=v*(1-(1-f)*s);
  return [[v,t,p],[q,v,p],[p,v,t],[p,q,v],[t,p,v],[v,p,q]][i%6].map(x=>Math.round(x*255));
}

export async function makePack(input, {name='Pet', palette='mint', sourceHue=0.72, hueTolerance=0.11}={}) {
  const decoded=sharp(input,{limitInputPixels:4_000_000});
  const meta=await decoded.metadata();
  if(meta.width!==1536 || ![1872,2288].includes(meta.height) || !meta.hasAlpha)
    throw new Error('透明アルファ付き1536×1872 (v1) または1536×2288 (v2) の画像が必要です');
  const {data,info}=await decoded.ensureAlpha().raw().toBuffer({resolveWithObject:true});
  const target=PALETTES[palette];
  if(!target) throw new Error('Unknown palette');
  const targetHue=hsv(...[1,3,5].map(i=>parseInt(target.slice(i,i+2),16)))[0];
  let changed=0,transparent=0;
  for(let i=0;i<data.length;i+=4) {
    if(data[i+3]===0) {transparent++;continue;}
    const [h,s,v]=hsv(data[i],data[i+1],data[i+2]);
    const delta=((h-sourceHue+1.5)%1)-0.5;
    if(Math.abs(delta)<=hueTolerance && s>=0.12 && v>=0.45 && palette!=='lavender') {
      const out=rgb(targetHue+delta,s,v);
      data[i]=out[0];data[i+1]=out[1];data[i+2]=out[2];changed++;
    }
  }
  if(transparent<info.width*info.height*0.1) throw new Error('透明領域が不足しています');
  const sheet=await sharp(data,{raw:info}).webp({lossless:true}).toBuffer();
  const slug=name.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')||'pet';
  const manifest={id:`${slug}-${palette}`,displayName:name,description:`${palette} palette variant`,spriteVersionNumber:meta.height===2288?2:1,spritesheetPath:'spritesheet.webp'};
  const settings={sourceHue:palette==='lavender'?sourceHue:targetHue,hueTolerance,minSaturation:0.12,minValue:0.45,palettes:PALETTES};
  const zip=zipSync({'spritesheet.webp':sheet,'pet.json':strToU8(JSON.stringify(manifest,null,2)),
    'palette.json':strToU8(JSON.stringify(settings,null,2))},{level:6});
  return {zip,sheet,manifest,changedPixels:changed,alphaPreserved:true};
}

