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

uses fun, base, core, Classes;

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
    // Cooperative cancellation. checkCancelled reads this through the worker
    // thread's _cancelFlag pointer at loop/call safe points.
    FCancel: LongInt;
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
    procedure Cancel;
    property ThreadId: TThreadID read FThreadId;
  end;

// One submitted pool job. A task owns its result and cancel flag; a slot only
// refers to it while the job runs, so a task can outlive slot reuse.
  CPoolTask = class(CBase)
  private
    FLock: TRTLCriticalSection;
    FEvent: PRTLEvent;
    FDone: Boolean;
    FCancel: LongInt;
    FEntry: fun.str;
    FPayload: fun.str;
    FResult: fun.str;
    FError: fun.str;
    procedure SetDone(const aresult, aerror: fun.str);
  public
    constructor Create(const entry, payload: fun.str);
    destructor Destroy; override;
    // Wait for completion. timeout < 0 waits forever. Returns False on timeout.
    function Join(timeout: fun.int): Boolean;
    function ResultText: fun.str;
    function ErrorText: fun.str;
    function HasError: Boolean;
    function Alive: Boolean;
    procedure Cancel;
  end;

  CWorkerPool = class;

// A resident slot: one OS thread with a private parsed module and CEnv. The
// module is parsed once and runs jobs serially, so module globals persist
// between jobs handled by the same slot.
  CWorkerSlot = class(CBase)
  private
    FSource: fun.str;
    FIsFile: Boolean;
    FBaseEnv: CEnv;
    FModule: CRun;
    FEnv: CEnv;
    FThreadId: TThreadID;
    FStarted: Boolean;
    FJobEvent: PRTLEvent;
    FExitEvent: PRTLEvent;
    FLock: TRTLCriticalSection;
    FTask: CPoolTask;
    FStop: Boolean;
    FStartError: fun.str;
    procedure Execute;
    procedure ResetEnv;
    function RunEntry(const entry, payload: fun.str): fun.str;
    function ErrorTextOf(e: EBase): fun.str;
  public
    constructor Create(aBaseEnv: CEnv; const source: fun.str; isFile: Boolean);
    destructor Destroy; override;
    procedure StartSlot;
    procedure Assign(task: CPoolTask);
    procedure Stop;
    function IsIdle: Boolean;
  end;

// A fixed-size pool of resident slots. One pool serves one module; each job
// names its entry function.
  CWorkerPool = class(CBase)
  private
    FSlots: CList;
    FLock: TRTLCriticalSection;
    FSize: fun.int;
    FClosed: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(env: CEnv; const source: fun.str; isFile: Boolean; size: fun.int);
    function Submit(const entry, payload: fun.str): CPoolTask;
    function IdleCount: fun.int;
    function Size: fun.int;
    procedure Close;
  end;

// 'Worker'.start(source, entry, payload, file = true)
procedure _workerStart(env: CEnv; exp: CExp; exps: CExps; val: PValue);

// 'Pool'.open(source, size, file = true)
procedure _poolOpen(env: CEnv; exp: CExp; exps: CExps; val: PValue);

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
    function Delete(const key: fun.str): Boolean;
    procedure Clear;
    function KeyAt(index: fun.int): fun.str;
  end;

// 'Shared'.open(name)
procedure _sharedOpen(env: CEnv; exp: CExp; exps: CExps; val: PValue);

// A named, process-wide FIFO channel. Workers on different threads open the
// same channel by name. Payloads are copied in and out, so no Fun string is
// referenced from two threads. recv() blocks in 1 ms steps; close() makes a
// blocked recv return nil after draining queued items.
type
  CChannelItem = class(CBase)
  public
    value: fun.str;
    constructor Create(const avalue: fun.str);
  end;

  CChannel = class(CBase)
  private
    FLock: TRTLCriticalSection;
    FItems: TList;
    FClosed: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Send(const value: fun.str);
    function TryRecv(out s: fun.str): Boolean;
    function Recv(timeout: fun.int; out s: fun.str): Boolean;
    procedure Close;
    function Closed: Boolean;
    function Count: fun.int;
  end;

// 'Channel'.open(name)
procedure _channelOpen(env: CEnv; exp: CExp; exps: CExps; val: PValue);

// 'Shared'.open / 'Channel'.open dispatcher.
procedure _openNamed(env: CEnv; exp: CExp; exps: CExps; val: PValue);

{$EndIf}

implementation

{$IfDef FunThreads}

uses SysUtils, parse;

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
      // Every loop and function call inside this worker now checks FCancel.
      _cancelFlag := @FCancel;
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
      on E: EBase do
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
    _cancelFlag := nil;
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

procedure CWorker.Cancel;
begin
  // A plain aligned 32-bit write is atomic on every supported target. The
  // worker reads it through checkCancelled at its next safe point.
  InterLockedExchange(FCancel, 1);
