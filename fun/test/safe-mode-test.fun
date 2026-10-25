// Safe build (-dFunSafe) must refuse the capability categories listed in
// SAFETY.zh.md while leaving ordinary data processing alone.
// Run it with funcmd-safe, not the normal interpreter:
//   fun/test/run-safe-regression.sh
use 'fun/lib/test.fun';

fun identity(x)
  result = x;
end fun;

// --- ordinary string/number/JSON work is unchanged -----------------------
test('plain data processing', {
  assert.equal('123'.toNum(), 123);
  assert.equal('abc'.upper(), 'ABC');
  assert.equal('A'.toByte(0), 65);
  assert.equal('{"a": 1}'.getJson(json: true).a, 1);
  var zero = 0;
  assert.is_true(zero.time() > 0);
  var name = 'world';
  assert.equal('hello $name'.eval(), 'hello world');
});

test('bounded string writes still work', {
  var s = 'abc';
  s[0] = 'Z';
  assert.equal(s, 'Zbc');
});

test('compile from a string is still allowed', {
  assert.not_nil('?. 1 + 2;'.compile());
});

// --- NAT: native code -----------------------------------------------------
test('getapi is blocked', {
  assert.raises({ 'libc.so.6'.getapi('getpid', ':i'); }, 'safe mode');
});

test('native callback is blocked', {
  assert.raises({ identity.@toCallback(nil, 'i:i'); }, 'safe mode');
});

// --- MEM: raw memory ------------------------------------------------------
test('move to a numeric address is blocked', {
  assert.raises({ 'abc'.move(0); }, 'safe mode');
});

test('movs to a numeric address is blocked', {
  assert.raises({ 'abc'.movs(0); }, 'safe mode');
});

test('toNum bounded reinterpret reads are allowed', {
  var i = 'abcd'.toNum(ptr: 1);
  'abcd'.toNum(ptr: 2);
  'abcdefgh'.toNum(ptr: 3);
  assert.is_true(i <> 0);
});

test('fromByte raw writes are blocked', {
  assert.raises({ 'ab'.fromByte(0, 65); }, 'safe mode');
});

test('fractional-index byte writes are blocked', {
  assert.raises({
    var s = 'abc';
    s[0.5] = 'Z';
  }, 'safe mode');
});

// --- FSR: file system reads ----------------------------------------------
test('file reads are blocked', {
  assert.raises({ 'README.md'.load(); }, 'safe mode');
  assert.raises({ 'README.md'.hash(); }, 'safe mode');
  assert.raises({ 'README.md'.size(); }, 'safe mode');
  assert.raises({ 'README.md'.time(); }, 'safe mode');
  assert.raises({ 'README.md'.find(); }, 'safe mode');
});

// --- FSW: file system writes ---------------------------------------------
test('file writes are blocked', {
  assert.raises({ 'safe-mode-out.txt'.save('x'); }, 'safe mode');
  assert.raises({ 'README.md'.copy('safe-mode-copy.txt'); }, 'safe mode');
  assert.raises({ 'README.md'.move('safe-mode-moved.md'); }, 'safe mode');
});

// --- SRC: loading code from a file / injecting inline ---------------------
test('compile from a file is blocked', {
  assert.raises({ 'README.md'.compile(); }, 'safe mode');
});

test('inline compile is blocked', {
  assert.raises({ '?. 1;'.compile(inline: true); }, 'safe mode');
});

runTests();
