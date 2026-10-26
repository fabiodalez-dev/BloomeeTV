import test from 'node:test';
import assert from 'node:assert/strict';
import {playbackState, createPhoneRemote} from '../phone-remote.js';

test('remote state contains only playback metadata', () => {
  const state = playbackState({audio:{paused:false,currentTime:12,duration:Infinity,volume:.5},
    queue:[{Name:'Song',token:'secret',url:'http://private/?key=secret'}], current:0,
    artist:()=> 'Artist',shuffle:false,repeat:true});
  assert.equal(state.positionMs,12000);
  assert.equal(state.durationMs,0);
  assert.equal(state.repeat,'all');
  assert.deepEqual(state.queue,[{title:'Song',artist:'Artist'}]);
  assert.ok(!JSON.stringify(state).includes('secret'));
});
test('mailbox executes a command once and acknowledges it on next tick', async () => {
  let calls=0,executed=0,ack;
  let finish;
  const complete = new Promise(r => finish=r);
  const remote=createPhoneRemote({snapshot:()=>({}),execute:async()=>{executed++;},
    request:async(path,body)=>{
      calls++;ack=body.ack;
      if(calls===1)return {active:true,command:{id:7,action:'next'}};
      finish();return {active:false};
    }});
  remote.start();
  await complete;
  remote.stop();
  assert.equal(executed,1);
  assert.equal(ack,7);
});

test('slow catalog request leaves pause and player state updates responsive',async()=>{
 let resolveSearch,finish,calls=0,paused=false;
 const search=new Promise(r=>resolveSearch=r),done=new Promise(r=>finish=r);
 const remote=createPhoneRemote({snapshot:()=>({playing:!paused}),
  execute:async command=>{if(command.action==='browse')return search;paused=true;return {};},
  request:async(path,body)=>{
   calls++;
   if(calls===1)return {active:true,commands:[{id:1,action:'browse'},{id:2,action:'pause'}]};
   if(calls===2){assert.equal(paused,true);assert.ok(body.acks.some(a=>a.id===2));resolveSearch({items:[]});return {active:true,commands:[{id:1,action:'browse'}]};}
   assert.ok(body.acks.some(a=>a.id===1));finish();return {active:false};
  }});
 remote.start();await done;remote.stop();assert.ok(calls>=3);
});
