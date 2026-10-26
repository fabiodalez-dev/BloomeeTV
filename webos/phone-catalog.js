// The phone sees only opaque capabilities and display text. All service objects
// and playable URLs remain in this TV process.
export function createRemoteCatalog({storage, youtubeSearch, youtubeLibrary, youtubeCollection,
  jellyfinSearch, jellyfinCollection, connected, play, enqueue}) {
  let epoch=0, sequence=0;
  const entries=new Map(), pages=new Map();
  const key='bloomee.remote.playlists';
  const current=e=>{if(e!==epoch)throw Error('Collegamento cambiato. Ripeti la ricerca.');};
  const id=()=>epoch+'-'+(++sequence);
  function register(entry) {
    const token=id();entries.set(token,entry);
    if(entries.size>6000)entries.delete(entries.keys().next().value);
    return {id:token,title:entry.title,artist:entry.artist||'',kind:entry.kind,source:entry.source,
      editable:false,...(entry.owner ? {owner:entry.owner}: {})};
  }
  function entry(token) {const e=entries.get(token);if(!e)throw Error('Risultato scaduto. Aggiorna l’elenco.');return e;}
  function page(load) {
    const token=id();let pending=null;
    pages.set(token,()=>pending||(pending=load().catch(e=>{pending=null;throw e;})));
    if(pages.size>100)pages.delete(pages.keys().next().value);
    return token;
  }
  function locals() {try {const p=JSON.parse(storage.getItem(key)||'[]');return Array.isArray(p)?p:[];} catch(_){return [];} }
  const names=t=>(t.Artists||[]).join(', ')||t.AlbumArtist||'';
  const song=(t,source,owner)=>register({title:t.Name,artist:names(t),kind:'song',source,tracks:async()=>[t],owner});
  function yt(item) {
    if(item.kind==='song')return song(item.track,'YouTube');
    return register({title:item.title,artist:item.subtitle,kind:'playlist',source:'YouTube',tracks:()=>youtubeCollection(item.browseId)});
  }
  function jf(item) {
    if(item.Type==='Audio')return song(item,'Jellyfin');
    return register({title:item.Name,artist:'Playlist Jellyfin',kind:'playlist',source:'Jellyfin',tracks:()=>jellyfinCollection(item.Id)});
  }
  function local(p) {return register({title:p.name,artist:'Playlist locale',kind:'playlist',source:'Locale',localId:p.id,
    tracks:async()=>{const found=locals().find(t=>t.id===p.id);if(!found)throw Error('Playlist non disponibile.');return found.tracks;}});}
  async function collection(token,start,cached) {
    const e=epoch, item=entry(token), tracks=cached||await item.tracks();current(e);
    return {items:tracks.slice(start,start+50).map(t=>song(t,item.source,item.localId?token:null)),
      total:tracks.length,title:item.title,editable:false,errors:[],
      next:start+50<tracks.length?page(()=>collection(token,start+50,tracks)):null};
  }
  async function search(query,filter,source,cursor,library) {
    const e=epoch, items=[], errors=[], next={}, initial=!Object.keys(cursor).length;
    const jobs=[];
    function run(name,load) {
      if(!initial&&!Object.prototype.hasOwnProperty.call(cursor,name))return;
      let accepted=true;
      let timer;
      const guard=()=>accepted&&e===epoch;
      const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{accepted=false;reject(Error());},12000);});
      jobs.push(Promise.race([load(guard),timeout]).catch(()=>errors.push(name+' non disponibile. Riprova.')).finally(()=>{accepted=false;clearTimeout(timer);}));
    }
    if(source==='all'||source==='local')run('Locale',async guard=>{
      if((filter==='playlists'||library)&&guard()){const found=locals().filter(p=>p.name.toLowerCase().includes(query.toLowerCase())),start=cursor.Locale||0;items.push(...found.slice(start,start+30).map(local));if(start+30<found.length)next.Locale=start+30;}
    });
    if(source==='all'||source==='youtube')run('YouTube',async guard=>{
      if(library) {
        if(!connected().youtube)return;
        const found=await youtubeLibrary();if(guard()){const start=cursor.YouTube||0;items.push(...found.slice(start,start+30).map(yt));if(start+30<found.length)next.YouTube=start+30;}
      } else {
        const found=await youtubeSearch(query,filter==='playlists'?'playlist':'song',cursor.YouTube);
        if(!guard())return;
        items.push(...found.items.filter(t=>filter==='playlists'?t.kind==='playlist'&&t.browseId:t.kind==='song'&&t.track).map(yt));
        if(found.next&&JSON.stringify(found.next)!==JSON.stringify(cursor.YouTube))next.YouTube=found.next;
      }
    });
    if(connected().jellyfin&&(source==='all'||source==='jellyfin'))run('Jellyfin',async guard=>{
      const start=cursor.Jellyfin||0;
      const found=await jellyfinSearch(query,filter==='playlists'?'Playlist':'Audio',start);
      if(!guard())return;
      items.push(...found.map(jf));if(found.length===30)next.Jellyfin=start+found.length;
    });
    await Promise.all(jobs);current(e);
    return {items,errors,next:Object.keys(next).length?page(()=>search(query,filter,source,next,library)):null};
  }
  async function browse(body) {
    if(body.cursor) {const load=pages.get(body.cursor);if(!load)throw Error('Pagina scaduta. Aggiorna l’elenco.');return load();}
    if(body.kind==='collection')return collection(body.id,0);
    return search((body.query||'').trim(),body.kind==='playlists'?'playlists':body.filter||'songs',body.source||'all',{},body.kind==='playlists');
  }
  async function command(action,value) {
    const e=epoch;
    if(!['playItem','enqueueItem','shuffleItem'].includes(action))throw Error('Comando non disponibile.');
    const item=entry(value),tracks=await item.tracks();current(e);
    if(!tracks.length)throw Error('Questa playlist non contiene brani riproducibili.');
    if(action==='enqueueItem')enqueue(tracks);
    else await play(tracks,item.title,action==='shuffleItem');
    return {};
  }
  return {browse,command,reset(){epoch++;entries.clear();pages.clear();}};
}
