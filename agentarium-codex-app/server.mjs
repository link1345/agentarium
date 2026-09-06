// Small tool-only app based on the official Apps SDK Streamable HTTP quickstart.
import { pathToFileURL } from 'node:url';
import { createServer } from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { randomUUID, timingSafeEqual, createHash } from 'node:crypto';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';
import { recipe, makePack, PALETTES } from './pet-tools.mjs';

const port=Number(process.env.PORT||8788);
const publicUrl=(process.env.PUBLIC_BASE_URL||`http://127.0.0.1:${port}`).replace(/\/$/,'');
const skill=readFileSync(new URL('./skills/create-agentarium-pet/SKILL.md',import.meta.url),'utf8');
const files=new Map();
const annotations={readOnlyHint:true,destructiveHint:false,openWorldHint:false,idempotentHint:true};
const fileSchema=z.object({download_url:z.string().url(),file_id:z.string(),mime_type:z.string().optional(),file_name:z.string().optional()});
const MAX_BYTES=20*1024*1024;

function registerSkill(server) {
  const base=new URL('./skills/create-agentarium-pet/',import.meta.url);
  const resources=[];
  function walk(relative='') {
    for(const item of readdirSync(new URL(relative,base),{withFileTypes:true})) {
      if(item.name.startsWith('.')||item.name==='__pycache__') continue;
      const path=relative+item.name;
      if(item.isDirectory()) {walk(path+'/');continue;}
      if(!/\.(md|py|json|yaml|txt)$/.test(path) && !/LICENSE/.test(path)) continue;
      const bytes=readFileSync(new URL(path,base));
      if(bytes.length>1024*1024) throw new Error('Skill resource too large');
      const uri='skill://agentarium-codex-app/create-agentarium-pet/'+path;
      resources.push({uri,digest:'sha256:'+createHash('sha256').update(bytes).digest('hex')});
      server.registerResource(path,uri,{},async()=>({contents:[{uri,mimeType:'text/plain',text:bytes.toString('utf8')}]}));
    }
  }
  walk();
  if(resources.length>100) throw new Error('Skill resource count exceeds import limit');
  const entry={uri:'skill://agentarium-codex-app/create-agentarium-pet/SKILL.md',
    frontmatter:{name:skill.match(/^name: (.+)$/m)[1],description:skill.match(/^description: (.+)$/m)[1]},resources};
  server.server.registerCapabilities({extensions:{'io.modelcontextprotocol/skills':{}}});
  server.server.setRequestHandler(z.object({method:z.literal('skills/list'),params:z.object({cursor:z.string().optional()}).optional()}),async({params})=>({skills:params?.cursor?[]:[entry]}));
  server.server.setRequestHandler(z.object({method:z.literal('skills/get'),params:z.object({uri:z.string()})}),async({params})=>{
    if(params.uri!==entry.uri) throw new Error('Unknown skill');
    return {skill:entry};
  });
}

