// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// jsonschema: validate JSON/FD data against a JSON Schema subset.
//
//     use 'jsonschema.fun';
//
//     var schema = 'user.schema.fd'.load();      // FD (default), or JSON text
//     var r = JsonSchema.check(data, schema);
//     if not r.ok then
//       ?. r.first.path & ': ' & r.first.message;
//     end if;
//
//     JsonSchema.valid(data, schema);            // -> true / false
//     JsonSchema.assert(data, schema);           // raises on the first error
//
// A schema may be an already parsed value (object), an FD document (the
// default authoring format) or JSON text. parse() auto-detects the text
// format: a leading '{' or '[' selects JSON, anything else selects FD.
//
// FD schemas are easy to read and can carry '#' comments:
//
//     # user.schema.fd
//     type object
//     required
//       - id
//       - name
//     properties
//       id
//         type integer
//         minimum 1
//       name
//         type string
//         minLength 1
//       email
//         type string
//         pattern ^[^@]+@[^@]+$
//       tags
//         type array
//         items
//           type string
//         maxItems 10
//     additionalProperties false
//
// FD notes:
//   - Write 'key value' (a space), not 'key: value'. A colon becomes part of
//     the key.
//   - Quote the words 'null', 'true' and 'false' when they are strings, e.g.
//     "type 'null'" or a list item "- 'table'". Unquoted they parse as the
//     FD constants nil/true/false.
//   - A value containing spaces (a regex, a description) must be quoted.
//
// Supported keywords (v0): type (string or list), properties, required,
// additionalProperties (bool or schema), items (single schema), minItems,
// maxItems, minimum, maximum, exclusiveMinimum, exclusiveMaximum, minLength,
// maxLength, pattern (PCRE), enum, const. title / description / default /
// $schema / $id / $comment / examples are ignored. Unknown keywords are
// ignored unless opts.strict is true.
//
// check() options: [maxErrors: 100, strict: false]. maxErrors caps the error
// list (a value <= 0 restores the default); strict also reports unknown
// keywords as 'schema' errors.
//
// Error objects carry path / keyword / message / expected / actual, where path
// is a JSON Pointer (/user/name, /tags/0) with ~ and / escaped as ~0 and ~1.
//
// Not yet supported: $ref/$defs, allOf/anyOf/oneOf/not, tuple items,
// patternProperties, propertyNames, dependencies, uniqueItems, format.
//
// minLength/maxLength count Unicode code points on UTF-8 and UTF-16 builds and
// GBK characters on a GBK build, not the raw string length.

var _enc = nil;

fun _detectEnc()
  // '你' is one code point: 3 bytes in UTF-8, 1 UTF-16 unit, 2 GBK bytes.
  var n = '你'.length();
  if n = 1 then return 'utf16'; end if;
  if n = 2 then return 'gbk'; end if;
  result = 'utf8';
end fun;

fun _cpLen(s)
  if _enc = 'utf8' then
    // Drop continuation bytes; PCRE does this scan in C.
    result = s.replace(/[\x80-\xBF]/g, '').length();
  elsif _enc = 'utf16' then
    // Count UTF-16 units except the low half of a surrogate pair.
    var n = 0;
    for i = 0 to s.length() - 1 do
      var b = s.toByte(i);
      if b < 55296 or b > 57343 then n += 1; end if;
    end do;
    result = n;
  else
    // GBK: a lead byte is always followed by a trail byte.
    var n = 0;
    var l = s.length();
    var i = 0;
    while i < l do
      var b = s.toByte(i);
      if b >= 129 and b <= 254 and i + 1 < l then i += 1; end if;
      n += 1;
      i += 1;
    end do;
    result = n;
  end if;
end fun;

fun _isColl(v)
  result = false;
  try
    // Strict equality is defined for basic values and is nil for collections,
    // so this avoids an exception per scalar (the @count probe was ~30x slower
    // on a 20k-record payload). The except branch covers odd objects whose
    // 'eq' member is not callable.
    result = not v.eq(v);
  except
    result = true;
  end try;
end fun;

fun _shape(v)
  var n = v.@count();
  if n = 0 then
    if v.@toJson(json: true) = '{}' then return 'object'; end if;
    return 'array';
  end if;
  var isObj = false;
  v.@each((x, k){
    if not isObj and k <> nil and k <> '' then isObj = true; end if;
  });
  if isObj then result = 'object'; else result = 'array'; end if;
end fun;

fun _kind(v)
  if _isColl(v) then return _shape(v); end if;
  var t = v.type();
  if t = 0 then return 'null'; end if;
  if t = 11 then return 'boolean'; end if;
  if t = 8 then return 'string'; end if;
  if t = 3 or t = 5 or t = 6 then return 'number'; end if;
  if t = 7 then return 'string'; end if;   // dates serialize as strings
  result = 'other';
