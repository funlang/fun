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
unit base;

interface

uses SysUtils, StrUtils,
     fun;

type
  CValue  = System.Variant;
  PValue  = ^CValue;
  PPValue = ^PValue;
  CData   = System.TVarData;
  PData   = ^CData;

var
  NullValue: CValue;

type
  EBase  = SysUtils.Exception;

{$IfDef FunSafe}
// Compile-time safe build (-dFunSafe): the interpreter withholds capabilities
// that are fine for trusted scripts but unsafe for generated/untrusted code.
// See SAFETY.zh.md for the category list.
procedure SafeDeny(const what: fun.str);
{$EndIf}

type
  PArrayOfPtr = ^ArrayOfPtr;
   ArrayOfPtr = array[0..Maxint div 16 - 1] of fun.ptr;

const
  Max_Char = 39;

type
  PTrieNode = ^CTrieNode;
  CTrieNode = packed record
    Index: array[0..Max_Char+1] of fun.byte;
    Items: array of PTrieNode;
  end;
  
  CTrieEach = procedure (p: fun.ptr) of object;
  CTrieEachEx = procedure (p: fun.ptr; const s: fun.str) of object;
type

  CBase = class(TObject, IInterface)
  protected
    FRefCount: fun.int;
    function QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} IID: TGUID; out Obj): HResult; {$IfDef FPC}{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF}{$ELSE}stdcall{$ENDIF};
  public
    class function NewInstance: TObject; override;
    function _AddRef: fun.int; {$IfDef FPC}{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF}{$ELSE}stdcall{$ENDIF};
    function _Release: fun.int; {$IfDef FPC}{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF}{$ELSE}stdcall{$ENDIF};
  end;
  
  CList = class(CBase)
  private
    function GetItem(i: fun.int): fun.ptr;
    procedure SetSize(Value: fun.int);
    procedure SetCount(Value: fun.int);
  protected
    FAutoDel: fun.bool;
    FCount: fun.int;
    FSize: fun.int;
    procedure Clear; virtual;
    procedure Grow; virtual;
    property Size: fun.int read FSize write SetSize;
  public
    List: PArrayOfPtr;
    constructor Create(autoDel: fun.bool = true);
    destructor Destroy; override;
    function Add(p: fun.ptr; i: fun.int = -1): fun.int;
    function Contains(p: fun.ptr): fun.bool;
    property Count: fun.int read FCount write SetCount;
    property Item[i: fun.int]: fun.ptr read GetItem; default;
  end;
  
  CHash = class(CBase)
  private
    Root: PTrieNode;
    function NewNode: PTrieNode;
  protected
    procedure Clear; virtual;
    procedure FreeItem(p: fun.ptr); virtual;
    function GetItemById(const id: fun.str): fun.ptr; virtual;
    procedure SetItemById(const id: fun.str; Value: fun.ptr); virtual;
  public
    destructor Destroy; override;
    procedure Each(DoEach: CTrieEach);
    procedure EachEx(DoEach: CTrieEachEx; forName: fun.bool = false);
    function FindOrAdd(const id: fun.str; p: fun.ptr = nil; isOverwrite: fun.bool = false; isHexId: fun.bool = false): fun.ptr;
    property ItemById[const id: fun.str]: fun.ptr read GetItemById write SetItemById; default;
  end;
  
  CHist = class(CHash)
  private
    function GetItem(i: fun.int): fun.ptr;
    procedure SetItem(i: fun.int; Value: fun.ptr);
  protected
    procedure Clear; override;
    procedure FreeItem(p: fun.ptr); override;
    function GetItemById(const id: fun.str): fun.ptr; override;
    procedure SetItemById(const id: fun.str; Value: fun.ptr); override;
  public
    List: CList;
    constructor Create(autoDel: fun.bool = true);
    destructor Destroy; override;
    function Add(p: fun.ptr): fun.int; virtual;
    function Count: fun.int;
    property Item[i: fun.int]: fun.ptr read GetItem write SetItem;
  end;
  

type
  CVarStack = class;

  CFunStack = class(CBase)
  protected
    level: fun.int;
    vars: CList;
    procedure PopVars;
    procedure PushVar(avar: CVarStack);
  public
    start: fun.int;
    constructor Create;
    destructor Destroy; override;
    procedure Pop;
    procedure Push;
  end;
  
  CVarStack = class(CBase)
  private
    values: array of CValue;
  protected
    level: fun.int;
    owner: CFunStack;
    pp_val: PPValue;
    p_val: PValue;
    procedure Pop;
    procedure PushVar;
  public
    constructor Create(aowner: CFunStack; p: PValue; pp: PPValue);
    procedure Parse(p: PValue; pp: PPValue);
    procedure Push;
    function CanWriteDirect: Boolean;
    function DirectTarget: PValue;
  end;
  

