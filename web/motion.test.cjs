const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createBridge}=require('./motion.js');
const vm=require('node:vm');
const {readFileSync}=require('node:fs');
function fixture({secure=true,motionAPI={},orientationAPI={},touch=true,hud=true}={}){
 let now=0;const listeners=new Map(), nodes=new Map(), intervals=[];
 function target(){const handlers=new Map();return {textContent:'',hidden:false,disabled:false,focus(){d.activeElement=this;},width:400,height:700,handlers,addEventListener:(k,v)=>handlers.set(k,v),setAttribute(){},getBoundingClientRect:()=>({left:0,top:0,width:400,height:700}),setPointerCapture(id){this.captured=id;},hasPointerCapture(id){return this.captured===id;},releasePointerCapture(){this.captured=null;}};}
 for(const id of (hud ? ['canvas','motion-status','motion-prompt','motion-title','motion-enable','motion-skip'] : ['canvas']))nodes.set(id,target());
 const d={hidden:false,getElementById:id=>nodes.get(id),addEventListener:(k,v)=>listeners.set('doc:'+k,v)};
 const w={isSecureContext:secure,DeviceMotionEvent:motionAPI,DeviceOrientationEvent:orientationAPI,navigator:{maxTouchPoints:touch?1:0},removeEventListener:k=>listeners.delete(k),screen:{orientation:{angle:0,addEventListener:(k,v)=>listeners.set('screen:'+k,v)}},addEventListener:(k,v)=>listeners.set(k,v),setInterval:f=>intervals.push(f)};
 const api=createBridge(w,d,()=>now);api.bind();
 return {api,w,d,nodes,listeners,advance:t=>now=t,take:()=>JSON.parse(api.take()),fire:(k,e={})=>listeners.get(k)?.(e),status:()=>nodes.get('motion-status').textContent,interval:()=>intervals.forEach(f=>f())};
}
test('both iOS permission calls happen synchronously before awaiting',async()=>{
 const calls=[];let release;const promise=new Promise(r=>release=r);
 const f=fixture({motionAPI:{requestPermission(){calls.push('motion');return promise;}},orientationAPI:{requestPermission(){calls.push('orientation');return Promise.resolve('granted');}}});
 const enabled=f.api.enableMotion();assert.deepEqual(calls,['motion','orientation']);release('granted');assert.equal(await enabled,true);assert.equal(f.api.diagnostics.attached,true);
 await f.api.enableMotion();assert.equal(f.api.diagnostics.attached,true);
});
test('denial, exception, insecure and unsupported remain usable',async()=>{
 for(const args of [{secure:false},{motionAPI:null},{motionAPI:{requestPermission:()=>Promise.resolve('denied')}},{motionAPI:{requestPermission(){throw Error('blocked');}}}]){
  const f=fixture(args);assert.equal(await f.api.enableMotion(),false);assert.match(f.status(),/drag|Try again/);assert.equal(f.api.diagnostics.attached,false);
 }
});
test('null readings and no-events status; timestamp and all three axes collected',async()=>{
 const f=fixture();await f.api.enableMotion();f.advance(3000);f.interval();assert.match(f.status(),/No motion/);
 f.fire('devicemotion',{accelerationIncludingGravity:{x:null,y:null,z:null}});assert.equal(f.take().sample,null);
 f.fire('deviceorientation',{beta:90,gamma:20});f.advance(3010);f.fire('devicemotion',{accelerationIncludingGravity:{x:1,y:2,z:3},acceleration:{x:4,y:5,z:6}});
 assert.deepEqual(f.take().sample,{timestamp_ms:3010,angle:0,including:[1,2,3],acceleration:[4,5,6],orientation:[90,20]});
});
test('hide, blur and rotation invalidate samples and cancel grabs',async()=>{
 const f=fixture();await f.api.enableMotion();f.fire('devicemotion',{accelerationIncludingGravity:{x:0,y:0,z:9.81}});
 f.d.hidden=true;f.fire('doc:visibilitychange');assert.equal(f.take().sample,null);
 f.fire('devicemotion',{accelerationIncludingGravity:{x:1,y:2,z:3}});assert.equal(f.take().sample,null);
 f.d.hidden=false;f.fire('doc:visibilitychange');f.fire('orientationchange');assert.ok(f.take().events.some(e=>e.type==='cancel'));
 f.fire('blur');assert.equal(f.take().sample,null);
});
test('permission interrupted by visibility change is discarded',async()=>{
 let release;const f=fixture({motionAPI:{requestPermission:()=>new Promise(r=>release=r)}});
 const pending=f.api.enableMotion();f.d.hidden=true;f.fire('doc:visibilitychange');release('granted');assert.equal(await pending,false);assert.equal(f.api.diagnostics.attached,false);
});
test('single captured pointer ignores multitouch and cancellation releases capture',()=>{
 const f=fixture();const canvas=f.nodes.get('canvas');const event=id=>({pointerId:id,clientX:100,clientY:200,button:0,preventDefault(){}});
 canvas.handlers.get('pointerdown')(event(1));canvas.handlers.get('pointerdown')(event(2));canvas.handlers.get('pointermove')(event(2));canvas.handlers.get('pointermove')(event(1));canvas.handlers.get('pointerup')(event(1));
 const events=f.take().events;assert.deepEqual(events.map(e=>e.type),['down','move','up']);assert.ok(events.every(e=>e.id===1));assert.equal(events[0].x,0.25);assert.equal(events[0].y,200/700);assert.equal(canvas.captured,null);
 canvas.handlers.get('pointerdown')(event(3));canvas.handlers.get('pointercancel')();assert.equal(canvas.captured,null);assert.equal(f.take().events.at(-1).type,'cancel');
});

