{ G6.54 — справжнє машинне порівняння двох ЦИТОВАНИХ атомів D7.
  Канонічний вхід .sens (T5M), pinned binder + native evaluator — допуск.
  Linux x86-64 ELF64 ET_DYN виконує порівняння кожного біта,
  а не Pascal constant-fold; повертає точний фізичний D1 T5M.
  D7 — тільки дані, D12+ тут не виконуються. }
unit wsm.elfd7eq;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EELFD7EqError=class(Exception);
function BuildQuotedD7EqELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.d2source,wsm.binarybind,wsm.domain,wsm.bind,
     wsm.binaryexec;

const HeaderBytes=120;
      MaxMachineBytes=256;

procedure Require(Ok:Boolean;const MessageText:String);
begin
  if not Ok then raise EELFD7EqError.Create(MessageText);
end;

{ Borrowed TD2Node і Bound належать виклику. ValueAt перевіряє точну
  координату вже pinned binder, а не українське чи англійське ім'я. }
function ValueAt(N:TD2Node;At,Width:SizeInt;
  const Bits:RawByteString;const Bound:TBinaryWords):Boolean;
begin
  Result:=(N<>nil) and (N.Kind=dkIdentity) and
    (N.Width=Width) and (N.Bits=Bits) and
    (At>=0) and (At<Length(Bound));
  if Result then
    Result:=(Bound[At].Key.Width=Width) and
      (KeyBits(Bound[At].Key)=Bits) and
      (Bound[At].WordIndex=N.WordIndex) and
      (Bound[At].RootIndex=0) and (not Bound[At].IsEmpty);
end;

function QuotedW7(N:TD2Node;QuoteAt,AtomAt:SizeInt;
  const Bound:TBinaryWords):RawByteString;
var Head,Atom:TD2Node;
begin
  Require((N<>nil) and (N.Kind=dkList) and
    (Length(N.Children)=2),'Очікується окрема фізична цитата D3:001');
  Head:=N.Children[0];
  Atom:=N.Children[1];
  Require(ValueAt(Head,QuoteAt,3,'001',Bound),
    'Цитата має містити точну pinned голову D3:001');
  Require((Atom<>nil) and (Atom.Kind=dkIdentity) and
    (Atom.Width=7) and (Length(Atom.Bits)=7),
    'Цитата має містити рівно один атом D7');
  Require(ValueAt(Atom,AtomAt,7,Atom.Bits,Bound),
    'Втрачене exact-domain зв’язування D7');
  Result:=Atom.Bits;
end;

{ Physical — запозичені T5M bytes, AuthorityRoot — pinned SENS.
  Doc, Tables, Bound, Machine і Executor локальні, належать цьому виклику.
  Результат — новий керований RawByteString із справжнім ELF64 ET_DYN.
  Відмова: EELFD7EqError, жодних ELF-байтів не опубліковано.
  Питання: чому два W7 не є D12? Чому QuoteAt перевіряється окремо?
  Чи може ім'я «тотожне?» замінити D3:101? Де виконується XOR? }
function BuildQuotedD7EqELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Words,Outcome:TExactWords;
  Doc:TD2Document;
  Bound:TBinaryWords;
  Tables:TDomainSet;
  Engine:TBinaryExecutor;
  LeftBits,RightBits,Actual,ZeroBytes,OneBytes,Machine:RawByteString;
  Delta:Byte;
  I,Total:SizeInt;

  procedure Add(B:Byte);
  begin
    Require(Length(Machine)<MaxMachineBytes,'Перевищено квоту машинного коду');
    Machine:=Machine+AnsiChar(B);
  end;

  procedure Put(Offset:SizeInt;Value:QWord;Count:SizeInt);
  var J:SizeInt;
  begin
    Require((Offset>=0) and (Count>0) and (Count<=8) and
      (Offset<=Length(Result)-Count),'Пошкоджена межа ELF64');
    for J:=0 to Count-1 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

begin
  Result:='';Doc:=nil;Engine:=nil;
  try
    try
      Require((Length(Physical)>0) and (Length(Physical)<=65536),
        'Некоректна довжина фізичної програми');
      DecodeT5M(Physical,Words);
      Require(EncodeT5M(Words)=Physical,'Фізичний T5M не канонічний');
      Doc:=ParseD2Words(Words);
      LoadPinnedDomains(AuthorityRoot,Tables);
      BindD2Binary(Doc,Tables,Bound);
      Require((Length(Doc.Roots)=1) and (Length(Bound)=5),
        'Потрібна рівно одна форма D3:101 над двома D7 цитатами');
      Require((Doc.Roots[0]<>nil) and
        (Doc.Roots[0].Kind=dkList) and
        (Length(Doc.Roots[0].Children)=3),
        'Неприпустима арність фізичної тотожності D7');
      Require(ValueAt(Doc.Roots[0].Children[0],0,3,'101',Bound),
        'Немає ратифікованої фізичної голови D3:101');
      LeftBits:=QuotedW7(Doc.Roots[0].Children[1],1,2,Bound);
      RightBits:=QuotedW7(Doc.Roots[0].Children[2],3,4,Bound);

      { Тільки існуючий FPC виконавець перевіряє семантичний допуск.
        Він НЕ подає результат як машинну константу: обидва W7
        знижуються в окремі imm8, XOR/OR/TEST/SETE працюють в ELF. }
      Engine:=TBinaryExecutor.Create(AuthorityRoot);
      Actual:=Engine.ExecutePhysicalT5M(Physical);
      DecodeT5M(Actual,Outcome);
      Require((Length(Outcome)=1) and
        ((Outcome[0]='0') or (Outcome[0]='1')) and
        (EncodeT5M(Outcome)=Actual),
        'Чинний evaluator не підтвердив фізичну відповідь D1');

      SetLength(Outcome,1);
      Outcome[0]:='0';ZeroBytes:=EncodeT5M(Outcome);
      Outcome[0]:='1';OneBytes:=EncodeT5M(Outcome);
      Require((Length(ZeroBytes)=1) and (Length(OneBytes)=1) and
        (Ord(OneBytes[1])>Ord(ZeroBytes[1])) and
        (Ord(OneBytes[1])-Ord(ZeroBytes[1])<=127),
        'Змінився канонічний T5M вихід D1');
      Delta:=Ord(OneBytes[1])-Ord(ZeroBytes[1]);

      Machine:='';
      Add($31);Add($C0); { xor eax,eax: accumulator mismatches=0 }
      for I:=1 to 7 do begin
        { БІТИ exact W7 — окремі фізичні 0/1, без десяткової семантики.
          mov cl,L; xor cl,R; or al,cl. Всі 7 порівнянь — у CPU. }
        Add($B1);Add(Ord(LeftBits[I])-Ord('0'));
        Add($80);Add($F1);Add(Ord(RightBits[I])-Ord('0'));
        Add($08);Add($C8);
      end;
      Add($84);Add($C0);                   { test al,al }
      Add($0F);Add($94);Add($C0);          { sete al }
      Add($0F);Add($B6);Add($C0);          { movzx eax,al }
      Add($6B);Add($C0);Add(Delta);       { imul eax,eax,delta }
      Add($83);Add($C0);Add(Byte(ZeroBytes[1])); { add eax,T5M(D1:0) }
      Add($48);Add($83);Add($EC);Add($08); { sub rsp,8 }
      Add($88);Add($04);Add($24);          { mov [rsp],al }
      Add($B8);Add($01);Add(0);Add(0);Add(0); { write }
      Add($BF);Add($01);Add(0);Add(0);Add(0);
      Add($48);Add($89);Add($E6);
      Add($BA);Add($01);Add(0);Add(0);Add(0);
      Add($0F);Add($05);                   { write(1,physical D1,1) }
      { G6.218: RAX — число фізичних байтів, записаних Linux.
        Не оголошувати успіх при -EBADF, -ENOSPC чи короткому записі.
        Borrowed SENS W7/D1 не змінюються; Result ELF належить caller.
        1) Чому порівнюємо RAX з 1, а не AL після SETE?
        2) Чим host exit(2) відрізняється від SENS D1:0?
        3) Чому JNE пропускає рівно 9 байтів успішного завершення?
        4) Хто зберігає точні D7 та T5M перед цією машиною? }
      Add($48);Add($83);Add($F8);Add($01); { cmp rax,1 }
      Add($75);Add($09);                   { jne +9: host exit(2) }
      Add($B8);Add($3C);Add(0);Add(0);Add(0); { exit(0) }
      Add($31);Add($FF);Add($0F);Add($05);
      Add($B8);Add($3C);Add(0);Add(0);Add(0); { exit(2) }
      Add($BF);Add($02);Add(0);Add(0);Add(0);
      Add($0F);Add($05);
      Total:=HeaderBytes+Length(Machine);
      Result:=StringOfChar(#0,Total);
      Put(0,$464C457F,4);              { ELF magic }
      Put(4,2,1);Put(5,1,1);Put(6,1,1); { ELF64 little endian }
      Put(16,3,2);Put(18,62,2);Put(20,1,4); { ET_DYN x86-64 }
      Put(24,HeaderBytes,8);Put(32,64,8);
      Put(52,64,2);Put(54,56,2);Put(56,1,2);
      Put(64,1,4);Put(68,5,4);          { PT_LOAD RX }
      Put(80,0,8);Put(88,0,8);          { position-independent base }
      Put(96,QWord(Total),8);Put(104,QWord(Total),8);
      Put(112,$1000,8);
      for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];
    finally
      Engine.Free;
      Doc.Free;
    end;
  except
    on E:EELFD7EqError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EELFD7EqError.Create('Фізичний D7 ELF відхилено: '+E.Message);
    end;
  end;
end;
end.
