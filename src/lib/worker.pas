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
unit worker;

// Minimal native half of the worker model (FunThreads builds only).
//
// A worker owns a freshly parsed module and a cloned CEnv, so its AST and all
// per-node evaluation cells are private. Nothing Fun-visible crosses the thread
// boundary: arguments and results are plain strings, which is why this unit is
// deliberately small. The user-facing Worker class, FD encoding, timeouts and
// future message passing live in fun/lib/lib-worker.fun.

{$IfDef FunThreads}

interface

uses fun, base, core;

type
  // One evaluation thread with its own module and environment.
  CWorker = class(CBase)
  private
    FSource: fun.str;
    FEntry: fun.str;
    FPayload: fun.str;
    FResult: fun.str;
    FError: fun.str;
    FIsFile: Boolean;
    FStarted: Boolean;
    FDone: Boolean;
    FLock: TRTLCriticalSection;
    FEvent: PRTLEvent;
    FThreadId: TThreadID;
    FEnv: CEnv;
    procedure SetResult(const s: fun.str);
    procedure SetError(const s: fun.str);
    procedure Finish;
    procedure Execute;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(env: CEnv; const source, entry, payload: fun.str; isFile: Boolean);
    // Wait for completion. timeout < 0 waits forever. Returns False on timeout.
    function Join(timeout: fun.int): Boolean;
    function ResultText: fun.str;
    function ErrorText: fun.str;
    function HasError: Boolean;
    function Alive: Boolean;
    property ThreadId: TThreadID read FThreadId;
  end;

// 'Worker'.start(source, entry, payload, file = true)
procedure _workerStart(env: CEnv; exp: CExp; exps: CExps; val: PValue);

// A named, process-wide key/value store. Workers get the same object by name,
// so shared mutable data stays explicit and does not require sharing a Fun
// object. Values are strings (use FD for structured data) and are copied on
// both get and set, so no Fun string is referenced from two threads.
type
  CSharedItem = class(CBase)
  public
    key: fun.str;
    value: fun.str;
    constructor Create(const akey, avalue: fun.str);
  end;

  CShared = class(CBase)
  private
    FLock: TRTLCriticalSection;
    FItems: CList;
    function Find(const key: fun.str): CSharedItem;
  public
    constructor Create;
    destructor Destroy; override;
    function GetValue(const key: fun.str): fun.str;
    procedure SetValue(const key, value: fun.str);
    function Has(const key: fun.str): Boolean;
    function Count: fun.int;
    function Add(const key: fun.str; delta: Int64): Int64;
  end;

// 'Shared'.open(name)
procedure _sharedOpen(env: CEnv; exp: CExp; exps: CExps; val: PValue);

{$EndIf}

implementation

{$IfDef FunThreads}

uses SysUtils, Classes, parse;

type
  // Parse errors must stay on the worker thread. The driver's CFunParser
  // reports by writing to stderr and setting a process-wide hadError flag,
  // which is not safe from a worker, so raise instead and let Execute store it.
  CWorkerParser = class(CParser)
  public
    procedure DoError(const s: fun.str); override;
  end;

procedure CWorkerParser.DoError(const s: fun.str);
begin
  raise EBase.Create(s);
end;

function WorkerMain(p: Pointer): PtrInt;
begin
  result := 0;
  CWorker(p).Execute;
end;

//==============================================================
constructor CWorker.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FEvent := RTLEventCreate;
end;

destructor CWorker.Destroy;
begin
  // The handle owns the thread. Dropping it without join waits here instead of
  // leaving the worker with a dangling pointer, so there is no use-after-free.
  if FStarted and not FDone then Join(-1);
  if FEnv <> nil then del(FEnv);
  if FEvent <> nil then RTLEventDestroy(FEvent);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure CWorker.Start(env: CEnv; const source, entry, payload: fun.str; isFile: Boolean);
begin
  if FStarted then raise EBase.Create('worker already started');
  if source = '' then raise EBase.Create('worker source is empty');
  if entry = '' then raise EBase.Create('worker entry is empty');
  FSource := source;
  FEntry := entry;
  FPayload := payload;
  FIsFile := isFile;
  // Clone before the thread exists: the worker never reads the caller's env.
  FEnv := env.clone;
  FThreadId := BeginThread(@WorkerMain, Pointer(Self), FThreadId);
  FStarted := True;
end;

procedure CWorker.SetResult(const s: fun.str);
begin
  EnterCriticalSection(FLock);
  try
    FResult := s;
    FError := '';
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure CWorker.SetError(const s: fun.str);
begin
  EnterCriticalSection(FLock);
  try
    FResult := '';
    FError := s;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure CWorker.Finish;
begin
  EnterCriticalSection(FLock);
  try
    FDone := True;
  finally
    LeaveCriticalSection(FLock);
  end;
  RTLEventSetEvent(FEvent);
end;

procedure CWorker.Execute;
var
  env: CEnv;
  modu: CRun;
  v: CVar;
  args: CExps;
  e: CExp;
  rv: PValue;
  s: fun.str;
