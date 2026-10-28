{ Head-inventory CLI for the SENS native compiler front-end.
  Structural projection only: never grants semantic callability. }
program sensbind;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.source, wsm.domain, wsm.bind,
  wsm.bindindex, wsm.bindtree;
var
  Source: RawByteString;
  Root: RawByteString;
  Mode: String;
  FileName: String;
  Input: TFileStream;
  Document: TSourceDocument;
  Tables: TDomainSet;
  Index: TBindIndex;
  Heads: THeadOccurrences;
  I, BoundCount, UnknownCount, NonAtomCount: SizeInt;
  StateName: String;
begin
  if (ParamCount<>3) or
     ((ParamStr(1)<>'--analyze') and
      (ParamStr(1)<>'--require-bound')) then begin
    WriteLn(StdErr,'usage: sensbind --analyze|--require-bound source.lisp pinned-sens-root');
    Halt(64);
  end;
  Mode := ParamStr(1);
  FileName := ParamStr(2);
  Root := ParamStr(3);
  if LowerCase(ExtractFileExt(FileName))<>'.lisp' then begin
    WriteLn(StdErr,'SENSBIND-FAIL expected Ukrainian .lisp projection, not binary .sens');
    Halt(64);
  end;
  try
    Input := TFileStream.Create(FileName,fmOpenRead);
    try
      if Input.Size>16*1024*1024 then
        raise ESourceError.Create('source size limit');
      if Input.Size=0 then
        raise ESourceError.Create('empty source file');
      SetLength(Source,Input.Size);
      Input.ReadBuffer(Source[1],Length(Source));
    finally Input.Free; end;
    LoadPinnedDomains(Root,Tables);
    BuildBindIndex(Tables,Index);
    Document := ReadUkrainianSource(Source);
    try
      CollectHeadOccurrences(Document,Index,Heads);
      if Mode='--require-bound' then RequireBoundHeads(Heads);
    finally Document.Free; end;
    BoundCount:=0;
    UnknownCount:=0;
    NonAtomCount:=0;
    for I:=0 to High(Heads) do begin
      case Heads[I].State of
        hsBound: begin Inc(BoundCount); StateName:='bound'; end;
        hsUnknown: begin Inc(UnknownCount); StateName:='unknown'; end;
        hsNonAtom: begin Inc(NonAtomCount); StateName:='nonatom'; end;
      end;
      Write('SENSBIND-HEAD state=',StateName,
        ' byte=',Heads[I].ByteOffset,
        ' line=',Heads[I].Line,' byte-column=',Heads[I].ByteColumn);
      if Heads[I].State=hsBound then
        Write(' domain=',Heads[I].Key.Width,
          ' bits=',KeyBits(Heads[I].Key));
      Write(' form=',Heads[I].TopFormIndex,
        ' parent=',Heads[I].ParentIndex,
        ' child=',Heads[I].ChildIndex,
        ' depth=',Heads[I].Depth,
        ' list-byte=',Heads[I].ListByteOffset);
      WriteLn;
    end;
    WriteLn('SENSBIND-SUMMARY heads=',Length(Heads),
      ' bound=',BoundCount,' unknown=',UnknownCount,
      ' nonatom=',NonAtomCount,' callable=unverified');
  except
    on E:ESourceError do begin
      WriteLn(StdErr,'SENSBIND-FAIL source: ',E.Message);
      Halt(1);
    end;
    on E:EBindTreeError do begin
      WriteLn(StdErr,'SENSBIND-FAIL head byte=',E.ByteOffset,
        ' line=',E.Line,' byte-column=',E.ByteColumn,': ',E.Message);
      Halt(1);
    end;
    on E:Exception do begin
      WriteLn(StdErr,'SENSBIND-FAIL ',E.Message);
      Halt(1);
    end;
  end;
end.
