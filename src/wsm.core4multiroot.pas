{ G4.34 — кілька фізичних D2-коренів із повними складеними відповідями.
  Немає нового обчислювача: закони виконує лише pinned TCore4Runtime. }
unit wsm.core4multiroot;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.core4runtime;
type ECore4MultiRootError=class(Exception);
function ExecuteCore4Roots(Runtime:TCore4Runtime;
  const Physical:RawByteString):RawByteString;
implementation
uses wsm.t5m, wsm.d2source, wsm.physloc;
const MaxRoots=64;

function SourcePosition(const Physical:RawByteString;
  const Spans:TPhysicalWordSpans; Word:SizeInt):String;
var At:TPhysicalWordSpan;
begin
  At:=LocatePhysicalWord(Physical,Spans,Word);
  Result:='слово='+IntToStr(At.WordIndex)+
    ' трити=['+IntToStr(At.TritStart)+','+IntToStr(At.TritEnd)+
    ') байти=['+IntToStr(At.ByteStart)+','+IntToStr(At.ByteEnd)+')';
  if At.IsEOF then Result:=Result+' EOF=так'
  else Result:=Result+' EOF=ні';
end;

{ Physical — позичені канонічні байти T5M; Runtime — позичене
  довгоживуче середовище pinned Core4. Вихід — новий RawByteString:
  усі фізичні результати як незалежні D2-корені. Жодна часткова
  відповідь не публікується; тимчасові TD2Document звільняються.
  Один D2-список не можна сплющувати до атома або вгадувати як число. }
function ExecuteCore4Roots(Runtime:TCore4Runtime;
  const Physical:RawByteString):RawByteString;
var
  SourceWords,Part,ResponseWords,AllWords:TExactWords;
  Spans:TPhysicalWordSpans;
  SourceDoc,ReplyDoc:TD2Document;
  First,Finish,I,J,OldSize:SizeInt;
  ReplyPhysical:RawByteString;
begin
  Result:='';SourceDoc:=nil;ReplyDoc:=nil;AllWords:=nil;
  if Runtime=nil then
    raise ECore4MultiRootError.Create('відсутнє середовище pinned Core4');
  if (Length(Physical)<1) or (Length(Physical)>MAX_T5M_FILE_BYTES) then
    raise ECore4MultiRootError.Create('фізичне джерело поза межею T5M');
  DecodeT5MWithLocations(Physical,SourceWords,Spans);
  if EncodeT5M(SourceWords)<>Physical then
    raise ECore4MultiRootError.Create('неканонічний фізичний потік');
  try
    SourceDoc:=ParseD2WordsWide(SourceWords);
  except
    on E:ED2SourceError do
      raise ECore4MultiRootError.Create(
        'вхід D2: '+SourcePosition(Physical,Spans,E.WordIndex)+' '+E.Message);
  end;
  try
    if (Length(SourceDoc.Roots)<1) or (Length(SourceDoc.Roots)>MaxRoots) then
      raise ECore4MultiRootError.Create('дозволено 1..64 фізичні форми');
    for I:=0 to High(SourceDoc.Roots) do begin
      First:=SourceDoc.Roots[I].WordIndex-1;
      Finish:=SourceDoc.Roots[I].EndWordIndexExclusive-1;
      if (First<0) or (Finish<=First) or (Finish>Length(SourceWords)) then
        raise ECore4MultiRootError.Create('пошкоджено межі D2-кореня');
      SetLength(Part,Finish-First);
      for J:=0 to High(Part) do Part[J]:=SourceWords[First+J];
      try
        ReplyPhysical:=Runtime.ExecutePhysicalCall(EncodeT5M(Part));
        DecodeT5M(ReplyPhysical,ResponseWords);
        if (Length(ResponseWords)=0) or
           (EncodeT5M(ResponseWords)<>ReplyPhysical) then
          raise ECore4MultiRootError.Create('неканонічна відповідь Core4');
        ReplyDoc:=ParseD2WordsWide(ResponseWords);
        try
          if Length(ReplyDoc.Roots)<>1 then
            raise ECore4MultiRootError.Create('Core4 повернув не один D2-корінь');
        finally FreeAndNil(ReplyDoc) end;
        OldSize:=Length(AllWords);
        if Length(ResponseWords)>MaxD2Words-OldSize then
          raise ECore4MultiRootError.Create('сукупна відповідь перевищила межу D2');
        SetLength(AllWords,OldSize+Length(ResponseWords));
        for J:=0 to High(ResponseWords) do AllWords[OldSize+J]:=ResponseWords[J];
      except
        on E:Exception do
          raise ECore4MultiRootError.Create(
            'форма='+IntToStr(I+1)+' '+
            SourcePosition(Physical,Spans,SourceDoc.Roots[I].WordIndex)+
            ' '+E.Message);
      end;
    end;
    Result:=EncodeT5M(AllWords);
    if Length(Result)>MAX_T5M_FILE_BYTES then
      raise ECore4MultiRootError.Create('фізична відповідь поза межею T5M');
  finally SourceDoc.Free end;
end;
end.
