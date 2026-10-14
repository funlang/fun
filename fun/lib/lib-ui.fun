// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-ui
########################################
#  Copyright (c) 2011, funlang.org
########################################
#   built-in (7)
########################################
#     var ui = 'ui'.getlib();
##### UI ###############################
#     ui.form(caption, width, height, onclose, onmsg)
#     ui.run()
#     ui.delay(ms, doevent = false)
##### FORM #############################
#     form.show(alpha = 255, ontop = false)
#     form.hwnd() # Handle of Window
#     form.html() # DOM for HTML
########################################
# 1. form.show(alpha = 255, ontop = false)
#      alpha :
#        < 0 : Close
#        = 0 : Hide
#        > 0 : 1-255 : Show
#              1-254 : AlphaBlend
#              > 255 : Get Showing or not
#      ontop : Stay on top
########################################
use 'lib-ui-base.fun';

//==============================================================
// Form
//==============================================================
class Form = BaseForm()
  var f = ui.form(CalcCaption(caption), width, height, onclose, onmsg);
  var h;

  //------------------------------------
  // Public
  //------------------------------------
  var Web;
  var Doc;
  var Win;

  var AutoEvent = false;
  var Events    = new [];

  fun Show(alpha, ontop)
    f.show(alpha or 255, ontop);
    h    = f.hwnd();
    hWnd = h;
    this.OnShowing();

    Web = f.html();
          Web.Navigate('about:blank');
          Web.Silent = true;
          Web.RegisterAsBrowser = false;
          Web.RegisterAsDropTarget = false;
    Doc = Web.Document;
          Doc.write(this.Html());
    Win = Doc.parentWindow;
          Doc.focus();
          InitFunHost();

    this.InitEvents();
    fireEvent('beforeShow', GetEvent());
    Focus();
    this.OnShow();
  end fun;

  fun Closed()
    return not f.show(256);
  end fun;

  fun Hide()
    f.show(0);
  end fun;

  fun Close()
    f.show(-1);
  end fun;

  fun TopMost()
    f.show(256, true);
  end fun;

  //------------------------------------
  // Protected
  //------------------------------------
  fun Html()
    result = '<html><head>%s</head><body>%s</body></html>'.format(
        this.Head(), this.Body()
      );
  end fun;

  fun Head()
    result = '
<meta http-equiv="MSThemeCompatible" content="yes" />
<style>
 body{border:0; margin:0; overflow:visible}
 %s
</style>
'.format(this.Style()) & this.HeadEx();
  end fun;

  fun HeadEx()
  end fun;

  fun Style()
  end fun;

  fun Body()
  end fun;

  fun GetEvent(e)
    if e = null then
      e = Win.event;
    end if;
    return e;
  end fun;

  fun InitEvents()
    try
      Doc.onclick       = DoClick.@toEvent (this);
      Doc.oncontextmenu = DoFilter.@toEvent(this);
      Doc.onselectstart = DoFilter.@toEvent(this);
    except
      ?. @;
    end try;
  end fun;

  fun JsCall(js)
    Win.execScript(js, 'javascript');
  end fun;

  //------------------------------------
  // Private
  //------------------------------------
  fun DoClick(e)
    result = nil;
    try
      e = GetEvent(e);
      if AutoEvent and e.srcElement <> nil then
        var f = e.srcElement.getAttribute('fun:click', 2);
        if f <> null then
          f = this[f];
          if f <> null then
            fireEvent('beforeClick', e);
            try
              f(e);
            finally
              fireEvent('afterClick', e);
            end try;
          end if;
        else
          this.OnClick(e);
        end if;
      end if;
    except
      ?. 'fun:click: $@ at $@@()'.eval();
    end try;
  end fun;

  fun DoFilter(e) //BUG: Incorrect function
    result = nil;
    try
      e = GetEvent(e);
      var ee = e.srcElement;
      e.returnValue = false;
      while ee <> nil and ee.tagName <> 'body' do
        if ee.isTextEdit or ee.isContentEditable or ee.selectable = 'true' then
          e.returnValue = true;
          exit;
        end if;
        ee = ee.parentElement;
      end do;
    except
    end try;
  end fun;

  fun Alert(c)
    Win.alert(c);
  end fun;

  //------------------------------------
  // js -> fun
  //------------------------------------
  fun InitFunHost()
    Web.PutProperty('Fun:Host', FunCall.@toEvent(this));
    Doc.write(`<script>window.Fun=window.external;</script>`);
  end fun;

  fun FunCall(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9)
    try
      var f = this[a0];
      if f <> nil then
        return f(a1, a2, a3, a4, a5, a6, a7, a8, a9);
      end if;
    except
      ?. 'FunCall: $@ at $@@()'.eval();
    end try;
  end fun;

  fun FunCallUnsafe(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9)
    var f = this[a0];
    if f <> nil then
      return f(a1, a2, a3, a4, a5, a6, a7, a8, a9);
    end if;
  end fun;

  //------------------------------------
  // Events
  //------------------------------------
  fun fireEvent(action, event)
    var e = nil;
    try e = Events[action]; except end try;
    if e <> nil then
      try
        e(event, this);
      except
        ?. action & ': ' & @;
      end try;
    end if;
  end fun;
end class;