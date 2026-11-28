unit debugger;

// IDE2 debugger core.
//
// One TDebugSession is attached to the evaluation thread by CWorker. The
// session only touches runtime objects on that thread: breakpoints, stepping,
// snapshots and expression evaluation all happen while the thread is stopped
// at a trace hook. The UI thread talks to it through short command/event
// strings protected by a critical section.
//
// The default build never compiles this unit: funcmd.dpr and the trace hooks
// are guarded by IDE2, and make-linux-x86_64.sh only sets it for the opt-in
// funcmd-ide2 binary.

{$IfDef IDE2}

interface

uses fun, base, core, Classes, SysUtils;

type
  TDebugStatus = (dsIdle, dsRunning, dsPaused, dsDone, dsError, dsStopped);
  TDebugMode   = (dmGo, dmInto, dmOver, dmOut);

  TDebugSession = class(CBase, IDebugSink)
  private
    FLock: TRTLCriticalSection;
    FWake: PRTLEvent;
    FEnv: CEnv;
    FStatus: TDebugStatus;
    FMode: TDebugMode;
    FLastOver: CNode;
    FCurNode: CNode;
    FBreakpoints: TStringList;
    FCommands: TStringList;
    FEvents: TStringList;
    FStop: Boolean;
    FFinished: Boolean;
    FReportedStart: Boolean;
    procedure AddEventLocked(const json: fun.str);
    procedure AddEvent(const json: fun.str);
    function PopCommand(out cmd: fun.str): Boolean;
    function BreakKey(const fn: fun.str; line: fun.int): fun.str;
    function BreakpointHit(n: CNode): Boolean;
    procedure ApplyBreakpoint(const fn: fun.str; line: fun.int; on: fun.bool);
    function EvalText(const expr: fun.str): fun.str;
    procedure Pause(n: CNode; const reason: fun.str);
    function StatusName: fun.str;
    function MakePausedEvent(n: CNode; const reason: fun.str): fun.str;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Attach(env: CEnv);
    procedure Detach;
    procedure LoadBreakpoints(const text: fun.str);
    procedure DebugTrace(env: CEnv; n: CNode);
    procedure DebugTraced(env: CEnv; n: CNode; tracing: fun.bool);
    procedure DebugEcho(const s: fun.str);
    function Command(const cmd: fun.str): fun.bool;
    function Poll: fun.str;
    function StateName: fun.str;
    procedure Finish(status: TDebugStatus; const err: fun.str = '');
  end;

{$EndIf}

implementation

{$IfDef IDE2}

uses parse;

function JsonStr(const s: fun.str): fun.str;
var
  i: fun.int;
  c: fun.char;
begin
  result := '"';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    case c of
      '"': result := result + '\"';
      '\': result := result + '\\';
      #8: result := result + '\b';
      #9: result := result + '\t';
      #10: result := result + '\n';
      #12: result := result + '\f';
      #13: result := result + '\r';
    else
      if Ord(c) < 32 then
        result := result + '\u' + IntToHex(Ord(c), 4)
      else
        result := result + c;
    end;
  end;
  result := result + '"';
end;

function CutField(var s: fun.str; out f: fun.str): Boolean;
var
  p: fun.int;