type
  ECompResult = (EQ, LT, GT, NE);

function funBool(val: PValue): fun.bool;
function isNull(val: PValue): fun.bool;
function isStr(vt: TVarType): fun.bool; overload;
function isStr(val: PValue): fun.bool; overload;
function isNum(vt: TVarType; all: fun.bool = false): fun.bool; overload;
function isNum(val: PValue; all: fun.bool = false): fun.bool; overload;
function isFloat(vt: TVarType): fun.bool; overload;
function isFloat(val: PValue): fun.bool; overload;
function isOle(val: PValue): fun.bool;
function varComp(v1, v2: PValue; isCase: fun.bool): ECompResult;

function asObj(val: PValue): CBase;
function asPtr(val: PValue): fun.ptr;
function rawPtr(val: PValue): fun.ptr;
procedure setObj(val: PValue; obj: CBase; vt: fun.word = VarObject);
procedure clear(val: PValue);

// Write a Boolean result straight into a Variant's fields when the target
// does not own a managed payload. FPC's `Variant := Boolean` goes through the
// RTL and costs ~50ns, versus ~2ns for the two field writes below; comparison
// and logical operators produce a Boolean on every evaluation.
procedure setBool(val: PValue; b: fun.bool);

// Copy src into dst, keeping the scalar fast paths (Integer/Double/Boolean)
// out of VariantCopy. Falls back to the RTL for managed values and for a
// destination that still holds one (which must be cleared/released).
procedure copyValue(dst, src: PValue);

procedure add(obj: CBase);
procedure del(obj: CBase);

function calcIndex(i, N: fun.int): fun.int;
Function NewStringReplace(const S, OldPattern, NewPattern: string;  Flags: TReplaceFlags): string;
function ToFunTime(const s: fun.str): fun.time;

implementation

{$IfDef Unicode}{$WARN WIDECHAR_REDUCED OFF}{$EndIf}

uses Variants;

{$IfDef FunSafe}
procedure SafeDeny(const what: fun.str);
begin
  raise EBase.Create('safe mode: ' + what + ' is not allowed');
end;
{$EndIf}

{$IfDef FPC}
// FPC's own VarToDateTime is not locale-independent: it goes through
// TryStrToDateTime with the host's ShortDateFormat / DateSeparator (e.g.
// "M/d/yyyy" with a '/' separator on a US Windows), so Fun's ISO time literal
// ("2010-04-09 15:35:15") raises EVariantError. Parse the ISO form directly,
// matching the Unix builds. Delphi (a different VarToDateTime) keeps the
// plain conversion below.
function ToFunTime(const s: fun.str): fun.time;
var
  i, n: fun.int;
  yy, mm, dd, hh, nn, ss: fun.int;
  t: fun.time;
begin
  yy := 0; mm := 0; dd := 0;
  hh := 0; nn := 0; ss := 0;
  i := 1; n := Length(s);
  // date: yyyy-mm-dd  (digits then '-'-separated groups)
  while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
  begin yy := yy * 10 + (Ord(s[i]) - 48); inc(i); end;
  if (i <= n) and (s[i] = '-') then inc(i);
  while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
  begin mm := mm * 10 + (Ord(s[i]) - 48); inc(i); end;
  if (i <= n) and (s[i] = '-') then inc(i);
  while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
  begin dd := dd * 10 + (Ord(s[i]) - 48); inc(i); end;
  // time: hh:nn:ss  (optional, preceded by a space)
  if (i <= n) and (s[i] = ' ') then inc(i);
  while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
  begin hh := hh * 10 + (Ord(s[i]) - 48); inc(i); end;
  if (i <= n) and (s[i] = ':') then inc(i);
  while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
  begin nn := nn * 10 + (Ord(s[i]) - 48); inc(i); end;
  if (i <= n) and (s[i] = ':') then inc(i);
  while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
  begin ss := ss * 10 + (Ord(s[i]) - 48); inc(i); end;
  if (mm = 0) then mm := 1;
  if (dd = 0) then dd := 1;
  if (yy >= 1) and (yy <= 9999) and (mm >= 1) and (mm <= 12)
     and (dd >= 1) and (dd <= 31) and (hh <= 23) and (nn <= 59) and (ss <= 59) then
    t := EncodeDate(word(yy), word(mm), word(dd)) + EncodeTime(word(hh), word(nn), word(ss), 0)
  else
    t := VarToDateTime(s);  // fall through: let it raise if it must
  result := t;
