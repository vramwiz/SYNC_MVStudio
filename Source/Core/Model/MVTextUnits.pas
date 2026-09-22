unit MVTextUnits;

// UTF-16を壊さず、結合文字・異体字指定・絵文字結合を同じ配置要素へまとめる。
interface

uses MVDocument;

// 歌詞をLFへ正規化し、共通の前後部分の個別配置を維持して文字単位を再構成する。
procedure SetMVText(var Document: TMVDocument; const Text: string);
// 空白・改行だけの要素を除く。結合文字や絵文字の要素を分割せず、遅延順を数えるために使う。
function IsMVDelayUnit(const Text: string): Boolean;

implementation

uses System.SysUtils, System.Character, System.Generics.Collections;

function IsMVDelayUnit(const Text: string): Boolean;
var C: Char;
begin
  for C in Text do
    if not C.IsWhiteSpace then Exit(True);
  Result := False;
end;

function ReadCodePoint(const Text: string; var Index: Integer): Cardinal;
var
  C: Word;
begin
  C := Ord(Text[Index]);
  Inc(Index);
  Result := C;
  if (C >= $D800) and (C <= $DBFF) then
  begin
    if (Index > Length(Text)) or (Ord(Text[Index]) < $DC00) or (Ord(Text[Index]) > $DFFF) then
      raise EArgumentException.Create('不正なUTF-16文字列です。');
    Result := $10000 + Cardinal(C - $D800) * $400 + Cardinal(Ord(Text[Index]) - $DC00);
    Inc(Index);
  end
  else if (C >= $DC00) and (C <= $DFFF) then
    raise EArgumentException.Create('不正なUTF-16文字列です。');
end;

function IsExtension(Code: Cardinal): Boolean;
var
  Category: TUnicodeCategory;
begin
  Category := Char.GetUnicodeCategory(UCS4Char(Code));
  Result := (Category in [TUnicodeCategory.ucNonSpacingMark, TUnicodeCategory.ucCombiningMark,
    TUnicodeCategory.ucEnclosingMark]) or ((Code >= $FE00) and (Code <= $FE0F)) or
    ((Code >= $E0100) and (Code <= $E01EF)) or ((Code >= $1F3FB) and (Code <= $1F3FF)) or
    ((Code >= $E0020) and (Code <= $E007F));
end;

procedure SetMVText(var Document: TMVDocument; const Text: string);
var
  Normalized, Chunk: string;
  List: TList<TMVPlacement>;
  Item: TMVPlacement;
  Code, Previous: Cardinal;
  I, Start, N, Prefix, Suffix, RegionalCount: Integer;
  JoinNext: Boolean;
  NewUnits: TArray<TMVPlacement>;
begin
  Normalized := StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  if Length(Normalized) > MV_MAX_TEXT_LENGTH then
    raise EArgumentException.Create('歌詞は1024文字以内にしてください。');
  List := TList<TMVPlacement>.Create;
  try
    I := 1;
    Previous := 0;
    RegionalCount := 0;
    JoinNext := False;
    while I <= Length(Normalized) do
    begin
      Start := I;
      Code := ReadCodePoint(Normalized, I);
      Chunk := Copy(Normalized, Start, I - Start);
      N := List.Count;
      if (N > 0) and (Code <> 10) and (Previous <> 10) and
        (IsExtension(Code) or JoinNext or (Code = $200D) or
        ((Code >= $1F1E6) and (Code <= $1F1FF) and Odd(RegionalCount))) then
      begin
        Item := List[N - 1];
        Item.Text := Item.Text + Chunk;
        List[N - 1] := Item;
      end
      else
      begin
        Item := Default(TMVPlacement);
        Item.Text := Chunk;
        Item.Scale := 1;
        Item.ScaleX := 1;
        Item.ScaleY := 1;
        List.Add(Item);
      end;
      JoinNext := Code = $200D;
      if (Code >= $1F1E6) and (Code <= $1F1FF) then Inc(RegionalCount) else RegionalCount := 0;
      Previous := Code;
    end;
    if List.Count > MV_MAX_UNITS then
      raise EArgumentException.Create('文字配置は512要素以内にしてください。');
    NewUnits := List.ToArray;
  finally
    List.Free;
  end;
  Prefix := 0;
  while (Prefix < Length(NewUnits)) and (Prefix < Length(Document.Units)) and
    (NewUnits[Prefix].Text = Document.Units[Prefix].Text) do
  begin
    NewUnits[Prefix] := Document.Units[Prefix];
    Inc(Prefix);
  end;
  Suffix := 0;
  while (Suffix < Length(NewUnits) - Prefix) and (Suffix < Length(Document.Units) - Prefix) and
    (NewUnits[High(NewUnits) - Suffix].Text = Document.Units[High(Document.Units) - Suffix].Text) do
  begin
    NewUnits[High(NewUnits) - Suffix] := Document.Units[High(Document.Units) - Suffix];
    Inc(Suffix);
  end;
  Document.Text := Normalized;
  Document.Units := NewUnits;
end;

end.
