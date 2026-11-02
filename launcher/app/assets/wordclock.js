// Word clock: the time in lit words on a fixed 11 × 10 grid of letters, to the nearest five minutes
// ("IT IS TWENTY FIVE TO SEVEN"). The home page owns idle, keys and settings; this only draws.
//   WordClock.show() / WordClock.hide() / WordClock.active
//   WordClock.set({dots, level})  dots: floor to the five and light one dot per minute past it
//                                 level: 'soft' | 'medium' | 'bright'
// It does no work while hidden; while shown it checks the time every few seconds and only touches the
// letters when the words change.
// In the app, the letters are drawn natively at the panel's own resolution (WordClock.kt: the page itself
// is drawn at 1080p and scaled up, which leaves thin letters soft); this page then only says what's lit and
// draws the background. Elsewhere (a browser) it draws the letters itself.
(() => {
// unused letters are filler; NOIR on the ninth row is never lit
const ROWS = [
  "ITRISOHALFV",
  "TWENTYFIVEX",
  "QUARTERUTEN",
  "PASTMTONINE",
  "ONETWOTHREE",
  "FOURFIVESIX",
  "SEVENEIGHTL",
  "ELEVENATENK",
  "TWELVENOIRZ",
  "ESNOCLOCKAR",
];
const W = 11, FLAT = ROWS.join('');
const HOURS = ["TWELVE","ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT","NINE","TEN","ELEVEN"];
const MINS = {5:["FIVE"],10:["TEN"],15:["QUARTER"],20:["TWENTY"],25:["TWENTY","FIVE"],30:["HALF"]};
const native = !!(window.Launcher && Launcher.clockShow);
// lit lightness for Soft / Medium / Bright; Bright is as near SDR white as champagne gets
const LEVELS = {soft:'84%', medium:'94%', bright:'99%'};

// slot: five-minute steps since midnight (0–287); midnight and noon are both TWELVE O'CLOCK
function words(slot){
  const h = Math.floor(slot / 12) % 24, m = (slot % 12) * 5;
  if(m === 0) return ["IT","IS",HOURS[h % 12],"OCLOCK"];
  if(m <= 30) return ["IT","IS",...MINS[m],"PAST",HOURS[h % 12]];
  return ["IT","IS",...MINS[60 - m],"TO",HOURS[(h + 1) % 12]];
}
// each word is the first match after the one before it, kept within a row; null if the grid can't spell it
function cells(ws){
  const out = []; let from = 0;
  for(const w of ws){
    let i = from;
    for(;;){
      i = FLAT.indexOf(w, i);
      if(i < 0) return null;
      if(Math.floor(i / W) === Math.floor((i + w.length - 1) / W)) break;
      i++;
    }
    out.push([...w].map((_, k) => i + k));
    from = i + w.length;
  }
  return out;
}

const el = document.createElement('div');
el.id = 'wordclock';
if(native) el.className = 'native';
el.innerHTML = '<div class="wc"><div class="grid"></div><div class="dots"><i></i><i></i><i></i><i></i></div></div>';
document.body.appendChild(el);
const wc = el.firstChild, grid = wc.firstChild, dots = [...wc.querySelectorAll('.dots i')];
const letters = [...FLAT].map(ch => grid.appendChild(Object.assign(document.createElement('span'), {textContent:ch})));

let timer = null, drift = null, waitT = null, outT = null, ready = false, shown = '', opts = {dots:false, level:'medium'};

function render(){
  const d = new Date(), mins = d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60;
  const slot = (opts.dots ? Math.floor(mins / 5) : Math.round(mins / 5)) % 288;
  const extra = opts.dots ? Math.floor(mins) % 5 : 0;
  const key = slot + ':' + extra;
  if(!ready || key === shown) return;
  // the first words wait for the grid to come most of the way up (here it waits for Home to go too);
  // later ones wait for the old words to be fully out (1.2s), so two times are never lit together
  const lead = shown ? 1.2 : native ? 1.6 : 2.8;
  shown = key;
  const on = new Map();
  cells(words(slot)).forEach((cs, wi) => cs.forEach(i => on.set(i, lead + wi * .35)));
  if(native){ Launcher.clockLight(JSON.stringify({on:[...on], dots:extra, showDots:!!opts.dots, level:opts.level})); return; }
  letters.forEach((e, i) => {
    const want = on.has(i);
    if(want === e.classList.contains('on')) return;
    e.style.setProperty('--d', want ? on.get(i) + 's' : '0s');
    e.classList.toggle('on', want);
  });
  dots.forEach((e, i) => e.classList.toggle('on', i < extra));
}

function show(){
  if(timer) return;
  // start dark, without fading out the words left from last time
  shown = '';
  grid.classList.add('reset');
  letters.forEach(e => e.classList.remove('on'));
  grid.offsetWidth;
  grid.classList.remove('reset');
  clearTimeout(outT); document.body.classList.remove('wcout');
  document.body.classList.add('wordclock');
  // In the app the letters' surface only comes up once the page has gone fully dark (1.2s, wordclock.css):
  // Android builds it afresh each time and briefly disturbs the window while it does (a stale frame, a
  // misplaced edge), which can't show against a screen that's already one even dark.
  ready = !native;
  if(native) waitT = setTimeout(() => { ready = true; Launcher.clockShow(FLAT); render(); }, 1250);
  render();
  timer = setInterval(render, 5000);
  // burn-in: the lit words move every five minutes anyway; the whole grid drifts a few px every minute too
  drift = setInterval(() => wc.style.transform = `translate(${Math.round(Math.random()*24-12)}px,${Math.round(Math.random()*24-12)}px)`, 60000);
}
function hide(){
  if(!timer) return;
  clearTimeout(waitT); ready = false;
  clearInterval(timer); clearInterval(drift); timer = drift = null;
  if(native) Launcher.clockHide();
  // Home waits for the clock to clear (wordclock.css), then the hold comes off
  document.body.classList.add('wcout'); clearTimeout(outT); outT = setTimeout(() => document.body.classList.remove('wcout'), 700);
  document.body.classList.remove('wordclock');
}
function set(o){
  Object.assign(opts, o);
  el.style.setProperty('--wc-l', LEVELS[opts.level] || LEVELS.medium);
  el.classList.toggle('dots', !!opts.dots);
  if(timer){ shown = ''; render(); }
}

window.WordClock = {show, hide, set, words, cells, get active(){ return !!timer; }};
})();
