// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-ui.fun';
use 'lib-bind.fun';
use 'lib-dialog.fun';
use 'lib-message.fun';
use 'lib-unicode.fun';
use 'lib-cmdline.fun';
use ':notepad--fun.syntax' as syntax_fun;
use ':notepad--yml.syntax' as syntax_yml;
use ':notepad--html.syntax' as syntax_htm;
var syntaxes = [yml: syntax_yml, yaml: syntax_yml, xml: syntax_htm, htm: syntax_htm, html: syntax_htm];

main();
fun main()
  'defaultCodePage'.set(Unicode.utf8);

  var mf  = MainForm('notepad--', 800, 400, onClose.@toCallback(nil, ':i', true));
  mf.Show();
  mf.ShowMax();
  mf.AcceptDrag();
  mf.doLoad(CmdLineParams.options.file.substr(1));
  var mm = MainMsg();
  mm.mf = mf;
  mm.Process();
  ?. '[Done]';

  fun onClose()
    result = mf.doSave();
  end fun;
end fun;

class MainMsg = MessageHandler()
  var mf;
  var WM_DROPFILES = 0x0233;
  fun OnMessage(msg)
    case msg.message is
    when WM_DROPFILES do
      var f = mf.GetDragFile(msg);
      if mf.doSave(f) then
        mf.doLoad(f);
      end if;
      return true;
    end case;
    return false;
  end fun;
end class;