end;

//==============================================================
// Resident worker pool
//==============================================================
constructor CPoolTask.Create(const entry, payload: fun.str);
begin
  inherited Create;
  InitCriticalSection(FLock);
  FEvent := RTLEventCreate;
  FEntry := entry;
  FPayload := payload;
end;

destructor CPoolTask.Destroy;
begin
  if FEvent <> nil then RTLEventDestroy(FEvent);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure CPoolTask.SetDone(const aresult, aerror: fun.str);
begin
  EnterCriticalSection(FLock);
  try
    FResult := aresult;
    FError := aerror;
    FDone := True;
  finally
    LeaveCriticalSection(FLock);
  end;
  RTLEventSetEvent(FEvent);
end;

function CPoolTask.Join(timeout: fun.int): Boolean;
var
  waited: fun.int;
begin
  if not FDone then
  begin
    if timeout < 0 then
      RTLEventWaitFor(FEvent)
    else
    begin
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

function CPoolTask.ResultText: fun.str;
begin
  EnterCriticalSection(FLock);
  try
    result := FResult;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CPoolTask.ErrorText: fun.str;
begin
  EnterCriticalSection(FLock);
  try
    result := FError;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CPoolTask.HasError: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    result := FError <> '';
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CPoolTask.Alive: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    result := not FDone;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure CPoolTask.Cancel;
begin
  InterLockedExchange(FCancel, 1);
end;

//==============================================================
function SlotMain(p: Pointer): PtrInt;
begin
  result := 0;
  CWorkerSlot(p).Execute;
end;

constructor CWorkerSlot.Create(aBaseEnv: CEnv; const source: fun.str; isFile: Boolean);
begin
  inherited Create;
  // Clone on the caller thread, before the slot thread starts, so two slots
  // never read the same CEnv concurrently.
  FBaseEnv := aBaseEnv.clone;
  FSource := source;
  FIsFile := isFile;
  FStarted := False;
  FJobEvent := RTLEventCreate;
  FExitEvent := RTLEventCreate;
  InitCriticalSection(FLock);
end;

destructor CWorkerSlot.Destroy;
begin
  Stop;
  del(FEnv);
  del(FModule);
  del(FBaseEnv);
  if FJobEvent <> nil then RTLEventDestroy(FJobEvent);
  if FExitEvent <> nil then RTLEventDestroy(FExitEvent);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure CWorkerSlot.StartSlot;
begin
  if FStarted then raise EBase.Create('pool slot already started');
  FThreadId := BeginThread(@SlotMain, Pointer(Self), FThreadId);
  FStarted := True;
end;

function CWorkerSlot.IsIdle: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    result := FTask = nil;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure CWorkerSlot.Assign(task: CPoolTask);
begin
  EnterCriticalSection(FLock);
  try
    if FStop then raise EBase.Create('pool slot is stopped');
    if FTask <> nil then raise EBase.Create('pool slot is busy');
    FTask := task;
    add(FTask);
  finally
    LeaveCriticalSection(FLock);
  end;
  RTLEventSetEvent(FJobEvent);
end;

procedure CWorkerSlot.Stop;
var
  wasStopped: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    wasStopped := FStop;
    FStop := True;
  finally
    LeaveCriticalSection(FLock);
  end;
  if not FStarted then exit;
  RTLEventSetEvent(FJobEvent);
  if not wasStopped then RTLEventWaitFor(FExitEvent);
end;

procedure CWorkerSlot.ResetEnv;
begin
  if FEnv <> nil then del(FEnv);
  FEnv := FBaseEnv.clone;
  _ENV := FEnv;
  if FModule <> nil then FModule.run(FEnv);
end;

function CWorkerSlot.ErrorTextOf(e: EBase): fun.str;
begin
  result := e.Message;
  {$IfDef FunTraceback}
  try
    if FEnv <> nil then result := result + #10 + FEnv.traceBack;
  except
  end;
  {$EndIf}
end;

function CWorkerSlot.RunEntry(const entry, payload: fun.str): fun.str;
var
  v: CVar;
  args: CExps;
  e: CExp;
  rv: PValue;
begin
  v := FModule.UID(entry);
  if (v = nil) or not (v.asObj is CFun) then
    raise EBase.Create('worker entry not found: ' + entry);
  args := CExps.Create();
  try
    e := CExp.new(nil);
    e.assign(payload);
    args.Add(e);
    _ENV := FEnv;
    rv := CFun(v.asObj).call(FEnv, args);
    if rv = nil then
      result := ''
    else if isStr(rv) or isNum(rv) then
      result := fun.str(rv^)
    else
      raise EBase.Create('worker result must be a string or number (use .toJson(fd: true))');
  finally
    del(args);
  end;
end;