end;

{$Else}

// Delphi's VarToDateTime (OLE) accepts Fun's ISO form regardless of the
// host locale, so the Windows/Delphi build keeps the plain conversion.
function ToFunTime(const s: fun.str): fun.time;
begin
  result := VarToDateTime(s);
end;

{$EndIf}

procedure add(obj: CBase);
begin
  if obj <> nil then obj._AddRef;
end;

procedure del(obj: CBase);
begin
  if obj <> nil then obj._Release;
end;

//==============================================================
function asObj(val: PValue): CBase;
begin
  with PData(val)^ do
  begin
    if (VType = VarObject) or (VType = VarObjNew) then
      result := VPointer
    else
      result := nil
    ;
  end;
end;

// On 64-bit targets pointers are wider than fun.int, so reading a value as an
// address must not fall back to the 32-bit VInteger field.
{$IfDef Win64}
  {$Define FunPtrWide}
{$EndIf}
{$IfDef FPC}
  {$IfDef CPU64}
    {$Define FunPtrWide}
  {$EndIf}
{$EndIf}

// Pointer-width read of a numeric value. Unlike 'fun.int(val^)' (32-bit, truncates
// addresses on 64-bit targets), this reads the value slot at pointer width, so a
// full-width address survives while 32-bit targets stay exactly 32 bits.
//
// No Int64/ordinal typecast is used: Delphi rejects typecasts between Int64 and
// narrower ordinals ('E2089 Invalid typecast'), which would be the 32-bit path.
// The value is already stored at pointer width, so a plain field read suffices:
// varInt64 holds the full word, every other numeric type is 32-bit.
function asPtr(val: PValue): fun.ptr;
begin
{$IfDef FunPtrWide}
  with PData(val)^ do
    if VType = varInt64 then
      result := fun.ptr(fun.uintptr(VPointer))
    else
      result := fun.ptr(fun.uintptr(VInteger))
  ;
{$Else}
  result := fun.ptr(fun.uintptr(PData(val)^.VInteger));
{$EndIf}
end;

// Raw pointer-sized word stored in a value, for the raw-memory builtins
// (.move / .movs / .toNum(ptr:-1)) that pass addresses through the value model.
// String payloads and varInt64 values share the 8-byte value slot, so VPointer
// reads them full width; every other numeric type is 32-bit as before.
function rawPtr(val: PValue): fun.ptr;
begin
{$IfDef FunPtrWide}
  with PData(val)^ do
    if isStr(VType) or (VType = varInt64) then
      result := fun.ptr(fun.uintptr(VPointer))
    else
      result := fun.ptr(fun.uintptr(VInteger))
  ;
{$Else}
  result := fun.ptr(fun.uintptr(PData(val)^.VInteger));
{$EndIf}
end;

procedure setObj(val: PValue; obj: CBase; vt: fun.word);
begin
  if vt = VarObjNew then add(obj);
  clear(val);
  with PData(val)^ do
  begin
    VType    := vt;
    VInt64   := 0;
    VPointer := obj;
  end;
end;

procedure clear(val: PValue);
begin
  //asm
  //  call Variants.@VarClr
  //end;
  with PData(val)^ do
  begin
    if VType = VarObjNew then
    begin
      del(VPointer);
      VType  := VarEmpty;
      VInt64 := 0;
    end;
  end;
end;

// Variant types that own an allocation and therefore must be cleared by the
// RTL before the storage can be reused. Custom Fun objects count because
// VarObjNew is reference counted by setObj/clear above.
function isManagedVar(vt: TVarType): fun.bool;
begin
  result := isStr(vt) or
            (vt = varDispatch) or
            (vt = varVariant) or
            (vt = varUnknown) or
            (vt >= VarObject);
end;

procedure setBool(val: PValue; b: fun.bool);
begin
  if isManagedVar(PData(val)^.VType) then
    // Let the RTL release the old payload.
    val^ := b
  else
  begin
    PData(val)^.VType    := varBoolean;
    PData(val)^.VBoolean := b;
  end;
end;

procedure copyValue(dst, src: PValue);
var
  st, dt: TVarType;
begin
  st := PData(src)^.VType;
  dt := PData(dst)^.VType;
  if (st = varInteger) and ((dt = varInteger) or (dt <= varNull)) then
  begin
    PData(dst)^.VInteger := PData(src)^.VInteger;
    PData(dst)^.VType    := varInteger;
  end
  else if (st = varDouble) and not isManagedVar(dt) then
  begin
    PData(dst)^.VDouble := PData(src)^.VDouble;
    PData(dst)^.VType   := varDouble;
  end
  else if (st = varBoolean) and not isManagedVar(dt) then
  begin
    PData(dst)^.VBoolean := PData(src)^.VBoolean;
    PData(dst)^.VType    := varBoolean;
  end
  else
    // Value Assign
    dst^ := src^;