async function download(file) {
  const url=new URL(file.download_url);
  const extra=(process.env.ALLOWED_FILE_HOSTS||'').split(',').filter(Boolean);
  if(url.protocol!=='https:' || url.username || url.password ||
    !(url.hostname==='files.oaiusercontent.com' || url.hostname.endsWith('.oaiusercontent.com') || extra.includes(url.hostname)))
    throw new Error('ChatGPTが認可したファイルのHTTPSダウンロードURLが必要です');
  const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(20000)});
  if(!response.ok || Number(response.headers.get('content-length')||0)>MAX_BYTES) throw new Error('ファイルを取得できません');
  let bytes=0;const chunks=[];
  for await(const chunk of response.body) {
    bytes+=chunk.length;
    if(bytes>MAX_BYTES) {await response.body.cancel().catch(()=>{});throw new Error('画像は20 MiBまでです');}
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function createPetServer() {
  const server=new McpServer({name:'agentarium-codex-app',version:'0.3.0'});
  registerSkill(server);
  server.registerResource('pet-generation-skill','agentarium://skills/create-agentarium-pet',{},async()=>({contents:[{uri:'agentarium://skills/create-agentarium-pet',mimeType:'text/markdown',text:skill}]}));
  server.registerTool('get_pet_recipe',{
    title:'ペット画像の生成レシピ',description:'Use this when creating an original animated pet. Returns the exact ChatGPT/Codex v2 sprite format and bundled generation skill. Follow it with host-native image generation; this tool does not itself generate images.',
    inputSchema:{name:z.string().min(1).max(80),description:z.string().min(1).max(1000)},
    outputSchema:{recipe:z.object({name:z.string(),description:z.string(),width:z.number(),height:z.number(),cellWidth:z.number(),cellHeight:z.number(),spriteVersionNumber:z.number(),neutralLookCell:z.object({row:z.number(),column:z.number()}),rows:z.array(z.object({row:z.number(),state:z.string(),frames:z.number()})),palettes:z.record(z.string()),sourceHue:z.number(),hueTolerance:z.number(),background:z.string(),paletteApplication:z.string(),prompt:z.string(),generation:z.string()})},annotations
  },async({name,description})=>({structuredContent:{recipe:recipe(description,name)},content:[{type:'text',text:skill}]}));
  server.registerTool('swap_pet_palette',{
    title:'ペットの色違いパックを作成',description:'Use this when the user provides a finished transparent v1 or v2 pet atlas and wants a palette variant. Preserves alpha, neutral regions and animation layout. Returns a temporary downloadable Agentarium pet ZIP; does not install or publish it.',
    inputSchema:{file:fileSchema,name:z.string().min(1).max(80),palette:z.enum(Object.keys(PALETTES)),sourceHue:z.number().min(0).max(1).default(.72),hueTolerance:z.number().min(.01).max(.2).default(.11)},
    outputSchema:{downloadUrl:z.string(),name:z.string(),palette:z.string(),changedPixels:z.number(),alphaPreserved:z.boolean(),expiresInSeconds:z.number()},
    annotations:{...annotations,readOnlyHint:false,idempotentHint:false},_meta:{'openai/fileParams':['file']}
  },async({file,...options})=>{
    try {
      const result=await makePack(await download(file),options);
      for(const [id,item] of files) if(item.expires<Date.now()) files.delete(id);
      if(files.size>=16) return {isError:true,content:[{type:'text',text:'同時出力の上限です。しばらく待って再試行してください。'}]};
      const token=randomUUID();files.set(token,{bytes:result.zip,expires:Date.now()+3600_000});
      setTimeout(()=>files.delete(token),3600_000).unref();
      const downloadUrl=`${publicUrl}/files/${token}.zip`;
      return {structuredContent:{downloadUrl,name:options.name,palette:options.palette,changedPixels:result.changedPixels,alphaPreserved:true,expiresInSeconds:3600},content:[{type:'text',text:'色違いのペットパックを作成しました。ダウンロード後、Agentariumのペット取り込みで選択してください。'},{type:'resource_link',uri:downloadUrl,name:'agentarium-pet.zip',mimeType:'application/zip'}]};
    } catch(error) {return {isError:true,content:[{type:'text',text:error.message}]};}
  });
  return server;
}

function authorized(req) {
  const token=process.env.MCP_AUTH_TOKEN;
  if(!token) return true;
  const actual=Buffer.from(req.headers.authorization||''),expected=Buffer.from(`Bearer ${token}`);
  return actual.length===expected.length && timingSafeEqual(actual,expected);
}

export function start() {
  return createServer(async(req,res)=>{
    const path=(req.url||'/').split('?')[0];
    if(path==='/health') {res.writeHead(200,{'Content-Type':'application/json'}).end('{"ok":true}');return;}
    // Download URLs are random, expiring capability URLs; no directory listing.
    const match=path.match(/^\/files\/([a-f0-9-]{36})\.zip$/);
    if(match && req.method==='GET') {
      const file=files.get(match[1]);
      if(!file||file.expires<Date.now()) {res.writeHead(404).end();return;}
      res.writeHead(200,{'Content-Type':'application/zip','Content-Disposition':'attachment; filename="agentarium-pet.zip"','Cache-Control':'no-store'}).end(file.bytes);return;
    }
    if(path!=='/mcp') {res.writeHead(404).end();return;}
    if(!authorized(req)) {res.writeHead(401).end();return;}
    const origin=req.headers.origin;
    if(origin && !['https://chatgpt.com',publicUrl].includes(origin)) {res.writeHead(403).end();return;}
    if(req.method==='OPTIONS') {res.writeHead(204,{'Access-Control-Allow-Origin':origin||publicUrl,'Access-Control-Allow-Methods':'POST,GET,OPTIONS','Access-Control-Allow-Headers':'content-type,mcp-session-id,mcp-protocol-version,authorization'}).end();return;}
    if(!['POST','GET','DELETE'].includes(req.method)) {res.writeHead(405).end();return;}
    const server=createPetServer();
    const transport=new StreamableHTTPServerTransport({sessionIdGenerator:undefined,enableJsonResponse:true});
    res.on('close',()=>{transport.close();server.close();});
    try {await server.connect(transport);await transport.handleRequest(req,res);}
    catch {if(!res.headersSent) res.writeHead(500).end('MCP request failed');}
  }).listen(port,process.env.HOST||'127.0.0.1',()=>console.log(`Agentarium MCP ready on port ${port}`));
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) start();


