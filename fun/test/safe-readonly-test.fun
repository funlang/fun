// Read-only safe level (SAFE=readonly): file reads are allowed, file writes,
// native code, raw memory and code loading are still blocked.
use 'fun/lib/test.fun';

test('file reads are allowed', {
  assert.is_true('README.md'.load().length() > 0);
  assert.is_true('README.md'.size() > 0);
  assert.is_true('README.md'.time() > 0);
  assert.not_nil('README.md'.find());
  // `hash()` is MD5 (32 hex), `hash(1)` is SHA1 (40 hex). Both read the file
  // content, so they are read capabilities.
  assert.equal('README.md'.hash().length(), 32);
  assert.equal('README.md'.hash(1).length(), 40);
});

test('file writes are still blocked', {
  assert.raises({ 'safe-readonly-out.txt'.save('x'); }, 'safe mode');
  assert.raises({ 'README.md'.copy('safe-readonly-copy.txt'); }, 'safe mode');
  assert.raises({ 'README.md'.move('safe-readonly-moved.md'); }, 'safe mode');
});

test('setting file time is blocked', {
  var zero = 0;
  var now = zero.time();
  assert.raises({ 'README.md'.time(set: now); }, 'safe mode');
});

test('native code is still blocked', {
  assert.raises({ 'libc.so.6'.getapi('getpid', ':i'); }, 'safe mode');
});

test('raw addresses are still blocked', {
  assert.raises({ 'abc'.move(0); }, 'safe mode');
  assert.raises({ 'abc'.movs(0); }, 'safe mode');
});

test('code loading from a file is still blocked', {
  assert.raises({ 'README.md'.compile(); }, 'safe mode');
  assert.raises({ '?. 1;'.compile(inline: true); }, 'safe mode');
});

test('plain data processing still works', {
  assert.equal('123'.toNum(), 123);
  assert.equal('abc'.upper(), 'ABC');
  assert.equal('{"a": 1}'.getJson(json: true).a, 1);
});

runTests();