end;

//==============================================================
// Atomic refcounting uses the fast 32-bit x86 LOCK XADD only where it is
// valid. The inline asm is 32-bit x86 specific, so it is only used on
// genuine 32-bit x86 targets. ARM, AArch64 and every 64-bit target fall
// back to the portable non-atomic path (matching the existing Win64 build,
// which also runs the interpreter single threaded).
{$IfDef ARM}
  {$Define FunNoRefAsm}
{$EndIf}
{$IfDef FPC}
  {$IfDef CPU64}
    {$Define FunNoRefAsm}
  {$EndIf}
{$EndIf}
{$IfDef Win64}
  {$Define FunNoRefAsm}
{$EndIf}

function lockInc(var I: fun.int): fun.int;
{$IfNDef FunNoRefAsm}
asm
      MOV   EDX,1
      XCHG  EAX,EDX
 LOCK XADD  [EDX],EAX
      INC   EAX
{$Else}
begin
  Inc(I);
  result := I;
{$EndIf}
end;

function lockDec(var I: fun.int): fun.int;
{$IfNDef FunNoRefAsm}
asm
      MOV   EDX,-1
      XCHG  EAX,EDX
 LOCK XADD  [EDX],EAX
      DEC   EAX
{$Else}
begin
  Dec(I);
  result := I;
{$EndIf}
end;

//==============================================================
class function CBase.NewInstance: TObject;
begin
  Result := inherited NewInstance;
  CBase(Result).FRefCount := 1;
end;

function CBase.QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE
  ;
end;

function CBase._AddRef: fun.int;
begin
  Result := lockInc(FRefCount);
end;

function CBase._Release: fun.int;
begin
  Result := lockDec(FRefCount);
  if Result <= 0 then Destroy;
end;

//==============================================================
constructor CList.Create(autoDel: fun.bool = true);
begin
  FAutoDel := autoDel;
  inherited Create;
end;

destructor CList.Destroy;
begin
  Clear;
  Size := 0;
  inherited Destroy;
end;

function CList.Add(p: fun.ptr; i: fun.int = -1): fun.int;
begin
  if i < 0 then
    Result := FCount
  else
    Result := i
  ;
  while Result >= Size do Grow;
  List^[Result] := p;
  if FCount <= Result then FCount := Result + 1;
end;

procedure CList.Clear;
var
  i: fun.int;
begin
  for i := count-1 downto 0 do
  begin
    if FAutoDel then del(Item[i]);
  end;
  FCount := 0;
end;

function CList.Contains(p: fun.ptr): fun.bool;
var
  i: fun.int;
begin
  result := false;
  for i := 0 to count-1 do
  begin
    if Item[i] = p then
    begin
      result := true;
      exit;
    end;
  end;
end;

function CList.GetItem(i: fun.int): fun.ptr;
begin
  // Defensive: internal callers index by logical Count, but a raw array read
  // outside it would read heap memory past the list (or the string header).
  if (i < 0) or (i >= FCount) then
    Result := nil
  else
    Result := List^[i]
  ;
end;

// Assigning Count resizes the storage, so a script that grows a list through
// `.@count(n)` cannot leave Count pointing past the allocated buffer. A
// negative count (e.g. popping an empty list) is an error, not a header write.
procedure CList.SetCount(Value: fun.int);
begin
  if Value < 0 then
    raise EBase.Create('list count out of range: ' + IntToStr(Value));
  if Value > FSize then
    Size := Value;   // ReallocMem + zero-fill the new slots
  FCount := Value;
end;

procedure CList.Grow;
begin
  if Size = 0 then
    Size := 16
  else
    Size := Size * 2
  ;
end;

procedure CList.SetSize(Value: fun.int);
var
  P: fun.ptr;
begin
  ReallocMem(List, Value * SizeOf(fun.ptr));
  // Address of the first newly-grown element. Use @List^[FSize] (pure
  // address arithmetic) instead of fun.int(List)+... so the heap pointer is
  // not truncated on 64-bit targets where fun.int is only 32-bit.
  P := @List^[FSize];
  FillChar(P^, (Value-FSize)*SizeOf(fun.ptr), 0);
  FSize := Value;
end;

