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
//     // text entry points: parse the data first, then validate
//     JsonSchema.checkJson(jsonText, schema);
//     JsonSchema.checkFd(fdText, schema);
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
// Supported keywords (v0.x): type (string or list), properties, required,
// additionalProperties (bool or schema), items (single schema or tuple),
// additionalItems, minItems, maxItems, uniqueItems, minimum, maximum,
// exclusiveMinimum, exclusiveMaximum, minLength, maxLength, pattern (PCRE),
// patternProperties, propertyNames, enum, const, allOf / anyOf / oneOf / not,
// $ref / $defs / definitions (local JSON Pointers only), and format (email,
// date, time, date-time, uri, uri-reference, uuid, ipv4, hostname, regex).
// title / description / default / $schema / $id / $comment / examples are
// ignored. Unknown keywords are ignored unless opts.strict is true.
//
// check() options: [maxErrors: 100, strict: false]. maxErrors caps the error
// list (a value <= 0 restores the default); strict also reports unknown
// keywords as 'schema' errors.
//
// Error objects carry path / keyword / message / expected / actual, where path
// is a JSON Pointer (/user/name, /tags/0) with ~ and / escaped as ~0 and ~1.
//
// Not yet supported: external $ref (file/URL), dependencies, if/then/else,
// contains, and boolean root schemas. Unknown formats are annotations and pass.
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

// --- format checks --------------------------------------------------------

fun _validDate(s)
  if not (s =~ /^\d{4}-\d{2}-\d{2}$/) then return false; end if;
  var y = s.substr(0, 4).toNum(0);
  var m = s.substr(5, 2).toNum(0);
  var d = s.substr(8, 2).toNum(0);
  if m < 1 or m > 12 then return false; end if;
  var days = [31,28,31,30,31,30,31,31,30,31,30,31];
  var md = days[m - 1];
  if m = 2 and ((y mod 4 = 0 and y mod 100 <> 0) or y mod 400 = 0) then md = 29; end if;
  result = d >= 1 and d <= md;
end fun;

fun _validTime(s)
  result = s =~ /^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:[Zz]|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/;
end fun;

fun _formatOk(fmt, s)
  if fmt = 'email' then
    result = s =~ /^[^@\s]+@[^@\s]+$/;
  elsif fmt = 'date' then
    result = _validDate(s);
  elsif fmt = 'time' then
    result = _validTime(s);
  elsif fmt = 'date-time' then
    var at = s.subpos('T');
    if at < 0 then at = s.subpos('t'); end if;
    if at <= 0 then
      result = false;
    else
      result = _validDate(s.substr(0, at)) and _validTime(s.substr(at + 1, s.length()));
    end if;
  elsif fmt = 'uri' then
    result = s =~ /^[A-Za-z][A-Za-z0-9+.-]*:\S*$/;
  elsif fmt = 'uri-reference' then
    result = s =~ /^\S*$/;
  elsif fmt = 'uuid' then
    result = s =~ /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  elsif fmt = 'ipv4' then
    result = s =~ /^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$/;
  elsif fmt = 'hostname' then
    result = s =~ /^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$/;
  elsif fmt = 'regex' then
    try
      // toRegex() alone defers PCRE compilation; matching forces it and
      // surfaces a bad pattern as an exception.
      var probe = '';
      var ok = (probe =~ s.toRegex());
      result = true;
    except
      result = false;
    end try;
  else
    // Unknown formats are annotations in JSON Schema, so they pass.
    result = true;
  end if;
end fun;

// --- local $ref resolution ------------------------------------------------

fun _ptrDecode(s)
  // RFC 6901: ~1 is '/', ~0 is '~'. Decode ~1 first so ~01 becomes ~1,
  // not '/'.
  result = s.replace(/~1/g, '/').replace(/~0/g, '~');
end fun;

