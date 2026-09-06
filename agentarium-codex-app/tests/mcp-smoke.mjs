import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StreamableHTTPClientTransport} from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import {writeFile} from 'node:fs/promises';
import {z} from 'zod';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const client=new Client({name:'agentarium-contract-test',version:'1'});
await client.connect(new StreamableHTTPClientTransport(new URL('http://127.0.0.1:8788/mcp')));
try {
 const tools=await client.listTools();
 assert.deepEqual(tools.tools.map(x=>x.name).sort(),['get_pet_recipe','swap_pet_palette']);
 const catalog=await client.request({method:'skills/list',params:{}},z.object({skills:z.array(z.any())}));
 assert.equal(catalog.skills.length,1);
 for(const entry of catalog.skills[0].resources) {
  const r=await client.readResource({uri:entry.uri});
  assert.equal('sha256:'+createHash('sha256').update(r.contents[0].text).digest('hex'),entry.digest);
 }
 const result=await client.callTool({name:'get_pet_recipe',arguments:{name:'Lumi',description:'a small lavender cat-fox with neutral white face, dark ink eyes and teal inner ears'}});
 assert.equal(result.structuredContent.recipe.spriteVersionNumber,2);
 await writeFile(new URL('../../artifacts/pet-production/lumi/mcp-recipe.json',import.meta.url),JSON.stringify(result,null,2));
 const resource=await client.readResource({uri:'agentarium://skills/create-agentarium-pet'});
 assert.match(resource.contents[0].text,/host.*native image generation/i);
 const blocked=await client.callTool({name:'swap_pet_palette',arguments:{file:{download_url:'http://127.0.0.1/private',file_id:'test'},name:'Lumi',palette:'mint'}});
 assert.equal(blocked.isError,true);
 console.log('PASS MCP: initialize, tools/list, recipe, bundled skill, rejected unsafe file URL');
} finally {await client.close();}