procedure CWorkerSlot.Execute;
var
  t: CPoolTask;
  r: fun.str;
  stopped: Boolean;
  failed: Boolean;
begin
  try
    try
      if FIsFile then
        FModule := CRun(CParser.ParseOrLoad(FSource, nil, CWorkerParser))
      else
        FModule := CParser.Parse(FSource, CWorkerParser, '', nil);
      ResetEnv;
    except
      on E: EBase do FStartError := ErrorTextOf(E);
    end;

    while True do
    begin
      RTLEventWaitFor(FJobEvent);
      RTLEventResetEvent(FJobEvent);
      EnterCriticalSection(FLock);
      try
        stopped := FStop;
        t := FTask;
      finally
        LeaveCriticalSection(FLock);
      end;
      if stopped then
      begin
        if t <> nil then
        begin
          EnterCriticalSection(FLock);
          try
            FTask := nil;
          finally
            LeaveCriticalSection(FLock);
          end;
          t.SetDone('', 'worker pool closed');
          del(t);
        end;
        break;
      end;
      if t = nil then continue;

      if FStartError <> '' then
      begin
        EnterCriticalSection(FLock);
        try
          FTask := nil;
        finally
          LeaveCriticalSection(FLock);
        end;
        t.SetDone('', FStartError);
        del(t);
      end
      else
      begin
        failed := False;
        r := '';
        _cancelFlag := @t.FCancel;
        try
          try
            r := RunEntry(t.FEntry, t.FPayload);
          except
            on E: EBase do
            begin
              failed := True;
              _cancelFlag := nil;
              r := ErrorTextOf(E);
              // A job that raised (or was cancelled) may have left module
              // globals half-updated. Rebuild before the next job.
              try
                ResetEnv;
              except
                on E2: EBase do FStartError := ErrorTextOf(E2);
              end;
            end;
          end;
        finally
          _cancelFlag := nil;
        end;
        // Release the slot before publishing the result, so a caller that
        // observes completion also sees an idle slot (no race with idle()).
        // The reference created by Assign moves to the local t here.
        EnterCriticalSection(FLock);
        try
          FTask := nil;
        finally
          LeaveCriticalSection(FLock);
        end;
        if failed then
          t.SetDone('', r)
        else
          t.SetDone(r, '')
        ;
        del(t);
      end;
    end;
  finally
    _cancelFlag := nil;
    _ENV := nil;
    del(FEnv);
    FEnv := nil;
    del(FModule);
    FModule := nil;
    RTLEventSetEvent(FExitEvent);
  end;
end;

//==============================================================
constructor CWorkerPool.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FSlots := CList.Create(True);
end;

destructor CWorkerPool.Destroy;
begin
  Close;
  del(FSlots);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure CWorkerPool.Start(env: CEnv; const source: fun.str; isFile: Boolean; size: fun.int);
var
  i: fun.int;
  slot: CWorkerSlot;
begin
  if FSlots.Count > 0 then raise EBase.Create('worker pool already started');
  if size < 1 then raise EBase.Create('worker pool size must be at least 1');
  FSize := size;
  for i := 1 to size do
  begin
    slot := CWorkerSlot.Create(env, source, isFile);
    // CList owns its entries and releases them on Clear; the creation
    // reference transfers to the list, so do not del(slot) here.
    FSlots.Add(slot);
    slot.StartSlot;
  end;
end;

function CWorkerPool.Submit(const entry, payload: fun.str): CPoolTask;
var
  t: CPoolTask;
  i: fun.int;
  got: Boolean;
begin
  t := CPoolTask.Create(entry, payload);
  try
    while True do
    begin
      got := False;
      EnterCriticalSection(FLock);
      try
        if FClosed then raise EBase.Create('worker pool is closed');
        for i := 0 to FSlots.Count - 1 do
          if CWorkerSlot(FSlots[i]).IsIdle then
          begin
            CWorkerSlot(FSlots[i]).Assign(t);
            got := True;
            break;
          end;
      finally
        LeaveCriticalSection(FLock);
      end;
      if got then break;
      Sleep(1);
    end;
    result := t;
  except
    del(t);
    raise;
  end;
end;

function CWorkerPool.IdleCount: fun.int;
var
  i: fun.int;
begin
  result := 0;
  for i := 0 to FSlots.Count - 1 do
    if CWorkerSlot(FSlots[i]).IsIdle then Inc(result);
end;

function CWorkerPool.Size: fun.int;
begin
  result := FSize;
end;

procedure CWorkerPool.Close;
var
  i: fun.int;
begin
  EnterCriticalSection(FLock);
  try
    if FClosed then exit;
    FClosed := True;
  finally
    LeaveCriticalSection(FLock);
  end;
  for i := 0 to FSlots.Count - 1 do
    CWorkerSlot(FSlots[i]).Stop;
end;

