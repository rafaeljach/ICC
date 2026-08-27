#!/usr/bin/env bash
set -e
mkdir -p /opt/motor && cd /opt/motor
echo "== 1/6 · runner =="
cat > motor-headless.js <<'RUNNEREOF'
#!/usr/bin/env node
/* ═══ ICC MOTOR HEADLESS ═══
   NO reescribe el motor: extrae el <script> de dashboard.html y lo ejecuta
   tal cual bajo un DOM simulado. La lógica matemática es literalmente la misma
   —rawFeatures, standardize, predict, decide, resolve, marketPrice— porque es
   el mismo archivo. Lo único que cambia es el entorno: feed real, reloj real,
   persistencia en disco y sin pestaña que Android pueda matar.            */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const WS = require('ws');

const DIR  = __dirname;
const HTML = path.join(DIR, 'dashboard.html');
const CFGF = path.join(DIR, 'config.json');
const STOR = path.join(DIR, 'estado.json');
const PORT = +(process.env.PORT || 8080);
const SYNCF = path.join(__dirname,'sync.js');

/* ── configuración: mismos ids que los campos del dashboard ── */
const CFG_DEF = {
  cfgsrc:'binance', cfgmkt:'0', cfgfee:'1.56', cfgedge:'2', cfgkelly:'0.10',
  cfgmin:'0', cfglr:'0.06', cfgkeep:'8000', cfgq:'bajo', cfgboot:'2000',
  cfgmaxpx:'90', cfgminpx:'5', cfgbank:'50', cfgshrink:'50', cfgdec:'1',
  bnbmkt:'', bnbrelay:'', cfgbnbfee:'1.8',
};
const TOG_DEF = { cfgmicro:true, cfglearn:true, cfgmax:false,
                  cfgpoly:false, cfgpolygate:false, cfgfrozen:true, cfgbnb:false };
let CFG = {...CFG_DEF}, TOG = {...TOG_DEF};
try { const j = JSON.parse(fs.readFileSync(CFGF,'utf8'));
      CFG = {...CFG, ...(j.cfg||{})}; TOG = {...TOG, ...(j.tog||{})}; } catch(e){}

/* ── DOM simulado: los campos devuelven la config, el resto son stubs ── */
const ctxStub = new Proxy({}, { get:(t,p) =>
  (p==='createRadialGradient'||p==='createLinearGradient') ? () => ({addColorStop(){}})
  : p==='canvas' ? {width:300,height:150} : () => {} });

function mkEl(id){
  const cls = new Set(TOG[id] ? ['tog','on'] : []);
  const el = { id, textContent:'', innerHTML:'', dataset:{}, width:300, height:150,
    clientWidth:300, clientHeight:150, onclick:null,
    style:new Proxy({},{get:()=>'',set:()=>true}),
    classList:{ add:c=>cls.add(c), remove:c=>cls.delete(c),
      toggle:(c,v)=>v?cls.add(c):cls.delete(c), contains:c=>cls.has(c) },
    getContext:()=>ctxStub, getBoundingClientRect:()=>({width:300,height:340}),
    addEventListener(){}, appendChild(){}, remove(){}, click(){} };
  Object.defineProperty(el,'value',{ get:()=>CFG[id]??'', set:v=>{CFG[id]=String(v);} });
  Object.defineProperty(el,'className',{ get:()=>[...cls].join(' '),
    set:v=>{cls.clear();String(v).split(/\s+/).forEach(c=>c&&cls.add(c));} });
  return el;
}
const ELS = new Map();
global.document = { hidden:false, visibilityState:'visible',
  getElementById:id => ELS.get(id) || (ELS.set(id, mkEl(id)), ELS.get(id)),
  querySelectorAll:()=>[], createElement:()=>mkEl('tmp'),
  addEventListener(){}, body:{appendChild(){}} };

