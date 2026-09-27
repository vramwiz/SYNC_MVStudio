unit MVTextUnits;

// UTF-16を壊さず、結合文字・異体字指定・絵文字結合を同じ配置要素へまとめる。
interface

uses MVDocument;

// 歌詞をLFへ正規化し、文字ごとの書式を維持する。歌詞変更時は配置を中央揃えの初期状態へ戻す。
procedure SetMVText(var Document: TMVDocument; const Text: string);
// 空白・改行だけの要素を除く。結合文字や絵文字の要素を分割せず、遅延順を数えるために使う。
function IsMVDelayUnit(const Text: string): Boolean;

implementation

uses System.SysUtils, System.Character, System.Generics.Collections, System.Math;

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

procedure MVLineRanges(const Units: TArray<TMVPlacement>; out Starts, Counts: TArray<Integer>);
var I, LineStart, LineCount: Integer;
begin
  SetLength(Starts, Length(Units) + 1);
  SetLength(Counts, Length(Units) + 1);
  LineStart := 0;
  LineCount := 0;
  for I := 0 to High(Units) do
    if Units[I].Text = #10 then
    begin
      Starts[LineCount] := LineStart;
      Counts[LineCount] := I - LineStart;
      Inc(LineCount);
      LineStart := I + 1;
    end;
  Starts[LineCount] := LineStart;
  Counts[LineCount] := Length(Units) - LineStart;
  SetLength(Starts, LineCount + 1);
  SetLength(Counts, LineCount + 1);
end;

function NearestMVLine(const Counts: TArray<Integer>; Line: Integer): Integer;
var Index, Distance: Integer;
begin
  Result := -1;
  if Length(Counts) = 0 then Exit;
  Index := Min(Line, High(Counts));
  for Distance := 0 to High(Counts) do
  begin
    if (Index - Distance >= 0) and (Counts[Index - Distance] > 0) then Exit(Index - Distance);
    if (Index + Distance <= High(Counts)) and (Counts[Index + Distance] > 0) then Exit(Index + Distance);
  end;
end;

procedure SetMVText(var Document: TMVDocument; const Text: string);
var
  Normalized, Chunk: string;
  List: TList<TMVPlacement>;
  Item: TMVPlacement;
  Code, Previous: Cardinal;
  I, J, K, Start, N, Prefix, Suffix, RegionalCount: Integer;
  OldMiddle, NewMiddle, Width, Substitution, Best: Integer;
  Line, OldLine, OldStart, OldCount, NewStart, NewCount: Integer;
  JoinNext, LyricsChanged: Boolean;
  NewUnits: TArray<TMVPlacement>;
  Mapping, Costs, OldStarts, OldCounts, NewStarts, NewCounts: TArray<Integer>;
begin
  Normalized := StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  LyricsChanged := Normalized <> Document.Text;
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
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < Length(NewUnits) - Prefix) and (Suffix < Length(Document.Units) - Prefix) and
    (NewUnits[High(NewUnits) - Suffix].Text = Document.Units[High(Document.Units) - Suffix].Text) do
    Inc(Suffix);
  SetLength(Mapping, Length(NewUnits));
  for K := 0 to High(Mapping) do Mapping[K] := -1;
  for K := 0 to Prefix - 1 do Mapping[K] := K;
  for K := 0 to Suffix - 1 do Mapping[High(Mapping) - K] := High(Document.Units) - K;
  OldMiddle := Length(Document.Units) - Prefix - Suffix;
  NewMiddle := Length(NewUnits) - Prefix - Suffix;
  // 同じ文字を安価に、置換を削除＋挿入と同じ費用にして、別フレーズでも書式の対応を残す。
  Width := NewMiddle + 1;
  SetLength(Costs, (OldMiddle + 1) * Width);
  for I := 0 to OldMiddle do Costs[I * Width] := I;
  for J := 0 to NewMiddle do Costs[J] := J;
  for I := 1 to OldMiddle do
    for J := 1 to NewMiddle do
    begin
      if Document.Units[Prefix + I - 1].Text = NewUnits[Prefix + J - 1].Text then Substitution := 0
      else if (Document.Units[Prefix + I - 1].Text = #10) or
        (NewUnits[Prefix + J - 1].Text = #10) then Substitution := MV_MAX_UNITS * 2 + 1
      else Substitution := 2;
      Best := Min(Costs[(I - 1) * Width + J] + 1, Costs[I * Width + J - 1] + 1);
      Costs[I * Width + J] := Min(Best, Costs[(I - 1) * Width + J - 1] + Substitution);
    end;
  I := OldMiddle;
  J := NewMiddle;
  while (I > 0) or (J > 0) do
  begin
    if (I > 0) and (J > 0) and
      (Document.Units[Prefix + I - 1].Text = NewUnits[Prefix + J - 1].Text) and
      (Costs[I * Width + J] = Costs[(I - 1) * Width + J - 1]) then
    begin
      Mapping[Prefix + J - 1] := Prefix + I - 1;
      Dec(I); Dec(J);
    end
    else if (I > J) and (I > 0) and
      (Costs[I * Width + J] = Costs[(I - 1) * Width + J] + 1) then Dec(I)
    else if (J > I) and (J > 0) and
      (Costs[I * Width + J] = Costs[I * Width + J - 1] + 1) then Dec(J)
    else if (I > 0) and (J > 0) and
      (Document.Units[Prefix + I - 1].Text <> #10) and (NewUnits[Prefix + J - 1].Text <> #10) and
      (Costs[I * Width + J] = Costs[(I - 1) * Width + J - 1] + 2) then
    begin
      Mapping[Prefix + J - 1] := Prefix + I - 1;
      Dec(I); Dec(J);
    end
    else if (I > 0) and (Costs[I * Width + J] = Costs[(I - 1) * Width + J] + 1) then Dec(I)
    else Dec(J);
  end;
  MVLineRanges(Document.Units, OldStarts, OldCounts);
  MVLineRanges(NewUnits, NewStarts, NewCounts);
  for Line := 0 to High(NewStarts) do
  begin
    OldLine := NearestMVLine(OldCounts, Line);
    if OldLine < 0 then Continue;
    OldStart := OldStarts[OldLine];
    OldCount := OldCounts[OldLine];
    NewStart := NewStarts[Line];
    NewCount := NewCounts[Line];
    for K := NewStart to NewStart + NewCount - 1 do
      if (Mapping[K] < OldStart) or (Mapping[K] >= OldStart + OldCount) then
        // 改行をまたぐ対応や未対応文字は、同じ行の相対位置にある旧文字の装飾へ戻す。
        Mapping[K] := OldStart + Min(OldCount - 1, (K - NewStart) * OldCount div NewCount);
  end;
  for K := 0 to High(NewUnits) do
    if Mapping[K] >= 0 then
    begin
      Item := Document.Units[Mapping[K]];
      Item.Text := NewUnits[K].Text;
      NewUnits[K] := Item;
    end;
  if LyricsChanged then
    for K := 0 to High(NewUnits) do
    begin
      // 組版側で行ごとに中央揃えする。旧フレーズの手動変形は新しい歌詞へ持ち込まない。
      NewUnits[K].X := 0;
      NewUnits[K].Y := 0;
      NewUnits[K].Positioned := False;
      NewUnits[K].Scale := 1;
      NewUnits[K].ScaleX := 1;
      NewUnits[K].ScaleY := 1;
      NewUnits[K].Angle := 0;
      NewUnits[K].Shear := 0;
    end;
  Document.Text := Normalized;
  Document.Units := NewUnits;
end;

end.