test('stale orientation is excluded from a fresh motion event',async()=>{
 const f=fixture();await f.api.enableMotion();f.fire('deviceorientation',{beta:90,gamma:0});f.advance(500);f.fire('devicemotion',{accelerationIncludingGravity:{x:0,y:0,z:9.81}});assert.equal(f.take().sample.orientation,null);
});

test('viewport resize releases pointer capture and leaves sensor input available',async()=>{
 const f=fixture();await f.api.enableMotion();
 f.fire('devicemotion',{accelerationIncludingGravity:{x:0,y:0,z:9.81}});
 const canvas=f.nodes.get('canvas');
 canvas.handlers.get('pointerdown')({pointerId:3,clientX:100,clientY:200,button:0,preventDefault(){}});
 f.take();f.fire('resize');
 const result=f.take();assert.equal(canvas.captured,null);
 assert.equal(result.events.at(-1).type,'cancel');assert.ok(result.sample);
 assert.equal(f.api.diagnostics.attached,true);
});


test('locked portrait keeps display angle while physical right lean changes sensor pose',async()=>{
 const f=fixture();await f.api.enableMotion();
 f.fire('deviceorientation',{beta:60,gamma:90});
 f.fire('devicemotion',{acceleration:{x:0,y:0,z:0}});
 assert.deepEqual(f.take().sample.orientation,[60,90]);
 assert.equal(f.take().sample.angle,0);
 // A physical lean alone does not rotate the locked UI or invalidate the pose.
 f.advance(20);f.fire('deviceorientation',{beta:120,gamma:-90});
 f.fire('devicemotion',{acceleration:{x:0,y:0,z:0}});
 assert.deepEqual(f.take().sample.orientation,[120,-90]);
 assert.equal(f.take().sample.angle,0);
});


test('fresh browser boot never requests permission until Enable motion is clicked',async()=>{
 const calls=[];
 const f=fixture({motionAPI:{requestPermission(){calls.push('motion');return Promise.resolve('granted');}},orientationAPI:{requestPermission(){calls.push('orientation');return Promise.resolve('granted');}}});
 f.w.performance={now:()=>0};
 vm.runInNewContext(readFileSync(`${__dirname}/motion.js`,'utf8'),{window:f.w,document:f.d});
 assert.deepEqual(calls,[]);assert.equal(f.w.CargoHold.diagnostics.permission,'idle');
 assert.equal(f.nodes.get('motion-prompt').hidden,false);assert.equal(f.nodes.get('canvas').inert,true);
 f.nodes.get('motion-enable').handlers.get('click')();
 assert.deepEqual(calls,['motion','orientation']);
 assert.equal(f.nodes.get('motion-enable').disabled,true);
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(f.w.CargoHold.diagnostics.permission,'granted');
 assert.equal(f.nodes.get('motion-prompt').hidden,false);
 f.fire('devicemotion',{accelerationIncludingGravity:{x:0,y:0,z:9.81}});
 assert.equal(f.nodes.get('motion-prompt').hidden,true);assert.equal(f.nodes.get('canvas').inert,false);
});

test('desktop suggests a phone even when browser exposes motion APIs',()=>{
 const f=fixture({touch:false,motionAPI:{requestPermission:()=>Promise.resolve('granted')}});assert.match(f.status(),/Open on your phone/);
 assert.equal(f.nodes.get('motion-skip').textContent,'Play with mouse');
 f.api.focusPrompt();assert.equal(f.d.activeElement,f.nodes.get('motion-skip'));
 f.nodes.get('motion-skip').handlers.get('click')();
 assert.equal(f.nodes.get('motion-prompt').hidden,true);
 const canvas=f.nodes.get('canvas');canvas.handlers.get('pointerdown')({pointerId:1,clientX:100,clientY:200,button:0,preventDefault(){}});
 assert.equal(f.take().events.at(-1).type,'down');
});

test('missing sensor API offers fallback without an enable button',()=>{
 const f=fixture({motionAPI:null});assert.match(f.status(),/phone/);
 assert.equal(f.nodes.get('motion-enable').hidden,true);
 f.api.focusPrompt();assert.equal(f.d.activeElement,f.nodes.get('motion-skip'));
});

