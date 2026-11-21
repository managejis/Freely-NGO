// Runs Code.gs against an in-memory mock of Google's services.   node google-apps-script/test.js
const fs = require('fs');
const vm = require('vm');
const crypto = require('crypto');
const path = require('path');

class Range {
  constructor(sh, r, c, nr, nc) { Object.assign(this, { sh, r, c, nr, nc }); }
  getValues() { const o = []; for (let i = 0; i < this.nr; i++) { const row = []; for (let j = 0; j < this.nc; j++) row.push(this.sh.get(this.r + i, this.c + j)); o.push(row); } return o; }
  setValues(v) { for (let i = 0; i < v.length; i++) for (let j = 0; j < v[i].length; j++) this.sh.set(this.r + i, this.c + j, v[i][j]); return this; }
  setValue(v) { this.sh.set(this.r, this.c, v); return this; }
  setNumberFormat() { return this; }
  setFontWeight() { return this; }
}
class Sheet {
  constructor(name) { this.name = name; this.cells = {}; }
  get(r, c) { const v = this.cells[r + ',' + c]; return v === undefined ? '' : v; }
  set(r, c, v) { this.cells[r + ',' + c] = String(v); }
  getRange(r, c, nr = 1, nc = 1) { return new Range(this, r, c, nr, nc); }
  getLastRow() { let m = 0; for (const k of Object.keys(this.cells)) if (this.cells[k] !== '') m = Math.max(m, +k.split(',')[0]); return m; }
  getMaxRows() { return 1000; }
  setFrozenRows() {}
}
const sheets = [new Sheet('Sheet1')];
const store = {};
let uuid = 0;
const ctx = {
  console, JSON, Math, Date, String, Number, Object, Array, Error,
  SpreadsheetApp: { getActiveSpreadsheet: () => ({
    getSheetByName: n => sheets.find(s => s.name === n) || null,
    insertSheet: n => { const s = new Sheet(n); sheets.push(s); return s; },
    getSheets: () => sheets,
    deleteSheet: s => sheets.splice(sheets.indexOf(s), 1),
  }) },
  PropertiesService: { getScriptProperties: () => ({
    getProperty: k => (k in store ? store[k] : null),
    getProperties: () => ({ ...store }),
    setProperty: (k, v) => { store[k] = String(v); },
    setProperties: o => { for (const k in o) store[k] = String(o[k]); },
  }) },
  LockService: { getScriptLock: () => ({ waitLock() {}, releaseLock() {} }) },
  Utilities: {
    getUuid: () => crypto.randomUUID(),
    computeDigest: (_a, s) => Array.from(crypto.createHash('sha256').update(s).digest()).map(x => (x > 127 ? x - 256 : x)),
    DigestAlgorithm: { SHA_256: 1 }, Charset: { UTF_8: 1 },
  },
  ContentService: { createTextOutput: s => ({ text: s, setMimeType() { return this; } }), MimeType: { JSON: 1 } },
};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, 'Code.gs'), 'utf8'), ctx);

const call = req => JSON.parse(ctx.doPost({ postData: { contents: JSON.stringify(req) } }).text);
let failed = 0;
const ok = (cond, msg) => { if (cond) console.log('  ok   ' + msg); else { failed++; console.log('  FAIL ' + msg); } };

let n = 0;
const rec = (type, id, data, o = {}) => ({ id, type, data, version: 1, updatedAt: new Date(Date.now() + ++n).toISOString(), by: 'x', deleted: false, hash: crypto.randomBytes(6).toString('hex'), lineage: [], ...o });

console.log('setup');
let r = call({ action: 'init', orgName: 'Hope Foundation', mobile: '9876543210', name: 'Super Admin' });
ok(r.ok && r.orgCode.length === 8 && r.adminToken, 'admin creates the NGO');
const A = { mobile: '9876543210', deviceId: 'adm', token: r.adminToken };
const CODE = r.orgCode;
ok(!call({ action: 'init', orgName: 'Other', mobile: '9876543210' }).ok, 'second init is refused');
ok(sheets.map(s => s.name).includes('Beneficiaries') && sheets.map(s => s.name).includes('Expenses') && !sheets.some(s => s.name === 'Sheet1'), 'tabs created, default Sheet1 removed');

