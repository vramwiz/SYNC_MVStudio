unit MVArrangement;

// 選択文字を歌詞順に整列する。個別の倍率・回転と装飾を保ち、位置だけを変更する。
interface

uses MVDocument, MVLayout;

// Indicesが空なら全可視文字。Modeは縦0・横1・斜め2。選択全体の中心を保つ。
procedure ArrangeMVUnits(var Document: TMVDocument; Layout: TMVLayout; const Indices: TArray<Integer>;
  Mode: Integer; Gap, SideStep: Single);

implementation

uses System.Types, System.Math, System.SysUtils, MVAnimationTypes, MVAnimatedBounds;

procedure ArrangeMVUnits(var Document: TMVDocument; Layout: TMVLayout; const Indices: TArray<Integer>;
  Mode: Integer; Gap, SideStep: Single);
var Selected: array[0..MV_MAX_UNITS - 1] of Boolean; I, N: Integer;
    Before, After, R: TRectF; Delta, Target: TPointF; Cursor, Extent: Single; Candidate: TMVDocument;
begin
  if (Layout = nil) or (Length(Layout.Units) <> Length(Document.Units)) then Exit;
  if Length(Document.Units) > MV_MAX_UNITS then Exit;
  if not (Mode in [0..2]) or IsNan(Gap) or IsInfinite(Gap) or (Abs(Gap) > 512) or
    IsNan(SideStep) or IsInfinite(SideStep) or (Abs(SideStep) > 512) then
    raise EArgumentException.Create('整列の設定値が有効な範囲外です。');
  for I := Low(Selected) to High(Selected) do Selected[I] := False;
  if Length(Indices) = 0 then
  begin
    for I := 0 to High(Document.Units) do Selected[I] := Layout.Units[I].Image <> nil;
  end
  else
    for I in Indices do
      if (I >= 0) and (I < Length(Document.Units)) then Selected[I] := Layout.Units[I].Image <> nil;
  Candidate := CloneMVDocument(Document);
  N := 0; Cursor := 0; Before := TRectF.Empty; After := TRectF.Empty;
  for I := 0 to High(Candidate.Units) do
    if Selected[I] then
    begin
      R := MVAnimatedGlyphBounds(Candidate.Units[I], Layout.Units[I].HitBounds,
        Layout.Units[I].Position, 0, DefaultMVMotion);
      if N = 0 then Before := R else Before := TRectF.Union(Before, R);
      if Mode = 1 then
      begin
        Extent := R.Width; Target := PointF(Cursor + Extent / 2, 0);
      end
      else
      begin
        Extent := R.Height; Target := PointF(0, Cursor + Extent / 2);
        if Mode = 2 then Target.X := N * SideStep;
      end;
      Delta := Target - R.CenterPoint;
      Candidate.Units[I].X := Layout.Units[I].Position.X + Delta.X;
      Candidate.Units[I].Y := Layout.Units[I].Position.Y + Delta.Y;
      Candidate.Units[I].Positioned := True;
      R.Offset(Delta);
      if N = 0 then After := R else After := TRectF.Union(After, R);
      Cursor := Cursor + Max(1, Extent + Gap);
      Inc(N);
    end;
  if N = 0 then Exit;
  Delta := Before.CenterPoint - After.CenterPoint;
  for I := 0 to High(Candidate.Units) do
    if Selected[I] then
    begin
      Candidate.Units[I].X := Candidate.Units[I].X + Delta.X;
      Candidate.Units[I].Y := Candidate.Units[I].Y + Delta.Y;
    end;
  ValidateMVDocument(Candidate);
  Document := Candidate;
end;

end.
