// Exhaustive check of one search (seek or spot-the-difference) in the local preview. Load tools/playbot.js first,
// open a search (a save with S.search set), then:  await ST.seek()  or  await ST.diff()
// Each returns { ok: [...], bad: [...] }: every case it tried, and the ones that did not behave as expected.
window.ST = (() => {
  const $ = id => document.getElementById(id);
  const w = ms => new Promise(r => setTimeout(r, ms));
  const st = () => JSON.parse(localStorage.getItem('rlyeh-merge-v2'));
  const ST = {};
  let pid = 3000;
  const fire = async (el, x, y, down = true) => {
    pid++;
    if (down) el.dispatchEvent(new PointerEvent('pointerdown', { clientX: x, clientY: y, pointerId: pid, bubbles: true, isPrimary: true }));
    await w(40);
    el.dispatchEvent(new PointerEvent('pointerup', { clientX: x, clientY: y, pointerId: pid, bubbles: true, isPrimary: true }));
    await w(250);
  };
  // A real-looking press on a button: pointer events on the element, then its click.
  const press = async el => { const r = el.getBoundingClientRect(); await fire(el, r.left + r.width / 2, r.top + r.height / 2); el.click(); await w(250); };
  const gapOf = box => {   // a point inside a button group that is on none of its buttons
    const r = box.getBoundingClientRect();
    for (let y = r.top + 2; y < r.bottom - 2; y += 3) for (let x = r.left + 2; x < r.right - 2; x += 3) {
      const el = document.elementFromPoint(x, y);
      if (el && box.contains(el) && !el.closest('button')) return { x, y, el };
    }
    return null;
  };
  const sanNow = () => { const s = st().search; return { miss: s.miss || 0, found: s.found.length }; };

  ST.seek = async () => {
    const ok = [], bad = [], check = (name, cond, info) => (cond ? ok : bad).push(info === undefined ? name : `${name}: ${JSON.stringify(info)}`);
    const s0 = st().search, th = scnTheme(s0.ch), H = await PB.scene(th);
    const SW = 2400, SH = 1600, k = Math.max(SW / H.w, SH / H.h), ox = (SW - H.w * k) / 2, oy = (SH - H.h * k) / 2;
    const view = () => { const m = $('slayer').style.transform.match(/translate\(([-\d.]+)px,\s*([-\d.]+)px\)\s*scale\(([-\d.]+)\)/); return { x: +m[1], y: +m[2], z: +m[3] }; };
    const tap = async ([x, y]) => { const v = view(), r = $('sview').getBoundingClientRect(); await fire($('sview'), r.left + v.x + (x * k + ox) * v.z, r.top + v.y + (y * k + oy) * v.z); return sanNow(); };
    $('zfit').click(); await w(400);
    // the list, as the game drew it
    const rows = [...document.querySelectorAll('#finds .find')].map(f => ({ all: f.classList.contains('all'), name: f.querySelector('.nm').textContent }));
    const items = rows.map(r => H.items.find(i => i.ja === r.name));
    check('list read', items.every(Boolean), rows.map(r => r.name));
    if (s0.hv === 2) check('no ambiguous item listed', items.every(i => !i || !i.amb), items.filter(i => i && i.amb).map(i => i.ja));
    if (s0.hv === 2 && rows.some(r => r.all)) check('"find all" is fully recorded', items[rows.findIndex(r => r.all)].ok === 1);
    // misses: an empty spot, and an item that is not on the list
    const allPts = H.items.flatMap(i => i.at); let blank;
    for (let t = 0; t < 600; t++) { blank = [60 + Math.random() * (H.w - 120), 60 + Math.random() * (H.h - 120)]; if (allPts.every(([a, b, r]) => Math.hypot(a - blank[0], b - blank[1]) > r + 60)) break; }
    let n = sanNow(), a;
    a = await tap(blank); check('empty spot is a miss', a.miss === n.miss + 1 && a.found === n.found, { n, a });
    const other = H.items.find(i => !items.includes(i) && i.at.every(([x, y, r]) => items.every(t => t.at.every(([p, q, s]) => Math.hypot(p - x, q - y) > r + s + 30))));
    if (other) { n = a; a = await tap(other.at[0]); check(`unlisted item (${other.ja}) is a miss`, a.miss === n.miss + 1, { n, a }); }
    // the buttons, and the gaps between them, never count
    n = sanNow();
    for (const id of ['zin', 'zin', 'zout', 'zout', 'zout', 'zfit', 'zin', 'zout']) await press($(id));
    const gap = gapOf(document.querySelector('.zoombar'));
    if (gap) await fire(gap.el, gap.x, gap.y);   // a real finger there lands on the bar itself
    a = sanNow(); check('zoom buttons and their gaps are not taps', a.miss === n.miss && a.found === n.found, { n, a, gap: !!gap });
    // the eye: costs one eye, no sanity
    const eyes0 = st().eyes; n = sanNow();
    if (eyes0 > 0) { $('eyeBtn').click(); await w(400); a = sanNow(); check('eye costs an eye, not sanity', st().eyes === eyes0 - 1 && a.miss === n.miss, { eyes0, eyes: st().eyes }); }
    $('zfit').click(); await w(400);
    // each listed item: a copy other than the first when there is one, then the same item again (no effect)
    for (let j = 0; j < items.length; j++) {
      const it = items[j]; if (!it) continue;
      if (rows[j].all) continue;
      n = sanNow();
      const copy = it.at.length > 1 ? it.at[1] : it.at[0];
      // one of them while zoomed in: wheel-zoom on the copy itself, as a pinch on it would
      if (j === 1) {
        const v = view(), r = $('sview').getBoundingClientRect(), cx = r.left + v.x + (copy[0] * k + ox) * v.z, cy = r.top + v.y + (copy[1] * k + oy) * v.z;
        for (let z = 0; z < 6; z++) $('sview').dispatchEvent(new WheelEvent('wheel', { clientX: cx, clientY: cy, deltaY: -300, bubbles: true, cancelable: true }));
        await w(300);
      }
      a = await tap(copy);
      check(`${it.ja}: copy ${it.at.length > 1 ? 2 : 1} counts${j === 1 ? ' (zoomed in)' : ''}`, a.found === n.found + 1 && a.miss === n.miss, { n, a });
      if (j === 1) { $('zfit').click(); await w(300); }
      n = a; a = await tap(it.at[0]);
      check(`${it.ja}: tapping it again does nothing`, a.found === n.found && a.miss === n.miss, { n, a });
    }
    // "find them all": every copy, one by one; a copy tapped twice does nothing
    const ai = rows.findIndex(r => r.all);
    if (ai >= 0) {
      const it = items[ai];
      for (let c = 0; c < it.at.length; c++) {
        n = sanNow(); a = await tap(it.at[c]);
        if (c === 0) { const b = await tap(it.at[0]); check(`${it.ja}: a found copy tapped again does nothing`, b.miss === a.miss && b.found === a.found); }
        if (c < it.at.length - 1) check(`${it.ja}: copy ${c + 1}/${it.at.length} is not a miss`, a.miss === n.miss && a.found === n.found, { n, a });
        else check(`${it.ja}: last copy completes it`, a.found === n.found + 1 && a.miss === n.miss, { n, a });
      }
    }
    await w(1800);
    const panel = $('overlay').hidden ? '' : $('panel').innerText.split('\n').filter(Boolean).slice(0, 2).join(' / ');
    check('all found: the result window opens', /解決/.test(panel), panel);
    return { ok, bad };
  };
  // the scene of a chapter's seek, as the game picks it
  const scnTheme = ch => { const i = ch === 6 ? 5 : ch % 6; return i === 0 ? 'hs-0b' : 'hs-' + i; };

  ST.diff = async () => {
    const ok = [], bad = [], check = (name, cond, info) => (cond ? ok : bad).push(info === undefined ? name : `${name}: ${JSON.stringify(info)}`);
    const A = $('dA'), B = $('dB'), W = A.width, H = A.height;
    // the changed blobs, found by comparing the two pictures
    const a = A.getContext('2d').getImageData(0, 0, W, H).data, b = B.getContext('2d').getImageData(0, 0, W, H).data, C = 16, hot = [];
    for (let y = 0; y < H; y += C) for (let x = 0; x < W; x += C) {
      let d = 0;
      for (let yy = y; yy < Math.min(H, y + C); yy += 4) for (let xx = x; xx < Math.min(W, x + C); xx += 4) { const i = (yy * W + xx) * 4; d += Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2]); }
      if (d > 400) hot.push({ x: x + C / 2, y: y + C / 2 });
    }
    const cl = [];
    hot.forEach(p => { const c = cl.find(c => Math.hypot(c.x - p.x, c.y - p.y) < 90); if (c) { c.n++; c.sx += p.x; c.sy += p.y; c.x = c.sx / c.n; c.y = c.sy / c.n; } else cl.push({ x: p.x, y: p.y, sx: p.x, sy: p.y, n: 1 }); });
    const want = +$('dTitle').textContent.match(/\/ (\d+)/)[1];
    check('every difference shows as a change between the pictures', cl.length >= want, { blobs: cl.length, want });
    const at = (cv, p) => { const r = cv.getBoundingClientRect(), k = r.width / W; return { x: r.left + p.x * k, y: r.top + p.y * k }; };
    const tap = async (cv, p) => { const q = at(cv, p); await fire(cv, q.x, q.y); return sanNow(); };
    // misses: spots far from every change, on each picture
    const far = () => { for (let t = 0; t < 800; t++) { const p = { x: 30 + Math.random() * (W - 60), y: 30 + Math.random() * (H - 60) }; if (hot.every(h => Math.hypot(h.x - p.x, h.y - p.y) > 160)) return p; } return { x: 6, y: 6 }; };
    let n = sanNow(), r;
    r = await tap(B, far()); check('an unchanged spot is a miss', r.miss === n.miss + 1 && r.found === n.found, { n, r });
    n = r; r = await tap(A, far()); check('an unchanged spot of the memory picture is a miss', r.miss === n.miss + 1 && r.found === n.found, { n, r });
    // buttons and gaps
    n = sanNow();
    for (const id of ['dzIn', 'dzIn', 'dzOut', 'dzOut', 'dzOut', 'dzFit']) await press($(id));
    const gap = gapOf(document.querySelector('.dzoom'));
    if (gap) await fire(gap.el, gap.x, gap.y);
    r = sanNow(); check('zoom buttons and their gaps are not taps', r.miss === n.miss && r.found === n.found, { n, r, gap: !!gap });
    const eyes0 = st().eyes;
    if (eyes0 > 0) { n = sanNow(); $('dEye').click(); await w(400); r = sanNow(); check('eye costs an eye, not sanity', st().eyes === eyes0 - 1 && r.miss === n.miss); }
    // every changed blob, tapped in turn: each is either a new find or part of one already found - never a miss.
    // Modes rotate: the scene now, the memory, zoomed in, one picture at a time.
    // zoomed in first, on a change nobody has found yet: wheel-zoom on it (no glide), then tap it
    n = sanNow();
    { const z = at(B, cl[0]); for (let t = 0; t < 4; t++) B.dispatchEvent(new WheelEvent('wheel', { clientX: z.x, clientY: z.y, deltaY: -100, bubbles: true, cancelable: true })); await w(250);
      r = await tap(B, cl[0]); check('a difference found zoomed in', r.found === n.found + 1 && r.miss === n.miss, { n, r, zoom: B.closest('.dlay').style.transform }); }
    const modes = ['now', 'memory', 'single'], seen = { now: 0, memory: 0, single: 0 };
    n = sanNow(); const miss0 = n.miss; let again = null;
    for (let i = 0; i < cl.length && sanNow().found < want; i++) {
      const mode = modes[i % 3];
      $('dzFit').click(); if (document.getElementById('dpanes').classList.contains('single')) $('dOne').click(); await w(150);
      if (mode === 'single') { $('dOne').click(); await w(300); }
      let cv = mode === 'memory' ? A : B;
      if (mode === 'single') cv = [A, B].find(c => !c.closest('.dpane').classList.contains('off'));


      const q = at(cv, cl[i]), vp = cv.closest('.dvp').getBoundingClientRect();
      if (!(q.x > vp.left + 2 && q.x < vp.right - 2 && q.y > vp.top + 2 && q.y < vp.bottom - 2)) { $('dzFit').click(); await w(200); }
      const before = sanNow(); r = await tap(cv, cl[i]);
      if (r.found > before.found) seen[mode]++;
      if (r.found > before.found && !again) again = cl[i];
    }
    if (again) { n = sanNow(); r = await tap(B, again); check('a found difference tapped again does nothing', r.found === n.found && r.miss === n.miss, { n, r }); }
    r = sanNow();
    check('every difference found by tapping the changes', r.found === want, { found: r.found, want });
    check('tapping the changes made no miss', r.miss === miss0, { miss0, miss: r.miss });
    check('finds made in each view (now / memory / one at a time)', Object.values(seen).filter(v => v > 0).length >= Math.min(3, want - 1), seen);
    await w(1700);
    const ans = $('overlay').hidden ? 0 : document.querySelectorAll('.danslist li').length;
    check('the answers list every difference', ans === want, { ans, want });
    document.querySelector('#panel [data-go]')?.click(); await w(800);
    const panel = $('overlay').hidden ? '' : $('panel').innerText.split('\n').filter(Boolean).slice(0, 2).join(' / ');
    check('then the result window opens', /解決/.test(panel), panel);
    return { ok, bad };
  };
  // Run one case end to end: from a backed-up save, open chapter ch's seek ('seek') or difference ('diff') search
  // (hv 2 = the rules from ver 1.60; 0 = a search begun before), reload, play it through. Call twice: the first call
  // sets up and reloads, the second (after the reload) plays and returns the result.
  ST.prep = (ch, mode, hv = 2, backup = 'rlyeh-hv-backup') => {
    const s = JSON.parse(localStorage.getItem(backup)), stage = mode === 'diff' ? 1 : 0;
    Object.assign(s, { ch, introCh: ch, stage, eyes: 5, view: 'search', tips: { dice: 2 } });
    s.search = Object.assign({ seed: 7000 + ch * 31 + stage, ch, found: [], stage, ex: [] }, mode === 'diff' ? { mode: 'diff' } : {}, hv === 2 ? { hv: 2 } : {});
    localStorage.setItem('rlyeh-merge-v2', JSON.stringify(s));
    localStorage.setItem('rlyeh-st-case', JSON.stringify({ ch, mode, hv }));
    setTimeout(() => location.reload(), 50);
    return 'prepared';
  };
  ST.play = async () => {
    const c = JSON.parse(localStorage.getItem('rlyeh-st-case')), errs = [];
    window.addEventListener('error', e => errs.push(e.message));
    if (!$('title').hidden) document.querySelector('[data-t="go"]')?.click();
    await w(2800);
    for (let k = 0; k < 4 && !$('overlay').hidden; k++) { document.querySelector('#panel [data-go]')?.click(); await w(400); }
    const res = c.mode === 'diff' ? await ST.diff() : await ST.seek();
    return { case: `ch${c.ch + 1} ${c.mode}${c.hv === 2 ? '' : ' (old search)'}`, ok: res.ok.length, bad: res.bad, errs };
  };
  return ST;
})();
'ST ready';