begin
  env := FEnv;
  modu := nil;
  args := nil;
  try
    try
      _ENV := env;
      if FIsFile then
        modu := CRun(CParser.ParseOrLoad(FSource, nil, CWorkerParser))
      else
        modu := CParser.Parse(FSource, CWorkerParser, '', nil);
      modu.run(env);
      v := modu.UID(FEntry);
      if (v = nil) or not (v.asObj is CFun) then
        raise EBase.Create('worker entry not found: ' + FEntry);
      args := CExps.Create();
      e := CExp.new(nil);
      e.assign(FPayload);
      args.Add(e);
      rv := CFun(v.asObj).call(env, args);
      if rv = nil then
        s := ''
      else if isStr(rv) or isNum(rv) then
        s := fun.str(rv^)
      else
        raise EBase.Create('worker result must be a string or number (use .toJson(fd: true))');
      SetResult(s);
    except
      on E: Exception do
      begin
        s := E.Message;
        {$IfDef FunTraceback}
        try
          if env <> nil then s := s + #10 + env.traceBack;
        except
        end;
        {$EndIf}
        SetError(s);
      end;
    end;
  finally
    _ENV := nil;
    del(args);
    del(modu);
    del(FEnv);
    FEnv := nil;
    Finish;
  end;
end;

function CWorker.Join(timeout: fun.int): Boolean;
var
  waited: fun.int;
begin
  if not FStarted then exit(False);
  if not FDone then
  begin
    if timeout < 0 then
      RTLEventWaitFor(FEvent)
    else
    begin
      // Simple phase-1 wait: a 1 ms poll is plenty for a join timeout and
      // avoids depending on an RTL overload that differs between FPC targets.
      waited := 0;
      while (waited < timeout) and not FDone do
      begin
        Sleep(1);
        Inc(waited);
      end;
    end;
  end;
  result := FDone;
end;

function CWorker.ResultText: fun.str;
begin
  EnterCriticalSection(FLock);
  try
    result := FResult;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CWorker.ErrorText: fun.str;
begin
  EnterCriticalSection(FLock);
  try
    result := FError;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CWorker.HasError: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    result := FError <> '';
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CWorker.Alive: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    result := FStarted and not FDone;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

//==============================================================
// Named shared key/value store
//==============================================================
var
  SharedLock: TRTLCriticalSection;
  SharedList: TStringList; // name -> CShared (OwnsObjects)

function CopyStr(const s: fun.str): fun.str;
begin
  if s = '' then exit('');
  SetLength(result, Length(s));
  Move(s[1], result[1], Length(s));
end;

constructor CSharedItem.Create(const akey, avalue: fun.str);
begin
  inherited Create;
  key := CopyStr(akey);
  value := CopyStr(avalue);
end;

constructor CShared.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FItems := CList.Create(True);
end;

destructor CShared.Destroy;
begin
  del(FItems);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function CShared.Find(const key: fun.str): CSharedItem;
var
  i: fun.int;
begin
  result := nil;
  for i := 0 to FItems.Count - 1 do
    if CSharedItem(FItems[i]).key = key then
      exit(CSharedItem(FItems[i]));
end;

function CShared.GetValue(const key: fun.str): fun.str;
var
  it: CSharedItem;
begin
  EnterCriticalSection(FLock);
  try
    it := Find(key);
    if it = nil then result := '' else result := CopyStr(it.value);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure CShared.SetValue(const key, value: fun.str);
var
  it: CSharedItem;
begin
  EnterCriticalSection(FLock);
  try
    it := Find(key);
    if it = nil then
      FItems.Add(CSharedItem.Create(key, value))
    else
      it.value := CopyStr(value)
    ;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CShared.Has(const key: fun.str): Boolean;
begin
  EnterCriticalSection(FLock);
  try
    result := Find(key) <> nil;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CShared.Count: fun.int;
begin
  EnterCriticalSection(FLock);
  try
    result := FItems.Count;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CShared.Add(const key: fun.str; delta: Int64): Int64;
var
  it: CSharedItem;
  v: Int64;
begin
  EnterCriticalSection(FLock);
  try
    it := Find(key);
    if it = nil then
    begin
      v := delta;
      FItems.Add(CSharedItem.Create(key, IntToStr(v)));
    end
    else
    begin
      v := StrToInt64Def(it.value, 0) + delta;
      it.value := IntToStr(v);
    end;
    result := v;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure _sharedOpen(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e: CExp;
  name: fun.str;
  s: CShared;
  i: fun.int;
begin
  e := CExps.Find(exps, '', 0);
  if e = nil then name := '' else name := e.asStr;
  EnterCriticalSection(SharedLock);
  try
    i := SharedList.IndexOf(name);
    if i < 0 then
    begin
      s := CShared.Create;
      SharedList.AddObject(name, s);
    end
    else
      s := CShared(SharedList.Objects[i])
    ;
    setObj(val, s, VarObjNew);
  finally
    LeaveCriticalSection(SharedLock);
  end;
end;

//==============================================================
procedure _workerStart(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  source, entry, payload: fun.str;
  e: CExp;
  w: CWorker;
  isFile: Boolean;
begin
  source  := '';
  entry   := 'main';
  payload := '';
  e := CExps.Find(exps, '', 0);
  if e <> nil then source := e.asStr;
  e := CExps.Find(exps, '', 1);
  if e <> nil then entry := e.asStr;
  e := CExps.Find(exps, '', 2);
  if e <> nil then payload := e.asStr;
  isFile := CExps.FindAsVal(exps, 'file', 3, True);
  w := CWorker.Create;
  try
    w.Start(env, source, entry, payload, isFile);
    setObj(val, w, VarObjNew);
  finally
    del(w);
  end;
end;

{$EndIf}

{$IfDef FunThreads}
initialization
  InitCriticalSection(SharedLock);
  SharedList := TStringList.Create;
  SharedList.OwnsObjects := True;
  SharedList.CaseSensitive := True;
finalization
  SharedList.Free;
  DoneCriticalSection(SharedLock);
{$EndIf}

end.
