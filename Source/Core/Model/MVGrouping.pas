unit MVGrouping;

// 選択した文字の永続的な動作グループを編集する。配置・書式・現在の選択とは独立して保持する。
interface

uses MVDocument;

// 登録は2文字以上を新しい集合へまとめる。解除は選択文字だけを外す。変更した場合にTrueを返す。
function SetMVAnimationGroup(var Document: TMVDocument; const Selected: TArray<Integer>; Clear: Boolean): Boolean;
// 選択文字と同じ登録グループに属する文字も含めた、歌詞順の選択集合を返す。
function ExpandMVAnimationGroups(const Document: TMVDocument; const Selected: TArray<Integer>): TArray<Integer>;

implementation

uses System.SysUtils, MVTextUnits;

function SetMVAnimationGroup(var Document: TMVDocument; const Selected: TArray<Integer>; Clear: Boolean): Boolean;
var
  Chosen: array[0..MV_MAX_UNITS - 1] of Boolean;
  Used: array[0..MV_MAX_UNITS] of Boolean;
  I, Count, ID: Integer;
begin
  ValidateMVDocument(Document);
  FillChar(Chosen, SizeOf(Chosen), 0);
  FillChar(Used, SizeOf(Used), 0);
  Count := 0;
  for I in Selected do
    if (I >= 0) and (I < Length(Document.Units)) and not Chosen[I] and
      IsMVDelayUnit(Document.Units[I].Text) then
    begin
      Chosen[I] := True;
      Inc(Count);
    end;
  if not Clear and (Count < 2) then
    raise EArgumentException.Create('グループにする文字を2文字以上選択してください。');
  ID := 0;
  if not Clear then
  begin
    // 選択文字の旧IDは再利用できるが、選択外の所属は変えない。
    for I := 0 to High(Document.Units) do
      if not Chosen[I] then Used[Document.Units[I].AnimationGroup] := True;
    ID := 1;
    while (ID <= MV_MAX_UNITS) and Used[ID] do Inc(ID);
    if ID > MV_MAX_UNITS then raise EArgumentException.Create('動作グループの上限を超えています。');
  end;
  Result := False;
  for I := 0 to High(Document.Units) do
    if Chosen[I] and (Document.Units[I].AnimationGroup <> ID) then
    begin
      Document.Units[I].AnimationGroup := ID;
      Result := True;
    end;
end;

function ExpandMVAnimationGroups(const Document: TMVDocument; const Selected: TArray<Integer>): TArray<Integer>;
var
  Groups: array[0..MV_MAX_UNITS] of Boolean;
  Chosen: array[0..MV_MAX_UNITS - 1] of Boolean;
  I, Count: Integer;
begin
  ValidateMVDocument(Document);
  FillChar(Groups, SizeOf(Groups), 0);
  FillChar(Chosen, SizeOf(Chosen), 0);
  for I in Selected do
    if (I >= 0) and (I < Length(Document.Units)) then
    begin
      Chosen[I] := True;
      if Document.Units[I].AnimationGroup > 0 then Groups[Document.Units[I].AnimationGroup] := True;
    end;
  SetLength(Result, Length(Document.Units));
  Count := 0;
  for I := 0 to High(Document.Units) do
    if Chosen[I] or Groups[Document.Units[I].AnimationGroup] then
    begin
      Result[Count] := I;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

end.
