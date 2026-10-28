{ G4.7: атомарне виділення top-level форм pinned Core4.
  Це механічні UTF-8 зрізи української .lisp-проєкції, не SENS evaluator.
  Вхід — тільки вже зафіксований файл external/sens/lib/core4.lisp. }
unit wsm.core4slice;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  ECore4SliceError = class(Exception);
  TCore4SourceSlice = record
    { 1-based байтова адреса початку, напіввідкрита кінцева адреса. }
    StartByte, EndByteExclusive: SizeInt;
    Source: RawByteString;
  end;
  TCore4SourceSlices = array of TCore4SourceSlice;
  TCore4SourcePackage = record
    { Коментарі/пропуски до першої форми збережено без змін. }
    Prefix: RawByteString;
    Forms: TCore4SourceSlices;
  end;
procedure SlicePinnedCore4(const RepoRoot: String; out PackageData: TCore4SourcePackage);
implementation
uses wsm.core4source, wsm.source;

procedure SlicePinnedCore4(const RepoRoot: String; out PackageData: TCore4SourcePackage);
var
  Physical, Candidate: RawByteString;
  Doc, One: TSourceDocument;
  Staged: TCore4SourcePackage;
  I, FirstByte, EndByte: SizeInt;
begin
  PackageData.Prefix:='';
  SetLength(PackageData.Forms,0);
  Staged.Prefix:='';
  SetLength(Staged.Forms,0);
  Doc:=nil;
  Physical:=ReadPinnedCore4(RepoRoot);
  Doc:=ReadUkrainianSource(Physical);
  try
    if Length(Doc.Forms)=0 then
      raise ECore4SliceError.Create('у pinned Core4 немає жодної форми');
    FirstByte:=Doc.Forms[0].ByteOffset;
    if (FirstByte<1) or (FirstByte>Length(Physical)) then
      raise ECore4SliceError.Create('неприпустима початкова фізична адреса');
    Staged.Prefix:=Copy(Physical,1,FirstByte-1);
    SetLength(Staged.Forms,Length(Doc.Forms));
    for I:=0 to High(Doc.Forms) do begin
      FirstByte:=Doc.Forms[I].ByteOffset;
      if I<High(Doc.Forms) then
        EndByte:=Doc.Forms[I+1].ByteOffset
      else
        EndByte:=Length(Physical)+1;
      if (FirstByte<1) or (EndByte<=FirstByte) or
         (EndByte>Length(Physical)+1) then
        raise ECore4SliceError.Create('пошкоджений інтервал джерела Core4');
      Candidate:=Copy(Physical,FirstByte,EndByte-FirstByte);
      { Повторний незалежний структурний допуск одного фрагмента.
        Ні українське написання, ні число не встановлюють семантику. }
      One:=ReadUkrainianSource(Candidate);
      try
        if (Length(One.Forms)<>1) or
           (One.Forms[0].ByteOffset<>1) or
           (One.Forms[0].Kind<>Doc.Forms[I].Kind) then
          raise ECore4SliceError.Create('фрагмент Core4 не є однією формою');
      finally One.Free end;
      Staged.Forms[I].StartByte:=FirstByte;
      Staged.Forms[I].EndByteExclusive:=EndByte;
      Staged.Forms[I].Source:=Candidate;
    end;
    { Назовні не виходить частково побудований масив. }
    PackageData:=Staged;
  finally Doc.Free end;
end;
end.
