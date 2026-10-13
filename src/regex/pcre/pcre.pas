unit pcre;

interface

type
  CPcreOptions = set of (
    preCaseLess,       // /i -> Case insensitive
    preMultiLine,      // /m -> ^ and $ also match before/after a newline, not just at the beginning and the end of the PCREString
    preSingleLine,     // /s -> Dot matches any character, including \n (newline). Otherwise, it matches anything except \n
    preExtended,       // /x -> Allow regex to contain extra whitespace, newlines and Perl-style comments, all of which will be filtered out
    preAnchored,       // /A -> Successful match can only occur at the start of the subject or right after the previous match
    preUnGreedy,       // Repeat operators (+, *, ?) are not greedy by default (i.e. they try to match the minimum number of characters instead of the maximum)
    preNoAutoCapture,  // (group) is a non-capturing group; only named groups capture
    preUTF8
  );

type
  CPcreState = set of (
    preNotBOL,         // Not Beginning Of Line: ^ does not match at the start of Subject
    preNotEOL,         // Not End Of Line: $ does not match at the end of Subject
    preNotEmpty        // Empty matches not allowed
  );

const
  MAX_GROUPS = 99;

{$IFDEF UNICODE}
{$WARN IMPLICIT_STRING_CAST OFF}
type
  PCREString = UTF8String;
{$ELSE UNICODE}
type
  PCREString = AnsiString;
{$ENDIF UNICODE}

type
  CPcreAction = function (Sender: TObject): string of object;

type
  CPcre = class
  private
    FCompiled: Boolean;
    FPattern, FReplacement, FSubject: PCREString;
    FOptions: CPcreOptions;
    FPcreAction: CPcreAction;
    FActionTag: Pointer;
    FState: CPcreState;
    FStop, LastOffset: Integer;
    function GetMatched: PCREString;
    function GetMatchedLength: Integer;
    function GetMatchedOffset: Integer;
    function GetGroupCount: Integer;
    function GetGroups(Index: Integer): PCREString;
    function GetGroupLengths(Index: Integer): Integer;
    function GetGroupOffsets(Index: Integer): Integer;
    function GetSuccess: Boolean;
    procedure SetSubject(const Value: PCREString);
    procedure SetPattern(const Value: PCREString);
    procedure SetOptions(Value: CPcreOptions);
    procedure SetStart(const Value: Integer);
    procedure SetStop(const Value: Integer);
  public
    FStart: Integer;
    Offsets: array[0..(MAX_GROUPS+1)*3] of Integer;
  private
    OffsetCount: Integer;
    pcreOptions: Integer;
    pregex, hints, chartable: Pointer;
    FSubjectPChar: PAnsiChar;
  protected
    procedure CleanUp;
    property Start: Integer read FStart write SetStart;
    property Stop: Integer read FStop write SetStop;
    property State: CPcreState read FState write FState;
  public
    constructor Create();
    destructor Destroy; override;
    class function EscapePatternChars(const S: string): string;
  public
    procedure Compile;
    function Match: Boolean;
    function MatchOne: PCREString;
    function MatchAll: PCREString;
    function Replace: PCREString;
    function ReplaceAll: Boolean;
    function ComputeReplacement: PCREString;
    function NamedGroup(const Name: PCREString): Integer;
    function SubjectLeft: PCREString;
    function SubjectRight: PCREString;
    property Compiled: Boolean read FCompiled;
    property Success: Boolean read GetSuccess;
    property Matched: PCREString read GetMatched;
    property MatchedLength: Integer read GetMatchedLength;
    property MatchedOffset: Integer read GetMatchedOffset;
    property GroupCount: Integer read GetGroupCount;
    property Groups[Index: Integer]: PCREString read GetGroups;
    property GroupLengths[Index: Integer]: Integer read GetGroupLengths;
    property GroupOffsets[Index: Integer]: Integer read GetGroupOffsets;
  public
    property Subject: PCREString read FSubject write SetSubject;
    property Pattern: PCREString read FPattern write SetPattern;
    property Options: CPcreOptions read FOptions write SetOptions;
    property Replacement: PCREString read FReplacement write FReplacement;
    property PcreAction: CPcreAction read FPcreAction write FPcreAction;
    property ActionTag: Pointer read FActionTag write FActionTag;
  end;


implementation

uses SysUtils, {$IfNDef UNIX}Windows, {$ENDIF}
     pcrd;

