{ G6.28: тільки фізичний stdout T5M для уже допущеної D3:110.
  Джерело законів — pinned SENS; жодного власного виконання умов.
  Довжина машинного коду не змінюється, JNE не перераховуємо. }
unit wsm.elfcondt5m;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EElfCondT5MError=class(Exception);
function BuildCondT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.elfcond,wsm.t5m;

const
  HeaderBytes=120;
  { Рівно вісім байтів: машинний SETE/MOVZX/ASCII-add тільки в
    обраному expression; SETE у предикаті не має ASCII-add. }
  OldComputed=#$0F#$94#$C0#$0F#$B6#$C0#$04#$30;
  LiteralHead=#$48#$83#$EC#$08#$C6#$04#$24;
  ComputedTail=#$48#$83#$EC#$08#$88#$04#$24;
  WriteTwo=#$BA#$02#0#0#0+#$0F#$05;
  WriteThree=#$BA#$03#0#0#0+#$0F#$05;
  WriteOne=#$BA#$01#0#0#0+#$0F#$05;

function ReadQWord(const Bytes:RawByteString; Offset:SizeInt):QWord;
var J:SizeInt;
begin
  if (Offset<0) or (Offset>Length(Bytes)-8) then
    raise EElfCondT5MError.Create('Неправильні межі ELF64');
  Result:=0;
  for J:=7 downto 0 do
    Result:=(Result shl 8) or QWord(Ord(Bytes[Offset+J+1]));
end;

function OneWord(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1); W[0]:=Bits;
  Result:=EncodeT5M(W);
  if Length(Result)<>1 then
    raise EElfCondT5MError.Create('Канонічний T5M результат не 1 байт');
end;

function BuildCondT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Image,Candidate,ByteZero,ByteOne,ByteEmpty,NewComputed:RawByteString;
    I,J,DirectCount,ComputedCount,WriteCount,EmptyCount:SizeInt;
    Delta:Byte;
    C:AnsiChar;
