// Full play-through driver for the local preview (load tools/playbot.js first).
// Plays from a new game to the ending without skipping anything: every request, every search (with one deliberate
// miss each), the climax requests, the altar and the ending; uses each feature at least once; then fills the dex.
// Start:  PB.full()   — runs in the background; poll PB.R for progress, PB.R.errors for page errors.
(() => {
  const $ = id => document.getElementById(id);
  const w = ms => new Promise(r => setTimeout(r, ms));
  const st = () => JSON.parse(localStorage.getItem('rlyeh-merge-v2'));
  const R = PB.R = { phase: 'init', log: [], errors: [], did: {}, steps: 0, done: false };
  const note = m => { R.log.push(`[ch${(st() || {}).ch}] ${m}`); if (R.log.length > 400) R.log.shift(); };
  window.addEventListener('error', e => R.errors.push(String(e.message)));
  window.addEventListener('unhandledrejection', e => R.errors.push('promise: ' + String(e.reason)));
  const open = () => !$('overlay').hidden;
  const click = el => { if (el && !el.disabled) { el.click(); return true; } return false; };

  // Close whatever popup is up; the altar and the ending need their own handling.
  async function settle() {
    for (let k = 0; k < 30; k++) {
      if (!$('ending').hidden) { await ending(); continue; }
      if (!open()) return;
      const P = $('panel');
      if (P.querySelector('[data-sh]') || (P.innerText.includes('封印の儀') && P.querySelector('[data-go]'))) { await altar(); continue; }
      const go = P.querySelector('[data-go]');
      if (go) { R.log.push('close: ' + P.innerText.split('\n').filter(Boolean).slice(0, 2).join(' / ')); go.click(); await w(250); } else return;
    }
  }
  async function altar() {
    note('altar');
    const P = $('panel');
    if (!R.did.altarMiss) { const b = P.querySelector('[data-sh="3"]'); if (b) { R.did.altarMiss = 1; b.click(); await w(800); note('altar: deliberate wrong shard'); } }
    for (let i = 0; i < 6; i++) { const b = $('panel').querySelector(`[data-sh="${i}"]`); if (b) { b.click(); await w(500); } }
    const go = $('panel').querySelector('[data-go]'); if (go) { go.click(); await w(500); }
  }
  async function ending() {
    note('ending: watching');
    R.phase = 'ending';
    for (let t = 0; t < 400 && !$('eend'); t++) await w(500);   // let the whole ending play
    note('ending: epilogue lines ' + document.querySelectorAll('#etext .wline').length);
    $('eend').click(); await w(800);
  }

  /* ---- one search, as a player would: open, use the eye once, make one deliberate miss, then solve ---- */
  async function search() {
    $('goSearch').click(); await w(400);
    for (let k = 0; k < 4 && open(); k++) { const go = $('panel').querySelector('[data-go]'); go.click(); await w(500); }
    await w(1800);
    const S = st();
    if (!S.search) { note('search did not start; will retry'); return; }
    if (!$('diffView').hidden) {
      R.phase = 'diff';
      click($('dEye')); await w(400); R.did.eye = 1;
      const B = $('dB'), r = B.getBoundingClientRect();
      B.dispatchEvent(new PointerEvent('pointerup', { clientX: r.left + 6, clientY: r.top + 6, pointerId: 77, bubbles: true }));   // deliberate miss at a corner
      await w(300);
      const n = await PB.solveDiff(160);
      note(`diff solved (${n} blobs), SAN ${$('dsan').innerText.replace(/\n/g, ' ')}`);
    } else {
      R.phase = 'seek';
      const ch = S.search.ch, i = ch === 6 ? 5 : ch % 6, th = i === 0 ? 'hs-0b' : 'hs-' + i;   // same scene rule as theme()
      click($('eyeBtn')); await w(500); R.did.eye = 1;
      await missLookalike(th, ch);
      const found = await PB.solveSeek(th, Math.min(8 + ch, 12), 110);
      note(`seek solved ${found.length} in ${th}, SAN ${$('san').innerText.replace(/\n/g, ' ')}`);
    }
    await w(1700);
  }
  // Tap a second copy of a listed (not "find all") item: by the rules that is a miss.
  async function missLookalike(th, ch) {
    const H = await PB.scene(th), s = st().search, names = [...document.querySelectorAll('#finds .find:not(.all) .nm')].map(e => e.textContent);
    const it = H.items.find(i => names.includes(i.ja) && i.at.length > 1);
    if (!it) { note('no look-alike copy to miss on'); return; }
    $('zfit').click(); await w(700);
    const SW = 2400, SH = 1600, k = Math.max(SW / H.w, SH / H.h), ox = (SW - H.w * k) / 2, oy = (SH - H.h * k) / 2;
    const L = $('slayer'), sv = $('sview'), m = new DOMMatrix(getComputedStyle(L).transform), r = sv.getBoundingClientRect();
    const [x, y] = it.at[1], q = { x: r.left + m.e + (x * k + ox) * m.a, y: r.top + m.f + (y * k + oy) * m.a };
    sv.dispatchEvent(new PointerEvent('pointerdown', { clientX: q.x, clientY: q.y, pointerId: 91, bubbles: true, isPrimary: true }));
    await w(40);
    sv.dispatchEvent(new PointerEvent('pointerup', { clientX: q.x, clientY: q.y, pointerId: 91, bubbles: true, isPrimary: true }));
    await w(300);
    note(`deliberate miss on the other copy of ${it.ja}: SAN ${$('san').innerText.replace(/\n/g, ' ')}`);
  }

  /* ---- chores: use each feature once, and keep the tools upgraded ---- */
  async function shopBuy(id) { $('shopBtn').click(); await w(250); const ok = click($('panel').querySelector(`[data-buy="${id}"]`)); await w(250); await settle(); return ok; }
  async function chores() {   // reads the save afresh before each spend
    const S = st(), D = R.did;
    // tool upgrades whenever affordable
    const gi = S.cells.findIndex(c => c && c.k === 'gen' && c.lv < 5 && st().coins >= [0, 0, 30, 90, 240, 600][c.lv + 1]);
    if (gi >= 0) { await PB.tap(gi); if (click($('info').querySelector('[data-act="upgrade"]'))) { D.upgrade = (D.upgrade || 0) + 1; } await w(150); }
    if (!D.daily) { $('dayBtn').click(); await w(250); click($('dLogin')); await w(250); await settle(); D.daily = 1; note('daily: login reward'); }
    if (S.daily && S.daily.tasks.some(t => !t.got)) { $('dayBtn').click(); await w(200); for (const b of $('panel').querySelectorAll('[data-task]')) if (!b.disabled) { b.click(); D.dailyTask = 1; note('daily task claimed'); await w(250); break; } await settle(); }
    if (!D.vault && S.cells.some(c => c && c.k === 'item')) {
      const v = S.cells.findIndex(c => c && c.k === 'vault'), it = S.cells.findIndex(c => c && c.k === 'item' && c.t === 0);
      if (v >= 0 && it >= 0) { await PB.drag(it, v); await PB.tap(v); await w(200); click($('panel').querySelector('[data-take="0"]')); await w(200); await settle(); D.vault = 1; note('vault: stored and took out'); }
    }
    for (const id of ['eye', 'reroll', 'pack', 'myth', 'chest', 'unseal']) if (!D['buy_' + id] && st().coins >= 450) { if (await shopBuy(id)) { D['buy_' + id] = 1; note('shop: bought ' + id); } break; }
    if (!D.res && st().coins >= 500) { $('shopBtn').click(); await w(250); if (click($('panel').querySelector('[data-res]'))) { D.res = 1; note('research: one step'); } await w(250); await settle(); }
    if ((D.dice || 0) < 3 && st().coins >= 600) { $('shopBtn').click(); await w(250); $('toDice').click(); await w(250); $('rollBtn').click(); await w(1900); note('dice: ' + $('diceMsg').innerText + ' / ' + $('figOut').innerText.split('\n')[0]); D.dice = (D.dice || 0) + 1; await settle(); }
    if (!D.expand && st().coins >= 900) { const v = S.cells.findIndex(c => c && c.k === 'vault'); if (v >= 0) { await PB.tap(v); await w(200); if (click($('storeUp'))) { D.expand = 1; note('vault expanded'); } await w(200); await settle(); } }
    if (!D.dexOpen && S.ch >= 1) { $('dexBtn').click(); await w(300); const b = $('panel').querySelector('[data-lore]'); if (b) b.click(); await w(200); await settle(); D.dexOpen = 1; note('journal opened, a lore note read'); }
  }

  /* ---- the whole run ---- */
  PB.full = async () => {
    PB.pace = 35;
    R.phase = 'title';
    if (!$('title').hidden) {
      const nb = document.querySelector('[data-t="new"]');
      if (nb) { nb.click(); await w(200); nb.click(); } else document.querySelector('[data-t="go"]').click();
      await w(600);
    }
    let lastCh = -1, guard = 0;
    while (!R.stop) {
      guard++;
      await settle();
      const S = st();
      if (S.ch !== lastCh) { note('chapter start: ' + document.getElementById('chTitle').textContent); lastCh = S.ch; }
      if (S.cleared && S.ch > 6) break;
      if (!$('goSearch').hidden && !open()) { await search(); continue; }
      if (guard % 25 === 0) await chores();
      const r = await PB.step(); R.steps++;
      if (r === 'stuck') { note('stuck'); await w(200); }
    }
    R.phase = 'dex';
    note('ending done; filling the dex');
    // Fill the dex: one of each 8th-stage item (and a relic from two of the first chain's).
    for (let c = 0; c < 3 && !R.stop; c++) {
      PB.targets = [{ c, t: 7 }];
      for (let n = 0; n < 6000 && !R.stop && !st().dex[`${c}-7`]; n++) { await settle(); await PB.step(); if (n % 40 === 0) await chores(); }
      note(`dex: chain ${c} final stage made`);
    }
    PB.targets = null;
    R.phase = 'title';
    R.done = true;
    note('all done; dex ' + Object.keys(st().dex).length + ' / 24');
  };
})();
'full-run ready';
