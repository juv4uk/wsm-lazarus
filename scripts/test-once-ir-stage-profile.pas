{ G6.188 — вимірювання ТІЛЬКИ FPC-механізмів T5M/WideIR без зміни компілятора.
  Профіль: 16 РІЗНИХ фізичних .sens, 3 обходи, перший/повторний
  decode + IR + guard, pinned таблиці заново для КОЖНОГО прикладу.
  Не вимірює backend, process cold start, host-wall чи джоулі.
  Виклики дубльованого IR тут — контрольований експеримент, НЕ
  твердження, що всі компілятори роблять рівно стільки ж роботи.

  Borrowed Path → owned RawByteString; TDomainSet/TWideIR/FPC arrays
  належать одному вимірюваному виклику і виходять зі scope після нього.
  Result: TSV із сирими наносекундами CLOCK_MONOTONIC для незалежного
  агрегатора, жодних .sens/.lisp/ELF файлів не переписує.
  Питання: чому повторне декодування міряємо окремо від першого?
  Чому LoadPinnedDomains виконується заново для КОЖНОЇ програми?
  Чому clock_gettime не дорівнює RAPL? Чому перевіряємо exact IR?
  Чому цей профіль не є доказом швидшого production backend? }
program test_once_ir_stage_profile;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.bind,wsm.wideir,wsm.wideirguard;
type
  EProfileError=class(Exception);
  TTimespec=record
    tv_sec:Int64;
    tv_nsec:Int64;
  end;
function ClockGetTime(ClockId:LongInt;var T:TTimespec):LongInt;
  cdecl;external 'c' name 'clock_gettime';
const
  ClockMonotonic=1;
  Count=16;
  Repeats=3;
procedure Need(Ok:Boolean;const Reason:String);
begin if not Ok then raise EProfileError.Create(Reason) end;
function NowNs:QWord;
var T:TTimespec;
begin
  Need(ClockGetTime(ClockMonotonic,T)=0,'clock_gettime відмовив');
  Need((T.tv_sec>=0) and (T.tv_nsec>=0) and
       (T.tv_nsec<1000000000),'некоректний монотонний час');
  Result:=QWord(T.tv_sec)*1000000000+QWord(T.tv_nsec);
end;
function ReadPhysical(const FileName:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  Need((ExtractFileExt(FileName)='.sens') and (Length(FileName)<=4096),
       'потрібні фізичні .sens');
  F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=65536),'T5M поза квотою');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Порівнюємо повні фізичні вузли без digest/hash-колізії:
  width, bits, parent, child, word, root та provenance.
  Зовнішні managed T5M і IR не змінюємо. }
procedure SameIR(const A,B:TWideIR);
var I:SizeInt;X,Y:TWideIRNode;
begin
  Need((Length(A.Nodes)=Length(B.Nodes)) and
       (Length(A.Roots)=Length(B.Roots)) and
       (A.PhysicalLeaves=B.PhysicalLeaves) and
       (A.OpaqueLeaves=B.OpaqueLeaves),
       'повторний WideIR має інший розмір');
  for I:=0 to High(A.Roots) do
    Need(A.Roots[I]=B.Roots[I],'інший корінь повторного WideIR');
  for I:=0 to High(A.Nodes) do begin
    X:=A.Nodes[I];Y:=B.Nodes[I];
    Need((X.Kind=Y.Kind) and (X.RootIndex=Y.RootIndex) and
         (X.ParentIndex=Y.ParentIndex) and
         (X.ChildIndex=Y.ChildIndex) and (X.Depth=Y.Depth) and
         (X.WordIndex=Y.WordIndex) and (X.OwnWord=Y.OwnWord) and
         (X.Width=Y.Width) and (X.Bits=Y.Bits) and
         (X.HasPinnedKey=Y.HasPinnedKey) and
         (X.NarrowKey.Width=Y.NarrowKey.Width) and
         (X.NarrowKey.Bits=Y.NarrowKey.Bits) and
         (X.Physical.WordIndex=Y.Physical.WordIndex) and
         (X.Physical.TritStart=Y.Physical.TritStart) and
         (X.Physical.TritEnd=Y.Physical.TritEnd) and
         (X.Physical.ByteStart=Y.Physical.ByteStart) and
         (X.Physical.ByteEnd=Y.Physical.ByteEnd) and
         (X.Physical.IsEOF=Y.Physical.IsEOF),
         'повторний IR втратив exact фізичну тотожність');
  end;