/* ── almacenamiento en disco vía localStorage (el motor ya lo soporta) ── */
let STORE = {};
try { STORE = JSON.parse(fs.readFileSync(STOR,'utf8')); } catch(e){}
let guardarT = null;
function persistir(){
  clearTimeout(guardarT);
  guardarT = setTimeout(() => {
    try { fs.writeFileSync(STOR, JSON.stringify(STORE)); } catch(e){}
  }, 1500);
}
global.localStorage = {
  setItem:(k,v)=>{ STORE[k]=String(v); persistir(); },
  getItem:k => (k in STORE ? STORE[k] : null),
  removeItem:k=>{ delete STORE[k]; persistir(); },
};
global.indexedDB = undefined;

global.window = { isSecureContext:false, addEventListener(){}, devicePixelRatio:1,
                  localStorage: global.localStorage };
Object.defineProperty(global,'navigator',{ configurable:true, writable:true,
  value:{ hardwareConcurrency:1, storage:null } });
global.WebSocket = WS;                       // feed REAL
global.requestAnimationFrame = () => 0;      // sin animación
global.alert = () => {}; global.confirm = () => true;
global.URL = global.URL || require('url').URL;
global.Blob = function(){}; global.Worker = function(){ this.postMessage=()=>{}; this.terminate=()=>{}; };

/* ── cargar y ejecutar el motor SIN TOCARLO ── */
const html = fs.readFileSync(HTML,'utf8');
const i = html.indexOf('<script>'), k = html.lastIndexOf('</script>');
if (i < 0 || k < 0) { console.error('No encuentro el <script> en dashboard.html'); process.exit(1); }
const CODIGO = html.slice(i + 8, k);
console.log(`[motor] ejecutando ${CODIGO.length.toLocaleString()} bytes de dashboard.html sin modificar`);
CODIGO_EXPORT();
function CODIGO_EXPORT(){
  (0, eval)(CODIGO + '\n;globalThis.__ICC = {S, M, cfg, tog};\n');
}
const X = globalThis.__ICC;

/* ── log periódico ── */
let ultVent = 0;
setInterval(() => {
  const S = X.S, M = X.M;
  const n = (M.gN||0) + (M.uN||0);
  if (n !== ultVent) {
    ultVent = n;
    const sk = M.sN ? (1 - (M.sMB/M.sN)/((M.sCB||M.sBB)/M.sN)) * 100 : 0;
    console.log(`[${new Date().toISOString().slice(11,19)}] ventanas ${n}` +
      ` · descartadas ${S.skipped||0} · ops ${M.trades||0}` +
      ` · banco ${(S.bank||0).toFixed(2)} · skill ${sk.toFixed(3)}%` +
      ` · |w| ${(M.w.reduce((a,b)=>a+Math.abs(b),0)/M.w.length).toFixed(4)}`);
  }
}, 10000);