//==============================================================
// MainForm
//==============================================================
class MainForm = Form()
  autoEvent    = true;
  var databind = Bind(this, []); // HotKey

  var tags = #*['ol', 'li']; # ['div', 'p'];
  var re = `|\b(0[xX][\dA-Fa-f]+|0[bB][01]+|\d+\.\d+[eE][-+]?\d+|[\d\.]+)\b|([`&'`'&`'",.:()\[\]{}\|\\<>=+\-*\/\?\^%!~]+)|(\xb7+)`;
  var file = nil;
  var txt  = nil;
  var old  = txt;
  var isUTF8 = false;
  var isUNIX = false;
  var encodings  = ['ANSI', 'UTF8'];
  var fileformat = ['DOS',  'UNIX'];

  fun doLoad(f)
    if f <> nil then
      file = f;
      txt = file.load();
      old = txt;
      isUNIX = not not txt =~ /\n/ and txt !~ /\r/;
      isUTF8 = Unicode.isUtf8(txt);
      if not isUTF8 then
        txt = Unicode.gb2312toUtf8(txt);
      end if;
      var ext = file.match(/[^\.]++$/).@@();
      if ext <> nil then
        var ef = CmdLineParams.@path & 'notepad--$ext.syntax'.eval();
        if ef.size() then
          ext = '(^$)|' & ef.load() & re; ?. ext;
        elsif syntaxes[ext] <> nil then
          ext = '(^$)|' & syntaxes[ext] & re; ?. ext;
        elsif txt =~ /^<([?!]|\w++)/ then
          ext = '(^$)|' & syntaxes.xml & re; ?. ext;
        else
          ext = '';
        end if;
      end if;
      txt = toHTML(txt);
      showStatus();
      win.r   = ext;
      win.txt = txt;
      jsCall(`RE();HL(true);`);
    end if;
  end fun;

  fun doSave(f, rt)
    txt = doc.getElementById('txt').innerHTML;
    result = f = nil or f <> file;
    if isUTF8 then
      txt = Unicode.toBytes(txt, Unicode.utf8);
    else
      txt = '' & txt;
    end if;
    txt = toText(txt);
    if result and file <> nil and old <> txt then ?. old.length(); ?. Unicode.utf8toGbk(old); ?. txt.length(); ?. Unicode.utf8toGbk(txt);
      result = rt or msgbox('Save ' & file, 'Confirm', 0x23);
      if result = 6 then // IDYES
        file.save(txt);
        old = txt;
      end if;
      result = result <> 2; // IDCANCEL
    end if;
  end fun;

  fun toHTML(s)
    result = s.replace(/^([^\r\n]*+)\r?/gm, (m){
      result = '<%s>'.format(tags[1]) & m.@(1)
              .replace(/&/g, '&amp;')
              .replace(/\x20/g, '&#183;') // ·
              .replace(/</g, '&lt;').replace(/>/g, '&gt;')
              & '</%s>'.format(tags[1]);
      });
  end fun;

  fun toText(s)
    var t = new ['\r\n'.escape(), '\n'.escape()]; t = t[isUNIX];
    var b = ['\xa1\xa4', '\xc2\xb7'];             b = b[isUTF8];
    result = s.replace(%</(p|li)>\s*+%gi, t).replace(/<[^>]++>/g, '')
              .replace('$b|&#183;|&nbsp;'.eval().toRegex('g'), ' ') // ·
              .replace(/^\x20$/gm, '')
              .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
              .replace(/&amp;/g, '&');
  end fun;

  fun showStatus()
    var flag = '[%s] [%s]'.format(fileformat[isUnix], encodings[isUtf8]);
    setCaption('notepad--  $file  --  $flag  --  [F4] Open ... [F5] Refresh [Ctrl-Z] Undo [Ctrl-S] Save [F6] Save as ... [F7] Save as ANSI [F8] Save as UTF8'.eval());
  end fun;

  fun saveIt()
    doSave(0, 6);
  end fun;

  fun loadIt()
    doLoad(file);
  end fun;

  fun saveAs8()
    saveAs(nil, true);
  end fun;

  fun saveAs7()
    saveAs(nil, false, true);
  end fun;

  fun saveAs(e, asUtf8, asAnsi)
    var f = file;
    if not (asUtf8 or asAnsi) or f = nil then
      f = saveDialog(file: file);
    end if;
    if f <> nil then
      file = f;
      isUtf8 = asUtf8 or not asAnsi;
      doSave(0, 6);
      old = txt;
      showStatus();
    end if;
  end fun;

  fun openIt()
    if doSave() then
      var f = openDialog(file: file);
      if f <> nil then
        doLoad(f);
      end if;
    end if;
  end fun;

  fun undo()
    jsCall('UNDO();');
  end fun;

  fun find(e, replace)
    jsCall(`RE(true);HL(false,true,%s);`.format(replace or 'false'));
  end fun;

  fun replace(e)
    find(e, 'true');
  end fun;

  fun echo(s)
    ?. s;
  end fun;

  fun HeadEx()
    result = `<script>try {
  var r0 = /(^$)|%s%s/g; var re = r0;
  function highlight (n, replace, child) {
    if (n.tagName == 'P' || n.tagName == 'LI' || n.tagName == 'SPAN' || n.tagName == 'I') {
      n.innerHTML = n.innerHTML.replace(/<[^>]+>/g, '').replace(/ |&nbsp;/g, '·').replace(child||re, function($0,k0,$1,$2,$3,$4){
        if (k0) return '<i class="k0">'+(replace && replace.Is ? replace.Str : k0)+'</i>';
        if ($1) {
          if ($1.charAt(0) == '.') return '<i class="k2">.</i>'+$1.substring(1);
          if ($1.substring(0, 2) == '?.') return '<i class="k2">?.</i>'+$1.substring(2);
          return '<i class="k1">'+$1+'</i>';
        }
        if ($2) return '<i class="k2">'+$2+'</i>';
        if ($3) return '<i class="k3">'+$3+'</i>';
        if ($4) return '<i class="k4">'+$4+'</i>';
        return '';
      }) || '';
      if (rf && n.tagName == 'P' || n.tagName == 'LI') child = rf;
      else return;
    }
    for (var i=0; i<n.children.length; i++) {
      highlight(n.children.item(i), replace, child);
    }
  }
  function savePoint (o) {
    if (o) {
      var r = document.body.createTextRange();
      r.moveToPoint(o.left, o.top);
      r.select();
    } else return document.selection.createRange().getBoundingClientRect();
  }
  var undos = [];
  window.UNDO = function () { HL();
    if (undos.length > 1) {
      undos.pop();
      var o = savePoint();
      document.getElementById('txt').innerHTML = undos[undos.length-1];
      savePoint(o);
    }
  }
  window.txt = '';
  window.HL = function (load, find, replace) {
    try {
      var o = savePoint();
      var n = document.getElementById('txt');
      if (load) {
        undos = [];
        n.innerHTML = txt;
      }
      if (find || !undos.length || undos[undos.length-1] != n.innerHTML) {
        highlight(n, {Is: replace, Str: replace ? document.getElementById('replace').innerText : ''});
        undos.push(n.innerHTML);
        savePoint(o);
      }
    } catch (e) { Fun.call('echo', e.message);
    }
  }
  window.r  = '';
  window.RE = function (find) {
    re = r0;
    try {
      var f = document.getElementById('find').innerText; window.rf = find && f ? new RegExp('('+f+')', 'g') : undefined;
      if (r||find) re = new RegExp(find && f ? (r||re.source).replace(/^\([^)]+/, '('+f) : r, 'g');
    } catch(e) { //alert(e.message + ': ' + r);
    }
  }
} catch(e) { alert(e.message);
}</script>`.format(syntax_fun, re); //?. result;
  end fun;

  fun Style() // find框输入 http://[/ 或 http://[\ 会导致字体坏掉
    result = `*{ font-family:Consolas,"Courier New"; font-size:15px; color:#fff; background-color:#000; }
b{ display:block; position:absolute; right:24px; top:2px; font-weight:normal; color:#aaa; background: transparent; }
a{ font-family:Wingdings; font-size:19px; color:#aaa; cursor:pointer; text-decoration:none; background: transparent; }
.a2{ font-family:Webdings; }
a:hover{ color:#fff; }
.input{ display:inline-block; padding:0 19px; border:1px solid; border-color:#888 #ccc #ccc #888; margin-right:6px; }
div,ol{ width:100%; height:100%; border:0; overflow:auto; padding:4px; }
p,li{ margin:1px; border-bottom:dotted 1px #222; }
.k0{ background-color:#f50; border:0 solid #ff0; border-width:1px 0; font-style: normal; }
.k1{ color:#00a4ef; font-weight: bold; }
.k2{ color:#f25022; font-style: normal; }
.k3{ color:#ffb900; font-style: normal; }
.k4{ color:#777; }`;
    var f = CmdLineParams.@path & 'notepad--.css';
    if f.size() then
      result &= f.load();
    end if;
  end fun;

  fun Body()
    return `<b>
<a fun:click="openIt"  fun:key="F4"      href="javascript:void(0)" title="[F4] Open ..."     class="a1">&#49;</a>
<a fun:click="loadIt"  fun:key="F5"      href="javascript:void(0)" title="[F5] Refresh"      class="a2">&#113;</a>
<a fun:click="undo"    fun:key="Ctrl-Z"  href="javascript:void(0)" title="[Ctrl-Z] Undo"     class="a1">&#197;</a>
<a fun:click="saveIt"  fun:key="Ctrl-S"  href="javascript:void(0)" title="[Ctrl-S] Save"     class="a1">&#60;</a>
<a fun:click="saveAs"  fun:key="F6"      href="javascript:void(0)" title="[F6] Save as ..."  class="a2">&#50;</a>
<a fun:click="saveAs7" fun:key="F7"      href="javascript:void(0)" title="[F7] Save as ANSI" class="a2">&#62;</a>
<a fun:click="saveAs8" fun:key="F8"      href="javascript:void(0)" title="[F8] Save as UTF8" class="a2">&#253;</a>
<span id="find" onkeyup="var o=savePoint();highlight(this);savePoint(o)" class="input" contentEditable="true"
 title="Regex supported (Don't have any capture group)"></span>
<a fun:click="find"    fun:key="F3"      href="javascript:void(0)" title="[F3] Find"         class="a2">&#36;</a>
<span id="replace" onkeyup="var o=savePoint();highlight(this);savePoint(o)" class="input" contentEditable="true"
 title="Constant only (No any $1 or etc.)"></span>
<a fun:click="replace" fun:key="Ctrl-F3" href="javascript:void(0)" title="[Ctrl-F3] Replace" class="a1">&#220;</a>
</b><%s id="txt" onkeyup="HL()" contentEditable="true" title='Drag file to edit ...'
 onkeydown="if(event.ctrlKey && event.keyCode==90)return false" oncontextmenu="return false">Drag file to edit ...</%s>`.format(tags[0], tags[0]);
  end fun;
end class;