//==============================================================
destructor CHash.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure CHash.Clear;
  
  procedure Clear(n: PTrieNode);
  var
    p: fun.ptr;
    i: fun.int;
  begin
    if n <> nil then
    begin
      i := n.Index[Max_Char] - 1;
      if i >= 0 then
      begin
        p := n.Items[i];
        n.Items[i] := nil;
        FreeItem(p);
      end;
  
      for i := 0 to Length(n.Items)-1 do
      begin
        Clear(n.Items[i]);
      end;
      SetLength(n.Items, 0);
  
      Dispose(n);
    end;
  end;
  
begin
  Clear(Root);
  Root := nil;
end;

procedure CHash.Each(DoEach: CTrieEach);
  
  procedure Each(n: PTrieNode);
  var
    i, j: fun.int;
  begin
    if n <> nil then
    begin
      i := n.Index[Max_Char] - 1;
      if i >= 0 then
      begin
        DoEach(n.Items[i]);
      end;
  
      for j := 0 to Length(n.Items)-1 do
      begin
        if j <> i then Each(n.Items[j]);
      end;
    end;
  end;
  
begin
  Each(Root);
end;

procedure CHash.EachEx(DoEach: CTrieEachEx; forName: fun.bool = false);
  
  procedure Each(n: PTrieNode; const s: fun.str);
  var
    i, j: fun.int;
  
    function Index: fun.int;
    var
      i: fun.int;
    begin
      result := -1;
      for i := 0 to Length(n.Index) -1 do
      begin
        if n.Index[i] = j + 1 then
        begin
          if forName then
          case i of
             0.. 9: result := i + Ord('0'); // 0-9
            10..36: result := i - 10 + Ord('@'); // 10-36
                37: result := Ord('_');
                38: result := Ord('$');
          end
          else
            result := i;
          ;
          exit;
        end;
      end;
    end;
  
  begin
    if n <> nil then
    begin
      i := n.Index[Max_Char] - 1;
      if i >= 0 then
      begin
        DoEach(n.Items[i], s);
      end;
  
      for j := 0 to Length(n.Items)-1 do
      begin
        if j <> i then Each(n.Items[j], s + fun.char(Index));
      end;
    end;
  end;
  
begin
  Each(Root, '');
end;

function CHash.FindOrAdd(const id: fun.str; p: fun.ptr = nil; isOverwrite: fun.bool = false; isHexId: fun.bool = false): fun.ptr;
var
  i: fun.int;
  n: PTrieNode;
  c: fun.char;
  b, b2: fun.word;
  
  label Find_b;
  
  function AddNode(indx: fun.int; node: fun.ptr): fun.ptr;
  var
    leng: fun.int;
  begin
    leng := Length(n.Items);
    SetLength(n.Items, leng + 1);
    n.Index[indx] :=   leng + 1;
    n.Items[leng] :=   node;
    result        :=   node;
  end;
  
begin
  result := nil;
  if Root = nil then
  begin
    if p = nil then         // Not found
      exit
    else                    // Add
      Root := NewNode
    ;
  end;
  
  n := Root;
  for i := 1 to Length(id) do
  begin
    c  := id[i];
    b2 := 0;
    if isHexId then
      b := Ord(c)
    else
    begin
      case c of
        '0'..'9': b := Ord(c) - Ord('0'); // 0-9
        '@'..'Z': b := Ord(c) - Ord('@') + Ord('9') - Ord('0') + 1; // 10-36
        'a'..'z': b := Ord(c) - Ord('a') + Ord('9') - Ord('0') + 2; // 11-36
        '_'     : b := 37;
        '$'     : b := 38;
        else
        begin
          b  := Max_Char + 1; // [^0-9@-Za-z_$]
          b2 := Ord(c);
        end;
      end;
    end;
  
    Find_b:
  
    if n.Index[b] > 0 then  // Found
      n := n.Items[ n.Index[b] - 1 ]
    else if p = nil then    // Not found
      exit
    else                    // Add
      n := AddNode(b, NewNode)
    ;
  
    if b2 > 0 then          // More than Max_Char
    begin
      b  := b2 mod Max_Char;
      b2 := b2 div Max_Char;
      goto Find_b;
    end;
  end{for};
  
  i := n.Index[Max_Char];
  if i > 0 then             // Found
  begin
    result := n.Items[i - 1];
    if isOverwrite then     // Delete or Replace
    begin
      n.Items[i - 1] := p;
      result         := p;
    end;
  end
  else if p <> nil then     // Add
  begin
    result := AddNode(Max_Char, p);
  end;
end;

procedure CHash.FreeItem(p: fun.ptr);
begin
  del(p);
