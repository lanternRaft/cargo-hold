/* Sensor collection and DOM lifecycle only. Motion physics lives in GDScript. */
(function (root) {
  'use strict';
  function createBridge(w, d, clock = () => w.performance.now()) {
    let sample = null, orientation = null, orientationTime = -Infinity, events = [], activePointer = null;
    let attached = false, permission = 'idle', lastEvent = -Infinity, started = 0, epoch = 0;
    let report = null, canvas = null;
    let promptDismissed = false;
    const touch = () => (w.navigator?.maxTouchPoints || 0) > 0 || !!w.matchMedia?.('(pointer: coarse)').matches;
    const angle = () => Number(w.screen?.orientation?.angle ?? w.orientation ?? 0);
    const triple = v => v && ['x', 'y', 'z'].every(k => Number.isFinite(v[k])) ? [v.x, v.y, v.z] : null;
    function status(message) {
      const label = d.getElementById('motion-status');
      if (label) label.textContent = message;
    }
    function prompt(message, {title = 'Tilt & shake', label = 'Try again', disabled = false, available = true} = {}) {
      status(message);
      const heading = d.getElementById('motion-title'), button = d.getElementById('motion-enable');
      if (heading) heading.textContent = title;
      if (button) { button.textContent = label; button.disabled = disabled; button.hidden = !available; }
    }
    function showWelcome() {
      const overlay = d.getElementById('motion-prompt');
      if (overlay) { overlay.hidden = false; overlay.setAttribute('data-input', touch() ? 'touch' : 'mouse'); canvas.inert = true; }
      const fallback = d.getElementById('motion-skip');
      if (fallback) fallback.textContent = touch() ? 'Continue with touch' : 'Play with mouse';
      if (!w.isSecureContext || !w.DeviceMotionEvent) {
        prompt('Open on your phone for tilt & shake. You can also drag to grab, throw and tilt the box here.', {title:'Play your way', available:false});
      } else if (!touch()) {
        // Desktop browsers may expose the API even without physical sensors.
        prompt('Open on your phone for tilt & shake. Or play here: drag shapes to throw them and empty space to tilt.', {title:'Better on your phone', label:'Try motion on this device'});
      } else {
        prompt('Enable motion to tilt & shake the cargo with your device. You can also drag to play.', {label:'Enable motion'});
      }
    }
    function focusPrompt() {
      const overlay = d.getElementById('motion-prompt');
      if (!overlay || overlay.hidden) return;
      overlay.inert = false;
      const enable = d.getElementById('motion-enable');
      (touch() && enable && !enable.hidden && !enable.disabled ? enable : d.getElementById('motion-skip'))?.focus();
    }
    function dismissPrompt() {
      promptDismissed = true;
      const overlay = d.getElementById('motion-prompt');
      if (overlay) { overlay.hidden = true; canvas.inert = false; canvas.focus(); }
    }
    function continueWithoutMotion() {
      epoch++; permission = 'fallback'; invalidate();
      if (attached) {
        w.removeEventListener('devicemotion', motion);
        w.removeEventListener('deviceorientation', orient);
        attached = false;
      }
      dismissPrompt();
    }
    function motion(e) {
      if (d.hidden) return;
      const including = triple(e.accelerationIncludingGravity), acceleration = triple(e.acceleration);
      const currentOrientation = clock()-orientationTime <= 350 ? orientation : null;
      if (!including && !currentOrientation) { status('No sensor readings · drag to play'); return; }
      lastEvent = clock();
      sample = {timestamp_ms:lastEvent, angle:angle(), including, acceleration, orientation:currentOrientation};
      status('Motion on · tilt & shake');
      if (!promptDismissed) dismissPrompt();
    }
    function orient(e) {
      orientation = Number.isFinite(e.beta) && Number.isFinite(e.gamma) ? [e.beta, e.gamma] : null;
      orientationTime = clock();
    }
    function attach() {
      if (attached) return;
      w.addEventListener('devicemotion', motion);
      w.addEventListener('deviceorientation', orient);
      attached = true;
    }
    function cancel() {
      events.push({type:'cancel'});
      if (activePointer !== null && canvas?.hasPointerCapture(activePointer)) canvas.releasePointerCapture(activePointer);
      activePointer = null;
    }
    function invalidate() { sample = null; orientation = null; orientationTime = -Infinity; lastEvent = -Infinity; cancel(); }
    // Called synchronously in the DOM click stack: both privileged requests
    // happen BEFORE awaiting either result (iOS transient user activation).
    function enableMotion() {
      if (permission === 'requesting') return Promise.resolve(false);
      if (!w.isSecureContext) { permission='insecure'; prompt('Motion needs HTTPS · drag to play', {available:false}); return Promise.resolve(false); }
      if (!w.DeviceMotionEvent) { permission='unsupported'; prompt('Motion unavailable · open on your phone or drag to play', {available:false}); return Promise.resolve(false); }
      const generation = ++epoch;
      permission = 'requesting';
      prompt('Allow motion in your browser’s permission prompt.', {label:'Waiting for permission…', disabled:true});
      const requests = [];
      for (const api of [w.DeviceMotionEvent, w.DeviceOrientationEvent]) {
        try {
          if (typeof api?.requestPermission === 'function') requests.push(Promise.resolve(api.requestPermission()));
        } catch (error) { requests.push(Promise.reject(error)); }
      }
      return Promise.allSettled(requests).then(outcomes => {
        if (generation !== epoch || d.hidden) return false;
        const failure = outcomes.find(result => result.status === 'rejected');
        if (failure) return permissionFailure(failure.reason);
        if (outcomes.some(result => result.value !== 'granted')) {
          permission='denied';
          prompt('Motion access was denied. Try again, or check your browser’s site permissions and continue with touch or mouse.');
          return false;
        }
        permission='granted'; started=clock(); invalidate(); attach();
        prompt('Tilt or shake your device to start. Waiting for sensor readings…', {label:'Motion enabled', disabled:true});
        return true;
      });
    }
    function permissionFailure(error) {
      permission = error?.name === 'NotAllowedError' ? 'gesture' : 'denied';
      prompt(permission === 'gesture' ? 'Tap Try again to allow motion. If access stays blocked, check your browser’s site permissions or drag to play.' : 'Motion could not be enabled. Try again or drag to play.');
      return Promise.resolve(false);
    }
    function pointer(e, type) {
      if (type === 'down') {
        if (activePointer !== null || e.button > 0) return;
        activePointer = e.pointerId;
        canvas.setPointerCapture(activePointer);
      }
      if (e.pointerId !== activePointer) return;
      const rect = canvas.getBoundingClientRect();
      events.push({type,id:e.pointerId,x:(e.clientX-rect.left)/rect.width,y:(e.clientY-rect.top)/rect.height,time:clock()});
      e.preventDefault();
      if (type === 'up') {
        const id = activePointer; activePointer = null;
        if (canvas.hasPointerCapture(id)) canvas.releasePointerCapture(id);
      }
    }
    function bind() {
      canvas = d.getElementById('canvas');
      // Keep privileged requests directly inside this explicit DOM click.
      d.getElementById('motion-enable')?.addEventListener('click', () => enableMotion());
      d.getElementById('motion-skip')?.addEventListener('click', continueWithoutMotion);
      showWelcome();
      const overlay = d.getElementById('motion-prompt');
      overlay?.addEventListener('keydown', e => {
        if (e.key !== 'Tab') return;
        const buttons = ['motion-enable','motion-skip'].map(id => d.getElementById(id)).filter(button => button && !button.hidden && !button.disabled);
        const index = buttons.indexOf(d.activeElement);
        buttons[(index + (e.shiftKey ? -1 : 1) + buttons.length) % buttons.length]?.focus();
        e.preventDefault();
      });
      for (const [event,type] of [['pointerdown','down'],['pointermove','move'],['pointerup','up']]) canvas.addEventListener(event, e => pointer(e,type));
      canvas.addEventListener('pointercancel', cancel);
      canvas.addEventListener('lostpointercapture', () => { if (activePointer !== null) cancel(); });
      w.addEventListener('resize', cancel);
      w.addEventListener('blur', invalidate);
      function interrupt() {
        epoch++;
        if (permission === 'requesting') { permission='gesture'; prompt('Motion permission was interrupted. Try again or drag to play.'); }
        invalidate();
      }
      w.addEventListener('pagehide', interrupt);
      d.addEventListener('visibilitychange', () => { interrupt(); if (!d.hidden && permission==='granted') started=clock(); });
      w.addEventListener('orientationchange', invalidate);
      w.screen?.orientation?.addEventListener('change', invalidate);
      w.setInterval(() => {
        if (!d.hidden && permission==='granted' && clock()-Math.max(lastEvent,started)>2500) {
          if (!promptDismissed) prompt('No motion readings received. Open on a phone for tilt & shake, try again, or drag to play.', {title:'No motion readings'});
          else status('No motion readings · drag to play');
        }
      },1000);
    }
    const api = {
      enableMotion, bind, focusPrompt,
      take() { const result={now_ms:clock(),hidden:d.hidden,sample,events,permission}; events=[]; return JSON.stringify(result); },
      report(value) { report=value; d.getElementById('canvas')?.setAttribute('data-simulation',JSON.stringify(value)); },
      get diagnostics() { return {permission,attached,report}; },
    };
    return api;
  }
  if (typeof module !== 'undefined') module.exports={createBridge};
  else { root.CargoHold=createBridge(root,document); root.CargoHold.bind(); }
})(typeof window !== 'undefined' ? window : globalThis);
