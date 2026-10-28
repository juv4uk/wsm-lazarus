{ G5.9 — перевіряємо фізичний пакет, не створюючи нових законів SENS. }
program test_binarybatch;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.binaryexec,
  wsm.binarybatch;
var
  Engine: TBinaryExecutor;
  Answers: TBinaryBatchAnswers;
  Input: RawByteString;
  W: TExactWords;
  I, FailCount: SizeInt;
  Failed: Boolean;

procedure Check(Condition: Boolean; const MessageText: String);
begin
  if not Condition then begin
    WriteLn(StdErr,#$D0#$A2#$D0#$95#$D0#$A1#$D0#$A2#$2D#$D0#$9F#$D0#$90#$D0#$9A#$D0#$95#$D0#$A2#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$3A#$20,MessageText);
    Halt(1);
  end;
end;

function WordsOf(const Items: array of RawByteString): TExactWords;
var J: SizeInt;
begin
  SetLength(Result,Length(Items));
  for J := 0 to High(Items) do Result[J]:=Items[J];
end;

procedure SaveFile(const Path: String; const Data: RawByteString);
var F: TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free; end;
end;

procedure ExpectBad(const Data: RawByteString; const Name: String;
  Root, Word: SizeInt);
begin
  { Позначаємо вихід довільною старою відповіддю; відмова мусить стерти її. }
  SetLength(Answers,1);
  Answers[0]:=#$D0#$BD#$D0#$B5#$2D#$D0#$BF#$D1#$83#$D0#$B1#$D0#$BB#$D1#$96#$D0#$BA#$D1#$83#$D0#$B2#$D0#$B0#$D1#$82#$D0#$B8;
  Failed:=False;
  try ExecuteBinaryBatch(Data,Engine,Answers);
  except on E: EBinaryBatchError do
    Failed:=(E.RootIndex=Root) and (E.WordIndex=Word);
  end;
  Check(Failed,Name+#$3A#$20#$D0#$BD#$D0#$B5#$20#$D0#$BE#$D1#$82#$D1#$80#$D0#$B8#$D0#$BC#$D0#$B0#$D0#$BD#$D0#$BE#$20#$D0#$BE#$D1#$87#$D1#$96#$D0#$BA#$D1#$83#$D0#$B2#$D0#$B0#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$BF#$D0#$BE#$D0#$B7#$D0#$B8#$D1#$86#$D1#$96#$D0#$B9#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BC#$D0#$BE#$D0#$B2#$D0#$B8);
  Check(Length(Answers)=0,Name+#$3A#$20#$D1#$81#$D1#$82#$D0#$B0#$D1#$80#$D0#$B8#$D0#$B9#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D1#$87#$D0#$B0#$D1#$81#$D1#$82#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D1#$80#$D0#$B5#$D0#$B7#$D1#$83#$D0#$BB#$D1#$8C#$D1#$82#$D0#$B0#$D1#$82);
  Inc(FailCount);
end;

begin
  Engine:=TBinaryExecutor.Create('external/sens');
  try
    W:=WordsOf(['1','10','111','00','1','000','01','0']);
    Input:=EncodeT5M(W);
    SaveFile('build/m0.2/binarybatch-positive.sens',Input);
    ExecuteBinaryBatch(Input,Engine,Answers);
    Check((Length(Answers)=3) and (Answers[0]='1') and
      (Answers[1]='(1)') and (Answers[2]='0'),
      #$D1#$82#$D1#$80#$D0#$B8#$20#$D1#$80#$D0#$B5#$D0#$B0#$D0#$BB#$D1#$8C#$D0#$BD#$D1#$96#$20#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BD#$D1#$96#$20#$44#$31#$2F#$44#$33#$2F#$44#$31#$20#$D0#$B7#$20#$D1#$80#$D1#$96#$D0#$B7#$D0#$BD#$D0#$B8#$D0#$BC#$D0#$B8#$20#$D1#$80#$D0#$B5#$D0#$B7#$D1#$83#$D0#$BB#$D1#$8C#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0#$D0#$BC#$D0#$B8);

    { Той самий SINGLE-ROOT executor є джерелом кожного результату.
      Не порівнюємо з історичною текстовою реалізацією чи SID8. }
    Check(Answers[0]=Engine.ExecutePhysical(EncodeT5M(WordsOf(['1']))),
      #$D0#$BF#$D0#$B5#$D1#$80#$D1#$88#$D0#$B8#$D0#$B9#$20#$D0#$BA#$D0#$BE#$D1#$80#$D1#$96#$D0#$BD#$D1#$8C#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$82#$D0#$B8#$20#$D1#$87#$D0#$B8#$D0#$BD#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D1#$86#$D1#$8F);
    Check(Answers[1]=Engine.ExecutePhysical(
      EncodeT5M(WordsOf(['10','111','00','1','000','01']))),
      #$D0#$B4#$D1#$80#$D1#$83#$D0#$B3#$D0#$B8#$D0#$B9#$20#$D0#$BA#$D0#$BE#$D1#$80#$D1#$96#$D0#$BD#$D1#$8C#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$82#$D0#$B8#$20#$D1#$87#$D0#$B8#$D0#$BD#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D1#$86#$D1#$8F);
    Check(Answers[2]=Engine.ExecutePhysical(EncodeT5M(WordsOf(['0']))),
      #$D1#$82#$D1#$80#$D0#$B5#$D1#$82#$D1#$96#$D0#$B9#$20#$D0#$BA#$D0#$BE#$D1#$80#$D1#$96#$D0#$BD#$D1#$8C#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$82#$D0#$B8#$20#$D1#$87#$D0#$B8#$D0#$BD#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D1#$86#$D1#$8F);

    SaveFile('build/m0.2/binarybatch-root1.sens',
      EncodeT5M(WordsOf(['1'])));
    SaveFile('build/m0.2/binarybatch-root2.sens',
      EncodeT5M(WordsOf(['10','111','00','1','000','01'])));
    SaveFile('build/m0.2/binarybatch-root3.sens',
      EncodeT5M(WordsOf(['0'])));

    FailCount:=0;
    Input:=EncodeT5M(WordsOf(['1','10','001','00','1','01']));
    SaveFile('build/m0.2/binarybatch-unsupported.sens',Input);
    ExpectBad(Input,#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$96#$D0#$B4#$D1#$82#$D0#$B2#$D0#$B5#$D1#$80#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$B0#$20#$44#$33#$20#$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0#$20#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$D0#$BF#$D1#$80#$D0#$B0#$D0#$B2#$D0#$B8#$D0#$BB#$D1#$8C#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$BF#$D1#$80#$D0#$B5#$D1#$84#$D1#$96#$D0#$BA#$D1#$81#$D0#$B0,
      1,3);

    Input:=EncodeT5M(WordsOf(['1','10','111']));
    SaveFile('build/m0.2/binarybatch-unclosed.sens',Input);
    ExpectBad(Input,#$D0#$BD#$D0#$B5#$D0#$B7#$D0#$B0#$D0#$BA#$D1#$80#$D0#$B8#$D1#$82#$D0#$B8#$D0#$B9#$20#$44#$32#$20#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$D0#$BF#$D1#$80#$D0#$B0#$D0#$B2#$D0#$B8#$D0#$BB#$D1#$8C#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$BF#$D1#$80#$D0#$B5#$D1#$84#$D1#$96#$D0#$BA#$D1#$81#$D0#$B0,0,4);

    Input:=#243;
    SaveFile('build/m0.2/binarybatch-corrupt.sens',Input);
    ExpectBad(Input,#$D0#$BF#$D0#$BE#$D1#$88#$D0#$BA#$D0#$BE#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$B8#$D0#$B9#$20#$54#$35#$4D,0,0);
    ExpectBad('',#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$BF#$D0#$BE#$D1#$82#$D1#$96#$D0#$BA,0,0);
    ExpectBad(EncodeT5M(WordsOf(['01'])),#$D0#$B7#$D0#$B0#$D0#$BA#$D1#$80#$D0#$B8#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$44#$32#$20#$D0#$B1#$D0#$B5#$D0#$B7#$20#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BA#$D1#$80#$D0#$B8#$D1#$82#$D1#$82#$D1#$8F,0,1);
    ExpectBad(EncodeT5M(WordsOf(['10','1'])),
      #$D0#$B7#$D0#$B0#$D0#$BA#$D1#$96#$D0#$BD#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F#$20#$D0#$BF#$D0#$BE#$D1#$81#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B4#$20#$D1#$81#$D0#$BF#$D0#$B8#$D1#$81#$D0#$BA#$D1#$83,0,3);
    ExpectBad(EncodeT5M(WordsOf(['1111111111'])),
      #$D0#$BD#$D0#$B5#$D0#$BF#$D1#$96#$D0#$B4#$D1#$82#$D1#$80#$D0#$B8#$D0#$BC#$D0#$B0#$D0#$BD#$D0#$B0#$20#$D1#$88#$D0#$B8#$D1#$80#$D0#$B8#$D0#$BD#$D0#$B0#$20#$31#$30,0,1);
    ExpectBad(EncodeT5M(WordsOf(['10','1','11','01'])),
      #$D0#$BA#$D1#$80#$D0#$B0#$D0#$BF#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B0#$20#$D0#$BF#$D0#$B0#$D1#$80#$D0#$B0#$20#$D0#$B1#$D0#$B5#$D0#$B7#$20#$D1#$85#$D0#$B2#$D0#$BE#$D1#$81#$D1#$82#$D0#$B0,0,4);

    SetLength(W,MaxBatchRoots+1);
    for I:=0 to High(W) do W[I]:='1';
    ExpectBad(EncodeT5M(W),#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D0#$BA#$D1#$96#$D0#$BB#$D1#$8C#$D0#$BA#$D1#$96#$D1#$81#$D1#$82#$D1#$8C#$20#$D0#$B2#$D0#$B5#$D1#$80#$D1#$85#$D0#$BD#$D1#$96#$D1#$85#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC,0,0);
    ExpectBad(EncodeT5M(WordsOf(['1','10','001','0','01','0'])),
      #$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0#$20#$D0#$B2#$20#$D0#$B4#$D1#$80#$D1#$83#$D0#$B3#$D0#$BE#$D0#$BC#$D1#$83#$20#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BD#$D1#$96#$20#$D0#$B1#$D0#$B5#$D0#$B7#$20#$D1#$87#$D0#$B0#$D1#$81#$D1#$82#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D1#$80#$D0#$B5#$D0#$B7#$D1#$83#$D0#$BB#$D1#$8C#$D1#$82#$D0#$B0#$D1#$82#$D1#$83,1,3);

    { Відмова не отруює стан уже створеного TBinaryExecutor. }
    ExecuteBinaryBatch(EncodeT5M(WordsOf(['0','1'])),Engine,Answers);
    Check((Length(Answers)=2) and (Answers[0]='0') and
      (Answers[1]='1'),#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D0#$BE#$D0#$B2#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F#$20#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$D0#$BF#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$BB#$D0#$BE#$D0#$BA);

    WriteLn(#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$98#$D0#$99#$2D#$D0#$9F#$D0#$90#$D0#$9A#$D0#$95#$D0#$A2#$2D#$D0#$93#$D0#$90#$D0#$A0#$D0#$90#$D0#$97#$D0#$94#$20#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BD#$D1#$96#$3D#$33#$20#$D0#$BD#$D0#$B5#$D0#$B3#$D0#$B0#$D1#$82#$D0#$B8#$D0#$B2#$D0#$BD#$D1#$96#$3D,FailCount,
      #$20#$D0#$B2#$D0#$B8#$D1#$81#$D0#$BD#$D0#$BE#$D0#$B2#$D0#$BA#$D0#$B8#$3D#$D1#$87#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B7#$2D#$D0#$BD#$D0#$B0#$D1#$8F#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D0#$B5#$D1#$86#$D1#$8C#$20#$D0#$B2#$D0#$B8#$D0#$B2#$D1#$96#$D0#$B4#$3D#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC#$D0#$B0#$D1#$80#$D0#$BD#$D0#$B8#$D0#$B9);
    WriteLn(#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$98#$D0#$99#$2D#$D0#$9F#$D0#$90#$D0#$9A#$D0#$95#$D0#$A2#$2D#$D0#$9C#$D0#$95#$D0#$96#$D0#$86#$3A#$20#$D1#$81#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B4#$D0#$BE#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$3D#$D0#$BD#$D0#$B5#$D0#$B7#$D0#$B0#$D0#$BB#$D0#$B5#$D0#$B6#$D0#$BD#$D0#$B5#$20,
      #$52#$45#$50#$4C#$3D#$D0#$BD#$D0#$B5#$2D#$D0#$BF#$D0#$BE#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$43#$6F#$72#$65#$34#$3D#$D0#$BD#$D0#$B5#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D1#$83#$D1#$94#$D1#$82#$D1#$8C#$D1#$81#$D1#$8F);
  finally Engine.Free; end;
end.