begin
  p := Pos(#9, s);
  if p > 0 then
  begin
    f := Copy(s, 1, p - 1);
    s := Copy(s, p + 1, Length(s));
    result := True;
  end
  else
  begin
    f := s;
    s := '';
    result := f <> '';
  end;
end;

function FileOfNode(n: CNode): fun.str;
begin
  result := '';
  if (n <> nil) and (n.root is CModu) then
    result := CModu(n.root).fileName;
end;

function LineOfNode(n: CNode): fun.int;
begin
  result := 0;
  if n is CRune then result := CRune(n).row;
end;

function FunNameOfNode(n: CNode): fun.str;
var
  f: CFun;
begin
  result := '';
  f := nil;
  while n <> nil do
  begin
    if n is CFun then
    begin
      f := CFun(n);
      break;
    end;
    if n is CModu then break;
    n := n.parent;
  end;
  if f <> nil then result := f.displayName;
end;

//==============================================================
constructor TDebugSession.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FWake := RTLEventCreate;
  FBreakpoints := TStringList.Create;
  FBreakpoints.CaseSensitive := False;
  FCommands := TStringList.Create;
  FEvents := TStringList.Create;
  FStatus := dsIdle;
  FMode := dmGo;
end;

destructor TDebugSession.Destroy;
begin
  if FWake <> nil then RTLEventDestroy(FWake);
  FBreakpoints.Free;
  FCommands.Free;
  FEvents.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TDebugSession.Attach(env: CEnv);
begin
  FEnv := env;
  FStatus := dsRunning;
  FStop := False;
  FFinished := False;
  FReportedStart := False;
  debugSink := Self;
end;

procedure TDebugSession.Detach;
begin
  debugSink := nil;
  FEnv := nil;
end;

procedure TDebugSession.AddEventLocked(const json: fun.str);
begin
  FEvents.Add(json);
end;

procedure TDebugSession.AddEvent(const json: fun.str);
begin
  EnterCriticalSection(FLock);
  try
    AddEventLocked(json);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TDebugSession.PopCommand(out cmd: fun.str): Boolean;
begin
  result := False;
  cmd := '';
  EnterCriticalSection(FLock);
  try
    if FCommands.Count > 0 then
    begin
      cmd := FCommands[0];
      FCommands.Delete(0);
      result := True;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TDebugSession.BreakKey(const fn: fun.str; line: fun.int): fun.str;
var
  s: fun.str;
begin
  s := fn;
  try
    s := ExpandFileName(s);
  except
  end;
  result := LowerCase(s) + #1 + IntToStr(line);
end;

function TDebugSession.BreakpointHit(n: CNode): Boolean;
var
  fn: fun.str;
  key: fun.str;
begin
  // Fast path for the common case: no breakpoints, no path work per node.
  if FBreakpoints.Count = 0 then exit(False);
  fn := FileOfNode(n);
  if fn = '' then exit(False);
  key := BreakKey(fn, LineOfNode(n));
  EnterCriticalSection(FLock);
  try
    result := FBreakpoints.IndexOf(key) >= 0;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDebugSession.ApplyBreakpoint(const fn: fun.str; line: fun.int; on: fun.bool);
var
  key: fun.str;
  i: fun.int;
begin
  key := BreakKey(fn, line);
  EnterCriticalSection(FLock);
  try
    i := FBreakpoints.IndexOf(key);
    if on then
    begin
      if i < 0 then FBreakpoints.Add(key);
    end
    else if i >= 0 then
      FBreakpoints.Delete(i);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDebugSession.LoadBreakpoints(const text: fun.str);
var
  p, q: fun.int;
  line, fileN, num: fun.str;
  row: fun.int;
begin
  p := 1;
  while p <= Length(text) do
  begin
    q := Pos(#10, text, p);
    if q = 0 then q := Length(text) + 1;
    line := Copy(text, p, q - p);
    p := q + 1;
    if (line <> '') and (line[Length(line)] = #13) then
      line := Copy(line, 1, Length(line) - 1);
    if line <> '' then
    begin
      if CutField(line, fileN) and CutField(line, num) then
      begin
        try
          row := StrToInt(num);
        except
          row := 0;
        end;
        if (fileN <> '') and (row > 0) then
          ApplyBreakpoint(fileN, row, True);
      end;
    end;
  end;
end;

function TDebugSession.MakePausedEvent(n: CNode; const reason: fun.str): fun.str;
var
  i, depth: fun.int;
  {$IfDef FunTraceback}
  frame, outer: CCallFrame;
  {$EndIf}
  name, callerName, fn, curFile: fun.str;
  row, curLine: fun.int;
  stack: fun.str;
  first: Boolean;
begin
  stack := '';
  first := True;
  name := FunNameOfNode(n);
  curFile := FileOfNode(n);
  curLine := LineOfNode(n);
  if (name <> '') or (curFile <> '') then
  begin
    stack := '{"name":' + JsonStr(name) + ',"file":' + JsonStr(curFile) +
             ',"line":' + IntToStr(curLine) + '}';
    first := False;
  end;
  {$IfDef FunTraceback}
  depth := FEnv.callDepth;
  // frameAt(i) stores the call to frameAt(i)'s callee from the frame outside
  // it. The synthetic entry above is the function we are stopped in, at its
  // current statement. Each call frame is therefore the caller's location, and
  // its name comes from the next frame out (empty at the top level).
  for i := 0 to depth - 1 do
  begin
    if not FEnv.frameAt(i, frame) then break;
    callerName := '';
    if FEnv.frameAt(i + 1, outer) and (outer.callee <> nil) then
      callerName := outer.callee.displayName;
    fn := FrameFileName(frame);
    row := FrameLine(frame);
    if (callerName = '') and (fn = '') then continue;
    if not first then stack := stack + ',';
    stack := stack + '{"name":' + JsonStr(callerName) + ',"file":' + JsonStr(fn) +
             ',"line":' + IntToStr(row) + '}';
    first := False;
  end;
  {$EndIf}
  result := '{"type":"paused","reason":' + JsonStr(reason) +
            ',"file":' + JsonStr(curFile) + ',"line":' + IntToStr(curLine) +
            ',"cls":' + JsonStr(n.ClassName) + ',"name":' + JsonStr(n.name) +
            ',"stack":[' + stack + ']}';
end;

function TDebugSession.EvalText(const expr: fun.str): fun.str;
var
  tree: CRun;
  e: CExp;
  scope: CNode;
begin
  result := '';
  tree := nil;
  scope := FCurNode;
  if scope = nil then scope := FEnv.lastNode;
  try
    e := CParser.ParseExp(expr, scope, tree);
    if e = nil then
      result := '(no expression)'
    else
    begin
      e.calcValue(FEnv);
      result := e.asStr;
      if result = '' then result := '(empty)';
    end;
  except
    on E: Exception do
      result := 'error: ' + E.Message;
  end;
  if tree <> nil then FreeAndNil(tree);
end;

procedure TDebugSession.Pause(n: CNode; const reason: fun.str);
var
  snap, cmd: fun.str;
  resume, stop: Boolean;
  op, rest, id, expr: fun.str;
begin
  FCurNode := n;
  snap := MakePausedEvent(n, reason);
  EnterCriticalSection(FLock);
  try
    FStatus := dsPaused;
    AddEventLocked(snap);
  finally
    LeaveCriticalSection(FLock);
  end;

  repeat
    // A timed wait keeps a broken UI from parking the worker forever. Commands
    // and a stop request both set the event, so the normal path wakes at once.
    RTLEventWaitFor(FWake, 200);
    RTLEventResetEvent(FWake);

    EnterCriticalSection(FLock);
    try
      stop := FStop;
    finally
      LeaveCriticalSection(FLock);
    end;
    if stop then raise ECancelled.Create('stopped');

    resume := False;
    while PopCommand(cmd) do
    begin
      rest := cmd;
      if CutField(rest, op) then
      begin
        if (op = 'continue') or (op = 'go') then
        begin
          FMode := dmGo;
          FLastOver := nil;
          resume := True;
        end
        else if op = 'into' then
        begin
          FMode := dmInto;
          FLastOver := nil;
          resume := True;
        end
        else if op = 'over' then
        begin
          FMode := dmOver;
          FLastOver := FCurNode;
          resume := True;
        end
        else if op = 'out' then
        begin
          FMode := dmOut;
          FLastOver := CVar.findOwner(FCurNode);
          resume := True;
        end
        else if op = 'eval' then
        begin
          if CutField(rest, id) then
          begin
            expr := rest;
            AddEvent('{"type":"eval","id":' + JsonStr(id) + ',"ok":true,"value":' +
                     JsonStr(EvalText(expr)) + '}');
          end
          else
            AddEvent('{"type":"eval","id":"","ok":false,"value":"missing id"}');
        end
        else if op = 'bp' then
        begin
          expr := rest;
          if CutField(expr, id) and CutField(expr, rest) then
          begin
            try
              ApplyBreakpoint(id, StrToInt(rest), expr <> '0');
            except
            end;
          end;
        end
        else if op = 'bpoff' then
        begin
          expr := rest;
          if CutField(expr, id) and CutField(expr, rest) then
          begin
            try
              ApplyBreakpoint(id, StrToInt(rest), False);
            except
            end;
          end;
        end
        else if op = 'bpclear' then
        begin
          EnterCriticalSection(FLock);
          try
            FBreakpoints.Clear;
          finally
            LeaveCriticalSection(FLock);
          end;
        end
        else if op = 'stop' then
        begin
          EnterCriticalSection(FLock);
          try
            FStop := True;
          finally
            LeaveCriticalSection(FLock);
          end;
          raise ECancelled.Create('stopped');
        end
        else
          AddEvent('{"type":"error","message":' + JsonStr('unknown command: ' + op) + '}');
      end;
      if resume then break;
    end;
  until resume;

  EnterCriticalSection(FLock);
  try
    FStatus := dsRunning;
    AddEventLocked('{"type":"resumed"}');
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDebugSession.DebugTrace(env: CEnv; n: CNode);
var
  fn: fun.str;
  row, bpCount: fun.int;
begin
  if FFinished then exit;
  if (n = nil) or (n is CFun) or not (n is CRune) then exit;
  if FStop then raise ECancelled.Create('stopped');
  if not FReportedStart then
  begin
    FReportedStart := True;
    fn := FileOfNode(n);
    row := LineOfNode(n);
    EnterCriticalSection(FLock);
    try
      bpCount := FBreakpoints.Count;
    finally
      LeaveCriticalSection(FLock);
    end;
    AddEvent('{"type":"started","file":' + JsonStr(fn) +
             ',"line":' + IntToStr(row) +
             ',"breakpoints":' + IntToStr(bpCount) + '}');
  end;
  if FMode = dmInto then
    Pause(n, 'step')
  else if BreakpointHit(n) then
    Pause(n, 'breakpoint');
end;

procedure TDebugSession.DebugTraced(env: CEnv; n: CNode; tracing: fun.bool);
begin
  if FFinished then exit;
  if FStop then raise ECancelled.Create('stopped');
  if (FLastOver <> nil) and (n = FLastOver) and
     ((FMode = dmOver) or ((FMode = dmOut) and not tracing)) then
    Pause(n, 'step');
end;

procedure TDebugSession.DebugEcho(const s: fun.str);
begin
  AddEvent('{"type":"output","text":' + JsonStr(s) + '}');
end;

function TDebugSession.Command(const cmd: fun.str): fun.bool;
var
  op, rest: fun.str;
  a1, a2: fun.str;
begin
  result := True;
  rest := cmd;
  if not CutField(rest, op) then exit(False);
  if op = 'stop' then
  begin
    EnterCriticalSection(FLock);
    try
      FStop := True;
    finally
      LeaveCriticalSection(FLock);
    end;
    RTLEventSetEvent(FWake);
    exit;
  end;
  // Breakpoints can change while the target is running, so apply them here
  // instead of waiting for the next pause.
  if op = 'bp' then
  begin
    a1 := rest;
    if CutField(a1, a2) and CutField(a1, rest) then
    begin
      try
        ApplyBreakpoint(a2, StrToInt(rest), a1 <> '0');
      except
      end;
    end;
    exit;
  end;
  if op = 'bpoff' then
  begin
    a1 := rest;
    if CutField(a1, a2) and CutField(a1, rest) then
    begin
      try
        ApplyBreakpoint(a2, StrToInt(rest), False);
      except
      end;
    end;
    exit;
  end;
  if op = 'bpclear' then
  begin
    EnterCriticalSection(FLock);
    try
      FBreakpoints.Clear;
    finally
      LeaveCriticalSection(FLock);
    end;
    exit;
  end;
  EnterCriticalSection(FLock);
  try
    FCommands.Add(cmd);
  finally
    LeaveCriticalSection(FLock);
  end;
  RTLEventSetEvent(FWake);
end;

function TDebugSession.Poll: fun.str;
var
  i: fun.int;
begin
  result := '';
  EnterCriticalSection(FLock);
  try
    for i := 0 to FEvents.Count - 1 do
      result := result + FEvents[i] + #10;
    FEvents.Clear;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TDebugSession.StatusName: fun.str;
begin
  EnterCriticalSection(FLock);
  try
    case FStatus of
      dsIdle: result := 'idle';
      dsRunning: result := 'running';
      dsPaused: result := 'paused';
      dsDone: result := 'done';
      dsError: result := 'error';
      dsStopped: result := 'stopped';
    else
      result := 'unknown';
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TDebugSession.StateName: fun.str;
begin
  result := StatusName;
end;

procedure TDebugSession.Finish(status: TDebugStatus; const err: fun.str = '');
var
  ev: fun.str;
begin
  EnterCriticalSection(FLock);
  try
    if FFinished then exit;
    FFinished := True;
    FStatus := status;
    if status = dsError then
      ev := '{"type":"error","message":' + JsonStr(err) + '}'
    else if status = dsStopped then
      ev := '{"type":"stopped"}'
    else
      ev := '{"type":"done"}';
    AddEventLocked(ev);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

{$EndIf}

end.
