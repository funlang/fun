// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-xml-unx: the Unix backend of lib-xml (XML parsing on libxml2).
//
// The Windows lib-xml.fun is MSXML COM ('MsXml2.DomDocument'), so it cannot run
// on Unix (XmlDocument() raises .newobj not found). Following the <name>-unx
// convention this backend exposes the same XmlDocument surface that is actually
// used (lib-orm.LoadSchema: load() + toJson()), built on libxml2.
//
// Why libxml2 rather than a hand-written parser: it is ABI-stable (plain
// function calls, no struct-layout guessing), and free correctness for
// encodings, entities, CDATA and namespaces. It is the Unix analogue of
// depending on libcurl/libsqlite3/libcrypto in the other -unx backends.
//
// It uses the xmlTextReader *pull* API on purpose: xmlTextReaderRead walks the
// stream and ConstName/ConstValue hand back strings, so nothing here needs
// xmlNode's struct offsets (which is where a libxml2 DOM binding would get
// fragile).
//
// toJson() reproduces lib-xml.fun's shape exactly, because lib-orm reads it:
// an element becomes a set with  @ = element name, one key per attribute, and
// $ = the list of child element sets (text nodes appear as @ = '#text', with no
// value, matching the Windows implementation).

use 'lib-host.fun';

// libxml2: Linux libxml2.so.2, macOS the compat library libxml2.2.dylib.
var _xmllib = DyLib('libxml2.so.2', 'libxml2.2.dylib');

var _forMemory    = _xmllib.getapi('xmlReaderForMemory',      'pippi:p');
var _read         = _xmllib.getapi('xmlTextReaderRead',       'p:i');
var _nodeType     = _xmllib.getapi('xmlTextReaderNodeType',   'p:i');
var _constName    = _xmllib.getapi('xmlTextReaderConstName',  'p:s');
var _constValue   = _xmllib.getapi('xmlTextReaderConstValue', 'p:s');
var _isEmpty      = _xmllib.getapi('xmlTextReaderIsEmptyElement', 'p:i');
var _firstAttr    = _xmllib.getapi('xmlTextReaderMoveToFirstAttribute', 'p:i');
var _nextAttr     = _xmllib.getapi('xmlTextReaderMoveToNextAttribute',  'p:i');
var _freeReader   = _xmllib.getapi('xmlFreeTextReader',       'p:v');
var _setGenError  = _xmllib.getapi('xmlSetGenericErrorFunc',  'pc:v');

// libxml2 prints parser diagnostics to stderr by default, which would interleave
// non-deterministically with script output. Install a no-op generic error
// handler (we raise 'XML parse error' ourselves when Read() returns < 0).
fun _xmlSilent(ctx, msg)
end fun;
var _xmlErrCb = _xmlSilent.@toCallback(nil, 'ps:v');
_setGenError(0, _xmlErrCb);

// xmlReaderTypes
var XMLR_ELEMENT    = 1;
var XMLR_TEXT       = 3;
var XMLR_CDATA      = 4;
var XMLR_END_ELEM   = 15;

// XML_PARSE_NONET: never fetch external entities/Dtds over the network.
var XML_PARSE_NONET = 2048;

fun _blank(s)
  var n = s.length();
  var i = 0;
  result = true;
  while i < n and result do
    var c = s[i + 0.5];
    if not (c = 32 or c = 9 or c = 13 or c = 10) then result = false; end if;
    i += 1;
  end do;
end fun;

// Build the root element set from XML text (the toJson() shape).
fun _parse(text)
  result = nil;
  if text = '' then return; end if;
  var reader = _forMemory(text.toNum(-1), text.length(), 0, 0, XML_PARSE_NONET);
  if reader = 0 then raise 'lib-xml-lnx: cannot create reader'; end if;
  var stack = new [];
  var root = nil;
  var rc = 0;
  loop
    rc = _read(reader);
    exit when rc <= 0;
    var t = _nodeType(reader);
    if t = XMLR_ELEMENT then
      var e = new [];
      e.@ = _constName(reader);
      // IsEmptyElement is only valid while positioned on the element itself,
      // so read it before MoveToFirstAttribute moves us onto an attribute.
      var empty = _isEmpty(reader);
      var has = _firstAttr(reader);
      while has = 1 do
        e[_constName(reader)] = _constValue(reader);
        has = _nextAttr(reader);
      end do;
      if stack.@count() > 0 then
        var top = stack[stack.@count() - 1];
        if top.$ = nil then top.$ = new []; end if;
        top.$.@add(e);
      elsif root = nil then
        root = e;
      end if;
      if empty = 0 then stack.@add(e); end if;
    elsif t = XMLR_TEXT or t = XMLR_CDATA then
      var v = _constValue(reader);
      // formatting whitespace is dropped, matching MSXML's default
      if v <> nil and not _blank(v) then
        var tn = new [];
        tn.@ = '#text';
        tn.text = v; // Linux addition: the Windows toJson() drops text values
        if stack.@count() > 0 then
          var top2 = stack[stack.@count() - 1];
          if top2.$ = nil then top2.$ = new []; end if;
          top2.$.@add(tn);
        end if;
      end if;
    elsif t = XMLR_END_ELEM then
      if stack.@count() > 0 then stack.@count(-1); end if; // pop
    end if;
  end loop;
  if rc < 0 then
    _freeReader(reader);
    raise 'lib-xml-lnx: XML parse error';
  end if;
  _freeReader(reader);
  result = root;
end fun;

# wrap root or load xml
class XmlDocument(root)
  var xmltext = '';

  fun load(fn)
    // Same heuristic as the Windows file: a short string that names an existing
    // file is a path, otherwise the argument is the XML text itself.
    if fn.length() < 256 and fn.find() then
      xmltext = fn.load();
    else
      xmltext = fn;
    end if;
    root = _parse(xmltext);
    result = root <> nil;
  end fun;

  fun toJson()
    if root = nil and xmltext <> '' then root = _parse(xmltext); end if;
    result = root;
  end fun;

  // current node (set), for parity with the Windows class
  var curr = nil;

  var prop = (name){
    result = nil;
    if curr <> nil then result = curr[name]; end if;
  };

  fun name()
    result = nil;
    if curr <> nil then result = curr.@; end if;
  end fun;

  // Walk the parsed tree. The callback gets (this, node, eachChild) like the
  // Windows version, but nodes here are the toJson() sets (elements only; text
  // nodes carry no value in that shape).
  fun each(f)
    if root = nil then return; end if;
    fun walk(n)
      curr = n;
      f(this, n, (start){
        var cs = n.$ or new [];
        var i = start or 0;
        while i < cs.@count() do
          walk(cs[i]);
          i += 1;
        end do;
      });
    end fun;
    walk(root);
  end fun;
end class;