begin
  Result:='';
  try
    { Увесь pinned admission та D3 evaluation виконує чинний emitter.
      Його результат не стає константою машинної гілки. }
    Image:=BuildCondELF(Physical,AuthorityRoot);
    if (Length(Image)<HeaderBytes+40) or
       (Length(Image)>HeaderBytes+4096) or
       (Copy(Image,1,4)<>#$7F'ELF') or
       (Ord(Image[5])<>2) or (Ord(Image[6])<>1) or
       (Ord(Image[17])<>2) or (Ord(Image[19])<>62) or
       (Ord(Image[65])<>1) or (Ord(Image[69])<>5) or
       (ReadQWord(Image,24)<>QWord($400000+HeaderBytes)) or
       (ReadQWord(Image,96)<>QWord(Length(Image))) or
       (ReadQWord(Image,104)<>QWord(Length(Image))) or
       (Copy(Image,Length(Image)-6,7)<>
          #$BF#$02#0#0#0+#$0F#$05) then
      raise EElfCondT5MError.Create('Змінився допущений x86-64 ELF ABI');

    ByteZero:=OneWord('0'); ByteOne:=OneWord('1');
    ByteEmpty:=OneWord('000');
    if (ByteZero=ByteOne) or (ByteZero=ByteEmpty) or
       (ByteOne=ByteEmpty) or
       (Ord(ByteOne[1])<=Ord(ByteZero[1])) or
       (Ord(ByteOne[1])-Ord(ByteZero[1])>127) then
      raise EElfCondT5MError.Create('Непідтверджена відстань T5M D1');
    Delta:=Ord(ByteOne[1])-Ord(ByteZero[1]);
    { SETE AL лишає верхні 24 біти EAX нульовими, бо перед EQ
      emitter виконав MOV EAX,D1. 8 bytes => 8 bytes, JNE незмінний:
      SETE AL; IMUL EAX,EAX,Delta; ADD AL,EncodedZero. }
    NewComputed:=#$0F#$94#$C0#$6B#$C0+AnsiChar(Delta)+
      #$04+ByteZero[1];
    Candidate:=Image;
    DirectCount:=0; ComputedCount:=0;
    EmptyCount:=0; WriteCount:=0;
    I:=HeaderBytes+1;
    while I<=Length(Candidate) do begin
      if (Copy(Candidate,I,Length(OldComputed))=OldComputed) then begin
        if Copy(Candidate,I+8,Length(ComputedTail))<>ComputedTail then
          raise EElfCondT5MError.Create('Невідомий машинний EQ stdout');
        for J:=1 to 8 do Candidate[I+J-1]:=NewComputed[J];
        Inc(ComputedCount);
      end;
      if Copy(Candidate,I,Length(LiteralHead))=LiteralHead then begin
        C:=Candidate[I+Length(LiteralHead)];
        case C of
          '0','1':
            begin
              if Copy(Candidate,I+8,5)<>#$C6#$44#$24#$01#$0A then
                raise EElfCondT5MError.Create('Невідомий D1 literal writer');
              if C='0' then Candidate[I+7]:=ByteZero[1]
              else Candidate[I+7]:=ByteOne[1];
            end;
          '(':
            begin
              if Copy(Candidate,I+8,10)<>
                  #$C6#$44#$24#$01#$29#$C6#$44#$24#$02#$0A then
                raise EElfCondT5MError.Create('Невідомий D3 empty writer');
              Candidate[I+7]:=ByteEmpty[1];
              Inc(EmptyCount);
            end;
          else raise EElfCondT5MError.Create('Невідома literal-форма D3:110');
        end;
        Inc(DirectCount);
      end;
      if (Copy(Candidate,I,Length(WriteTwo))=WriteTwo) or
         (Copy(Candidate,I,Length(WriteThree))=WriteThree) then begin
        { G6.229: WriteTwo/Three мають відразу після syscall
          спільний машинний CMP RAX,2|3; JNE exit(2).
          При фізичній T5M проєкції друкується один байт, тому
          міняємо ЗВ'ЯЗАНО обидва machine imm8: EDX=1 і CMP RAX,1.
          Жодної зміни довжини, rel8 або ET_EXEC геометрії.
          Candidate — owned RawByteString, Image з pinned admission
          не змінюється. Runtime стек належить ELF Linux процесу.
          1) Чому лише mov edx,1 недостатньо?
          2) Чому порівнюємо 64-бітний RAX, а не SENS D1?
          3) Чому перевіряємо саме 6 байтів CMP/JNE?
          4) Що означає D3:000, якщо умов не виконано? }
        if Copy(Candidate,I,Length(WriteTwo))=WriteTwo then C:=#$02
        else C:=#$03;
        if Copy(Candidate,I+Length(WriteOne),6)<>
           (#$48#$83#$F8+C+#$75#$09) then
          raise EElfCondT5MError.Create(
            'Відсутній перевірений 64-bit machine CMP/JNE після write');
        for J:=1 to Length(WriteOne) do Candidate[I+J-1]:=WriteOne[J];
        Candidate[I+Length(WriteOne)+3]:=#$01; { cmp rax,1 imm8 }
        Inc(WriteCount);
      end;
      Inc(I);
    end;
    { Один write для кожного допущеного шляху (включно з
      вичерпанням). Якщо ABI зміниться, відмова, не напів-ELF. }
    if (EmptyCount<>1) or (DirectCount<1) or
       (WriteCount<>DirectCount+ComputedCount) or
       (Pos(OldComputed,Candidate)>0) or
       (Pos(WriteTwo,Candidate)>0) or (Pos(WriteThree,Candidate)>0) or
       (Length(Candidate)<>Length(Image)) then
      raise EElfCondT5MError.Create('Неповний фізичний machine writer');
    Result:=Candidate;
  except
    on E:EElfCondT5MError do begin Result:=''; raise end;
    on E:Exception do begin
      Result:='';
      raise EElfCondT5MError.Create('D3:110 T5M відхилено: '+E.Message);
    end;
  end;
end;

{ Тип: ELF64 ET_EXEC RawByteString, байти 1..N; вхід Physical —
  канонічні T5M байти, AuthorityRoot — pinned path. Вивід — окремий
  ELF із RX сегментом, без нового allocation у машинному runtime:
  8 байтів стека для одного stdout байта. При відмові немає ELF.
  Питання: 1) Чому не використовується Answer як константа?
  2) Чому всі JNE зберегли зміщення?
  3) Чому D3:000 не тотожне D1:0?
  4) Чому IMUL потрібний лише EQ-expression?
  5) Яка умова відкидає змінений ELF writer ABI? }
end.