test('denial is visible and retry requires another explicit button click',async()=>{
 let calls=0;const f=fixture({motionAPI:{requestPermission:()=>{calls++;return Promise.resolve(calls===1?'denied':'granted');}}});
 assert.equal(await f.api.enableMotion(),false);assert.match(f.status(),/denied/);
 assert.equal(f.nodes.get('motion-enable').disabled,false);
 assert.equal(f.nodes.get('motion-prompt').hidden,false);
 const canvas=f.nodes.get('canvas');assert.equal(canvas.handlers.has('click'),false);
 f.nodes.get('motion-enable').handlers.get('click')();
 await new Promise(resolve=>setImmediate(resolve));assert.equal(calls,2);assert.equal(f.api.diagnostics.permission,'granted');
});

test('NotAllowedError leaves an actionable retry',async()=>{
 const f=fixture({motionAPI:{requestPermission:()=>Promise.reject(Object.assign(new Error('Needs activation'),{name:'NotAllowedError'}))}});
 assert.equal(await f.api.enableMotion(),false);assert.equal(f.api.diagnostics.permission,'gesture');
 assert.match(f.status(),/Try again/);assert.equal(f.nodes.get('motion-enable').disabled,false);
});

test('no readings and null samples keep fallback visible; late valid readings close it',async()=>{
 const f=fixture();await f.api.enableMotion();f.advance(3000);f.interval();
 assert.match(f.status(),/No motion readings/);assert.equal(f.nodes.get('motion-enable').disabled,false);
 f.fire('devicemotion',{accelerationIncludingGravity:{x:null,y:null,z:null}});
 assert.equal(f.nodes.get('motion-prompt').hidden,false);
 f.fire('devicemotion',{accelerationIncludingGravity:{x:0,y:0,z:9.81}});
 assert.equal(f.nodes.get('motion-prompt').hidden,true);
 f.advance(6000);f.interval();assert.equal(f.nodes.get('motion-prompt').hidden,true);
});

test('continue with touch invalidates pending permission and cannot be undone by its result',async()=>{
 let release;const f=fixture({motionAPI:{requestPermission:()=>new Promise(r=>release=r)}});
 const pending=f.api.enableMotion();f.nodes.get('motion-skip').handlers.get('click')();release('granted');
 assert.equal(await pending,false);assert.equal(f.api.diagnostics.permission,'fallback');
 assert.equal(f.api.diagnostics.attached,false);assert.equal(f.nodes.get('motion-prompt').hidden,true);
});

test('continue after sensor timeout detaches readings and keeps manual play available',async()=>{
 const f=fixture();await f.api.enableMotion();f.advance(3000);f.interval();
 f.nodes.get('motion-skip').handlers.get('click')();
 assert.equal(f.api.diagnostics.attached,false);assert.equal(f.api.diagnostics.permission,'fallback');
 f.fire('devicemotion',{accelerationIncludingGravity:{x:0,y:0,z:9.81}});assert.equal(f.take().sample,null);
});

test('duplicate clicks do not overlap permission prompts, and interruption enables retry',async()=>{
 let release,calls=0;const f=fixture({motionAPI:{requestPermission:()=>{calls++;return new Promise(r=>release=r);}}});
 const pending=f.api.enableMotion();assert.equal(await f.api.enableMotion(),false);assert.equal(calls,1);
 f.d.hidden=true;f.fire('doc:visibilitychange');assert.equal(f.nodes.get('motion-enable').disabled,false);
 release('granted');assert.equal(await pending,false);assert.equal(f.api.diagnostics.permission,'gesture');
});

test('prompt keeps keyboard focus on available actions and returns focus to canvas',()=>{
 const f=fixture();f.api.focusPrompt();assert.equal(f.d.activeElement,f.nodes.get('motion-enable'));
 const key=shiftKey=>({key:'Tab',shiftKey,preventDefault(){}});
 const tab=f.nodes.get('motion-prompt').handlers.get('keydown');
 tab(key(false));assert.equal(f.d.activeElement,f.nodes.get('motion-skip'));
 tab(key(false));assert.equal(f.d.activeElement,f.nodes.get('motion-enable'));
 tab(key(true));assert.equal(f.d.activeElement,f.nodes.get('motion-skip'));
 f.nodes.get('motion-skip').handlers.get('click')();assert.equal(f.d.activeElement,f.nodes.get('canvas'));
});

test('synchronous API failures consume all permission rejections without dropping retry UI',async()=>{
 const f=fixture({motionAPI:{requestPermission:()=>Promise.reject(new Error('blocked'))},orientationAPI:{requestPermission(){throw new Error('blocked too');}}});
 assert.equal(await f.api.enableMotion(),false);assert.equal(f.nodes.get('motion-enable').disabled,false);
 assert.equal(f.nodes.get('motion-prompt').hidden,false);
});