end;

function CHash.GetItemById(const id: fun.str): fun.ptr;
begin
  result := FindOrAdd(id);
end;

function CHash.NewNode: PTrieNode;
begin
  result := New(PTrieNode);
  FillChar(result^, SizeOf(CTrieNode), 0);
end;

procedure CHash.SetItemById(const id: fun.str; Value: fun.ptr);
begin
  FindOrAdd(id, Value);
end;

//==============================================================
constructor CHist.Create(autoDel: fun.bool = true);
begin
  inherited Create;
  List := CList.Create(autoDel);
end;

destructor CHist.Destroy;
begin
  del(List);
  inherited Destroy;
end;

function CHist.Add(p: fun.ptr): fun.int;
begin
  result := List.Add(p);
end;

procedure CHist.Clear;
begin
  // todo
  //List.Clear;
  inherited Clear;
end;

function CHist.Count: fun.int;
begin
  Result := List.Count;
end;

procedure CHist.FreeItem(p: fun.ptr);
begin
  // no action
end;

function CHist.GetItem(i: fun.int): fun.ptr;
begin
  result := List[i];
end;

function CHist.GetItemById(const id: fun.str): fun.ptr;
begin
  Result := inherited GetItemById(id);
  if result <> nil then
  begin
    result := List[fun.uint(result)-1];
  end;
end;

procedure CHist.SetItem(i: fun.int; Value: fun.ptr);
begin
  List.Add(Value, i);
end;

procedure CHist.SetItemById(const id: fun.str; Value: fun.ptr);
var
  p: fun.ptr;
begin
  p := FindOrAdd(id, fun.ptr(List.Count+1));
  if fun.uint(p) = fun.uint(List.Count+1) then
    List.Add(Value)
  else
    List.List^[fun.uint(p)] := Value
  ;
end;

//==============================================================
constructor CFunStack.Create;
begin
  inherited Create;
  vars  := CList.Create(false);
  start := 1;
end;

destructor CFunStack.Destroy;
begin
  del(vars);
  inherited Destroy;
end;

procedure CFunStack.Pop;
begin
  Dec(level);
  if level >= start then PopVars;
end;

procedure CFunStack.PopVars;
var
  i: fun.int;
  vs: CVarStack;
begin
  for i := 0 to vars.count -1 do
  begin
    vs := CVarStack(vars[i]);
    if vs.level = level - start + 1 then vs.Pop;
  end;
end;

procedure CFunStack.Push;
begin
  Inc(level);
end;

procedure CFunStack.PushVar(avar: CVarStack);
begin
  if (level > start) and (avar.level < level-start) then
  begin
    avar.PushVar;
    if not vars.Contains(avar) then vars.Add(avar);
  end;
end;

//==============================================================
constructor CVarStack.Create(aowner: CFunStack; p: PValue; pp: PPValue);
begin
  inherited Create;
  owner  := aowner;
  Parse(p, pp);
end;

procedure CVarStack.Parse(p: PValue; pp: PPValue);
begin
  p_val  := p;
  pp_val := pp;
end;

procedure CVarStack.Pop;
begin
  Dec(level);
  if level = 0 then
    pp_val^ := p_val
  else
    pp_val^ := @values[level-1]
  ;
end;

procedure CVarStack.Push;
begin
  owner.PushVar(self);
end;

function CVarStack.CanWriteDirect: Boolean;
begin
  // Mirror CFunStack.PushVar: no push is needed when the variable is already
  // at the current scope level.
  result := not ((owner.level > owner.start) and (level < owner.level - owner.start));
end;

function CVarStack.DirectTarget: PValue;
begin
  if CanWriteDirect then
    result := pp_val^
  else
    result := nil;
end;

procedure CVarStack.PushVar;
begin
  Inc(level);
  if Length(values) < level then SetLength(values, level);
  pp_val^ := @values[level-1];
end;


//==============================================================
function funBool(val: PValue): fun.bool;
begin
  if isStr(val) then
    try
      result := fun.bool(val^);
    except
      result := not isNull(val);
    end
  else result := fun.bool(val^);
end;

function isNull(val: PValue): fun.bool;
begin
  with PData(val)^ do
  begin
    if VType <= varNull then
      result := true
    else if VType = varOleStr then
      result := Length(VOleStr) = 0
    else if VType in [varDouble, varCurrency, varDate, varInt64] then
      result := VInt64 = 0
    else
      result := VInteger = 0
    ;
  end;
end;