/* ── HTTP: dashboard + estado ── */
http.createServer((req,res) => {
  res.setHeader('Access-Control-Allow-Origin','*');
  const u = new URL(req.url,'http://x');

  if (u.pathname === '/' || u.pathname === '/index.html') {
    const v = path.join(DIR,'visor.html');
    if (fs.existsSync(v)) { res.setHeader('Content-Type','text/html; charset=utf-8');
      return res.end(fs.readFileSync(v)); }
  }
  if (u.pathname === '/motor' || u.pathname === '/dashboard') {
    /* dashboard TAL CUAL + bloque de sincronización añadido al final.
       El archivo en disco no se toca: solo se concatena después. */
    res.setHeader('Content-Type','text/html; charset=utf-8');
    let extra='';
    try{ extra='\n<script>\n'+fs.readFileSync(SYNCF,'utf8')+'\n</script>\n'; }catch(e){}
    return res.end(fs.readFileSync(HTML,'utf8') + extra);
  }
  if (u.pathname === '/precio') {          // fijar el precio de mercado a mano
    const v = u.searchParams.get('up');
    if (v) { CFG.cfgmkt = String(v);
      fs.writeFileSync(CFGF, JSON.stringify({cfg:CFG,tog:TOG},null,2)); }
    res.setHeader('Content-Type','application/json');
    return res.end(JSON.stringify({cfgmkt:CFG.cfgmkt}));
  }
  if (u.pathname === '/full') {          // estado íntegro para sincronizar el dashboard
    const S=X.S, M=X.M;
    res.setHeader('Content-Type','application/json');
    return res.end(JSON.stringify({ M,
      S:{ hist:(S.hist||[]).slice(-400), log:(S.log||[]).slice(-200),
          pnl:(S.pnl||[]).slice(-400), bank:S.bank, skipped:S.skipped||0,
          conn:S.conn, spot:S.spot, sigSec:S.sigSec, kSig:S.kSig,
          gateLog:(S.gateLog||[]).slice(-300), frozenWin:S.frozenWin||0,
          conStat:S.conStat||null, polyBlocked:S.polyBlocked||0 } }));
  }
  if (u.pathname === '/export') {          // ledger crudo para el bootstrap
    res.setHeader('Content-Type','application/json');
    return res.end(STORE['icc:btc5m:ledger'] || '[]');
  }

  const S = X.S, M = X.M, n = (M.gN||0) + (M.uN||0);
  const q = M.sN || 1;
  res.setHeader('Content-Type','application/json');
  res.end(JSON.stringify({
    motor: 'dashboard.html sin modificar',
    feed: S.conn, spot: S.spot,
    ventanaActual: S.win ? {
      abre: new Date(S.win.start).toISOString(),
      precioBatir: S.win.open,
      restante_s: Math.round((S.win.end - Date.now())/1000),
      sucia: S.win.dirty || null } : null,
    ventanas: n, descartadas: S.skipped||0,
    muestrasEntrenadas: M.n||0,
    operaciones: M.trades||0, ganadas: M.wins||0,
    banco: +(S.bank||0).toFixed(2),
    skill: M.sN ? +((1-(M.sMB/q)/((M.sCB||M.sBB)/q))*100).toFixed(3) : null,
    brierModelo: M.sN ? +(M.sMB/q).toFixed(5) : null,
    brierBase:   M.sN ? +((M.sCB||M.sBB)/q).toFixed(5) : null,
    acierto: M.sN ? +(M.sAcc/q*100).toFixed(1) : null,
    sombra: M.shN ? { disparos:M.shN, de:M.shSeen,
      edgeRealizado_c: +(M.shPnl/M.shN*100).toFixed(2),
      baseline_c: +(M.sh0Pnl/(M.sh0N||1)*100).toFixed(2) } : null,
    pesos: M.w.map(v=>+v.toFixed(4)),
    precioMercadoUP: CFG.cfgmkt,
    ahora: Date.now(),
    prediccion: S.live ? { p:+(S.live.p*100).toFixed(1), base:+(S.live.p0*100).toFixed(1),
      micro:+((S.live.p-S.live.p0)*100).toFixed(2) } : null,
    rejilla: (S.hist||[]).slice(-24).map(x=>({
      t:new Date(x.id).toISOString().slice(11,16),
      p:Math.round((x.p||0)*100), y:x.y,
      ok:((x.p>=.5?1:0)===x.y) })),
    ops: (S.log||[]).slice(-10).reverse().map(o=>({
      t:new Date(o.t).toISOString().slice(11,16), up:o.up,
      px:+(o.px*100).toFixed(1), stake:o.stake, pnl:o.pnl,
      won:o.won, voided:!!o.voided })),
    poblaciones: (M.gN||M.uN) ? {
      disparo:M.gN||0, noDisparo:M.uN||0,
      skillDisparo: M.gN ? +((1-(M.gMB/M.gN)/((M.gCB/M.gN)||1))*100).toFixed(2) : null,
      skillNoDisparo: M.uN ? +((1-(M.uMB/M.uN)/((M.uCB/M.uN)||1))*100).toFixed(2) : null } : null,
    config: { kelly:CFG.cfgkelly, umbral:CFG.cfgedge, minMuestras:CFG.cfgmin,
              minpx:CFG.cfgminpx, maxpx:CFG.cfgmaxpx, comision:CFG.cfgfee },
  }, null, 2));
}).listen(PORT, '0.0.0.0', () => console.log(`[http] 0.0.0.0:${PORT}`));