fun _resolveRef(root, ref)
  if ref = '#' then return root; end if;
  if ref.substr(0, 2) <> '#/' then return nil; end if;
  var cur = root;
  var ptr = ref.substr(2, ref.length());
  while ptr <> '' do
    var at = ptr.subpos('/');
    var seg = '';
    if at < 0 then
      seg = ptr;
      ptr = '';
    else
      seg = ptr.substr(0, at);
      ptr = ptr.substr(at + 1, ptr.length());
    end if;
    var key = _ptrDecode(seg);
    if not _isColl(cur) then return nil; end if;
    if not cur.@has(key) then return nil; end if;
    cur = cur[key];
  end do;
  result = cur;
end fun;

fun _stackHas(stack, key)
  var found = false;
  stack.@each((x){
    if not found and x = key then found = true; end if;
  });
  result = found;
end fun;

fun _parseFailure(kind, message)
  var e = new [
    path: '',
    keyword: 'parse',
    message: message,
    expected: kind,
    actual: nil
  ];
  result = new [ok: false, errors: [e], first: e];
end fun;

// Keywords consumed by this module plus annotations that are deliberately
// ignored. Anything else is unknown, and only strict mode reports it.
var _known = [
  type: true,
  properties: true,
  required: true,
  additionalProperties: true,
  items: true,
  additionalItems: true,
  minItems: true,
  maxItems: true,
  uniqueItems: true,
  minimum: true,
  maximum: true,
  exclusiveMinimum: true,
  exclusiveMaximum: true,
  minLength: true,
  maxLength: true,
  pattern: true,
  patternProperties: true,
  propertyNames: true,
  enum: true,
  const: true,
  allOf: true,
  anyOf: true,
  oneOf: true,
  'not': true,
  '$ref': true,
  '$defs': true,
  definitions: true,
  format: true,
  title: true,
  description: true,
  default: true,
  '$schema': true,
  '$id': true,
  '$comment': true,
  examples: true
];