function isStr(vt: TVarType): fun.bool; overload;
begin
  result := (vt = varOleStr)
         or (vt = varString)
     {$IfDef Unicode}
     {$IfNDef WinCE}
         or (vt = varUString)
     {$EndIf}
     {$EndIf}
         ;
end;

function isStr(val: PValue): fun.bool;
begin
  result := isStr(PData(val).VType);
end;

function isNum(vt: TVarType; all: fun.bool = false): fun.bool;
begin
  result := (vt in
         [  varSmallInt
          , varInteger
          , varBoolean
          , varShortInt
          , varByte
          , varWord
          , varLongWord
          , varInt64
     {$IfDef Unicode}
     {$IfNDef WinCE}
          , varUInt64
     {$EndIf}
     {$EndIf}
         ]) or all and isFloat(vt);
end;

function isNum(val: PValue; all: fun.bool = false): fun.bool;
var
  i: fun.int;
begin
  with PData(val)^ do
  begin
    result := isNum(VType, all);

    if not result then
    begin
      if isStr(VType) and (Length(fun.str(VString)) > 0) then
      begin
        //result := TryStrToInt(val^, i); //BUG: 地 => true
        for i := 1 to Length(fun.str(VString)) do
        begin
          if not (fun.str(VString)[i] in ['0'..'9']) then exit;
        end;
        result := true;
      end;
    end;
  end;
end;

function isFloat(vt: TVarType): fun.bool;
begin
  result := vt in
         [  varSingle
          , varDouble
         ];
end;

function isFloat(val: PValue): fun.bool;
begin
  result := isFloat(PData(val)^.VType);
end;

function isOle(val: PValue): fun.bool;
begin
  result := PData(val).VType = VarDispatch;
end;

function varComp(v1, v2: PValue; isCase: fun.bool): ECompResult;
var
  i: fun.int;
  {$IfDef FPC}
  d1, d2: double;
  {$EndIf}
  a, b: PData;
  anil, bnil: fun.bool;
const
  ECbool: array [fun.bool] of ECompResult = (NE, EQ);
label
  _Else;
begin
  a := PData(v1);
  b := PData(v2);

  // Null
  anil := isNull(v1);
  bnil := isNull(v2);
  if anil and bnil then
    result := EQ
  else if anil and isOle(v2) then
    result := NE
  else if bnil and isOle(v1) then
    result := NE

  // Integer
  else if (a.VType = varInteger) and (b.VType = varInteger) then
  begin
    // Compare directly. Subtracting first overflows int32 whenever the two
    // operands are far apart (e.g. High(Integer) vs -1), which used to
    // reverse the result of <, >, <=, >= and <>.
    if a.VInteger = b.VInteger then
      result := EQ
    else if a.VInteger < b.VInteger then
      result := LT
    else
      result := GT
    ;
  end

  // Double
  else if (a.VType = varDouble) and (b.VType = varDouble) then
  begin
    if a.VDouble = b.VDouble then
      result := EQ
    else if a.VDouble < b.VDouble then
      result := LT
    else
      result := GT
    ;
  end
  else if (a.VType = varInteger) and (b.VType = varDouble) then
  begin
    if a.VInteger = b.VDouble then
      result := EQ
    else if a.VInteger < b.VDouble then
      result := LT
    else
      result := GT
    ;
  end
  else if (a.VType = varDouble) and (b.VType = varInteger) then
  begin
    if a.VDouble = b.VInteger then
      result := EQ
    else if a.VDouble < b.VInteger then
      result := LT
    else
      result := GT
    ;
  end

  // Object
  {$IfDef FPC}
  // FPC does not implement CompareOp for the custom object variant types, so
  // handle every Fun object variant (VarObject AND VarObjNew, e.g. objects
  // built with 'new') here by identity instead of falling through to the
  // generic variant compare (which would raise EVariantError).
  else if (a.VType = VarObject) or (a.VType = VarObjNew) then
    result := ECbool[(a.VType = b.VType) and (a.VPointer = b.VPointer)]
  else if (b.VType = VarObject) or (b.VType = VarObjNew) then
    result := NE
  {$Else}
  else if (a.VType >= VarObject) then
    result := ECbool[(a.VType = b.VType) and (a.VPointer = b.VPointer)]
  else if (b.VType >= VarObject) then
    result := NE
  {$EndIf}

  {$IfDef FPC}
  // Boolean vs number: align with Delphi/COM VarCmp - both operands
  // are coerced to a common numeric type (VARIANT_BOOL True = -1), so
  // the result is symmetric regardless of operand order. FPC generic
  // variant compare converts by operand order instead (true = 1 is
  // False while 1 = true is True).
  else if ((a.VType = varBoolean) and (b.VType in [varInteger, varDouble])) or
          ((a.VType in [varInteger, varDouble]) and (b.VType = varBoolean)) then
  begin
    // NB: do NOT use -ord(x.VBoolean <> false) here - the <> of two
    // WordBool operands stays WordBool and ord(WordBool True) = -1, so
    // -ord(...) evaluates to +1. Plain if/else keeps this obvious.
    if a.VType = varBoolean then
    begin
      if a.VBoolean then d1 := -1 else d1 := 0;
    end
    else if a.VType = varInteger then
      d1 := a.VInteger
    else
      d1 := a.VDouble;
    if b.VType = varBoolean then
    begin
      if b.VBoolean then d2 := -1 else d2 := 0;
    end
    else if b.VType = varInteger then
      d2 := b.VInteger
    else
      d2 := b.VDouble;
    if d1 = d2 then
      result := EQ
    else if d1 < d2 then
      result := LT
    else
      result := GT
    ;
  end
  {$EndIf}

  // String
  else if isStr(a.VType) then
  begin
    if isStr(b.VType) then
    begin
      if isCase then goto _Else;

      i := CompareText(v1^, v2^);
      if i = 0 then
        result := EQ
      else if i < 0 then
        result := LT
      else
        result := GT
      ;
    end
    else if not isNum(v1) then
      result := NE
    else
      goto _Else
    ;
  end
  else if isStr(b.VType) then
  begin
    if not isNum(v2) then
      result := NE
    else
      goto _Else
    ;
  end

  // Else
  else _Else:
  begin
    if v1^ = v2^ then
      result := EQ
    else if v1^ < v2^ then
      result := LT
    else
      result := GT
    ;
  end;
