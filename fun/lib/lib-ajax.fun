// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-unicode.fun';
use 'lib-base64.fun';
use 'lib-zlib.fun';
var defaultProxy    = nil;
var defaultCodePage = 0;
var Decode = _Decode;

//==============================================================
// Ajax
//==============================================================
class Ajax(container)
  var xhr; // Connect fail when https://...:Not443
  try
    xhr = "Msxml2.ServerXMLHTTP.6.0".newobj();
  except
    xhr = "Msxml2.ServerXMLHTTP".newobj();
  end try;
  var html  = '';
  var code  = 0;
  var message = '';
  var checks;
  var hide  = false;
  var async = true;
  var last  = '';
  try
    xhr.onreadystatechange = callback.@toEvent(this);
  except
    async = false;
    //?. 'set xhr.onreadystatechange: ' & @;
  end try;

  fun go(args)
    //args = js2fun(args);
    result = this.get(
      url: args.url,
      body: args.body,
      method: args.method,
      headers: args.headers,
      timeouts: args.timeouts,
      proxy: defaultProxy,
      dontUseCodePage: true,
      saveas: args.saveas,
      args: args
    );
  end fun;

  fun js2fun(s)
    result = new [];
    try
      result.url = s.url;
      try result.body = s.body; except end try;
      try result.method = s.method; except end try;
      try result.headers = s.headers.toStr().getJson(); except end try;
      try result.timeouts = s.timeouts.toStr().getJson(); except end try;
      try result.saveas = s.saveas; except end try;
      try result.no302 = s.no302; except end try;
    except
      result = s.toStr().getJson();
    end try;
  end fun;

  fun get(url, no_ui, referer, cookie, post, charset, userAgent, fnHeader, body, timeouts, headers, method, proxy, dontUseCodePage, check, saveas, args)
    args = args or [];
    result = nil;
    html = '';
    code  = 0;
    message = '';
    hide = no_ui;
    //?, url & ' ->';
    url  = CorrectURL(url, last);
    //?. url;
    last = url;

    try
      if timeouts then
        try
          xhr.setTimeouts(timeouts.resolveTimeout, timeouts.connectTimeout, timeouts.sendTimeout, timeouts.receiveTimeout);
        except
          ?. @;
        end try;
      end if;

      if proxy then
        try
          xhr.setProxy(proxy.mode, proxy.server); // mode: 0 (default); mode: 2, server: ip:port
          if proxy.user <> nil then
            headers = headers or new [];
            headers['Proxy-Authorization'] = proxy.basic;
            if post then
              //?. 'User: %s, password: %s'.format(proxy.user, proxy.password);
            end if;
            xhr.setProxyCredentials(proxy.user, proxy.password);
          end if;
        except
          ?. @;
        end try;
      end if;

      var m = method;
      if post then
        if body = '' then
          xhr.open("POST", url.replace(/\?.*+$/s, ''), async);
        else
          xhr.open("POST", url, async);
        end if;
      else
        if m = nil then
          m = 'GET';
        end if;
        xhr.open(m, url, async);
      end if;

      var gzip = false; var b64 = false;
      try
        if userAgent<>'' then xhr.setRequestHeader('User-Agent', userAgent); end if;
        if referer <> '' then xhr.setRequestHeader('Referer', referer); end if;
        if cookie  <> '' then xhr.setRequestHeader('Cookie',  cookie);  end if;
        //if charset <> '' then xhr.setRequestHeader("Charset", charset); end if;
        if fnHeader <> nil then
          fnHeader(xhr);
        end if;
        if headers then
          for k: v in headers do
            xhr.setRequestHeader(k, v);
            if k =~ /^(Content|Post)-Encoding$/i and v =~ /^(gzip|deflate)\b/ then
              gzip = v =~ /deflate/ and 2 or true;
              b64  = v =~ /,base64/;
            end if;
          end do;
        end if;
      except
        message = @;
        ?. 'head: ' & @;
      end try;

      #*
      try //?. xhr.getOption(2);
        //xhr.setOption(2, xhr.getOption(2) - 13056); //?. xhr.getOption(2);
        xhr.setOption(2, 13056);
      except
        ?. @;
      end try; #

      if gzip and zlib and body <> nil and body.length() > 1024*4 then
        var a = compress;
        if gzip = 2 then
          a = deflate;
        end if;
        body = a(body);
        if b64 then
          body = toBase64(body);
        else
          body = body.toStr(-2); // -> Unicode, and then -> UTF8
        end if;
      end if;
      if post then
        if body = '' then
          xhr.send(url.match(/(?<=\?).*+$/s).@@());
        else
          xhr.send(body);
        end if;
      else
        xhr.send(body);
      end if;
    except
      message = @;
      //?. 'get/post: ' & @;
    end try;

    if not async then
      result = callback(charset, dontUseCodePage, check, saveas, args);
    end if;
  end fun;
  var post(url, no_ui, referer, cookie,       charset, userAgent, fnHeader, body, timeouts, headers, method, proxy, dontUseCodePage, check, saveas, args)
     = get(url, no_ui, referer, cookie, true, charset, userAgent, fnHeader, body, timeouts, headers, method, proxy, dontUseCodePage, check, saveas, args);

  fun callback(charset, dontUseCodePage, check, saveas, args)
    result = nil;
    try
      if xhr.readyState = 4 then
        code = xhr.status;
        message = OleToStr(xhr.statusText);
        if xhr.status = 200 then
          if charset = nil then
            html = xhr.responseText;
          else
            html = Decode(xhr, charset);
          end if;
          if saveas <> nil then
            try
              Decode(xhr, saveas: saveas);
            except
              message = @;
            end try;
          end if;
          html = OleToStr(html, dontUseCodePage);
          result = html;
          try
            if not hide and container <> nil then
              container.innerHTML = html;
            end if;
          except
            ?. @;
          end try;
          CheckContent(check);
        elsif xhr.status in [301, 302, 303, 307, 308] then ?, xhr.status;
          if not args or not args.no302 then ?. '302->';
            result = get(xhr.getResponseHeader('Location'));
          end if;
        elsif xhr.status = 304 then
        else
          result = OleToStr(xhr.responseText, dontUseCodePage);
          html = result;
          //?. 'status: %s-%s, %s'.format(xhr.status, xhr.statusText, xhr.responseText);
        end if;
      end if;
    except
      //code = 0;
      message = @;
      ?. 'callback: ' & @;
    end try;
  end fun;

  fun CheckContent(check)
    try
      if check then
        checks = new [];
        var l = xhr.getResponseHeader('Content-Length');
        if l <> nil then
          var s = xhr.responseBody.toStr();
          checks.hasLength = true;
          checks.length = l * 1 = s.length();
          if check.md5 <> nil then //?. check.md5;
            var md5 = xhr.getResponseHeader(check.md5);
            if md5 <> nil then
              md5 = md5.replace(/"/g, '');
              var smd5 = s.md5();
              checks.hasMd5 = true;
              checks.md5 = md5 = smd5;
              if not checks.md5 then
                checks.md5 = md5 = Hex2Base64(smd5);
              end if;
            end if;
          end if;
          if check.code <> nil then 
            var code = check.code;
            if code =~ /^\s*+fun:/ then
              code = code.replace(/^\s*+fun:\s*+/, '');
              var ss = `
                fun a()
                  result = false;
                  try
                    $code;
                  except
                    ?. @;
                  end try;
                end fun;
              `.eval();
              try
                var c = ss.compile(true);
                result = c.a();
                checks.hasCode = true;
                checks.code = result;
              except
                ?, '@check error: ' & @;
              end try;
              ?, '@check [$result] $code'.eval();
            end if;
          end if;
        end if;
      end if;
    except
      ?. @;
    end try;
    result = checks;
  end fun;
end class;

//==============================================================
// Global functions
//==============================================================
fun CorrectURL(url, last)
  url = url.replace(%^about:(blank)?/?%i, '');
  if url !~ /^(https?|mailto|file|[a-z]):/i then
    if last = '' then
      url = 'http://' & url;
    else
      if last =~ %^https?://[^/]++$%i then
        url = last & '/' & url;
      else
        url = last.replace(%/[^/\\]*+$%, '') & '/' & url;
      end if;
    end if;
  end if;
  result = url;
end fun;

fun OleToStr(s, dontUseCodePage)
  result = s;
  if defaultCodePage > 0 and not dontUseCodePage then
    result = Unicode.toBytes(result, defaultCodePage);
  end if;
end fun;

fun _Decode(xhr, charset, saveas)
  var stream = ADOStream(charset);
  stream.Type = 1;
  stream.Open();
  try
    stream.Write(xhr.responseBody);
    stream.Position = 0;
    if charset <> nil then
      stream.Type     = 2;
      stream.Charset  = charset;
      result = stream.ReadText();
    end if;
  except
    ?. '$@@ $@'.eval();
  end try;
  if saveas <> nil then
    var b =  saveas & '.backup'; b.move();
    saveas.move(b); saveas.move();
    try
      stream.SaveToFile(saveas);
    except
      b.move(saveas);
      raise @;
    end try;
  end if;
  stream.Close();
end fun;

fun ADOStream(charset)
  try
    result = "AdoDb.Stream".newobj();
  except
    if charset = nil and 2010.time() >= 20250819 then
      result = ADOStreamClass();

      class ADOStreamClass()
        fun Open()
        end fun;
        fun Close()
        end fun;

        var ss = '';
        fun Write(s)
          this.ss = s.toStr();
        end fun;
        fun SaveToFile(f)
          f.save(this.ss, cp: 0xffff);
        end fun;
      end class;
    else
      raise @;
    end if;
  end try;
end fun;