fun _validate(v, s, path, errs, limit, strict, root, stack)
  if errs.@count() >= limit then return; end if;
  if s = true then return; end if;
  if s = false then
    _addErr(errs, path, 'false', 'value is not allowed by a false schema', false, v, limit);
    return;
  end if;
  if not _isColl(s) then return; end if;
  if _shape(s) <> 'object' then
    _addErr(errs, path, 'schema', 'schema must be an object or boolean', 'object', _kind(s), limit);
    return;
  end if;

  if strict then
    s.@each((x, k){
      if not _known.@has(k) then
        _addErr(errs, path, 'schema', 'unknown keyword: ' & k, nil, k, limit);
      end if;
    });
  end if;

  // $ref is resolved first; other keywords next to it are ignored, matching
  // draft-07. Only same-document JSON Pointers are supported.
  if s.@has('$ref') then
    var ref = s['$ref'];
    if _kind(ref) <> 'string' then
      _addErr(errs, path, '$ref', '$ref must be a string', 'string', _kind(ref), limit);
      return;
    end if;
    if not (ref =~ /^#/) then
      _addErr(errs, path, '$ref', 'only local references are supported: ' & ref, '#/...', ref, limit);
      return;
    end if;
    var target = _resolveRef(root, ref);
    if target = nil then
      _addErr(errs, path, '$ref', 'cannot resolve reference: ' & ref, ref, nil, limit);
      return;
    end if;
    // A schema that refers to itself at the same data path would never
    // terminate. The path is part of the key, so recursive schemas over
    // recursive data still work.
    var key = ref & '|' & path;
    if _stackHas(stack, key) then return; end if;
    if stack.@count() >= 256 then
      _addErr(errs, path, '$ref', 'reference nesting too deep', 256, stack.@count(), limit);
      return;
    end if;
    stack.@add(key);
    _validate(v, target, path, errs, limit, strict, root, stack);
    stack.@count(-1);
    return;
  end if;

  if s.@has('allOf') then
    var a = s['allOf'];
    if _isColl(a) and _shape(a) = 'array' then
      a.@each((sub){
        _validate(v, sub, path, errs, limit, strict, root, stack);
      });
    else
      _addErr(errs, path, 'allOf', 'allOf must be an array of schemas', 'array', _kind(a), limit);
    end if;
  end if;

  if s.@has('anyOf') then
    var a = s['anyOf'];
    if _isColl(a) and _shape(a) = 'array' then
      var passed = false;
      a.@each((sub){
        if not passed then
          var tmp = new [];
          _validate(v, sub, path, tmp, 1, strict, root, stack);
          if tmp.@count() = 0 then passed = true; end if;
        end if;
      });
      if not passed then
        _addErr(errs, path, 'anyOf', 'value does not match any schema', a.@count(), _kind(v), limit);
      end if;
    else
      _addErr(errs, path, 'anyOf', 'anyOf must be an array of schemas', 'array', _kind(a), limit);
    end if;
  end if;

  if s.@has('oneOf') then
    var a = s['oneOf'];
    if _isColl(a) and _shape(a) = 'array' then
      var hits = 0;
      a.@each((sub){
        var tmp = new [];
        _validate(v, sub, path, tmp, 1, strict, root, stack);
        if tmp.@count() = 0 then hits += 1; end if;
      });
      if hits <> 1 then
        _addErr(errs, path, 'oneOf',
          'value must match exactly one schema, matched ' & hits, 1, hits, limit);
      end if;
    else
      _addErr(errs, path, 'oneOf', 'oneOf must be an array of schemas', 'array', _kind(a), limit);
    end if;
  end if;

  if s.@has('not') then
    var tmp = new [];
    _validate(v, s['not'], path, tmp, 1, strict, root, stack);
    if tmp.@count() = 0 then
      _addErr(errs, path, 'not', 'value must not match the schema', false, true, limit);
    end if;
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
      if _isColl(s['required']) and _shape(s['required']) = 'array' then
        s['required'].@each((name){
          if not v.@has(name) then
            _addErr(errs, path, 'required', 'missing required property: ' & name, name, nil, limit);
          end if;
        });
      else
        _addErr(errs, path, 'required', 'required must be an array', 'array', _kind(s['required']), limit);
      end if;
    end if;

    var props = nil;
    if _isColl(s['properties']) and _shape(s['properties']) = 'object' then
      props = s['properties'];
    end if;
    var pats = new [];
    if _isColl(s['patternProperties']) and _shape(s['patternProperties']) = 'object' then
      s['patternProperties'].@each((ps, pat){
        try
          var re = pat.toRegex();
          var probe = '';
          var ok = (probe =~ re);
          pats.@add(new [re: re, schema: ps, text: pat]);
        except
          _addErr(errs, path, 'patternProperties', 'invalid pattern: ' & pat, pat, nil, limit);
        end try;
      });
    end if;
    var hasAp = s.@has('additionalProperties');
    var ap = nil;
    if hasAp then ap = s['additionalProperties']; end if;

    if s.@has('propertyNames') then
      var pn = s['propertyNames'];
      v.@each((cv, name){
        var tmp = new [];
        _validate('' & name, pn, _path(path, name), tmp, 1, strict, root, stack);
        if tmp.@count() > 0 then
          _addErr(errs, path, 'propertyNames',
            'property name is not allowed: ' & name, pn, name, limit);
        end if;
      });
    end if;

    // One pass over the value. properties and every matching
    // patternProperties schema both apply; additionalProperties only sees
    // names that neither matched.
    v.@each((cv, name){
      var matched = false;
      if props <> nil and props.@has(name) then
        _validate(cv, props[name], _path(path, name), errs, limit, strict, root, stack);
        matched = true;
      end if;
      pats.@each((p){
        if name =~ p['re'] then
          _validate(cv, p['schema'], _path(path, name), errs, limit, strict, root, stack);
          matched = true;
        end if;
      });
      if not matched and hasAp then
        if ap = false then
          _addErr(errs, _path(path, name), 'additionalProperties',
            'property is not allowed', false, cv, limit);
        else
          _validate(cv, ap, _path(path, name), errs, limit, strict, root, stack);
        end if;
      end if;
    });
  end if;

  if k = 'array' then
    var n = v.@count();
    if s.@has('items') then
      var it = s['items'];
      if _isColl(it) and _shape(it) = 'array' then
        var tn = it.@count();
        for i = 0 to n - 1 do
          if i < tn then
            _validate(v[i], it[i], _path(path, i), errs, limit, strict, root, stack);
          elsif s.@has('additionalItems') then
            var ai = s['additionalItems'];
            if ai = false then
              _addErr(errs, _path(path, i), 'additionalItems',
                'additional items are not allowed', false, v[i], limit);
            else
              _validate(v[i], ai, _path(path, i), errs, limit, strict, root, stack);
            end if;
          end if;
        end do;
      else
        for i = 0 to n - 1 do
          _validate(v[i], it, _path(path, i), errs, limit, strict, root, stack);
        end do;
      end if;
    end if;
    if s.@has('uniqueItems') and s['uniqueItems'] = true then
      var dup = false;
      for i = 0 to n - 1 do
        if not dup and i + 1 < n then
          for j = i + 1 to n - 1 do
            if not dup and _deepEq(v[i], v[j]) then
              dup = true;
              _addErr(errs, path, 'uniqueItems',
                'array items must be unique (duplicate at ' & i & ' and ' & j & ')',
                true, false, limit);
            end if;
          end do;
        end if;
      end do;
    end if;
    _countBounds(n, s, 'minItems', 'maxItems', path, errs, limit);
  end if;

  if k = 'string' then
    var sv = v.toStr();
    _countBounds(_cpLen(sv), s, 'minLength', 'maxLength', path, errs, limit);
    if s.@has('pattern') then
      try
        if not (sv =~ s['pattern'].toRegex()) then
          _addErr(errs, path, 'pattern', 'does not match pattern ' & s['pattern'], s['pattern'], sv, limit);
        end if;
      except
        _addErr(errs, path, 'pattern', 'invalid pattern: ' & s['pattern'], s['pattern'], sv, limit);
      end try;
    end if;
    if s.@has('format') then
      var fmt = s['format'];
      if _kind(fmt) = 'string' and not _formatOk(fmt, sv) then
        _addErr(errs, path, 'format', 'does not match format ' & fmt, fmt, sv, limit);
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
    if t.length() = 0 then raise 'jsonschema: schema text is empty'; end if;
    var isJson = t[0] = '{' or t[0] = '[';
    try
      if isJson then
        result = text.getJson(json: 2);
      else
        result = text.getJson(json: 2, fd: true);
      end if;
    except
      raise 'jsonschema: schema parse failed: ' & ('' & @);
    end try;
    if result = nil then raise 'jsonschema: schema parse failed'; end if;
    if not _isColl(result) or _shape(result) <> 'object' then
      raise 'jsonschema: schema root must be an object';
    end if;
    // The FD strict parser reports some invalid documents as an empty tree.
    if not isJson and result.@count() = 0 then
      raise 'jsonschema: schema parse failed';
    end if;
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
    _validate(data, s, '', errs, limit, strict, s, new []);
    var first = nil;
    if errs.@count() > 0 then first = errs[0]; end if;
    result = new [ok: errs.@count() = 0, errors: errs, first: first];
  end fun;

  fun valid(data, schema, opts)
    result = check(data, schema, opts)['ok'];
  end fun;

  fun checkJson(text, schema, opts)
    if text = nil then return _parseFailure('json', 'data text is nil'); end if;
    var v = nil;
    try
      // Parse through an object so a scalar root keeps its type instead of
      // becoming the parser's one-element root array.
      var w = ('{"__jsonschema_root__":' & text & '}').getJson(json: 2);
      v = w['__jsonschema_root__'];
    except
      return _parseFailure('json', '' & @);
    end try;
    result = check(v, schema, opts);
  end fun;

  fun checkFd(text, schema, opts)
    if text = nil then return _parseFailure('fd', 'data text is nil'); end if;
    var v = nil;
    try
      v = text.getJson(json: 2, fd: true);
    except
      return _parseFailure('fd', '' & @);
    end try;
    if not _isColl(v) or v.@count() = 0 then
      return _parseFailure('fd', 'no FD value');
    end if;
    result = check(v, schema, opts);
  end fun;

  fun validJson(text, schema, opts)
    result = checkJson(text, schema, opts)['ok'];
  end fun;

  fun validFd(text, schema, opts)
    result = checkFd(text, schema, opts)['ok'];
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