procedure _poolOpen(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  source: fun.str;
  size: fun.int;
  isFile: Boolean;
  e: CExp;
  p: CWorkerPool;
begin
  source := '';
  e := CExps.Find(exps, '', 0);
  if e <> nil then source := e.asStr;
  size := 4;
  e := CExps.Find(exps, '', 1);
  if e <> nil then size := e.asInt;
  isFile := CExps.FindAsVal(exps, 'file', 2, True);
  p := CWorkerPool.Create;
  try
    p.Start(env, source, isFile, size);
    setObj(val, p, VarObjNew);
  finally
    del(p);
  end;
end;

//==============================================================
// Named shared key/value store
//==============================================================
var
  SharedLock: TRTLCriticalSection;
  SharedList: TStringList; // name -> CShared (OwnsObjects)
  ChannelList: TStringList; // name -> CChannel (OwnsObjects)

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

function CShared.Delete(const key: fun.str): Boolean;
var
  i, j: fun.int;
  it: CSharedItem;
begin
  EnterCriticalSection(FLock);
  try
    result := False;
    for i := 0 to FItems.Count - 1 do
      if CSharedItem(FItems[i]).key = key then
      begin
        it := CSharedItem(FItems[i]);
        for j := i to FItems.Count - 2 do
          FItems.List^[j] := FItems.List^[j + 1];
        FItems.Count := FItems.Count - 1;
        del(it);
        result := True;
        exit;
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure CShared.Clear;
var
  i: fun.int;
begin
  EnterCriticalSection(FLock);
  try
    for i := FItems.Count - 1 downto 0 do
      del(CSharedItem(FItems[i]));
    FItems.Count := 0;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CShared.KeyAt(index: fun.int): fun.str;
begin
  EnterCriticalSection(FLock);
  try
    if (index < 0) or (index >= FItems.Count) then
      result := ''
    else
      result := CopyStr(CSharedItem(FItems[index]).key)
    ;
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
// FIFO channel
//==============================================================
constructor CChannelItem.Create(const avalue: fun.str);
begin
  inherited Create;
  value := CopyStr(avalue);
end;

constructor CChannel.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FItems := TList.Create;
end;

destructor CChannel.Destroy;
var
  i: fun.int;
begin
  for i := 0 to FItems.Count - 1 do
    CChannelItem(FItems[i]).Free;
  FItems.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure CChannel.Send(const value: fun.str);
begin
  EnterCriticalSection(FLock);
  try
    if FClosed then raise EBase.Create('channel is closed');
    FItems.Add(CChannelItem.Create(value));
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CChannel.TryRecv(out s: fun.str): Boolean;
var
  it: CChannelItem;
begin
  result := False;
  s := '';
  EnterCriticalSection(FLock);
  try
    if FItems.Count = 0 then exit;
    it := CChannelItem(FItems[0]);
    s := CopyStr(it.value);
    FItems.Delete(0);
    it.Free;
    result := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CChannel.Recv(timeout: fun.int; out s: fun.str): Boolean;
begin
  while True do
  begin
    checkCancelled;
    if TryRecv(s) then exit(True);
    if Closed then exit(False);
    if timeout = 0 then exit(False);
    Sleep(1);
    if timeout > 0 then Dec(timeout);
  end;
end;

procedure CChannel.Close;
begin
  EnterCriticalSection(FLock);
  try
    FClosed := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CChannel.Closed: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    result := FClosed;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function CChannel.Count: fun.int;
begin
  EnterCriticalSection(FLock);
  try
    result := FItems.Count;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure _channelOpen(env: CEnv; exp: CExp; exps: CExps; val: PValue);
var
  e: CExp;
  name: fun.str;
  c: CChannel;
  i: fun.int;
begin
  e := CExps.Find(exps, '', 0);
  if e = nil then name := '' else name := e.asStr;
  EnterCriticalSection(SharedLock);
  try
    i := ChannelList.IndexOf(name);
    if i < 0 then
    begin
      c := CChannel.Create;
      ChannelList.AddObject(name, c);
    end
    else
      c := CChannel(ChannelList.Objects[i])
    ;
    setObj(val, c, VarObjNew);
  finally
    LeaveCriticalSection(SharedLock);
  end;
end;

procedure _openNamed(env: CEnv; exp: CExp; exps: CExps; val: PValue);
begin
  if exp.asStr = 'Pool' then
    _poolOpen(env, exp, exps, val)
  else if exp.asStr = 'Channel' then
    _channelOpen(env, exp, exps, val)
  else
    _sharedOpen(env, exp, exps, val)
  ;
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
  ChannelList := TStringList.Create;
  ChannelList.OwnsObjects := True;
  ChannelList.CaseSensitive := True;
finalization
  ChannelList.Free;
  SharedList.Free;
  DoneCriticalSection(SharedLock);
{$EndIf}

end.