end;

// L = N - 1
//  0 1 2 3 4 5 >> ++ >> L(ast)
// -N << -- << -4 -3 -2 -1
function calcIndex(i, N: fun.int): fun.int;
begin
  if i < 0 then Inc(i, N);
  result := i;
end;

Function NewStringReplace(const S, OldPattern, NewPattern: string;  Flags: TReplaceFlags): string;
var
  OldPat,Srch: string;
  PatLength,NewPatLength,P,i,PatCount,PrevP: Integer;
  c,d: pchar;
begin
  PatLength:=Length(OldPattern);
  if PatLength=0 then begin
    Result:=S;
    exit;
  end;

  if rfIgnoreCase in Flags then begin
    Srch:=UpperCase(S);
    OldPat:=UpperCase(OldPattern);
  end else begin
    Srch:=S;
    OldPat:=OldPattern;
  end;

  PatLength:=Length(OldPat);
  if Length(NewPattern)=PatLength then begin
    Result:=S;
    P:=1;
    repeat
      P:=PosEx(OldPat,Srch,P);
      if P>0 then begin
        for i:=1 to PatLength do
          Result[P+i-1]:=NewPattern[i];
        if not (rfReplaceAll in Flags) then exit;
        inc(P,PatLength);
      end;
    until p=0;
  end else begin
    P:=1; PatCount:=0;
    repeat
      P:=PosEx(OldPat,Srch,P);
      if P>0 then begin
        inc(P,PatLength);
        inc(PatCount);
        if not (rfReplaceAll in Flags) then break;
      end;
    until p=0;
    if PatCount=0 then begin
      Result:=S;
      exit;
    end;
    NewPatLength:=Length(NewPattern);
    SetLength(Result,Length(S)+PatCount*(NewPatLength-PatLength));
    P:=1; PrevP:=0;
    c:=pchar(Result); d:=pchar(S);
    repeat
      P:=PosEx(OldPat,Srch,P);
      if P>0 then begin
        for i:=PrevP+1 to P-1 do begin
          c^:=d^;
          inc(c); inc(d);
        end;
        for i:=1 to NewPatLength do begin
          c^:=NewPattern[i];
          inc(c);
        end;
        if not (rfReplaceAll in Flags) then exit;
        inc(P,PatLength);
        inc(d,PatLength);
        PrevP:=P-1;
      end else begin
        for i:=PrevP+1 to Length(S) do begin
          c^:=d^;
          inc(c); inc(d);
        end;
      end;
    until p=0;
  end;
end;

initialization
  NullValue := Unassigned;

  SetLength(TrueBoolStrs, 2);
  TrueBoolStrs[0] := 'True';
  TrueBoolStrs[1] := 'Yes';
  SetLength(FalseBoolStrs, 3);
  FalseBoolStrs[0] := 'False';
  FalseBoolStrs[1] := 'No';
  FalseBoolStrs[2] := '';

end.