process.on('uncaughtException', e => console.error('[error]', e.message));
RUNNEREOF
node --check motor-headless.js && echo "   OK"
echo "== 2/6 · sincronizador =="
cat > sync.js <<'SYNCEOF'
/* ═══ SINCRONIZACIÓN CON EL MOTOR DEL DROPLET ═══
   El dashboard de arriba NO se modifica: este bloque se concatena después.
   El servidor es la fuente de verdad —él recoge 24/7 y entrena—; el navegador
   queda como visor y calcula la predicción en vivo con el mismo feed. */
(function(){
  var fallos = 0;
  function marca(txt, cls){
    var el = document.getElementById('runmode'); if(!el) return;
    el.innerHTML = '<span class="dot ' + cls + '"></span><span class="d">' + txt + '</span>';
  }
  async function sincronizar(){
    try{
      var r = await fetch('/full', {cache:'no-store'});
      if(!r.ok) throw new Error('HTTP ' + r.status);
      var j = await r.json();
      if(j.M) Object.assign(M, j.M);
      if(j.S){
        S.hist = j.S.hist || []; S.log = j.S.log || []; S.pnl = j.S.pnl || [];
        S.bank = j.S.bank; S.skipped = j.S.skipped || 0;
        S.gateLog = j.S.gateLog || []; S.frozenWin = j.S.frozenWin || 0;
        S.conStat = j.S.conStat || null; S.polyBlocked = j.S.polyBlocked || 0;
      }
      fallos = 0;
      var n = (M.gN||0) + (M.uN||0);
      marca('<b class="g">Sincronizado con el motor del droplet</b> \u2014 ' +
            n.toLocaleString() + ' ventanas \u00b7 ' + (M.trades||0) +
            ' operaciones \u00b7 estas metricas son las del servidor', 'on');
      try{
        if(typeof renderMetrics === 'function') renderMetrics();
        if(typeof renderLog     === 'function') renderLog();
        if(typeof renderPop     === 'function') renderPop();
        if(typeof renderGate    === 'function') renderGate();
        if(typeof renderConn    === 'function') renderConn();
        if(typeof drawCal       === 'function') drawCal();
        if(typeof drawPnl       === 'function') drawPnl();
      }catch(e){}
    }catch(e){
      if(++fallos > 2) marca('<b class="r">Sin conexion con el motor del droplet</b> \u2014 ' +
        'los numeros que ves son locales', 'off');
    }
  }
  try{ window.save = function(){}; window.stSet = async function(){}; }catch(e){}
  sincronizar(); setInterval(sincronizar, 4000);
})();
SYNCEOF
node --check sync.js && echo "   OK"
echo "== 3/6 · visor =="
cat > visor.html <<'VISOREOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>ICC · Motor en el servidor</title>
<link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@700;900&family=IBM+Plex+Mono:wght@400;500;600&family=Inter:wght@300;400;500&display=swap" rel="stylesheet">
<style>
:root{--bg:#07070C;--panel:#12121C;--raised:#171724;--gold:#D4AF37;--cyan:#00D4FF;
--green:#00FF88;--red:#FF4757;--amber:#FFB020;--txt:#E8E8F0;--dim:#7A7A96;--faint:#4A4A62;
--line:rgba(212,175,55,.14);--line2:rgba(255,255,255,.05);
--mono:'IBM Plex Mono',monospace;--disp:'Orbitron',sans-serif;--ui:'Inter',sans-serif}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
body{background:var(--bg);color:var(--txt);font-family:var(--ui);padding-bottom:40px;
background-image:radial-gradient(900px 500px at 78% -8%,rgba(0,212,255,.05),transparent 62%)}
.lbl{font-family:var(--mono);font-size:9px;letter-spacing:.16em;text-transform:uppercase;color:var(--faint)}
.g{color:var(--green)}.r{color:var(--red)}.c{color:var(--cyan)}.y{color:var(--gold)}
.a{color:var(--amber)}.d{color:var(--dim)}
header{position:sticky;top:0;z-index:9;background:rgba(7,7,12,.94);backdrop-filter:blur(18px);
border-bottom:1px solid var(--line);padding:11px 14px}
.brand{display:flex;align-items:center;gap:9px}
.mark{width:26px;height:26px;border:1px solid var(--gold);border-radius:6px;display:grid;
place-items:center;font-family:var(--disp);font-weight:900;font-size:10px;color:var(--gold)}
.bt{font-family:var(--disp);font-weight:700;font-size:12.5px;letter-spacing:.08em}
.bs{font-family:var(--mono);font-size:8.5px;color:var(--faint);letter-spacing:.12em;margin-top:1px}
.dot{width:7px;height:7px;border-radius:50%;background:var(--faint);flex:none}
.dot.on{background:var(--green);box-shadow:0 0 9px var(--green);animation:p 2s infinite}
.dot.off{background:var(--red);box-shadow:0 0 9px var(--red)}
@keyframes p{0%,100%{opacity:1}50%{opacity:.35}}
main{padding:12px;display:flex;flex-direction:column;gap:12px;max-width:760px;margin:0 auto}
.card{background:linear-gradient(168deg,var(--panel),#0E0E16);border:1px solid var(--line2);
border-radius:13px;overflow:hidden}
.ch{padding:9px 13px;border-bottom:1px solid var(--line2);display:flex;justify-content:space-between;
align-items:center;gap:8px}
.ct{font-family:var(--mono);font-size:9.5px;letter-spacing:.16em;text-transform:uppercase;color:var(--dim)}
.cb{padding:13px}
.mtx{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--line2)}
.mt{background:var(--panel);padding:11px 8px}
.mt .v{font-family:var(--mono);font-size:16px;font-weight:600;margin-top:3px}
.mt .s{font-family:var(--mono);font-size:8px;color:var(--faint);margin-top:2px}
.big{font-family:var(--disp);font-weight:900;font-size:48px;line-height:1;letter-spacing:-.03em}
.big sub{font-size:.3em;font-weight:500;color:var(--faint);vertical-align:baseline}
.row{display:flex;align-items:baseline;gap:8px;padding:6px 0;font-family:var(--mono);font-size:10.5px}
.row span:first-child{color:var(--dim);flex:1}
.row b{font-size:12px;font-weight:600}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(56px,1fr));gap:5px}
.gc{border-radius:5px;padding:6px 3px;text-align:center;font-family:var(--mono);border:1px solid}
.gc .p{font-size:12px;font-weight:600}.gc .t{font-size:7.5px;opacity:.6;margin-top:2px}
.gc.w{background:rgba(0,255,136,.09);border-color:rgba(0,255,136,.3);color:var(--green)}
.gc.l{background:rgba(255,71,87,.08);border-color:rgba(255,71,87,.26);color:var(--red)}
table{width:100%;border-collapse:collapse;font-family:var(--mono);font-size:9.5px}
th{text-align:left;color:var(--faint);font-size:8px;letter-spacing:.1em;text-transform:uppercase;
padding:0 5px 7px 0;border-bottom:1px solid var(--line2)}
td{padding:6px 5px 6px 0;border-bottom:1px solid rgba(255,255,255,.03);color:var(--dim);white-space:nowrap}
input{background:var(--raised);border:1px solid var(--line2);color:var(--txt);font-family:var(--mono);
font-size:13px;padding:9px 11px;border-radius:7px;width:88px;text-align:center;outline:none}
input:focus{border-color:var(--cyan)}
button{background:var(--raised);border:1px solid var(--line);color:var(--gold);font-family:var(--mono);
font-size:10px;letter-spacing:.1em;text-transform:uppercase;padding:9px 15px;border-radius:7px;cursor:pointer}
button:hover{background:rgba(212,175,55,.1)}
.nota{font-family:var(--mono);font-size:9px;color:var(--faint);line-height:1.7;margin-top:10px;
padding-top:9px;border-top:1px solid var(--line2)}
.bar{height:6px;border-radius:3px;background:var(--raised);overflow:hidden;margin-top:7px}
.bar b{display:block;height:100%;background:var(--cyan);transition:width .5s}
.empty{padding:20px;text-align:center;font-family:var(--mono);font-size:10px;color:var(--faint)}
footer{padding:18px 14px;text-align:center;font-family:var(--mono);font-size:8.5px;
color:var(--faint);letter-spacing:.1em;line-height:1.9}
</style>
</head>
<body>
<header><div class="brand">
  <div class="mark">ICC</div>
  <div style="flex:1"><div class="bt">MOTOR EN EL SERVIDOR</div>
  <div class="bs" id="sub">conectando…</div></div>
  <div class="dot" id="dot"></div>