function newUser(mobile, dev, name) {
  call({ action: 'join', orgCode: CODE, mobile, name, deviceId: dev });
  call({ action: 'approve', ...A, deviceId: dev });
  const t = call({ action: 'status', orgCode: CODE, mobile, deviceId: dev }).token;
  return { mobile, deviceId: dev, token: t };
}
const roles = (u, rl, branch) => {
  call({ action: 'setRoles', ...A, targetMobile: u.mobile, roles: rl });
  if (branch !== undefined) call({ action: 'setBranch', ...A, targetMobile: u.mobile, branch });
};
const sync = (u, changes = [], since = 0) => call({ action: 'sync', ...u, since, changes });
const typesOf = r => r.records.map(x => x.type);
const idsOf = (r, t) => r.records.filter(x => x.type === t).map(x => x.id);

console.log('joining');
ok(!call({ action: 'join', orgCode: 'WRONG', mobile: '9000000001', name: 'Asha', deviceId: 'd1' }).ok, 'wrong NGO code rejected');
r = call({ action: 'join', orgCode: CODE, mobile: '+91 90000 00001', name: 'Asha', deviceId: 'd1' });
ok(r.ok && r.status === 'pending', 'user requests access (mobile normalised)');
ok(call({ action: 'sync', mobile: '9000000001', deviceId: 'd1', token: 'guess', since: 0 }).code === 'DENIED', 'pending phone cannot sync');
ok(call({ action: 'approve', mobile: '9000000001', deviceId: 'd1', token: 'x' }).code === 'DENIED', 'a user cannot approve');
ok(call({ action: 'approve', ...A, deviceId: 'd1' }).ok, 'admin approves');
r = call({ action: 'status', orgCode: CODE, mobile: '9000000001', deviceId: 'd1' });
ok(r.status === 'approved' && r.token, 'user phone receives its token');
const U = { mobile: '9000000001', deviceId: 'd1', token: r.token };
ok(!call({ action: 'status', orgCode: CODE, mobile: '9000000001', deviceId: 'd1' }).token, 'token is handed over only once');

console.log('data set-up by the admin');
const brA = rec('branch', 'brA', { name: 'Sunrise Children Home', kind: 'Children Home' });
const brB = rec('branch', 'brB', { name: 'Evergreen Elders Home', kind: 'Old Age Home' });
const kid = rec('beneficiary', 'kid1', { bid: 'CH-AAAAAA', name: 'Ravi', category: 'child', branchId: 'brA', status: 'Active', admissionDate: '2026-01-05' });
const old = rec('beneficiary', 'old1', { bid: 'OA-BBBBBB', name: 'Mary', category: 'elder', branchId: 'brB', status: 'Active' });
const med = rec('medical', 'med1', { beneficiaryId: 'kid1', beneficiaryName: 'Ravi', category: 'child', branchId: 'brA', kind: 'Vaccination', date: '2026-02-01' });
const safe = rec('safeguard', 'sg1', { beneficiaryId: 'kid1', beneficiaryName: 'Ravi', category: 'child', branchId: 'brA', kind: 'Incident', date: '2026-02-02' });
const care = rec('care', 'care1', { beneficiaryId: 'old1', beneficiaryName: 'Mary', category: 'elder', branchId: 'brB', kind: 'Daily observation', date: '2026-02-03' });
const don = rec('donation', 'don1', { date: '2026-03-01', donor: 'Anna', type: 'Cash', amount: 5000, branchId: 'brA' });
const ann = rec('announcement', 'an1', { title: 'Welcome', body: 'Hello', date: '2026-03-01' });
const st = rec('settings', 'settings-1', { name: 'Hope Foundation HQ' });
r = sync(A, [brA, brB, kid, old, med, safe, care, don, ann, st]);
ok(r.ok && r.accepted.length === 10, 'admin pushes branches, beneficiaries, records, donation, notice, settings');
ok(sheets.find(s => s.name === 'Beneficiaries').get(2, 10) === 'Ravi', 'rows are readable in their tabs');
ok(sheets.find(s => s.name === 'Organization').get(2, 2) === 'Hope Foundation HQ', 'NGO name updated from settings');

