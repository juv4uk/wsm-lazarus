{ G6.203 — негативний свідок атомарності приватного SIR1 inspector.
  Канонічний .sens, D7 і pinned закони не змінюються. }
program test_sir1_inspect_atomic;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.compiler;

type
  { Власний потік тесту. FTarget — позиція opcode другого атома;
    дані копіюються із уже коректного приватного SIR1.
    Перший прохід читає коректний opcode, другий — зіпсований.
    1) Чому це саме другий прохід? 2) Хто звільняє Memory?
    3) Чому тест не декодує закони SENS? 4) Що означає FChanged? }
  TChangingStream=class(TMemoryStream)
  private
    FTarget:SizeInt;
    FSeen:Integer;
    FChanged:Boolean;
    FReplacement:Byte;
  public
    constructor Create(const Source:TMemoryStream; Target:SizeInt;
                       Replacement:Byte=255);
    function Read(var Buffer;Count:Longint):Longint; override;
    property Changed:Boolean read FChanged;
    property Seen:Integer read FSeen;
  end;

constructor TChangingStream.Create(const Source:TMemoryStream;Target:SizeInt;
                                   Replacement:Byte);
begin
  inherited Create;
  FTarget:=Target;
  FReplacement:=Replacement;
  FSeen:=0;
  FChanged:=False;
  Source.Position:=0;
  CopyFrom(Source,Source.Size);
  Position:=0;
end;

function TChangingStream.Read(var Buffer;Count:Longint):Longint;
begin
  if (Position=FTarget) and (Count>0) then begin
    Inc(FSeen);
    if FSeen=2 then begin
      PByte(Memory)[FTarget]:=FReplacement;
      FChanged:=True;
    end;
  end;
  Result:=inherited Read(Buffer,Count);
end;

procedure Check(Allowed:Boolean;const Why:String);
begin
  if not Allowed then begin
    WriteLn(StdErr,'SIR1-АТОМАРНІСТЬ-ЗБІЙ: ',Why);
    Halt(1);
  end;
end;

{ G6.207 — підміна саме ДРУГОГО проходу: допустимий SIR1 перевірився,
  але в запозиченому потоці змінено байт. Немає текстового dispatch SENS.
  Негативи перевіряють непублікацію out Stats, а не паритет мови. }
procedure ExpectSecondPassReject(const Src:RawByteString; Target:SizeInt;
                                 Replacement:Byte;const Description:String);
var
  Original:TMemoryStream;
  M:TChangingStream;
  Observed,Zero:TSIR1Stats;
  Caught:Boolean;
begin
  Original:=TMemoryStream.Create;
  try
    CompileSource(Src,Original);
    Check((Target>=0) and (Target<Original.Size),
          'поганий offset тесту '+Description);
    M:=TChangingStream.Create(Original,Target,Replacement);
    try
      FillChar(Observed,SizeOf(Observed),$7F);
      FillChar(Zero,SizeOf(Zero),0);
      Caught:=False;
      try
        InspectSIR1(M,Observed);
      except on E:ECompileError do
        Caught:=Pos('changed after structural verification',E.Message)>0;
      end;
      Check(Caught and M.Changed and (M.Seen=2),
            'не відхилено другий прохід: '+Description);
      Check(CompareMem(@Observed,@Zero,SizeOf(Observed)),
            'частковий out Stats після '+Description);
      { Після збою чистий фізичний host IR мусить знову читатися. }
      Original.Position:=0;
      InspectSIR1(Original,Observed);
      Check(Observed.Tokens>=2,'немає відновлення після '+Description);
    finally M.Free end;
  finally Original.Free end;
end;

var Base:TMemoryStream;Mut:TChangingStream;
    Stats,Empty:TSIR1Stats;Caught:Boolean;
    ExpectedTarget:SizeInt;
begin
  Base:=TMemoryStream.Create;
  try
    CompileSource('(а б)',Base);
    Base.Position:=0;
    InspectSIR1(Base,Stats);
    Check((Stats.Tokens=5) and (Stats.ListOpens=1) and
      (Stats.ListCloses=1) and (Stats.Atoms=2) and
      (Stats.Strings=0) and (Stats.MaxDepth=1),
      'позитивне читання структури SIR1');

    { Header(4), список(5), перший атом(5+байти української літери).
      Другий opcode лежить на точній байтовій межі, без іменного dispatch.
      1) Навіщо рахувати фактичні UTF-8 байти?
      2) Чому цей offset не є адресою домену D7?
      3) Як наступний Read підміняє лише другий прохід? }
    ExpectedTarget:=4+5+5+Length(RawByteString('а'));
    Mut:=TChangingStream.Create(Base,ExpectedTarget);
    try
      FillChar(Stats,SizeOf(Stats),$7F);
      Caught:=False;
      try InspectSIR1(Mut,Stats);
      except on E:ECompileError do
        Caught:=Pos('changed after structural verification',E.Message)>0;
      end;
      FillChar(Empty,SizeOf(Empty),0);
      Check(Caught and Mut.Changed and (Mut.Seen=2),
        'другий прохід не відмовив після фізичної підміни opcode');
      Check(CompareMem(@Stats,@Empty,SizeOf(Stats)),
        'out Stats витік частковим результатом після відмови');
    finally Mut.Free end;

    { Окремий справний потік не успадковує помилкової статистики. }
    Base.Position:=0;
    InspectSIR1(Base,Stats);
    Check((Stats.Tokens=5) and (Stats.Atoms=2) and
      (Stats.ListOpens=1) and (Stats.ListCloses=1),
      'відновлення структури SIR1 після попереднього збою');
    { Ці offsets — байти приватного SIR1: 4=перший opcode,
      5=молодший байт першої довжини; '()' End починається у 14,
      15=його Len; '() ()' другий open починається у 14.
      9=перший байт payload першого рядкового токена. }
    ExpectSecondPassReject('()',4,2,'зайвий close замість open');
    ExpectSecondPassReject('() ()',14,0,'ранній End перед хвостом');
    ExpectSecondPassReject('()',5,1,'ненульова структурна довжина');
    ExpectSecondPassReject('()',15,1,'ненульова довжина End');
    ExpectSecondPassReject('а',5,255,'довжина атома за межею');
    ExpectSecondPassReject('"а"',9,65,'пошкоджена межа рядка');
    ExpectSecondPassReject('()',0,0,'підмінений SIR1 magic');

    WriteLn('SIR1-АТОМАРНІСТЬ-ГАРАЗД FPC=checked ',
      'valid=1 corrupted-second-pass=reject out=zero recovery=1 ',
      'second-pass-guards=7 out=zero oracle=NOT-CHECKED energy=NOT-MEASURED');
  finally Base.Free end;
end.