</div></header>

<main>
  <div class="card">
    <div class="ch"><div class="ct">Ventana en curso</div><div class="lbl" id="vt">—</div></div>
    <div class="cb" style="display:flex;align-items:flex-end;gap:16px">
      <div class="big c" id="pbig">—<sub>%</sub></div>
      <div style="flex:1">
        <div class="row"><span>Base GBM</span><b class="d" id="pbase">—</b></div>
        <div class="row"><span>Ajuste micro</span><b id="pmicro">—</b></div>
        <div class="row"><span>Precio a batir</span><b class="y" id="pbatir">—</b></div>
        <div class="row"><span>Spot</span><b class="c" id="pspot">—</b></div>
      </div>
    </div>
  </div>

  <div class="card">
    <div class="ch"><div class="ct">Recolección</div><div class="lbl" id="rt">—</div></div>
    <div class="mtx">
      <div class="mt"><div class="lbl">Ventanas</div><div class="v c" id="mv">0</div><div class="s">limpias</div></div>
      <div class="mt"><div class="lbl">Descartadas</div><div class="v" id="md">0</div><div class="s">datos sucios</div></div>
      <div class="mt"><div class="lbl">Muestras</div><div class="v d" id="mm">0</div><div class="s">entrenadas</div></div>
    </div>
    <div class="cb" style="padding-top:11px">
      <div class="lbl">Progreso hacia 1,000 ventanas</div>
      <div class="bar"><b id="bar" style="width:0"></b></div>
      <div class="nota" id="eta">—</div>
    </div>
  </div>

  <div class="card">
    <div class="ch"><div class="ct">Diagnóstico del modelo</div><div class="lbl" id="dt">—</div></div>
    <div class="mtx">
      <div class="mt"><div class="lbl">Skill</div><div class="v" id="msk">—</div><div class="s">vs baseline</div></div>
      <div class="mt"><div class="lbl">Brier modelo</div><div class="v d" id="mbm">—</div><div class="s">menor=mejor</div></div>
      <div class="mt"><div class="lbl">Brier base</div><div class="v d" id="mbb">—</div><div class="s">GBM calibrado</div></div>
      <div class="mt"><div class="lbl">Acierto</div><div class="v" id="mac">—</div><div class="s">dirección</div></div>
      <div class="mt"><div class="lbl">Operaciones</div><div class="v" id="mop">0</div><div class="s">cerradas</div></div>
      <div class="mt"><div class="lbl">Banco</div><div class="v y" id="mba">—</div><div class="s">papel</div></div>
    </div>
  </div>

  <div class="card">
    <div class="ch"><div class="ct">Sombra · 1 contrato</div><div class="lbl">edge realizado</div></div>
    <div class="cb" id="som"><div class="empty">Sin disparos todavía.</div></div>
  </div>

  <div class="card">
    <div class="ch"><div class="ct">Precio de mercado UP</div><div class="lbl">manual</div></div>
    <div class="cb">
      <div style="display:flex;gap:9px;align-items:center">
        <input type="number" id="up" placeholder="58" min="0" max="100" step="0.5">
        <span class="lbl">¢</span>
        <button id="btn">Enviar</button>
        <span class="lbl" id="ok" style="margin-left:auto"></span>
      </div>
      <div class="nota">Míralo en la app de Binance y tómalo <b style="color:var(--txt)">siempre en el mismo
      momento</b> de la ventana. Actual en el servidor: <b class="c" id="act">—</b>¢</div>
    </div>
  </div>

  <div class="card">
    <div class="ch"><div class="ct">Rejilla de resolución</div><div class="lbl" id="gt">—</div></div>
    <div class="cb"><div class="grid" id="grid"><div class="empty" style="grid-column:1/-1">Sin ventanas resueltas.</div></div></div>
  </div>

  <div class="card">
    <div class="ch"><div class="ct">Últimas operaciones</div></div>
    <div class="cb" id="ops"><div class="empty">Sin operaciones.</div></div>
  </div>

  <footer>ICC · MOTOR HEADLESS 24/7<br>ESTE VISOR SOLO LEE — EL MOTOR CORRE EN EL DROPLET</footer>