function FirstCap(const S: string): string;
begin
{$IfNDef UNIX}
  if S = '' then Result := ''
  else begin
    Result := AnsiLowerCase(S);
  {$IFDEF UNICODE}
    CharUpperBuffW(@Result[1], 1);
  {$ELSE}
    CharUpperBuffA(@Result[1], 1);
  {$ENDIF}
  end
{$EndIf}
end;

function InitialCaps(const S: string): string;
var
  I: Integer;
  Up: Boolean;
begin
{$IfNDef UNIX}
  Result := AnsiLowerCase(S);
  Up := True;
{$IFDEF UNICODE}
  for I := 1 to Length(Result) do begin
    case Result[I] of
      #0..'&', '(', '*', '+', ',', '-', '.', '?', '<', '[', '{', #$00B7:
        Up := True
      else
        if Up and (Result[I] <> '''') then begin
          CharUpperBuffW(@Result[I], 1);
          Up := False
        end
    end;
  end;
{$ELSE UNICODE}
  if SysLocale.FarEast then begin
    I := 1;
    while I <= Length(Result) do begin
      if Result[I] in LeadBytes then begin
        Inc(I, 2)
      end
      else begin
        if Result[I] in [#0..'&', '('..'.', '?', '<', '[', '{'] then Up := True
        else if Up and (Result[I] <> '''') then begin
          CharUpperBuffA(@Result[I], 1);
          Result[I] := UpperCase(Result[I])[1];
          Up := False
        end;
        Inc(I)
      end
    end
  end
  else
    for I := 1 to Length(Result) do begin
      if Result[I] in [#0..'&', '('..'.', '?', '<', '[', '{', #$B7] then Up := True
      else if Up and (Result[I] <> '''') then begin
        CharUpperBuffA(@Result[I], 1);
        Result[I] := AnsiUpperCase(Result[I])[1];
        Up := False
      end
    end;
{$ENDIF UNICODE}
{$EndIf}
end;


procedure CPcre.CleanUp;
begin
  FCompiled := False;
  CallPCREFree(pregex);
  pregex := nil;
  hints := nil;
  OffsetCount := 0;
end;

procedure CPcre.Compile;
var
  Error: PAnsiChar;
  ErrorOffset: Integer;
begin
  if FPattern = '' then
    raise Exception.Create('RE Compile() - Please specify a regular expression in Pattern first');
  CleanUp;
  pregex := pcre_compile(PAnsiChar(FPattern), pcreOptions, @Error, @ErrorOffset, chartable);
  if pregex = nil then
    raise Exception.Create(Format('RE Compile() - Error in regex at offset %d: %s', [ErrorOffset, AnsiString(Error)]));
  FCompiled := True
end;

(* Backreference overview:

Assume there are 13 backreferences:

Text        CPcre         .NET      Java       ECMAScript
$17         $1 + "7"      "$17"     $1 + "7"   $1 + "7"
$017        $1 + "7"      "$017"    $1 + "7"   $1 + "7"
$12         $12           $12       $12        $12
$012        $1 + "2"      $12       $12        $1 + "2"
${1}2       $1 + "2"      $1 + "2"  error      "${1}2"
$$          "$"           "$"       error      "$"
\$          "$"           "\$"      "$"        "\$"
*)

function CPcre.ComputeReplacement: PCREString;
var
  Mode: AnsiChar;
  S: PCREString;
  I, J, N: Integer;

  procedure ReplaceBackreference(Number: Integer);
  var
    Backreference: PCREString;
  begin
    Delete(S, I, J-I);
    if Number <= GroupCount then begin
      Backreference := Groups[Number];
      if Backreference <> '' then begin
        // Ignore warnings; converting to UTF-8 does not cause data loss
        case Mode of
          'L', 'l': Backreference := AnsiLowerCase(Backreference);
          'U', 'u': Backreference := AnsiUpperCase(Backreference);
          'F', 'f': Backreference := FirstCap(Backreference);
          'I', 'i': Backreference := InitialCaps(Backreference);
        end;
        if S <> '' then begin
          Insert(Backreference, S, I);
          I := I + Length(Backreference);
        end
        else begin
          S := Backreference;
          I := MaxInt;
        end
      end;
    end
  end;

  procedure ProcessBackreference(NumberOnly, Dollar: Boolean);
  var
    Number, Number2: Integer;
    Group: PCREString;
  begin
    Number := -1;
    if (J <= Length(S)) and (S[J] in ['0'..'9']) then begin
      // Get the number of the backreference
      Number := Ord(S[J]) - Ord('0');
      Inc(J);
      if (J <= Length(S)) and (S[J] in ['0'..'9']) then begin
        // Expand it to two digits only if that would lead to a valid backreference
        Number2 := Number*10 + Ord(S[J]) - Ord('0');
        if Number2 <= GroupCount then begin
          Number := Number2;
          Inc(J)
        end;
      end;
    end
    else if not NumberOnly then begin
      if Dollar and (J < Length(S)) and (S[J] = '{') then begin
        // Number or name in curly braces
        Inc(J);
        case S[J] of
          '0'..'9': begin
            Number := Ord(S[J]) - Ord('0');
            Inc(J);
            while (J <= Length(S)) and (S[J] in ['0'..'9']) do begin
              Number := Number*10 + Ord(S[J]) - Ord('0');
              Inc(J)
            end;
          end;
          'A'..'Z', 'a'..'z', '_': begin
            Inc(J);
            while (J <= Length(S)) and (S[J] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(J);
            if (J <= Length(S)) and (S[J] = '}') then begin
              Group := Copy(S, I+2, J-I-2);
              Number := NamedGroup(Group);
            end
          end;
        end;
        if (J > Length(S)) or (S[J] <> '}') then Number := -1
          else Inc(J)
      end
      else if Dollar and (S[J] = '_') then begin
        // $_ (whole subject)
        Delete(S, I, J+1-I);
        Insert(Subject, S, I);
        I := I + Length(Subject);
        Exit;
      end
      else case S[J] of
        '&': begin
          // \& or $& (whole regex match)
          Number := 0;
          Inc(J);
        end;
        '+': begin
          // \+ or $+ (highest-numbered participating group)
          Number := GroupCount;
          Inc(J);
        end;
        '`': begin
          // \` or $` (backtick; subject to the left of the match)
          Delete(S, I, J+1-I);
          Insert(SubjectLeft, S, I);
          I := I + Offsets[0] - 1;
          Exit;
        end;
        '''': begin
          // \' or $' (straight quote; subject to the right of the match)
          Delete(S, I, J+1-I);
          Insert(SubjectRight, S, I);
          I := I + Length(Subject) - Offsets[1];
          Exit;
        end
      end;
    end;
    if Number >= 0 then ReplaceBackreference(Number)
      else Inc(I)
  end;

begin
  S := FReplacement;
  I := 1;
  while I < Length(S) do begin
    case S[I] of
      '\': begin
        J := I + 1;
        case S[J] of
          '$', '\': begin
            Delete(S, I, 1);
            Inc(I);
          end;
          'g': begin
            if (J < Length(S)-1) and (S[J+1] = '<') and (S[J+2] in ['A'..'Z', 'a'..'z', '_']) then begin
              // Python-style named group reference \g<name>
              J := J+3;
              while (J <= Length(S)) and (S[J] in ['0'..'9', 'A'..'Z', 'a'..'z', '_']) do Inc(J);
              if (J <= Length(S)) and (S[J] = '>') then begin
                N := NamedGroup(Copy(S, I+3, J-I-3));
                Inc(J);
                Mode := #0;
                if N > 0 then ReplaceBackreference(N)
                  else Delete(S, I, J-I)
              end
              else I := J
            end
            else I := I+2;
          end;
          'l', 'L', 'u', 'U', 'f', 'F', 'i', 'I': begin
            Mode := S[J];
            Inc(J);
            ProcessBackreference(True, False);
          end;
          else begin
            Mode := #0;
            ProcessBackreference(False, False);
          end;
        end;
      end;
      '$': begin
        J := I + 1;
        if S[J] = '$' then begin
          Delete(S, J, 1);
          Inc(I);
        end
        else begin
          Mode := #0;
          ProcessBackreference(False, True);
        end
      end;
      else Inc(I)
    end
  end;
  Result := S
end;

constructor CPcre.Create();
begin
  inherited Create();
  // fix bug - /(?<=\d)(?=(?:\d{1})+$)/g @ 2011-06-21
  //FState := [preNotEmpty];
  FState := [];
  // too slow so comment it @ 2010-12-28
  //chartable := pcre_maketables;
// backtracking too slow in UTF8 so use Regex_UTF8 @ 2010-12-29
//{$IFDEF UNICODE}
{$IFDEF Regex_UTF8}
  pcreOptions := PCRE_UTF8 or PCRE_NO_UTF8_CHECK or PCRE_NEWLINE_ANY;
{$ELSE}
  pcreOptions := PCRE_NEWLINE_ANY;
{$ENDIF}
end;

destructor CPcre.Destroy;
begin
  CallPCREFree(pregex);
  inherited Destroy;
end;

class function CPcre.EscapePatternChars(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  I := Length(Result);
  while I > 0 do begin
    case Result[I] of
      '.', '[', ']', '(', ')', '?', '*', '+', '{', '}', '^', '$', '|', '\':
        Insert('\', Result, I);
      #0: begin
        Result[I] := '0';
        Insert('\', Result, I);
      end;
    end;
    Dec(I);
  end;
end;

function CPcre.GetSuccess: Boolean;
begin
  Result := OffsetCount > 0;
end;

function CPcre.GetMatched: PCREString;
begin
  Result := GetGroups(0);
end;

function CPcre.GetMatchedLength: Integer;
begin
  Result := GetGroupLengths(0)
end;

function CPcre.GetMatchedOffset: Integer;
begin
  Result := GetGroupOffsets(0)
end;

function CPcre.GetGroupCount: Integer;
begin
  Result := OffsetCount
end;

function CPcre.GetGroupLengths(Index: Integer): Integer;
begin
  Result := Offsets[Index*2+1]-Offsets[Index*2]
end;

function CPcre.GetGroupOffsets(Index: Integer): Integer;
begin
  Result := Offsets[Index*2]
end;

function CPcre.GetGroups(Index: Integer): PCREString;
begin
  if Index > GroupCount then Result := ''
    else Result := Copy(FSubject, Offsets[Index*2], Offsets[Index*2+1]-Offsets[Index*2]);
end;

function CPcre.SubjectLeft: PCREString;
begin
  if not Success then
    Result := Copy(Subject, LastOffset, MaxInt)
  else
    Result := Copy(Subject, LastOffset, Offsets[0]-LastOffset)
  ;
end;

function CPcre.SubjectRight: PCREString;
begin
  Result := Copy(Subject, Offsets[1], MaxInt);
end;

function CPcre.Match: Boolean;
var
  I, Opts: Integer;
begin
  if FStart > 1 then LastOffset := FStart;
  
  if not Compiled then Compile;
  if preNotBOL in State then Opts := PCRE_NOTBOL else Opts := 0;
  if preNotEOL in State then Opts := Opts or PCRE_NOTEOL;
  if preNotEmpty in State then Opts := Opts or PCRE_NOTEMPTY;
  if FStart-1 > FStop then OffsetCount := -1
    else OffsetCount := pcre_exec(pregex, hints, FSubjectPChar, FStop, FStart-1, Opts, @Offsets[0], High(Offsets));
  Result := OffsetCount > 0;
  // Convert offsets into PCREString indices
  if Result then begin
    for I := 0 to OffsetCount*2-1 do
      Inc(Offsets[I]);
    FStart := Offsets[1];
    if Offsets[0] = Offsets[1] then Inc(FStart); // Make sure we don't get stuck at the same position
  end;
end;

function CPcre.MatchOne: PCREString;
begin
  Result := '';
  if Match then
  begin
    if Assigned(FPcreAction) then
      Result := FPcreAction(FActionTag)
    else
      Result := Matched
    ;
  end;
end;

function CPcre.MatchAll: PCREString;
begin
  Result := '';
  repeat
    Result := Result + MatchOne;
  until not Success;
end;

function CPcre.NamedGroup(const Name: PCREString): Integer;
begin
  Result := pcre_get_stringnumber(pregex, PAnsiChar(Name));
end;

function CPcre.Replace: PCREString;
var
  moff, mlen, rlen, len: Integer;
  d, s, d2, s2: Pointer;
begin
  // Substitute backreferences
  {$IfDef FPC}
  // FSubject may share its buffer with the caller's string value: FPC's
  // Variant -> AnsiString conversion returns the Variant's own buffer. The
  // in-place branches below write through raw pointers, which bypass
  // reference-counted copy-on-write, so force a private buffer first; otherwise
  // `b := a.replace(re, shorter)` also mutates `a`. Delphi's conversion hands
  // back a fresh string, so the original path is left untouched there.
  UniqueString(FSubject);
  {$EndIf FPC}
  if Assigned(FPcreAction) then
    Result := FPcreAction(FActionTag)
  else
    Result := ComputeReplacement
  ;
  
  // Perform substitution
  moff := MatchedOffset;
  mlen := MatchedLength;
  rlen := Length(Result);
  if (rlen = 0) and (mlen = 0) then // 无 -> 无
    // None
  else if rlen = 0 then             // 有 -> 无
    Delete(FSubject, moff, mlen)
  else if mlen = 0 then             // 无 -> 有
    Insert(Result, FSubject, moff)
  else begin                        // 有 -> 有
    d := @FSubject[moff];
    s := @Result[1];
    if rlen = mlen then             //    -> 等
      Move(s^, d^, mlen)
    else begin
      len := Length(FSubject);
      if rlen < mlen then begin     //    -> 短
        d2 := @FSubject[moff+rlen];
        s2 := @FSubject[moff+mlen];
        Move(s^ , d^ , rlen);
        Move(s2^, d2^, len-moff-mlen+1);
        SetLength(FSubject, len+rlen-mlen);
      end else begin                //    -> 长
        SetLength(FSubject, len+rlen-mlen);
        d2 := @FSubject[moff+rlen];
        s2 := @FSubject[moff+mlen];
        d  := @FSubject[moff];
        Move(s2^, d2^, len-moff-mlen+1);
        Move(s^ , d^ , rlen);
      end;
    end;
  end;
  
  FSubjectPChar := PAnsiChar(FSubject);
  // Position to continue search
  FStart := FStart - mlen + rlen;
  FStop := FStop - mlen + rlen;
  // Replacement no longer matches regex, we assume
  OffsetCount := 0;
end;

function CPcre.ReplaceAll: Boolean;
begin
  if Match then begin
    Result := True;
    repeat
      Replace
    until not Match;
  end
  else Result := False;
end;

procedure CPcre.SetOptions(Value: CPcreOptions);
begin
  if (FOptions <> Value) then begin
    FOptions := Value;
  // backtracking too slow in UTF8 so use Regex_UTF8 @ 2010-12-29
  //{$IFDEF UNICODE}
  {$IFDEF Regex_UTF8}
    pcreOptions := PCRE_UTF8 or PCRE_NO_UTF8_CHECK or PCRE_NEWLINE_ANY;
  {$ELSE}
    pcreOptions := PCRE_NEWLINE_ANY;
  {$ENDIF}
    if (preCaseLess in Value) then pcreOptions := pcreOptions or PCRE_CASELESS;
    if (preMultiLine in Value) then pcreOptions := pcreOptions or PCRE_MULTILINE;
    if (preSingleLine in Value) then pcreOptions := pcreOptions or PCRE_DOTALL;
    if (preExtended in Value) then pcreOptions := pcreOptions or PCRE_EXTENDED;
    if (preAnchored in Value) then pcreOptions := pcreOptions or PCRE_ANCHORED;
    if (preUnGreedy in Value) then pcreOptions := pcreOptions or PCRE_UNGREEDY;
    if (preNoAutoCapture in Value) then pcreOptions := pcreOptions or PCRE_NO_AUTO_CAPTURE;
    if (preUTF8 in Value) then pcreOptions := pcreOptions or PCRE_UTF8 or PCRE_NO_UTF8_CHECK;
    CleanUp
  end
end;

procedure CPcre.SetPattern(const Value: PCREString);
begin
  if FPattern <> Value then begin
    FPattern := Value;
    CleanUp
  end
end;

procedure CPcre.SetStart(const Value: Integer);
begin
  if Value < 1 then FStart := 1
  else FStart := Value;
  // If FStart > Length(Subject), MatchAgain() will simply return False
end;

procedure CPcre.SetStop(const Value: Integer);
begin
  if Value > Length(Subject) then FStop := Length(Subject)
    else FStop := Value;
end;

procedure CPcre.SetSubject(const Value: PCREString);
begin
  FSubject := Value;
  FSubjectPChar := PAnsiChar(Value);
  FStart := 1;
  FStop := Length(Subject);
  OffsetCount := 0;
  LastOffset  := 1;
end;


end.
