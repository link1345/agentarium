// Uses Gua's own MCP bridge client; every UI action goes through Gua.
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const source = process.env.GUA_SOURCE ?? resolve('../gua');
const { GuaBridgeClient } = await import(pathToFileURL(resolve(source, 'packages/mcp/src/index.ts')).href);
const client = new GuaBridgeClient(process.env.GUA_BRIDGE_URL ?? 'ws://127.0.0.1:18765');
const command = process.argv[2] ?? 'tree';
const pause = (ms: number) => new Promise(r => setTimeout(r, ms));
const clicks: unknown[] = [];
async function click(id: string) {
  const receipt = await client.performAction({ action: 'click', nodeId: id });
  if (!receipt) throw new Error('No action receipt: ' + id);
  const result = await client.waitForAction(receipt.requestId, 5000);
  if (!result.succeeded) throw new Error(JSON.stringify(result));
  clicks.push(result);
  await pause(100);
}
async function expect(id: string, text?: string) {
  const deadline = Date.now() + 4000;
  while (Date.now() < deadline) {
    const tree = await client.getUiTree();
    const n = tree.nodes.find((n: any) => n.id === id);
    if (n && (text === undefined || n.label?.includes(text))) return n;
    await pause(60);
  }
  throw new Error(`Expected ${id}: ${text}`);
}
async function screenshot(name: string) {
  await pause(1100); // Host publishes a fresh Gua viewport screenshot once per second.
  const shot = await client.getScreenshot();
  if (!shot.dataUri?.startsWith('data:image/png;base64,')) throw new Error('No Gua screenshot');
  await mkdir('artifacts/screenshots', { recursive: true });
  await writeFile(`artifacts/screenshots/${name}.png`, Buffer.from(shot.dataUri.split(',')[1], 'base64'));
  return shot;
}
try {
  if (command === 'question-watch') {
    const deadline=Date.now()+60000;
    let found=false;
    while(Date.now()<deadline){
      const tree=await client.getUiTree();
      if(tree.nodes.some((n:any)=>n.id==='question-alert')){
        await screenshot('v042-real-question-alert');
        found=true;break;
      }
      await pause(80);
    }
    if(!found)throw Error('Real question alert not received');
    await expect('state','質問待ち');
    await expect('headline','たすけて～～～！！！');
    await expect('stamp-01a07453-9710-7240-a3b4-d8c3eeb20978','stamp-question');
    console.log('PASS real question: full-window alert, question state, headline, icon');
  } else if (command === 'tree') console.log(JSON.stringify(await client.getUiTree()));
  else if (command === 'click') {
    const receipt = await client.performAction({ action: 'click', nodeId: process.argv[3] });
    if (!receipt) throw new Error('Gua returned no receipt');
    const result = await client.waitForAction(receipt.requestId, 5000);
    if (!result.succeeded) throw new Error(JSON.stringify(result));
    console.log(JSON.stringify(result));
  } else if (command === 'screenshot') {
    const name = (process.argv[3] ?? 'current').replace(/[^a-zA-Z0-9_-]/g, '_');
    const shot = await screenshot(name);
    const target = `artifacts/screenshots/${name}.png`;
    console.log(JSON.stringify({path: resolve(target), width: shot.width, height: shot.height}));
  } else if (command === 'v033') {
    const clean=async()=>{
      const tree=await client.getUiTree();
      if(tree.nodes.some((n:any)=>n.id.startsWith('up-')||n.id.startsWith('down-')||n.id.startsWith('list-state-')||n.id.startsWith('task-demo-')))throw Error('Removed UI still present');
      if(tree.nodes.some((n:any)=>n.label?.includes('タブビュー')))throw Error('Tab view still present');
    };
    await expect('sidebar-title');await clean();
    const normal=(await expect('task-sidebar')).bounds;
    await expect('stamp-demo-fox','stamp-flask');
    await click('edit-tasks');await clean();
    const editing=(await expect('task-sidebar')).bounds;
    if(normal.w!==editing.w||normal.x!==editing.x)throw Error('Sidebar width changed');
    const name=(await expect('list-demo-fox')).bounds, close=(await expect('hide-demo-fox')).bounds;
    if(close.x<name.x+name.w||Math.abs((close.y+close.h/2)-(name.y+name.h/2))>1)throw Error('Close button is not beside name');
    await screenshot('v033-edit');await click('edit-tasks');await screenshot('v033-normal');
    for(const [state,id,item] of [['working','fox','flask'],['question','fox','question'],['ci-failed','dog','bomb'],['failed','dog','basin'],['review','bird','balloon'],['completed','fox','gift'],['idle','fox','zzz']]){
      await click('demo-'+state);if(state==='question')await click('question-alert');
      await expect('stamp-demo-'+id,'stamp-'+item);
    }
    await click('settings');await click('layout-compact');await clean();
    await click('list-demo-bird');await expect('thread-title','プルリクエスト');
    await screenshot('v033-compact');
    await writeFile('artifacts/gua-v033-results.json',JSON.stringify({passed:true,sidebarWidth:normal.w,checks:['no order buttons','fixed sidebar width','close beside name','seven matching image stamps','no tabs','compact selection'],at:new Date().toISOString()},null,2));
    console.log('PASS v033: fixed-width sidebar, edit close button, 7 stamps, no tabs');
  } else if (command === 'connect-test') {
    await click('edit-tasks');await click('add-task');
    const enter=async(value:string)=>{
      const receipt=await client.performAction({action:'set_value',nodeId:'new-task-name',value});
      if(!(await client.waitForAction(receipt.requestId,5000)).succeeded)throw Error('Cannot enter link');
      await click('create-task');
    };
    await enter('https://example.com/not-a-codex-thread');await expect('add-error','codex://threads/UUID');
    const link='codex://threads/01a07453-9710-7240-a3b4-d8c3eeb20978';
    await enter(link);await expect('layout-mode','1スレッド');
    await click('add-task');await enter(link);await expect('layout-mode','1スレッド');
    await click('remove-01a07453-9710-7240-a3b4-d8c3eeb20978');await expect('layout-mode','0スレッド');
    await click('add-task');await enter(link);await expect('layout-mode','1スレッド');
    await screenshot('v032-connected-pending');
    console.log('PASS: deep link validation, add, deduplication and hidden-item reconnection');
  } else if (command === 'v031-saved') {
    const tree=await client.getUiTree();
    const ids=tree.nodes.filter((n:any)=>n.id.startsWith('list-')&&!n.id.startsWith('list-state-')).map((n:any)=>n.id);
    if(ids.join(',')!=='list-demo-dog,list-demo-bird,list-demo-fox')throw Error('Saved order not restored: '+ids);
    if(tree.nodes.some((n:any)=>n.id==='add-task'||n.id.startsWith('hide-')||n.id.startsWith('remove-')))throw Error('Editing persisted unexpectedly');
    console.log('PASS: drag order restored on restart; normal mode hides edit controls');
  } else if (command === 'v031') {
    const order=async()=> (await client.getUiTree()).nodes.filter((n:any)=>n.id.startsWith('list-')&&!n.id.startsWith('list-state-')).map((n:any)=>n.id);
    const noEdit=async()=>{
      if((await client.getUiTree()).nodes.some((n:any)=>n.id==='add-task'||n.id.startsWith('hide-')||n.id.startsWith('remove-')))throw Error('Edit controls exposed in normal mode');
    };
    const input=async(value:any)=>{
      const receipt=await client.performGameInput(value);
      const result=await client.waitForGameInput(receipt.requestId,5000);
      if(!result.succeeded)throw Error(JSON.stringify(result));
      await pause(160);
    };
    const drag=async(source:string,target:string)=>{
      const a=(await expect(source)).bounds, b=(await expect(target)).bounds;
      await input({type:'pointer_move',mode:'absolute',coordinateSpace:'viewport_pixels',x:a.x+a.w/2,y:a.y+a.h/2});
      await input({type:'pointer_button_down',button:'primary',leaseMs:4000});
      for(let step=1;step<=8;step++){
        const t=step/8;
        await input({type:'pointer_move',mode:'absolute',coordinateSpace:'viewport_pixels',x:a.x+a.w/2+(b.x+b.w/2-a.x-a.w/2)*t,y:a.y+a.h/2+(b.y+b.h*.8-a.y-a.h/2)*t});
      }
      await screenshot('v031-drop-indicator');
      await input({type:'pointer_button_up',button:'primary'});
      await pause(300);
    };
    await expect('sidebar-title');await noEdit();
    await drag('list-demo-fox','list-demo-bird');
    if((await order()).join(',')!=='list-demo-fox,list-demo-dog,list-demo-bird')throw Error('Normal mode allowed dragging');
    await click('edit-tasks');
    await drag('list-demo-fox','list-demo-bird');
    const actual=await order();
    if(actual.join(',')!=='list-demo-dog,list-demo-bird,list-demo-fox')throw Error('Drag order: '+actual);
    await expect('add-task');await expect('remove-demo-fox');await expect('hide-demo-dog');
    await screenshot('v031-edit');
    await click('hide-demo-dog');await click('add-task');await expect('restore-demo-dog');await click('restore-demo-dog');
    await click('edit-tasks');await noEdit();
    await writeFile('artifacts/gua-v031-results.json',JSON.stringify({passed:true,order:await order(),checks:['native pointer drag and drop','normal mode has no add/remove','edit controls','hide and restore','edit exit'],at:new Date().toISOString()},null,2));
    console.log('PASS v031: Gua native pointer drag, edit controls, hide/restore');
  } else if (command === 'alert-preview') {
    await click('toggle-demo');
    await click('demo-question');
    await expect('question-alert','質問が来ました！');
    await screenshot('v03-final-alert');
    await click('question-alert');
    await expect('state','回答が必要');
    console.log('PASS: final alert visible and dismissed');
  } else if (command === 'v03') {
    await click('edit-tasks');
    await expect('source','DEMO');
    await expect('sidebar-title','タスク一覧');
    await click('down-demo-fox');
    let tree=await client.getUiTree();
    const list=tree.nodes.filter((n:any)=>n.id.startsWith('list-')&&!n.id.startsWith('list-state-'));
    if(list[0]?.id!=='list-demo-dog') throw Error('Order did not change');
    await click('up-demo-fox');
    await click('hide-demo-dog');
    if((await client.getUiTree()).nodes.some((n:any)=>n.id==='list-demo-dog')) throw Error('Hidden task visible');
    await click('add-task');
    await expect('restore-demo-dog');
    await click('restore-demo-dog');
    await expect('list-demo-dog');
    await click('toggle-sidebar');
    if((await client.getUiTree()).nodes.some((n:any)=>n.id==='sidebar-title')) throw Error('Sidebar did not close');
    await click('settings');await click('layout-wide');
    await expect('layout-mode','並列');
    await click('demo-question');
    await expect('question-alert','質問が来ました！');
    await screenshot('v03-alert');
    await click('question-alert');
    await expect('state','回答が必要');
    await screenshot('v03-question-card');
    await click('demo-question');
    await expect('question-alert');
    await pause(4800);
    if((await client.getUiTree()).nodes.some((n:any)=>n.id==='question-alert')) throw Error('Alert failed to expire');
    await expect('state','回答が必要');
    for(const state of ['ci-failed','failed','review','completed','idle','working']){
      await click('demo-'+state);
      await screenshot('v03-'+state);
    }
    await click('settings');await click('layout-compact');
    await expect('layout-mode','タブ');
    await screenshot('v03-compact');
    await click('toggle-sidebar');await expect('sidebar-title');
    await click('list-demo-dog');await expect('thread-title','Windows');
    if((await client.getUiTree()).nodes.some((n:any)=>n.id==='sidebar-title')) throw Error('Compact drawer did not close after selection');
    await click('toggle-demo');
    await click('add-task');
    const receipt=await client.performAction({action:'set_value',nodeId:'new-task-name',value:'codex://threads/00000000-0000-0000-0000-000000000001'});
    if(!(await client.waitForAction(receipt.requestId,5000)).succeeded) throw Error('Text entry failed');
    await click('create-task');
    await expect('thread-title','接続待ち');
    const inbox=resolve(process.env.AGENTARIUM_TEST_DATA_DIR??'artifacts/v03-demo','inbox');
    await mkdir(inbox,{recursive:true});
    const event=async(id:string,type:string)=>writeFile(resolve(inbox,Date.now()+'-'+id+'.json'),JSON.stringify({id:Date.now()+'-'+id,task_id:id,type,title:'自動追加されたタスク',summary:'Gua integration event'}));
    await event('v03-auto','task.started');
    await pause(900);
    await click('toggle-sidebar');await expect('list-v03-auto','自動追加');
    await click('list-v03-auto');
    await event('v03-auto','task.failed');await pause(900);
    await expect('state','失敗');await screenshot('v03-basin');
    await event('v03-auto','input.required');await expect('question-alert');await click('question-alert');
    await click('remove-v03-auto');
    await event('v03-auto','task.progress');await pause(900);
    if((await client.getUiTree()).nodes.some((n:any)=>n.id==='task-v03-auto'))throw Error('Update resurrected hidden task');
    await click('add-task');await expect('restore-v03-auto');await click('restore-v03-auto');
    await expect('thread-title','自動追加');
    await writeFile('artifacts/gua-v03-results.json',JSON.stringify({passed:true,actions:clicks,checks:['reorder','hide/restore','sidebar/drawer','alert dismiss/timeout','seven state items','sleep','manual add','event auto-add','hidden update stays hidden'],at:new Date().toISOString()},null,2));
    console.log('PASS v03: '+clicks.length+' Gua actions');
  } else if (command === 'suite') {
    await expect('source', 'DEMO');
    for (const [state, title] of [['question','質問がた'],['failed','CI、こけ'],['review','レビューのお届け'],['completed','おつかれ'],['idle','ひとやすみ'],['working','こつこつ']]) {
      await click('demo-' + state);
      await expect('headline', title);
      await screenshot(state);
    }
    await click('demo-question');
    await click('acknowledge');
    await expect('state', '質問待ち');
    if ((await expect('acknowledge')).enabled) throw new Error('Acknowledgement must disable itself');
    await click('settings');
    await expect('settings-title');
    await click('focus-mode');
    await expect('focus-mode', 'ON');
    await expect('headline', '質問待ち');
    await screenshot('settings');
    await click('focus-mode');
    await click('reduced-motion');
    await expect('reduced-motion', 'ON');
    await click('reduced-motion');
    await click('palette-swap');
    await expect('palette-swap','2');
    await click('layout-compact');
    await expect('layout-mode','タブビュー');
    await expect('thread-title','Agentariumを育てる');
    await screenshot('responsive-compact');
    await click('task-demo-dog');
    await expect('thread-title','WindowsのCI');
    await click('task-demo-fox');
    await click('settings');
    await click('layout-wide');
    await expect('layout-mode','並列ビュー');
    await expect('thread-title-demo-dog','WindowsのCI');
    await screenshot('responsive-wide');
    await click('mode-mascot');
    await expect('mascot-state', '質問待ち');
    const shot = await screenshot('mascot');
    if (shot.width !== 360 || shot.height !== 320) throw new Error('Wrong mascot dimensions');
    await click('mascot-next');
    await expect('mascot-summary', 'Windows');
    await click('mode-theater');
    await expect('brand');
    await click('toggle-demo');
    await expect('source', 'CODEX');
    await click('toggle-demo');
    await screenshot('working');
    await writeFile('artifacts/gua-ui-results.json', JSON.stringify({passed:true, actions:clicks, checked:['six events','acknowledgement preserves state','quiet mode','reduced motion','mascot switch','pet cycle','empty live mode'],at:new Date().toISOString()},null,2));
    console.log(`PASS: ${clicks.length} Gua UI actions and screenshots`);
  } else if (command === 'expect') {
    console.log(JSON.stringify(await expect(process.argv[3],process.argv[4])));
  } else if (command === 'set-value') {
    const receipt = await client.performAction({action:'set_value',nodeId:process.argv[3],value:process.argv[4]});
    if (!receipt) throw new Error('No Gua value receipt');
    const result=await client.waitForAction(receipt.requestId,5000);
    if(!result.succeeded) throw new Error(JSON.stringify(result));
    console.log(JSON.stringify(result));
  } else if (command === 'input') {
    const receipt = await client.performGameInput(JSON.parse(process.argv[3]));
    const result = await client.waitForGameInput(receipt.requestId,5000);
    if (!result.succeeded) throw new Error(JSON.stringify(result));
    console.log(JSON.stringify(result));
  } else if (command === 'drag') {
    for (const input of [
      {type:'pointer_move',mode:'absolute',coordinateSpace:'viewport_pixels',x:175,y:170},
      {type:'pointer_button_down',button:'primary',leaseMs:3000},
      {type:'pointer_move',mode:'delta',x:30,y:20},
      {type:'pointer_button_up',button:'primary'}
    ]) {
      const receipt = await client.performGameInput(input);
      const result = await client.waitForGameInput(receipt.requestId,5000);
      if (!result.succeeded) throw new Error(JSON.stringify(result));
      await pause(150);
    }
    await screenshot('mascot-dragged');
    console.log('Gua pointer drag completed');
  } else if (command === 'clock') console.log(await client.controlClock({type: process.argv[3]}));
  else throw new Error(`Unknown command ${command}`);
} finally { client.close(); }