end fun;

fun _deepEq(a, b)
  var ka = _kind(a);
  var kb = _kind(b);
  if ka <> kb then return false; end if;
  if ka = 'null' then return true; end if;
  if ka = 'number' then return a = b; end if;   // 1 and 1.0 are equal in JSON
  if ka = 'object' then
    if a.@count() <> b.@count() then return false; end if;
    var ok = true;
    a.@each((v, k){
      if ok then
        if not b.@has(k) then ok = false;
        elsif not _deepEq(v, b[k]) then ok = false;
        end if;
      end if;
    });
    return ok;
  end if;
  if ka = 'array' then
    var n = a.@count();
    if n <> b.@count() then return false; end if;
    for i = 0 to n - 1 do
      if not _deepEq(a[i], b[i]) then return false; end if;
    end do;
    return true;
  end if;
  result = a.eq(b);
end fun;

fun _typeOk(v, k, t)
  if t = 'null' then return k = 'null'; end if;
  if t = 'integer' then
    if k <> 'number' then return false; end if;
    if v.type() = 3 then return true; end if;
    return v.toStr() =~ /^-?\d++$/;
  end if;
  result = k = t;
end fun;

fun _matchesType(v, k, t)
  if _isColl(t) then
    var ok = false;
    t.@each((x){
      if not ok and _typeOk(v, k, x) then ok = true; end if;
    });
    result = ok;
  else
    result = _typeOk(v, k, t);
  end if;
end fun;

fun _typeText(t)
  if _isColl(t) then
    var r = '';
    t.@each((x){
      if r <> '' then r &= ' | '; end if;
      r &= x;
    });
    result = r;
  else
    result = t;
  end if;
end fun;

fun _path(base, seg)
  var s = '' & seg;
  var r = '';
  for i = 0 to s.length() - 1 do
    var c = s[i];
    if c = '~' then r &= '~0';
    elsif c = '/' then r &= '~1';
    else r &= c; end if;
  end do;
  result = base & '/' & r;
end fun;

fun _addErr(errs, path, kw, msg, expected, actual, limit)
  if limit > 0 and errs.@count() >= limit then return; end if;
  errs.@add(new [
    path: path,
    keyword: kw,
    message: msg,
    expected: expected,
    actual: actual
  ]);
end fun;

fun _countBounds(n, s, lo, hi, path, errs, limit)
  if s.@has(lo) and n < s[lo] then
    _addErr(errs, path, lo, 'must be >= ' & s[lo], s[lo], n, limit);
  end if;
  if s.@has(hi) and n > s[hi] then
    _addErr(errs, path, hi, 'must be <= ' & s[hi], s[hi], n, limit);
  end if;
end fun;

fun _numBounds(v, s, path, errs, limit)
  if s.@has('minimum') and v < s['minimum'] then
    _addErr(errs, path, 'minimum', 'must be >= ' & s['minimum'], s['minimum'], v, limit);
  end if;
  if s.@has('maximum') and v > s['maximum'] then
    _addErr(errs, path, 'maximum', 'must be <= ' & s['maximum'], s['maximum'], v, limit);
  end if;
  if s.@has('exclusiveMinimum') and v <= s['exclusiveMinimum'] then
    _addErr(errs, path, 'exclusiveMinimum', 'must be > ' & s['exclusiveMinimum'], s['exclusiveMinimum'], v, limit);
  end if;
  if s.@has('exclusiveMaximum') and v >= s['exclusiveMaximum'] then
    _addErr(errs, path, 'exclusiveMaximum', 'must be < ' & s['exclusiveMaximum'], s['exclusiveMaximum'], v, limit);
  end if;
end fun;

// Keywords consumed by this module plus annotations that are deliberately
// ignored. Anything else is unknown, and only strict mode reports it.
var _known = [
  type: true,
  properties: true,
  required: true,
  additionalProperties: true,
  items: true,
  minItems: true,
  maxItems: true,
  minimum: true,
  maximum: true,
  exclusiveMinimum: true,
  exclusiveMaximum: true,
  minLength: true,
  maxLength: true,
  pattern: true,
  enum: true,
  const: true,
  title: true,
  description: true,
  default: true,
  '$schema': true,
  '$id': true,
  '$comment': true,
  examples: true
];