</main>

<script>
const $ = id => document.getElementById(id);
const fmt = (n,d=2) => Number.isFinite(n) ? n.toFixed(d) : '—';
const usd = n => (n<0?'-$':'$') + Math.abs(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});

async function tick(){
  let e;
  try { e = await (await fetch('/estado',{cache:'no-store'})).json(); }
  catch(err){ $('dot').className='dot off'; $('sub').textContent='SIN CONEXIÓN CON EL SERVIDOR'; return; }

  const vivo = e.feed === 'live';
  $('dot').className = 'dot ' + (vivo?'on':'off');
  $('sub').textContent = (vivo?'FEED EN VIVO':'FEED '+String(e.feed||'?').toUpperCase())
    + ' · ' + e.motor.toUpperCase();

  /* ventana */
  if (e.ventanaActual){
    const v=e.ventanaActual;
    $('vt').textContent = v.restante_s>0 ? Math.floor(v.restante_s/60)+':'+String(v.restante_s%60).padStart(2,'0') : 'resolviendo';
    $('pbatir').textContent = '$'+(v.precioBatir||0).toLocaleString('en-US',{maximumFractionDigits:1});
  }
  $('pspot').textContent = '$'+(e.spot||0).toLocaleString('en-US',{maximumFractionDigits:1});
  if (e.prediccion){
    const p=e.prediccion;
    const col = p.p>58?'g':p.p<42?'r':'c';
    $('pbig').innerHTML = fmt(p.p,1)+'<sub>%</sub>'; $('pbig').className='big '+col;
    $('pbase').textContent = fmt(p.base,1)+'%';
    $('pmicro').textContent = (p.micro>=0?'+':'')+fmt(p.micro,2)+'pp';
    $('pmicro').className = Math.abs(p.micro)<.5?'d':(p.micro>0?'g':'r');
  }

  /* recolección */
  $('mv').textContent = (e.ventanas||0).toLocaleString();
  $('md').textContent = (e.descartadas||0).toLocaleString();
  $('md').className = 'v ' + ((e.descartadas/Math.max(e.ventanas+e.descartadas,1))>.1?'r':'d');
  $('mm').textContent = (e.muestrasEntrenadas||0).toLocaleString();
  const pct = Math.min(e.ventanas/1000*100,100);
  $('bar').style.width = pct+'%';
  $('rt').textContent = fmt(pct,1)+'%';
  const faltan = Math.max(1000-e.ventanas,0);
  $('eta').innerHTML = faltan
    ? 'Faltan <b style="color:var(--txt)">'+faltan.toLocaleString()+'</b> ventanas · a 288/día son ~<b style="color:var(--txt)">'+fmt(faltan/288,1)+' días</b>'
    : '<b class="g">Muestra suficiente.</b> Ya puedes correr el bootstrap.';

  /* modelo */
  const sk=e.skill;
  $('msk').textContent = sk===null?'—':(sk>=0?'+':'')+fmt(sk,2)+'%';
  $('msk').className = 'v ' + (sk===null?'d':sk>.5?'g':sk>-.5?'a':'r');
  $('mbm').textContent = e.brierModelo??'—';
  $('mbb').textContent = e.brierBase??'—';
  $('mac').textContent = e.acierto===null?'—':fmt(e.acierto,1)+'%';
  $('mop').textContent = e.operaciones||0;
  $('mba').textContent = usd(e.banco);
  $('dt').textContent = e.ventanas<200 ? 'muestra insuficiente' : (sk>1?'la micro aporta':sk>0?'marginal':'sin edge');

  /* sombra */
  if (e.sombra){
    const s=e.sombra, dif=s.edgeRealizado_c-s.baseline_c;
    $('som').innerHTML =
      '<div class="row"><span>Disparos</span><b>'+s.disparos+'</b> <span class="d">de '+s.de+' ventanas</span></div>'+
      '<div class="row"><span>Edge realizado</span><b class="'+(s.edgeRealizado_c>0?'g':'r')+'">'+
        (s.edgeRealizado_c>=0?'+':'')+fmt(s.edgeRealizado_c,2)+'¢</b> <span class="d">por contrato</span></div>'+
      '<div class="row"><span>Baseline</span><b class="d">'+(s.baseline_c>=0?'+':'')+fmt(s.baseline_c,2)+'¢</b></div>'+
      '<div class="row"><span>Ventaja</span><b class="'+(dif>0?'g':'r')+'">'+(dif>=0?'+':'')+fmt(dif,2)+'¢</b></div>'+
      '<div class="nota">Si la ventaja no es positiva y creciente, la microestructura no aporta sobre el baseline.</div>';
  }

  /* rejilla */
  if (e.rejilla && e.rejilla.length){
    $('grid').innerHTML = e.rejilla.map(x =>
      '<div class="gc '+(x.ok?'w':'l')+'"><div class="p">'+x.p+'</div><div class="t">'+x.t+'</div></div>').join('');
    const ok = e.rejilla.filter(x=>x.ok).length;
    $('gt').textContent = ok+'/'+e.rejilla.length+' aciertos';
  }

  /* operaciones */
  if (e.ops && e.ops.length){
    $('ops').innerHTML = '<table><thead><tr><th>Hora</th><th>Dir</th><th>Entrada</th><th>Apostó</th>'+
      '<th>Result.</th><th>PnL</th></tr></thead><tbody>'+
      e.ops.map(o=>'<tr><td>'+o.t+'</td><td class="'+(o.up?'g':'r')+'">'+(o.up?'UP':'DN')+'</td>'+
      '<td>'+fmt(o.px,1)+'¢</td><td>'+usd(o.stake)+'</td>'+
      '<td class="'+(o.voided?'a':o.won?'g':'r')+'">'+(o.voided?'ANUL':o.won?'GANÓ':'PERDIÓ')+'</td>'+
      '<td class="'+(o.pnl>=0?'g':'r')+'">'+(o.pnl>=0?'+':'')+fmt(o.pnl,2)+'</td></tr>').join('')+
      '</tbody></table>';
  }

  $('act').textContent = e.precioMercadoUP||'0';
}

