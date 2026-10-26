// Only playback display metadata crosses the LAN, never source credentials.
export function playbackState({audio, queue, current, artist, shuffle, repeat}) {
  const item=queue[current], ms=value=>Number.isFinite(value)?Math.max(0,Math.round(value*1000)):0;
  return {title:item?item.Name:'Nessun brano',artist:item?artist(item):'',playing:!audio.paused&&!!item,
    positionMs:ms(audio.currentTime),durationMs:ms(audio.duration),volume:audio.volume,shuffle,repeat:repeat?'all':'off',index:current,
    queueTotal:queue.length,queue:queue.slice(0,500).map(t=>({title:t.Name,artist:artist(t)}))};
}

export function createPhoneRemote({request,snapshot,execute}) {
  let timer=null,running=false,epoch=0,last=null;
  const processing=new Set(), completed=new Set(), acknowledgements=new Map();
  async function tick(e) {
    if(!running||e!==epoch)return;
    const sent=Array.from(acknowledgements.values());
    try {
      const result=await request('/remote/tick',{state:snapshot(),acks:sent,
        ack:last&&last.id,error:last&&last.error,response:last&&last.response});
      if(!running||e!==epoch)return;
      sent.forEach(a=>acknowledgements.delete(a.id));
      if(!result.active){stop();return;}
      const commands=result.commands||(result.command?[result.command]:[]);
      commands.forEach(command=>{
        if(completed.has(command.id)||processing.has(command.id))return;
        processing.add(command.id);
        // Searches may load in parallel while pause/volume controls stay quick.
        const finish=(response,error)=>{
          if(e!==epoch)return;
          last={id:command.id,response:response||{},error:error||null};
          acknowledgements.set(command.id,last);completed.add(command.id);processing.delete(command.id);
          if(completed.size>100)completed.delete(completed.values().next().value);
        };
        Promise.resolve().then(()=>execute(command)).then(data=>finish(data,null),
          failure=>finish(null,failure&&failure.message?failure.message:'Comando non riuscito'));
      });
    } catch(_) { /* Acknowledgements are retried; completed actions are not replayed. */ }
    finally {if(running&&e===epoch)timer=setTimeout(()=>tick(e),400);}
  }
  function stop(){running=false;epoch++;clearTimeout(timer);}
  return {start(){if(!running){running=true;epoch++;last=null;processing.clear();completed.clear();acknowledgements.clear();tick(epoch);}},stop};
}