console.log('roles and visibility');
r = sync(U);
ok(r.roles.length === 0, 'a new user has no role');
ok(typesOf(r).every(t => ['branch', 'announcement', 'settings'].includes(t)) && typesOf(r).includes('branch'), 'without a role only branches, notices and settings are visible');
roles(U, ['doctor']);
r = sync(U);
let ty = typesOf(r);
ok(ty.includes('beneficiary') && ty.includes('medical') && ty.includes('care') && !ty.includes('donation') && !ty.includes('safeguard'), 'doctor sees beneficiaries, medical and care records, not donations or safeguarding');
ok(sync(U, [rec('medical', 'med2', { beneficiaryId: 'kid1', category: 'child', branchId: 'brA', kind: 'Health check-up', date: '2026-03-05' })]).accepted.length === 1, 'doctor can add a medical record');
ok(sync(U, [rec('beneficiary', 'k9', { name: 'X', category: 'child', branchId: 'brA' })]).accepted.length === 0, 'doctor cannot register beneficiaries');
ok(sync(U, [rec('donation', 'd9', { amount: 5, type: 'Cash', branchId: 'brA' })]).accepted.length === 0, 'doctor cannot enter donations');
ok(!call({ action: 'setRoles', ...U, targetMobile: '9000000001', roles: ['ngo_admin'] }).ok, 'a user cannot give roles');
ok(call({ action: 'setRoles', ...A, targetMobile: '9000000001', roles: ['accountant', 'bogus'] }).roles.join() === 'accountant', 'unknown roles are dropped');
r = sync(U);
ty = typesOf(r);
ok(ty.includes('donation') && !ty.includes('medical') && !ty.includes('safeguard'), 'accountant sees donations, never medical or safeguarding records');
ok(!ty.includes('person') && !ty.includes('beneficiary'), 'accountant sees no staff or beneficiary records');

console.log('category restriction for coordinators');
roles(U, ['children_coordinator'], '');
r = sync(U);
ok(idsOf(r, 'beneficiary').join() === 'kid1', 'children coordinator sees children only');
ok(!idsOf(r, 'care').includes('care1') && idsOf(r, 'safeguard').includes('sg1'), 'and only the care / safeguarding records of children');
ok(sync(U, [rec('beneficiary', 'k2', { name: 'Elder X', category: 'elder', branchId: 'brB' })]).accepted.length === 0, 'cannot register someone of another category');
ok(sync(U, [rec('beneficiary', 'k3', { name: 'Sita', category: 'child', branchId: 'brA' })]).accepted.length === 1, 'can register a child');
roles(U, ['children_coordinator', 'oldage_coordinator']);
r = sync(U);
ok(idsOf(r, 'beneficiary').includes('old1') && idsOf(r, 'beneficiary').includes('kid1'), 'two coordinator roles see both categories');

console.log('branch assignment');
roles(U, ['home_manager'], 'brB');
r = sync(U);
ok(r.branch === 'brB' && idsOf(r, 'beneficiary').join() === 'old1', 'home manager of branch B sees only branch B beneficiaries');
ok(!idsOf(r, 'donation').includes('don1') && !idsOf(r, 'medical').includes('med1'), 'and not the donations / medical records of branch A');
ok(sync(U, [rec('beneficiary', 'k4', { name: 'In A', category: 'child', branchId: 'brA' })]).accepted.length === 0, 'cannot write into branch A');
ok(sync(U, [rec('beneficiary', 'k5', { name: 'In B', category: 'elder', branchId: 'brB' })]).accepted.length === 1, 'can write into own branch');
const steal = rec('beneficiary', 'kid1', { ...kid.data, name: 'Stolen', branchId: 'brB' }, { version: 5, lineage: [kid.hash] });
ok(sync(U, [steal]).accepted.length === 0, 'cannot take over a record of another branch');
ok(!call({ action: 'setBranch', ...A, targetMobile: '9000000001', branch: 'nope' }).ok, 'unknown branch is refused');
ok(!call({ action: 'setBranch', ...U, targetMobile: '9000000001', branch: '' }).ok, 'a user cannot change branch assignments');

