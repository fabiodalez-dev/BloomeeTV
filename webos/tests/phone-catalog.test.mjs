import test from 'node:test';
import assert from 'node:assert/strict';
import {createRemoteCatalog} from '../phone-catalog.js';
function setup(overrides={}){
 const storage=new Map(),played=[],queued=[],q=[{Id:'q',Name:'Queue song',Artists:['Artist']}];
 const catalog=createRemoteCatalog({storage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)},
  connected:()=>({youtube:true,jellyfin:true}),queue:()=>q,
  youtubeSearch:async()=>({items:[{kind:'song',track:{source:'youtube',Name:'YT song',videoId:'abcdefghijk',Artists:['Artist'],cookie:'SECRET'}}],next:null}),
  youtubeLibrary:async()=>[{kind:'playlist',title:'YT playlist',browseId:'VL123'}],youtubeCollection:async()=>[{Name:'Playlist song',source:'youtube',videoId:'abcdefghijk'}],
  jellyfinSearch:async()=>[],jellyfinCollection:async()=>[],play:async(tracks,title,shuffle)=>played.push({tracks,title,shuffle}),enqueue:t=>queued.push(...t),...overrides});
 return {catalog,played,queued,storage};
}
test('search result capabilities play and enqueue without exposing service data',async()=>{
 const {catalog,played,queued}=setup();
 const page=await catalog.browse({kind:'search',query:'song',source:'youtube'});
 assert.ok(!JSON.stringify(page).includes('SECRET'));const song=page.items[0];
 await catalog.command('playItem',song.id);assert.equal(played[0].tracks[0].Name,'YT song');
 await catalog.command('enqueueItem',song.id);assert.equal(queued.length,1);
 catalog.reset();await assert.rejects(catalog.command('playItem',song.id),/scaduto/);
});
test('existing local playlists open and play without writes',async()=>{
 const {catalog,storage,played}=setup();
 const before=JSON.stringify([{id:'existing',name:'Viaggio',tracks:[{Id:'a',Name:'Song A'}]}]);
 storage.set('bloomee.remote.playlists',before);
 const p=(await catalog.browse({kind:'playlists',source:'local'})).items[0];assert.equal(p.editable,false);
 const tracks=await catalog.browse({kind:'collection',id:p.id});assert.equal(tracks.total,1);
 await catalog.command('playItem',p.id);assert.equal(played[0].tracks[0].Name,'Song A');
 await catalog.command('shuffleItem',p.id);assert.equal(played[1].shuffle,true);
 for(const action of ['createPlaylist','saveQueue','playlistAdd','playlistRemove','playlistRename'])await assert.rejects(catalog.command(action,p.id),/disponibile/);
 assert.equal(storage.get('bloomee.remote.playlists'),before);
});
test('existing local lists paginate without duplicate retries',async()=>{
 const {catalog,storage}=setup();
 storage.set('bloomee.remote.playlists',JSON.stringify(Array.from({length:31},(_,i)=>({id:'p'+i,name:'List '+i,tracks:[]}))));
 const first=await catalog.browse({kind:'playlists',source:'local'});assert.equal(first.items.length,30);
 const second=await catalog.browse({cursor:first.next});assert.equal(second.items.length,1);
 assert.strictEqual(await catalog.browse({cursor:first.next}),second);
});
