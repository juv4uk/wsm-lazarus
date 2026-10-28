{ G4.6 — структурний опис фізичного pinned Core4, без виконання.
  Єдиний авторитет — external/sens, лексичні дані не є законом. }
unit wsm.core4manifest;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  ECore4ManifestError=class(Exception);
function Core4Manifest(const RepoRoot:string):RawByteString;
implementation
uses wsm.core4source, wsm.source;
function Core4Manifest(const RepoRoot:string):RawByteString;
var
  Physical, OutText:RawByteString;
  Doc:TSourceDocument;
  I:SizeInt;
  C:LongWord;
  J:SizeInt;
  KindText:RawByteString;
begin
  Result:='';
  Doc:=nil;
  Physical:=ReadPinnedCore4(RepoRoot);
  { Strict upstream-file UTF-8 admission using existing structural reader. }
  Doc:=ReadUkrainianSource(Physical);
  try
    if Length(Doc.Forms)=0 then
      raise ECore4ManifestError.Create('порожній структурний Core4');
    { FNV-1a32 — повторювана контрольна сума випадкової зміни, не security. }
    C:=2166136261;
    for J:=1 to Length(Physical) do
      C:=(C xor Ord(Physical[J]))*LongWord(16777619);
    OutText:='CORE4-ОПИС-ГАРАЗД байтів='+IntToStr(Length(Physical))+
      ' форм='+IntToStr(Length(Doc.Forms))+
      ' fnv1a32='+IntToHex(C,8)+' виконання=ні'+#10;
    for I:=0 to High(Doc.Forms) do begin
      case Doc.Forms[I].Kind of
        skList: KindText:='список';
        skAtom: KindText:='атом';
        skString: KindText:='рядок';
      end;
      OutText:=OutText+'форма='+IntToStr(I+1)+
        ' вид='+KindText+
        ' байт='+IntToStr(Doc.Forms[I].ByteOffset)+
        ' рядок='+IntToStr(Doc.Forms[I].Line)+
        ' колонка-байт='+IntToStr(Doc.Forms[I].ByteColumn)+
        ' дітей='+IntToStr(Length(Doc.Forms[I].Children))+#10;
    end;
    Result:=OutText;
  finally Doc.Free end;
end;
end.
