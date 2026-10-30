// Play-test helper for the local preview: drives the game through DOM events only (the game itself is closed in an IIFE).
// Load in the browser console:  eval(await fetch('tools/playbot.js').then(r => r.text()))
// PB.pace sets the delay between actions (ms) so a person can follow along.
window.PB = (() => {
  const KEY = 'rlyeh-merge-v2', COLS = 7;
  const w = ms => new Promise(r => setTimeout(r, ms));
  const st = () => JSON.parse(localStorage.getItem(KEY));
  const $ = id => document.getElementById(id);
  const PB = { pace: 650, log: [] };
  const note = m => { PB.log.push(m); };

  /* ---- board ---- */
  const mb = () => $('mboard');
  const pt = i => { const r = mb().getBoundingClientRect(), z = r.width / COLS; return { x: r.left + (i % COLS + .5) * z, y: r.top + (Math.floor(i / COLS) + .5) * z }; };
  let pid = 1;
  const ev = (el, type, p) => el.dispatchEvent(new PointerEvent(type, { clientX: p.x, clientY: p.y, pointerId: pid, bubbles: true, isPrimary: true }));
  PB.tap = async i => { pid++; const p = pt(i); ev(mb(), 'pointerdown', p); ev(mb(), 'pointerup', p); await w(PB.pace); };
  PB.drag = async (a, b) => {
    pid++; const p = pt(a), q = pt(b);
    ev(mb(), 'pointerdown', p); ev(mb(), 'pointermove', { x: p.x + 12, y: p.y });
    for (let k = 1; k <= 6; k++) { await w(45); ev(mb(), 'pointermove', { x: p.x + (q.x - p.x) * k / 6, y: p.y + (q.y - p.y) * k / 6 }); }
    ev(mb(), 'pointerup', q); await w(PB.pace);
  };
  // Drag a board item onto a drop zone of the info panel ('abyss' or 'store'), which shows once the drag starts.
  PB.dropOn = async (a, zone) => {
    pid++; const p = pt(a);
    ev(mb(), 'pointerdown', p); ev(mb(), 'pointermove', { x: p.x + 12, y: p.y }); await w(60);
    const z = document.querySelector(`#info [data-dz="${zone}"]`);
    if (!z) { ev(mb(), 'pointerup', p); await w(PB.pace); return false; }
    const r = z.getBoundingClientRect(), q = { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    for (let k = 1; k <= 6; k++) { await w(45); ev(mb(), 'pointermove', { x: p.x + (q.x - p.x) * k / 6, y: p.y + (q.y - p.y) * k / 6 }); }
    ev(mb(), 'pointerup', q); await w(PB.pace); return true;
  };
  PB.toAbyss = a => PB.dropOn(a, 'abyss');
  const overlayOpen = () => !$('overlay').hidden;
  PB.closeOverlay = async () => { const b = document.querySelector('#panel [data-go]'); if (overlayOpen() && b) { b.click(); await w(PB.pace); return true; } return false; };

  // One sensible move: deliver, close a popup, open gifts/chests, merge toward what is asked, or tap a tool.
  PB.step = async () => {
    if (overlayOpen()) { await w(900); await PB.closeOverlay(); return 'overlay'; }
    // With a climax request up, work only toward it (other requests would eat the items it needs).
    const S = st(), focus = !!S.boss;
    const ready = document.querySelector(focus ? '#orders .order.boss [data-deliver]:not([disabled])' : '#orders [data-deliver]:not([disabled])');
    if (ready) { ready.click(); await w(PB.pace + 400); return 'deliver'; }
    const C = S.cells, empties = C.map((c, i) => c ? -1 : i).filter(i => i >= 0);
    const needs = PB.targets || (focus ? S.boss.need : S.orders.flatMap(o => o.need));
    const maxNeed = c => Math.max(-1, ...needs.filter(n => n.c === c).map(n => n.t));
    // a chain whose asked-for items are all already on the board needs no more merging
    const count = (c, t) => C.filter(x => x && x.k === 'item' && x.c === c && x.t === t).length;
    const met = c => needs.filter(n => n.c === c).every(n => count(n.c, n.t) >= needs.filter(m => m.c === n.c && m.t === n.t).length);
    // open presents and chests while there is room
    const box = C.findIndex(c => c && (c.k === 'gift' || c.k === 'chest'));
    // short on room: stack chests into one
    const chests = C.map((c, i) => c && c.k === 'chest' ? i : -1).filter(i => i >= 0);
    if (chests.length >= 2 && empties.length < 8) { await PB.drag(chests[1], chests[0]); return 'stack'; }
    if (box >= 0 && empties.length > 14) { await PB.tap(box); return 'open'; }   // merge first; open boxes only with room to spare
    // merge the lowest pair that is still useful
    const groups = {};
    C.forEach((c, i) => { if (c && c.k === 'item') (groups[c.c + '-' + c.t] = groups[c.c + '-' + c.t] || []).push(i); });
    const pairs = Object.entries(groups).filter(([k, v]) => v.length >= 2).map(([k, v]) => { const [c, t] = k.split('-').map(Number); return { c, t, v }; })
      .filter(p => (p.t < maxNeed(p.c) && !met(p.c)) || (p.t < 5 && needs.length === 0))
      .sort((a, b) => a.t - b.t);
    if (pairs.length) { await PB.drag(pairs[0].v[0], pairs[0].v[1]); return 'merge'; }
    if (box >= 0 && empties.length > 2 && !PB.targets) { await PB.tap(box); return 'open'; }   // nothing to merge: unpack a box before tapping a tool
    // make room: send a useless low item to the abyss
    if (empties.length < (PB.targets ? 12 : 2)) {   // working toward one item: keep plenty of room
      const junk = C.map((c, i) => ({ c, i })).filter(o => o.c && o.c.k === 'item' && o.c.t > maxNeed(o.c.c)).sort((a, b) => a.c.t - b.c.t)[0]
        || C.map((c, i) => ({ c, i })).filter(o => o.c && o.c.k === 'item').sort((a, b) => a.c.t - b.c.t)[0];
      if (junk) { await PB.toAbyss(junk.i); return 'abyss'; }
    }
    // tap the tool of the chain that is asked for the most
    const gens = C.map((c, i) => ({ c, i })).filter(o => o.c && o.c.k === 'gen');
    const open = needs.filter(n => !met(n.c)), want = open.length ? open[Math.floor(Math.random() * open.length)].c : needs.length ? needs[0].c : null;
    const g = gens.find(o => o.c.g === want) || gens[Math.floor(Math.random() * gens.length)];
    if (g) { await PB.tap(g.i); return 'produce'; }
    return 'stuck';
  };
  // Play the board until the search button shows (or a step limit).
  PB.playUntilSearch = async (limit = 400) => {
    for (let n = 0; n < limit; n++) {
      if (!$('goSearch').hidden && !overlayOpen()) return n;
      const r = await PB.step();
      if (r === 'stuck') { note('stuck at step ' + n); return -n; }
    }
    return -limit;
  };

  /* ---- seek-and-find: rebuild the target list from the seed exactly as the game does ---- */
  function mulberry(seed) { return () => { seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
  // The scene data lives inside index.html (HIDDEN = { 'hs-0b': {...}, ... }); cut one entry out of the source.
  PB.scene = async id => {
    const src = await fetch('index.html').then(r => r.text());
    let i = src.indexOf(`'${id}': {`); i = src.indexOf('{', i);
    let d = 0, j = i;
    for (; j < src.length; j++) { if (src[j] === '{') d++; else if (src[j] === '}' && --d === 0) break; }
    return Function('return ' + src.slice(i, j + 1))();
  };
  PB.solveSeek = async (hsId, count, tapPace = 900) => {
    $('zfit').click(); await w(800);
    const s = st().search, H = await PB.scene(hsId);
    const SW = 2400, SH = 1600, R = mulberry(s.seed), ex = s.ex || [];
    const k = Math.max(SW / H.w, SH / H.h), ox = (SW - H.w * k) / 2, oy = (SH - H.h * k) / 2;
    let pool = H.items.slice(); for (let i = pool.length - 1; i > 0; i--) { const j = Math.floor(R() * (i + 1)); [pool[i], pool[j]] = [pool[j], pool[i]]; }
    pool = pool.filter(it => !ex.includes(it.id)).concat(pool.filter(it => ex.includes(it.id)));
    const chosen = pool.slice(0, Math.min(count, pool.length));
    const spread = it => it.at.every((a, i) => it.at.every((b, j) => i === j || Math.hypot(a[0] - b[0], a[1] - b[1]) > H.w * .08));
    const many0 = pool.filter(it => it.at.length >= 3 && spread(it)), fresh = many0.filter(it => !ex.includes(it.id)), many = fresh.length ? fresh : many0;
    const all = many.length ? many[Math.floor(R() * many.length)] : null;
    if (all && !chosen.includes(all)) chosen[chosen.length - 1] = all;
    const sv = $('sview'), L = $('slayer');
    const toScr = p => { const m = new DOMMatrix(getComputedStyle(L).transform), r = sv.getBoundingClientRect(); return { x: r.left + m.e + p.x * m.a, y: r.top + m.f + p.y * m.a }; };
    for (const it of chosen) for (const [x, y] of (it === all ? it.at : [it.at[0]])) {
      const q = toScr({ x: x * k + ox, y: y * k + oy }); pid++;
      sv.dispatchEvent(new PointerEvent('pointerdown', { clientX: q.x, clientY: q.y, pointerId: pid, bubbles: true, isPrimary: true }));
      await w(60);
      sv.dispatchEvent(new PointerEvent('pointerup', { clientX: q.x, clientY: q.y, pointerId: pid, bubbles: true, isPrimary: true }));
      await w(tapPace);
    }
    return chosen.map(c => c.ja);
  };
  /* ---- spot the difference: compare the two canvases and tap each changed blob ---- */
  PB.solveDiff = async (tapPace = 1100) => {
    const A = $('dA'), B = $('dB'), W = A.width, H = A.height;
    const a = A.getContext('2d').getImageData(0, 0, W, H).data, b = B.getContext('2d').getImageData(0, 0, W, H).data;
    const C = 16, hot = [];
    for (let y = 0; y < H; y += C) for (let x = 0; x < W; x += C) {
      let d = 0;
      for (let yy = y; yy < Math.min(H, y + C); yy += 4) for (let xx = x; xx < Math.min(W, x + C); xx += 4) { const i = (yy * W + xx) * 4; d += Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2]); }
      if (d > 400) hot.push({ x: x + C / 2, y: y + C / 2 });
    }
    const cl = [];
    hot.forEach(p => { const c = cl.find(c => Math.hypot(c.x - p.x, c.y - p.y) < 90); if (c) { c.n++; c.sx += p.x; c.sy += p.y; c.x = c.sx / c.n; c.y = c.sy / c.n; } else cl.push({ x: p.x, y: p.y, sx: p.x, sy: p.y, n: 1 }); });
    for (const c of cl) {
      const rc = B.getBoundingClientRect(), k = rc.width / W; pid++;
      B.dispatchEvent(new PointerEvent('pointerup', { clientX: rc.left + c.x * k, clientY: rc.top + c.y * k, pointerId: pid, bubbles: true }));
      await w(tapPace);
    }
    return cl.length;
  };
  PB.st = st;
  return PB;
})();
'PB ready';