fun _validate(v, s, path, errs, limit, strict)
  if errs.@count() >= limit then return; end if;
  if not _isColl(s) then return; end if;

  if strict then
    s.@each((x, k){
      if not _known.@has(k) then
        _addErr(errs, path, 'schema', 'unknown keyword: ' & k, nil, k, limit);
      end if;
    });
  end if;

  if s.@has('enum') then
    var ok = false;
    s['enum'].@each((x){
      if not ok and _deepEq(v, x) then ok = true; end if;
    });
    if not ok then
      _addErr(errs, path, 'enum', 'value is not one of the allowed values', 'enum', v, limit);
    end if;
  end if;

  if s.@has('const') then
    if not _deepEq(v, s['const']) then
      _addErr(errs, path, 'const', 'value does not match const', s['const'], v, limit);
    end if;
  end if;

  var k = _kind(v);

  if s.@has('type') then
    if not _matchesType(v, k, s['type']) then
      _addErr(errs, path, 'type',
        'expected ' & _typeText(s['type']) & ', got ' & k,
        _typeText(s['type']), k, limit);
      return;
    end if;
  end if;

  if k = 'object' then
    if s.@has('required') then
      s['required'].@each((name){
        if not v.@has(name) then
          _addErr(errs, path, 'required', 'missing required property: ' & name, name, nil, limit);
        end if;
      });
    end if;

    var props = nil;
    if _isColl(s['properties']) and _shape(s['properties']) = 'object' then
      props = s['properties'];
    end if;
    var hasAp = s.@has('additionalProperties');
    var ap = nil;
    if hasAp then ap = s['additionalProperties']; end if;

    // One pass over the value: known properties get their schema, unknown
    // ones go through additionalProperties.
    v.@each((cv, name){
      if props <> nil and props.@has(name) then
        _validate(cv, props[name], _path(path, name), errs, limit, strict);
      elsif hasAp then
        if ap = false then
          _addErr(errs, _path(path, name), 'additionalProperties',
            'property is not allowed', false, cv, limit);
        elsif _isColl(ap) and _shape(ap) = 'object' then
          _validate(cv, ap, _path(path, name), errs, limit, strict);
        end if;
      end if;
    });
  end if;

  if k = 'array' then
    var n = v.@count();
    if s.@has('items') then
      var it = s['items'];
      // A list here is the draft-4 tuple form; v0 only supports one schema.
      if _isColl(it) and _shape(it) = 'object' then
        for i = 0 to n - 1 do
          _validate(v[i], it, _path(path, i), errs, limit, strict);
        end do;
      end if;
    end if;
    _countBounds(n, s, 'minItems', 'maxItems', path, errs, limit);
  end if;

  if k = 'string' then
    var sv = v.toStr();
    _countBounds(_cpLen(sv), s, 'minLength', 'maxLength', path, errs, limit);
    if s.@has('pattern') then
      if not (sv =~ s['pattern'].toRegex()) then
        _addErr(errs, path, 'pattern', 'does not match pattern ' & s['pattern'], s['pattern'], sv, limit);
      end if;
    end if;
  end if;

  if k = 'number' then
    _numBounds(v, s, path, errs, limit);
  end if;
end fun;

class _JsonSchemaApi()
  var DEFAULT_MAX_ERRORS = 100;

  fun parse(text)
    if text = nil then raise 'jsonschema: schema text is nil'; end if;
    var t = text.replace(/^\s++/, '');
    if t.length() > 0 and (t[0] = '{' or t[0] = '[') then
      result = text.getJson(json: true);
    else
      result = text.getJson(fd: true);
    end if;
    if result = nil then raise 'jsonschema: schema parse failed'; end if;
  end fun;

  fun check(data, schema, opts)
    var s = schema;
    if not _isColl(s) then
      if s = nil then raise 'jsonschema: schema is required'; end if;
      s = parse(s);
    end if;
    if _shape(s) <> 'object' then raise 'jsonschema: schema root must be an object'; end if;

    var limit = DEFAULT_MAX_ERRORS;
    var strict = false;
    if opts <> nil then
      if opts.@has('maxErrors') then limit = opts['maxErrors']; end if;
      if opts.@has('strict') then strict = opts['strict']; end if;
    end if;
    if limit <= 0 then limit = DEFAULT_MAX_ERRORS; end if;

    var errs = new [];
    _validate(data, s, '', errs, limit, strict);
    var first = nil;
    if errs.@count() > 0 then first = errs[0]; end if;
    result = new [ok: errs.@count() = 0, errors: errs, first: first];
  end fun;

  fun valid(data, schema, opts)
    result = check(data, schema, opts)['ok'];
  end fun;

  fun assert(data, schema, opts)
    var r = check(data, schema, opts);
    if not r['ok'] then
      var e = r['first'];
      raise 'jsonschema: ' & e['path'] & ' ' & e['keyword'] & ': ' & e['message'];
    end if;
    result = true;
  end fun;
end class;

_enc = _detectEnc();

var JsonSchema = _JsonSchemaApi();