$('btn').addEventListener('click', async () => {
  const v = $('up').value.trim();
  if(!v) return;
  try { await fetch('/precio?up='+encodeURIComponent(v));
    $('ok').textContent='GUARDADO'; $('ok').className='lbl g';
    setTimeout(()=>{$('ok').textContent='';},2500); tick();
  } catch(e){ $('ok').textContent='ERROR'; $('ok').className='lbl r'; }
});

tick(); setInterval(tick, 4000);
</script>
</body>
</html>
VISOREOF
echo "   $(wc -c < visor.html) bytes"
echo "== 4/6 · dashboard =="
[ -f dashboard.html ] || { echo "   FALTA dashboard.html en /opt/motor"; exit 1; }
echo "   $(wc -c < dashboard.html) bytes (sin modificar)"
echo "== 5/6 · dependencias =="
[ -f package.json ] || echo '{"name":"icc-motor","private":true,"dependencies":{"ws":"^8.18.0"}}' > package.json
npm install --omit=dev --silent && echo "   listo"
echo "== 6/6 · servicio =="
cat > /etc/systemd/system/icc-motor.service <<'SVC'
[Unit]
Description=ICC Motor headless
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
WorkingDirectory=/opt/motor
Environment=PORT=8080
ExecStart=/usr/bin/node /opt/motor/motor-headless.js
Restart=always
RestartSec=5
MemoryMax=400M
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable --now icc-motor >/dev/null 2>&1 || systemctl restart icc-motor
ufw allow 8080/tcp >/dev/null 2>&1 || true
sleep 20
IP=$(curl -s --max-time 5 ifconfig.me || echo TU-IP)
curl -s localhost:8080/estado | head -8
echo
echo "  ==============================================="
echo "   Visor rapido : http://$IP:8080/"
echo "   DASHBOARD    : http://$IP:8080/motor"
echo "   Estado JSON  : http://$IP:8080/estado"
echo "   Logs         : journalctl -u icc-motor -f"
echo "  ==============================================="