end;
procedure RejectInvalid(const Data:RawByteString);
var W:TExactWords;Rejected:Boolean;
begin
  Rejected:=False;
  try
    DecodeT5M(Data,W);
  except on E:Exception do Rejected:=True end;
  Need(Rejected,'неправильний фізичний T5M прийнято');
end;
procedure Run;
var
  Root,Dir,ID,Path:String;
  Bodies:array[1..Count] of RawByteString;
  Tables:TDomainSet;
  W1,W2:TExactWords;
  A,B:TWideIR;
  S1,S2:TWideIRGuardStats;
  T0:QWord;
  DecodeNs,EncodeNs,PinnedNs,IRNs,GuardNs:QWord;
  AgainDecodeNs,AgainIRNs,AgainGuardNs:QWord;
  R,I,J,K:SizeInt;
begin
  Need(ParamCount=2,'параметри: pinned-root каталог-фізичних-форм');
  Root:=ParamStr(1);Dir:=IncludeTrailingPathDelimiter(ParamStr(2));
  for I:=1 to Count do begin
    ID:=Format('%.2d',[I]);
    Path:=Dir+ID+'.sens';
    Bodies[I]:=ReadPhysical(Path);
    for J:=1 to I-1 do
      Need(Bodies[I]<>Bodies[J],'програми для профілю не різні');
  end;
  RejectInvalid('');
  RejectInvalid(#$FF);
  Writeln('trial'#9'id'#9'bytes'#9'first_decode_ns'#9'canonical_encode_ns'#9+
          'pinned_domains_ns'#9'first_wideir_ns'#9'first_guard_ns'#9+
          'redecode_ns'#9'rebuild_wideir_ns'#9'reverify_guard_ns');
  for R:=1 to Repeats do
    for K:=1 to Count do begin
      if (R mod 2)=1 then I:=K else I:=Count+1-K;
      ID:=Format('%.2d',[I]);
      T0:=NowNs;
      DecodeT5M(Bodies[I],W1);
      DecodeNs:=NowNs-T0;
      T0:=NowNs;
      Need(EncodeT5M(W1)=Bodies[I],'неканонічний T5M');
      EncodeNs:=NowNs-T0;
      T0:=NowNs;
      LoadPinnedDomains(RawByteString(Root),Tables);
      PinnedNs:=NowNs-T0;
      T0:=NowNs;
      BuildWideIR(Bodies[I],Tables,A);
      IRNs:=NowNs-T0;
      T0:=NowNs;
      VerifyWideIRStructure(A,S1);
      GuardNs:=NowNs-T0;
      T0:=NowNs;
      DecodeT5M(Bodies[I],W2);
      Need(EncodeT5M(W2)=Bodies[I],'декодування 2 відхилило T5M');
      AgainDecodeNs:=NowNs-T0;
      Need(Length(W1)=Length(W2),'повторний декодер втратив слова');
      for J:=0 to High(W1) do
        Need(W1[J]=W2[J],'підміна exact слова у повторному декодері');
      T0:=NowNs;
      BuildWideIR(Bodies[I],Tables,B);
      AgainIRNs:=NowNs-T0;
      T0:=NowNs;
      VerifyWideIRStructure(B,S2);
      AgainGuardNs:=NowNs-T0;
      Need((S1.Nodes=S2.Nodes) and (S1.Roots=S2.Roots) and
           (S1.PhysicalLeaves=S2.PhysicalLeaves) and
           (S1.OpaqueLeaves=S2.OpaqueLeaves) and
           (S1.MaxDepth=S2.MaxDepth),
           'повторна структурна перевірка дала інший доказ');
      SameIR(A,B);
      Writeln(R,#9,ID,#9,Length(Bodies[I]),#9,
              DecodeNs,#9,EncodeNs,#9,PinnedNs,#9,IRNs,#9,GuardNs,#9,
              AgainDecodeNs,#9,AgainIRNs,#9,AgainGuardNs);
    end;
end;
begin
  try Run
  except on E:Exception do begin
    Writeln(StdErr,'ЕТАПИ-T5M-WIDEIR-ВІДМОВА: ',E.Message);
    Halt(2);
  end end;
end.
