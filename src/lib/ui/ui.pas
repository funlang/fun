// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
unit ui;

interface

uses fun, base, core, host, KOL, Windows;

type
  CLform = class(CLib)
  private
  {$IfDef IDE}
    OnMsging: fun.bool;
  {$EndIf}
    CloseFun: function(): fun.bool; stdcall;
    Form: fun.ptr;
    Html: fun.ptr;
    MsgFun: function(hwnd, message, wParam, lParam: fun.int): fun.int; stdcall;
    procedure OnClose(Sender: PObj; var Accept: fun.bool);
    function OnMsg(var Msg: TMsg; var Ret: fun.int): fun.bool;
  public
    constructor Create;
    function accept(exp: CExp): fun.bool; override;
    procedure init;
  end;
  
  CLui = class(CLib)
  public
    constructor Create;
    function accept(exp: CExp): fun.bool; override;
  end;
  

var uilib:  CLui;
var uiform: CLform;

implementation

uses ie;

type
  PValue = base.PValue;

//==============================================================
// ui.form(caption = '', winclass = '', width = 640, height = 480)
// ui.form(caption = '', width = 640, height = 480, onclose, onmsg)
procedure _form(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  f: CLform;
  //s: fun.str;
  e: CExp;
  p: fun.ptr;
begin
  f := CLform.Create;

  f.Form := NewForm(nil, CExps.FindAsVal(exps, 'caption', 0, ''));
  if uiform.Form = nil then
  begin
    uiform.Form := f.Form;
    Applet      := f.Form;
  end;
  with PControl(f.Form)^ do
  begin
    if f.Form <> uiform.Form then Add2AutoFree(uiform.Form);
    //s := CExps.FindAsVal(exps, 'winclass', 1, '');
    //if s <> '' then SubClassName := s;
    SetSize(CExps.FindAsVal(exps, 'width',  1, 640),
            CExps.FindAsVal(exps, 'height', 2, 480));
    Border := 0;
    CenterOnParent();
    e := CExps.Find(exps, 'onclose', 3);
    if e <> nil then
    begin
      p := asPtr(e.value);
      if p <> nil then
      begin
        f.CloseFun := p;
        OnClose := f.OnClose;
      end;
    end;
    e := CExps.Find(exps, 'onmsg', 4);
    if e <> nil then
    begin
      p := asPtr(e.value);
      if p <> nil then
      begin
        f.MsgFun := p;
        OnMessage := f.OnMsg;
      end;
    end;
  end;

  f.Html := NewKOLWebBrowser(f.Form);
  with PKOLWebBrowser(f.Html)^ do
  begin
    SetAlign(caClient);
  end;

  base.setObj(val, f, VarObjNew); del(f);
end;

// ui.dialog(open = 'All files|*.*', file = '...', multi  = false)
// ui.dialog(save = 'All files|*.*', file = '...', defext = '...')
// ui.dialog(path = '...')
procedure _dialog(env: CEnv; exp: CExp; exps: CExps; val: PValue);
{$IfNDef NoDialog}
// NT 3.5 has no SHGetPathFromIDListA (introduced in NT 4.0). Define NoDialog
// to omit this dialog and its static shell32 import, so Fun can start on NT 3.5.
var
  s, f, ret: fun.str;
  isOpen, isSave, multi: fun.bool;
  os: TOpenSaveOptions;
begin
  ret := '';

  // open, save or path ??
  s := CExps.FindAsVal(exps, 'open', 0, '');
  isOpen := s <> '';
  isSave := false;
  if not isOpen then
  begin
    s := CExps.FindAsVal(exps, 'save', 0, '');
    isSave := s <> '';
    if not isSave then s := CExps.FindAsVal(exps, 'path', 0, '');
  end;

  if isOpen or isSave then
  begin
    os := [];
    if isOpen then
    begin
      Include(os, OSFileMustExist);
      multi := CExps.FindAsVal(exps, 'multi', 2, false);
      if multi then Include(os, OSAllowMultiSelect);
    end
    else
    begin
      os := os + [OSOverwritePrompt]; //, OSPathMustExist];
    end;

    f := CExps.FindAsVal(exps, 'file', 1, '');
    with NewOpenSaveDialog('', ExtractFilePath(f), os)^ do
    begin
      try
        Filter       := s;
        FileName     := f;
        OpenDialog   := isOpen;
        if isSave then DefExtension := CExps.FindAsVal(exps, 'defext', 2, '');;

        if Execute then ret := Filename;
      finally
        Destroy();
      end;
    end;
  end
  else
  begin
    with NewOpenDirDialog('', [])^ do
    begin
      try
        InitialPath := s;

        if Execute then ret := Path;
      finally
        Destroy();
      end;
    end;
  end;

  val^ := ret;
{$Else}
begin
{$EndIf}
end;

procedure _run(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  f: PControl;
begin
  f := uiform.Form;
  if f <> nil then
  begin
    Run(f);
  end;
end;

// ui.delay(ms = 0, doevent = false)
procedure _delay(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  ms: fun.int;
  de: fun.bool;

  procedure DoEvent;
  begin
    if de and (Applet <> nil) then Applet.ProcessMessages;
  end;

begin
  ms := CExps.FindAsVal(exps, 'ms',       0, 0);
  de := CExps.FindAsVal(exps, 'doevent',  1, false);
  DoEvent;
  Sleep(ms);
  DoEvent;
end;

//==============================================================
// form.show(alpha = 255, modal = false)
// form.show(alpha = 255, ontop = false)
procedure _show(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  f: CLform;
  alpha: fun.int;
begin
  if AppletTerminated then
  begin
    val^ := False;
    exit;
  end;

  AppletRunning := true;

  f     := CLform(exp.asObj);
  alpha := CExps.FindAsVal(exps, 'alpha', 0, 255);
  with PControl(f.Form)^ do
  begin
    if alpha in [1..255] then AlphaBlend := alpha;
    StayOnTop := CExps.FindAsVal(exps, 'ontop', 1, false);

    if alpha < 0 then
      Close
    else if alpha = 0 then
      Hide
    //else if CExps.FindAsVal(exps, 'modal', 1, false) then
    //  ShowModalParented(Applet)
    else if (alpha <= 255) and not Visible then
      Show
    ;

    val^ := Visible;
  end;
end;

procedure _hwnd(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := PControl(CLform(exp.asObj).Form).Handle;
end;

procedure _html(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  val^ := PKOLWebBrowser(CLform(exp.asObj).Html).Application;
end;

//==============================================================
constructor CLform.Create;
begin
  inherited Create;
  ids['show'] := CExp.new(nil).parse(Int64(fun.uintptr(@_show)));
  ids['hwnd'] := CExp.new(nil).parse(Int64(fun.uintptr(@_hwnd)));
  ids['html'] := CExp.new(nil).parse(Int64(fun.uintptr(@_html)));
  {$IfDef IDE}
    OnMsging := false;
  {$EndIf}
end;

function CLform.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj is CLform;
end;

procedure CLform.init;
begin
  {$IfDef IDE}
  Form   := nil;
  Applet := nil;
  AppletTerminated := False;
  {$EndIf}
end;

procedure CLform.OnClose(Sender: PObj; var Accept: fun.bool);
begin
  Accept := CloseFun();
end;

function CLform.OnMsg(var Msg: TMsg; var Ret: fun.int): fun.bool;
begin
  {$IfDef IDE}
  if (Msg.hwnd <> PControl(Form).Handle) then ret := 0 else
  if OnMsging then ret := 0 else
  {$EndIf}
  begin
  {$IfDef IDE}
    OnMsging := true;
  {$EndIf}
    ret := MsgFun(Msg.hwnd, Msg.message, Msg.wParam, Msg.lParam);
  {$IfDef IDE}
    OnMsging := false;
  {$EndIf}
  end;
  result := fun.bool(ret);
end;

//==============================================================
constructor CLui.Create;
begin
  inherited Create;
  ids['form']   := CExp.new(nil).parse(Int64(fun.uintptr(@_form)));
  ids['run']    := CExp.new(nil).parse(Int64(fun.uintptr(@_run)));
  ids['delay']  := CExp.new(nil).parse(Int64(fun.uintptr(@_delay)));
  ids['dialog'] := CExp.new(nil).parse(Int64(fun.uintptr(@_dialog)));
end;

function CLui.accept(exp: CExp): fun.bool;
begin
  result := exp.asObj is CLui;
end;


initialization
  uilib  := CLui.Create;
  uiform := CLform.Create;

finalization
  try
    Free_And_Nil(uiform.Form);
    del(uiform);
    del(uilib);
  except
  end;

end.
