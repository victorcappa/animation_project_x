// mediaBridge.js — plain JS
(function () {
  var audioEl = null;
  var audioCtx = null;
  var analyser = null;
  var srcNode = null;
  var rafId = 0;

  function log() {
    try { window.LOG && window.LOG.postMessage && window.LOG.postMessage(Array.from(arguments).join(' ')); } catch (e) {}
    try { console.log('[WAVE]', ...arguments); } catch (e) {}
  }

  function ensureAudioGraph() {
    if (!audioEl) {
      audioEl = document.createElement('audio');
      audioEl.setAttribute('playsinline', 'true'); // iOS inline
      audioEl.crossOrigin = 'anonymous';           // remote audio + analyser
      document.body.appendChild(audioEl);
    }
    if (!audioCtx) {
      var AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) { log('No AudioContext available'); return; }
      audioCtx = new AC();
      var resume = function () { if (audioCtx && audioCtx.state === 'suspended') { audioCtx.resume().catch(function(){}); } };
      window.addEventListener('touchend', resume, { once: true });
      window.addEventListener('click', resume, { once: true });
    }
    if (!analyser && audioCtx) {
      analyser = audioCtx.createAnalyser();
      analyser.fftSize = 1024;
    }
    if (!srcNode && audioEl && audioCtx) {
      srcNode = audioCtx.createMediaElementSource(audioEl);
      srcNode.connect(analyser);
      // Comment next line if you want visuals but no audible output
      analyser.connect(audioCtx.destination);
    }
  }

  function startDraw() {
    if (!analyser) return;
    cancelAnimationFrame(rafId);
    var canvas = document.getElementById('wave-canvas');
    if (!canvas) return;
    var ctx = canvas.getContext('2d');
    var buf = new Uint8Array(analyser.frequencyBinCount);

    function draw() {
      rafId = requestAnimationFrame(draw);
      analyser.getByteTimeDomainData(buf);
      var w = canvas.width = canvas.clientWidth || canvas.offsetWidth || 300;
      var h = canvas.height = canvas.clientHeight || canvas.offsetHeight || 150;
      ctx.clearRect(0, 0, w, h);
      ctx.lineWidth = 2;
      ctx.strokeStyle = '#2ecc71';
      ctx.beginPath();
      var step = w / buf.length;
      for (var i = 0; i < buf.length; i++) {
        var x = i * step;
        var y = (buf[i] / 255) * h;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
    draw();
  }

  // Ensure canvas & HUD exist
  (function ensureCanvasAndHUD() {
    if (!document.getElementById('wave-canvas')) {
      var c = document.createElement('canvas');
      c.id = 'wave-canvas';
      c.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;';
      document.body.appendChild(c);
    }
    if (!document.getElementById('wave-hud')) {
      var hud = document.createElement('div');
      hud.id = 'wave-hud';
      hud.style.cssText = 'position:fixed;left:8px;bottom:8px;background:#0008;color:#fff;padding:8px 10px;border-radius:8px;font:12px/1.3 system-ui;z-index:9999';
      hud.innerHTML = '' +
        '<div>state: <b id="wave-state">idle</b></div>' +
        '<div>ctx: <span id="ctx-state">-</span></div>' +
        '<div>time: <span id="audio-time">0.0</span></div>';
      document.body.appendChild(hud);
      setInterval(function () {
        var cs = document.getElementById('ctx-state');
        var at = document.getElementById('audio-time');
        if (cs) cs.textContent = audioCtx ? audioCtx.state : '-';
        if (at) at.textContent = audioEl ? String(audioEl.currentTime.toFixed(1)) : '0.0';
      }, 250);
    }
  })();

  // ===== Flutter -> Web events =====
  window.addEventListener('wave:attachMedia', function (e) {
    var d = e && e.detail || {};
    if (!d.url) return;
    ensureAudioGraph();
    audioEl.src = d.url;
    audioEl.loop = !!d.loop;
    audioEl.volume = Math.max(0, Math.min(1, (typeof d.volume === 'number' ? d.volume : 1)));
    log('attachMedia', d.url, 'vol', audioEl.volume, 'loop', audioEl.loop);
    if (d.autoplay && audioEl.play) {
      audioEl.play().then(function(){ log('autoplay ok'); }).catch(function(err){ log('autoplay failed', err); });
    }
    startDraw();
  });

  window.addEventListener('wave:mediaPlay', function () {
    if (!audioEl || !audioEl.play) return;
    audioEl.play().then(function(){ log('play ok'); }).catch(function(err){ log('play failed', err); });
  });

  window.addEventListener('wave:mediaPause', function () {
    if (audioEl && audioEl.pause) audioEl.pause();
    log('pause');
  });

  window.addEventListener('wave:mediaVolume', function (e) {
    var v = e && e.detail ? e.detail.volume : undefined;
    if (audioEl && typeof v === 'number') {
      audioEl.volume = Math.max(0, Math.min(1, v));
      log('volume', audioEl.volume);
    }
  });

  window.addEventListener('wave:detachMedia', function () {
    if (audioEl) { try { audioEl.pause(); } catch (e) {} audioEl.src = ''; }
    if (srcNode) { try { srcNode.disconnect(); } catch (e) {} srcNode = null; }
    log('detach');
  });

  // ===== State event =====
  window.addEventListener('wave-state', function (e) {
    var s = e && e.detail ? e.detail.state : undefined;
    log('state', s);
    var tag = document.getElementById('wave-state');
    if (tag) tag.textContent = s || 'unknown';
    if (s === 'active') startDraw();
  });

  log('mediaBridge ready');
})();
