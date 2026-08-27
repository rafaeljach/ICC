#!/usr/bin/env bash
# ═══ ICC · motor headless en el droplet ═══
# Ejecuta dashboard.html SIN MODIFICARLO bajo un DOM simulado.
set -e
mkdir -p /opt/motor && cd /opt/motor

echo "== 1/5 · runner =="
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
    res.setHeader('Content-Type','text/html; charset=utf-8');
    return res.end(fs.readFileSync(HTML));
  }
  if (u.pathname === '/precio') {          // fijar el precio de mercado a mano
    const v = u.searchParams.get('up');
    if (v) { CFG.cfgmkt = String(v);
      fs.writeFileSync(CFGF, JSON.stringify({cfg:CFG,tog:TOG},null,2)); }
    res.setHeader('Content-Type','application/json');
    return res.end(JSON.stringify({cfgmkt:CFG.cfgmkt}));
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
  }, null, 2));
}).listen(PORT, '0.0.0.0', () => console.log(`[http] 0.0.0.0:${PORT}`));

process.on('uncaughtException', e => console.error('[error]', e.message));
RUNNEREOF
node --check motor-headless.js && echo "   sintaxis OK"

echo "== 2/5 · dashboard =="
if [ ! -f dashboard.html ]; then
  echo "   FALTA /opt/motor/dashboard.html"
  echo "   Subelo primero:  curl -sL 'URL_RAW_DEL_DASHBOARD' -o /opt/motor/dashboard.html"
  exit 1
fi
echo "   $(wc -c < dashboard.html) bytes"

echo "== 3/5 · dependencias =="
[ -f package.json ] || echo '{"name":"icc-motor","private":true,"dependencies":{"ws":"^8.18.0"}}' > package.json
npm install --omit=dev --silent
echo "   listo"

echo "== 4/5 · servicio =="
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
echo "   activo con arranque automatico"

echo "== 5/5 · comprobacion =="
sleep 25
IP=$(curl -s --max-time 5 ifconfig.me || echo TU-IP)
curl -s localhost:8080/estado | head -14
echo
echo "  ==============================================="
echo "   Dashboard : http://$IP:8080/"
echo "   Estado    : http://$IP:8080/estado"
echo "   Ledger    : http://$IP:8080/export"
echo "   Precio UP : http://$IP:8080/precio?up=58"
echo "   Logs      : journalctl -u icc-motor -f"
echo "  ==============================================="
