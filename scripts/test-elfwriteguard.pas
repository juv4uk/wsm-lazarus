{ G6.145 — прямі негативи машинної рамки, не семантичний oracle.
  Справжній pinned D6 виклик компілює чинний BuildIRWideNegELF;
  псування відбувається ЛИШЕ в одноразових тестових ELF байтах. }
program test_elfwriteguard;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwideneg,wsm.elfwriteguard,wsm.elfgeometry;
const ExitOld:RawByteString=#$B8#$3C#0#0#0#$31#$FF#$0F#$05;
var F:TFileStream;Physical,Original,Safe,Bad,Snapshot:RawByteString;
    G:TELFGeometry;At,I,N:SizeInt;Negative:Integer;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create(Why) end;
procedure SetLE64(var S:RawByteString;At0:SizeInt;V:QWord);
var K:Integer;
begin for K:=0 to 7 do begin
  S[At0+K+1]:=AnsiChar(Byte(V and $FF));V:=V shr 8;
end end;
{ Candidate — короткоживучий managed фізичний ELF-клон, не .sens.
  Перевірка відмови не змінює Original і не створює файл.
  1) Навіщо псувати ELF після pinned admission?
  2) Чому невідомий machine epilogue — відмова, а не fallback?
  3) Де звільняється Candidate після винятку? }
procedure Reject(const Candidate:RawByteString);
var V:RawByteString;
begin
  try V:=RequireCompleteNativeWrite(Candidate)
  except on E:Exception do begin Inc(Negative);Exit end end;
  raise Exception.Create('неприпустимий machine ELF було прийнято: '+
     IntToStr(Length(V)));
end;
begin
  try
    Need(ParamCount=1,'потрібен канонічний D6 .sens вхід');
    F:=TFileStream.Create(ParamStr(1),fmOpenRead or fmShareDenyWrite);
    try
      Need((F.Size>0) and (F.Size<8192),'джерело поза host квотою');
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free end;
    Original:=BuildIRWideNegELF(Physical,'external/sens');
    Snapshot:=Copy(Original,1,Length(Original));
    Safe:=RequireCompleteNativeWrite(Original);
    Need(Original=Snapshot,'пошкоджено позичений донор');
    VerifySENSELF64(Safe,G);
    Need((G.Kind=3) and (G.FileBytes=Length(Safe)) and
      (Length(Safe)=Length(Original)+11),
      'guard не зберіг verified ELF64');
    At:=0;N:=0;
    for I:=121 to Length(Original)-8 do
      if Copy(Original,I,9)=ExitOld then begin
        Inc(N);At:=I;
      end;
    Need((N=1) and (At>122),'немає унікального донорського epilogue');
    Negative:=0;
    Bad:=Copy(Original,1,Length(Original));
    Bad[At]:=#$90;
    Reject(Bad);
    Bad:=Copy(Original,1,Length(Original));
    Bad[At-1]:=#$90;
    Reject(Bad);
    Bad:=Original+ExitOld;
    SetLE64(Bad,96,Length(Bad));
    SetLE64(Bad,104,Length(Bad));
    Reject(Bad);
    Need(Negative=3,'не всі відмови machine guard');
    Need(Original=Snapshot,'пошкоджено оригінал після негативів');
    WriteLn('G6.145-WRITE-GUARD-UNIT-OK negative=3 owned=verified immutable=yes');
  except on E:Exception do begin
    WriteLn(StdErr,'G6.145-WRITE-GUARD-UNIT-FAIL: ',E.Message);Halt(1);
  end end;
end.
