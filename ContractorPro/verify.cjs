const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const elements=new Map();function el(){return {textContent:'',innerHTML:'',style:{},hidden:false,addEventListener(){},querySelector(){return el()},querySelectorAll(){return []},showModal(){},close(){}}}
const store=new Map();const ctx={crypto:require('node:crypto').webcrypto,Intl,console,setTimeout,clearTimeout,location:{hash:''},window:{CP_CONFIG:{url:'',key:''}},document:{querySelector(s){if(!elements.has(s))elements.set(s,el());return elements.get(s)},querySelectorAll(){return []}},localStorage:{getItem:k=>store.get(k),setItem:(k,v)=>store.set(k,v)}};vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);
setImmediate(()=>{vm.runInContext(`
if(rows('projects').length!==2)throw Error('Demo projects');
if(sum(rows('payments'))!==20000)throw Error('Payments total');
if(netInvoice(rows('invoices')[0])!==14010)throw Error('Partial payment balance');
const s=projectStats(rows('projects')[0].id);
if(s.contract!==89500||s.cost!==24300||s.profit!==65200)throw Error('Project profit');
if(rows('quotations')[0].data.items.reduce((a,i)=>a+i.qty*i.rate,0)!==85000)throw Error('BOQ');
if(esc('<script>')!=='&lt;script&gt;')throw Error('Escape');
role='viewer';if(canKind('payments'))throw Error('Viewer permissions');
role='manager';if(canKind('payments')||!canKind('projects'))throw Error('Manager permissions');
role='finance';if(!canKind('payments')||canKind('variations'))throw Error('Finance permissions');
role='admin';
for(const key of Object.keys(modules)){location.hash='#'+key;render()}
`,ctx);for(const file of ['index.html','app.js','style.css','config.js','schema.sql','README.md'])assert.ok(fs.statSync(__dirname+'/'+file).size>0);console.log('PASS: demo arithmetic, access matrix, escaping, 13 module renders and assets. PostgreSQL integration not executed.');});