console.log('transfer keeps history with the beneficiary');
const moved = rec('beneficiary', 'kid1', { ...kid.data, branchId: 'brB' }, { version: 2, lineage: [kid.hash] });
ok(sync(A, [moved]).accepted.length === 1, 'admin transfers the child to branch B');
r = sync(U);
ok(idsOf(r, 'beneficiary').includes('kid1'), 'manager of B now sees the child');
roles(U, ['home_manager', 'doctor'], 'brB');
r = sync(U);
ok(idsOf(r, 'medical').includes('med1') && idsOf(r, 'medical').includes('med2'), 'and the medical history that came with the child');
ok(idsOf(r, 'safeguard').includes('sg1'), 'and the safeguarding history (manager role)');

console.log('expense workflow');
roles(U, ['caretaker'], 'brA');
const mk = (id, status = 'entered', extra = {}) => ({ date: '2026-04-01', category: 'Food and groceries', description: 'Rice', amount: 1200, mode: 'Cash', branchId: 'brA', status, enteredBy: '9000000001', ...extra });
const ex1 = rec('expense', 'ex1', mk('ex1'));
ok(sync(U, [ex1]).accepted.length === 1, 'caretaker enters an expense');
ok(sync(U, [rec('expense', 'ex2', mk('ex2', 'verified'))]).accepted.length === 0, 'a new expense cannot start as verified');
ok(sync(U, [rec('expense', 'ex3', mk('ex3', 'entered', { enteredBy: '9111111111' }))]).accepted.length === 0, 'cannot enter an expense in somebody else\'s name');
const mgr = newUser('9000000002', 'd2', 'Meena');
roles(mgr, ['home_manager'], 'brA');
const accn = newUser('9000000003', 'd3', 'Paul');
roles(accn, ['accountant'], '');
const exec = newUser('9000000004', 'd4', 'Chair');
roles(exec, ['ngo_admin'], '');
r = sync(U);
ok(idsOf(r, 'expense').join() === 'ex1' && !typesOf(r).includes('donation'), 'caretaker receives only the expense entries made by themselves');
ok(sync(U, [rec('expense', 'ex1', mk('ex1', 'verified', { verifiedBy: 'x' }), { version: 2, lineage: [ex1.hash] })]).accepted.length === 0, 'caretaker cannot verify their own expense');
const ex1v = rec('expense', 'ex1', mk('ex1', 'verified', { verifiedBy: mgr.mobile }), { version: 2, lineage: [ex1.hash] });
ok(sync(mgr, [ex1v]).accepted.length === 1, 'manager verifies');
const ex1a = rec('expense', 'ex1', mk('ex1', 'approved', { verifiedBy: mgr.mobile, approvedBy: 'x' }), { version: 3, lineage: [ex1.hash, ex1v.hash] });
ok(sync(mgr, [ex1a]).accepted.length === 0, 'manager cannot approve');
ok(sync(exec, [ex1a]).accepted.length === 1, 'administrator approves');
r = sync(U);
ok(idsOf(r, 'expense').includes('ex1') && r.records.find(x => x.id === 'ex1').data.status === 'approved', 'the person who entered it still receives its later steps');
const ex1p = rec('expense', 'ex1', mk('ex1', 'paid', { approvedBy: 'x', paidBy: accn.mobile }), { version: 4, lineage: [ex1.hash, ex1v.hash, ex1a.hash] });
ok(sync(exec, [ex1p]).accepted.length === 0, 'administrator cannot record payment (accountant only)');
ok(sync(accn, [ex1p]).accepted.length === 1, 'accountant records payment');
const ex1edit = rec('expense', 'ex1', mk('ex1', 'paid', { amount: 9999 }), { version: 5, lineage: [ex1.hash, ex1v.hash, ex1a.hash, ex1p.hash] });
ok(sync(accn, [ex1edit]).accepted.length === 0, 'a paid expense cannot be edited');
const ex1void = rec('expense', 'ex1', mk('ex1', 'paid', { void: true, voidReason: 'duplicate' }), { version: 5, lineage: [ex1.hash, ex1v.hash, ex1a.hash, ex1p.hash] });
ok(sync(accn, [ex1void]).accepted.length === 1, 'but it can be voided with a reason');
const revive = rec('expense', 'ex1', mk('ex1', 'paid'), { version: 6, lineage: [ex1.hash, ex1v.hash, ex1a.hash, ex1p.hash, ex1void.hash] });
sync(accn, [revive]);
ok(sync(A).records.find(x => x.id === 'ex1').data.void === true, 'a voided expense cannot be silently revived');

