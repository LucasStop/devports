const I = {
  x: '<svg viewBox="0 0 12 12"><path d="M2 2l8 8M10 2l-8 8"/></svg>',
  up: '<svg viewBox="0 0 12 12"><path d="M3 9l6-6M4 3h5v5"/></svg>',
  pause: '<svg class="f" viewBox="0 0 12 12"><rect x="2.5" y="2" width="2.6" height="8" rx=".6"/><rect x="6.9" y="2" width="2.6" height="8" rx=".6"/></svg>',
  play: '<svg class="f" viewBox="0 0 12 12"><path d="M3.2 1.9v8.2L10 6z"/></svg>',
  refresh: '<svg viewBox="0 0 12 12"><path d="M10 6a4 4 0 1 1-1.2-2.8M10 1.5V4H7.5"/></svg>',
  term: '<svg viewBox="0 0 12 12"><rect x="1" y="2" width="10" height="8" rx="1.5"/><path d="M3 5l1.6 1.2L3 7.4M6 7.6h3"/></svg>',
  search: '<svg viewBox="0 0 12 12" width="12" height="12" style="stroke:currentColor;fill:none;stroke-width:1.5;stroke-linecap:round"><circle cx="5" cy="5" r="3.3"/><path d="M7.6 7.6L10.5 10.5"/></svg>',
  chR: '<svg class="chev" viewBox="0 0 10 10"><path d="M3.5 1.5L7 5 3.5 8.5"/></svg>',
  chD: '<svg class="chev" viewBox="0 0 10 10"><path d="M1.5 3.5L5 7l3.5-3.5"/></svg>',
  err: '<svg viewBox="0 0 14 14"><circle cx="7" cy="7" r="5.5"/><path d="M7 4v3.4M7 9.6v.1"/></svg>',
  glyph: '<img src="../glyph.svg" width="18" height="18" alt="" class="gl">',
};
// Linhas de porta. opts: stop ('wait'|'late'), confirm, sys, pauseBtn, suspended, hoverPause
function portRow(p, o = {}) {
  const dim = o.stop || o.sys || o.suspended;
  const led = o.stop || o.sys || o.suspended ? 'idle' : p.net ? 'warn' : '';
  const badges = (p.net ? '<span class="badge net">REDE</span>' : '') + (o.sys ? '<span class="badge sys">SISTEMA</span>' : '') + (o.suspended ? '<span class="badge sus">SUSPENSO</span>' : '');
  let meta = `<div class="meta${o.stop === 'late' ? ' late' : ''}">${o.stop === 'wait' ? 'encerrando…' : o.stop === 'late' ? 'Não respondeu em 5 s' : p.meta}</div>`;
  let btns;
  if (o.stop === 'wait') btns = '<div class="ibtn"><span class="spin"></span></div>';
  else if (o.stop === 'late') btns = '<button class="sbtn strong danger">Forçar</button>';
  else if (o.confirm) btns = '<button class="sbtn filled danger">Encerrar</button><button class="sbtn">Cancelar</button>';
  else btns = `<div class="ibtn">${I.up}</div>` + (o.pauseBtn ? `<div class="ibtn${o.hoverPause ? ' hover' : ''}">${o.suspended ? I.play : I.pause}</div>` : '') + `<div class="ibtn">${I.x}</div>`;
  return `<div class="row${dim ? ' dim' : ''}"><span class="led ${led}"></span><div class="body"><span class="port">:${p.n}</span><div class="col"><div class="ttl"><span class="tt">${p.t}</span>${badges}</div>${meta}</div></div>${btns}</div>`;
}
function procRow(p, o = {}) {
  const btns = (o.pauseBtn ? `<div class="ibtn">${o.suspended ? I.play : I.pause}</div>` : '') + `<div class="ibtn">${I.x}</div>`;
  return `<div class="row proc${o.suspended ? ' dim' : ''}"><div class="pl"><span>${p.t}</span><span class="meta">&nbsp;·&nbsp;${o.suspended ? '<span class="badge sus">SUSPENSO</span> · ' : ''}pid ${p.pid} · ${p.up} · ${p.mem}</span></div>${btns}</div>`;
}
const P = {
  vite: { n: 3000, t: 'vite', meta: 'painel · node · 5h · 268 MB' },
  next: { n: 3001, t: 'next dev', meta: 'site · node · 2h · 412 MB' },
  http: { n: 8000, t: 'http.server 8000', meta: 'docs · python3 · 18min · 18 MB', net: true },
  sys: { n: 5000, t: 'ControlCenter', meta: 'Sistema · ControlCenter · 1d 16h · 64 MB', net: true },
  worker: { t: 'queue-worker', pid: 4104, up: '5h', mem: '96 MB' },
};
const seg = (on) => `<div class="seg">${['Portas', 'Apps', 'Terminal'].map((t) => `<span${t === on ? ' class="on"' : ''}>${t}</span>`).join('')}</div>`;
const header = (on = 'Portas') => `<div class="hdr">${I.glyph}<b>DevPorts</b><span class="sp"></span><div class="ibtn">${I.refresh}</div></div>${seg(on)}`;
const search = (q = '') => `<div class="search">${I.search}${q ? `<span class="q">${q}</span>` : 'Buscar porta, processo ou projeto'}</div>`;
const sec = (t, d) => `<div class="sec"><b>${t}</b><span>${d}</span></div>`;
const footer = (n = 1) => `<div class="foot"><span class="chk"></span><span>Mostrar sistema</span><span class="n">${n}</span><span class="sp"></span><span>Ajustes</span><span>Sair</span></div>`;
const group = (open, kids = '', band = '') => `<div class="grp${open ? ' open' : ''}">${open ? I.chD : I.chR}<span class="name">painel</span><span class="meta">1 processo · 96 MB</span>${open ? '<button class="sbtn danger">Encerrar todos</button>' : ''}</div>${band}${open ? kids : ''}`;
const confirmBand = (t) => `<div class="band danger"><span class="t">${t}</span><button class="sbtn filled danger">Encerrar</button><button class="sbtn">Cancelar</button></div>`;
const ports = (o = {}) => sec('Portas', 3) + portRow(P.vite, o.vite) + portRow(P.next, o.next) + portRow(P.http, o.http);
const list = (o = {}) => ports(o.ports) + '<div class="dv"></div>' + sec('Processos dev', '1 em 1 grupo') + (o.group || group(false));
const popover = (inner, o = {}) => `<div class="frame">${header(o.tab)}${search(o.q)}${inner}${o.band || ''}${footer(o.n)}${o.over || ''}</div>`;