console.log('conflicts');
r = sync(A);
const base = r.records.find(x => x.id === 'old1');
const byA = rec('beneficiary', 'old1', { ...base.data, phone: '222' }, { version: base.version + 1, lineage: [...base.lineage, base.hash] });
const byB = rec('beneficiary', 'old1', { ...base.data, phone: '333' }, { version: base.version + 1, lineage: [...base.lineage, base.hash] });
ok(sync(A, [byA]).accepted.length === 1, 'first edit accepted');
roles(U, ['ngo_admin'], '');
r = sync(U, [byB]);
ok(r.conflicts.length === 1 && r.conflicts[0].server.data.phone === '222', 'second edit from the same base is a conflict; nothing overwritten');
const merged = rec('beneficiary', 'old1', { ...base.data, phone: '222' }, { version: byA.version + 1, lineage: [...byB.lineage, byB.hash, byA.hash] });
ok(sync(U, [merged]).accepted.length === 1, 'resolved version (descends from both) accepted');

console.log('access control');
ok(sync(U, [rec('settings', 'settings-1', { name: 'Hacked' })]).accepted.length === 0, 'a user cannot change NGO settings');
ok(sync(U, [rec('branch', 'brC', { name: 'New' })]).accepted.length === 0, 'only the Super Admin creates branches');
ok(sync(U, [rec('audit', 'au1', { action: 'x', by: '9999999999' })]).accepted.length === 0, 'audit entries cannot be forged for another person');
ok(call({ action: 'setUserStatus', ...A, targetMobile: '9000000001', status: 'disabled' }).ok, 'admin disables the user');
r = sync(U);
ok(r.code === 'DENIED' && r.status === 'disabled', 'disabled user is denied with the reason');
ok(!call({ action: 'join', orgCode: CODE, mobile: '9000000001', name: 'Asha', deviceId: 'd9' }).ok, 'disabled user cannot rejoin');
call({ action: 'setUserStatus', ...A, targetMobile: '9000000001', status: 'approved' });
ok(call({ action: 'join', orgCode: CODE, mobile: '9000000001', name: 'Asha', deviceId: 'd9' }).status === 'pending', 're-enabled user must be approved again');
call({ action: 'approve', ...A, deviceId: 'd9' });
const U2 = { mobile: '9000000001', deviceId: 'd9', token: call({ action: 'status', orgCode: CODE, mobile: '9000000001', deviceId: 'd9' }).token };
ok(sync(U2).ok, 'approved again, sync works');
call({ action: 'forceLogout', ...A });
ok(sync(U2).status === 'loggedout', 'force logout cuts every user phone');
ok(call({ action: 'recover', ...A, deviceId: 'new-admin-phone' }).orgCode === CODE, 'admin key recovers the NGO on a new phone');
ok(call({ action: 'recover', ...A, token: 'bad' }).code === 'DENIED', 'wrong admin key is refused');

console.log(failed ? `\n${failed} FAILED` : '\nall passed');
process.exit(failed ? 1 : 0);
