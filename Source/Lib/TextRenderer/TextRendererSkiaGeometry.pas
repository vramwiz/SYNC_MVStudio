unit TextRendererSkiaGeometry;

// Skia文字列の行配置、外接範囲、下線・取り消し線の幾何と描画を共用する。

interface

uses
  System.Types,
  System.Skia,
  TextRendererTypes;

type
  TSkiaTextLine = record
    Advances     : TArray<Single>;  // グリフごとの装飾範囲を決める送り幅。
    BaselineY    : Single;          // 行の描画基線。
    Blob         : ISkTextBlob;     // グリフ位置を個別指定しない場合の描画内容。
    Glyphs       : TArray<Word>;    // Fontから取得したグリフID。
    LayoutBounds : TRectF;          // 影・ぼかしを除いた行の範囲。
    Positioned   : Boolean;         // TrueならPositionsを用いて描画する。
    Positions    : TArray<TPointF>; // 行内のグリフ位置。
    Text         : string;          // 改行を除いた行の文字列。
    X            : Single;          // 行揃えで決めた横方向の移動量。
  end;

  TSkiaDecorationMetrics = record
    UnderlinePosition   : Single; // 基線からの下線中心位置。
    UnderlineThickness  : Single; // 下線の幅。
    StrikeoutPosition   : Single; // 基線からの取り消し線中心位置。
    StrikeoutThickness  : Single; // 取り消し線の幅。
  end;

// 最初の矩形か既存範囲との和集合をTargetへ反映する。
procedure IncludeSkiaBounds(var Target: TRectF; var HasBounds: Boolean; const Source: TRectF);
// 行全体の塗りまたは縁の実際のグリフ範囲を返す。
procedure MeasureSkiaLine(const Font: ISkFont; const Line: TSkiaTextLine;
  const Paint: ISkPaint; out Bounds: TRectF);
// 行のグリフを指定した基線へ描く。
procedure DrawSkiaLine(const Canvas: ISkCanvas; const Font: ISkFont; const Line: TSkiaTextLine;
  X, Y: Single; const Paint: ISkPaint);
// GlyphIndexが-1なら行全体、0以上なら1グリフの装飾用横範囲を返す。
procedure SkiaDecorationRange(const Line: TSkiaTextLine; GlyphIndex: Integer;
  out Left, Right: Single);
// 下線・取り消し線を行の組版範囲へ含める。
procedure IncludeSkiaLineDecorationBounds(const Line: TSkiaTextLine;
  FontStyle: TTextRenderFontStyle; const Metrics: TSkiaDecorationMetrics; var Bounds: TRectF);
// 行または指定グリフの下線・取り消し線を描く。
procedure DrawSkiaLineDecorations(const Canvas: ISkCanvas; const Line: TSkiaTextLine;
  X, Y: Single; GlyphIndex: Integer; FontStyle: TTextRenderFontStyle;
  const Metrics: TSkiaDecorationMetrics; const FillPaint: ISkPaint);

implementation

uses
  System.Math;

procedure IncludeSkiaBounds(var Target: TRectF; var HasBounds: Boolean; const Source: TRectF);
begin
  if not HasBounds then
  begin
    Target := Source;
    HasBounds := True;
    Exit;
  end;
  Target.Left := Min(Target.Left, Source.Left);
  Target.Top := Min(Target.Top, Source.Top);
  Target.Right := Max(Target.Right, Source.Right);
  Target.Bottom := Max(Target.Bottom, Source.Bottom);
end;

procedure MeasureSkiaLine(const Font: ISkFont; const Line: TSkiaTextLine;
  const Paint: ISkPaint; out Bounds: TRectF);
var
  GlyphBounds: TArray<TRectF>;
  HasBounds: Boolean;
  I: Integer;
  R: TRectF;
begin
  if not Line.Positioned then
  begin
    Font.MeasureText(Line.Text, Bounds, Paint);
    Exit;
  end;
  GlyphBounds := Font.GetBounds(Line.Glyphs, Paint);
  HasBounds := False;
  for I := 0 to High(GlyphBounds) do
  begin
    R := GlyphBounds[I];
    R.Offset(Line.Positions[I]);
    IncludeSkiaBounds(Bounds, HasBounds, R);
  end;
  if not HasBounds then
    Bounds := TRectF.Empty;
end;

procedure DrawSkiaLine(const Canvas: ISkCanvas; const Font: ISkFont; const Line: TSkiaTextLine;
  X, Y: Single; const Paint: ISkPaint);
begin
  if Line.Positioned then
    Canvas.DrawGlyphs(Line.Glyphs, Line.Positions, PointF(X, Y), Font, Paint)
  else
    Canvas.DrawTextBlob(Line.Blob, X, Y, Paint);
end;

procedure SkiaDecorationRange(const Line: TSkiaTextLine; GlyphIndex: Integer;
  out Left, Right: Single);
var
  I: Integer;
  SegmentLeft: Single;
  SegmentRight: Single;
  Temporary: Single;
begin
  Left := 0;
  Right := 0;
  if Length(Line.Glyphs) = 0 then
    Exit;
  if GlyphIndex >= 0 then
  begin
    Left := Line.Positions[GlyphIndex].X;
    Right := Left + Line.Advances[GlyphIndex];
    if Right < Left then
    begin
      Temporary := Left;
      Left := Right;
      Right := Temporary;
    end;
    Exit;
  end;
  Left := Line.Positions[0].X;
  Right := Left + Line.Advances[0];
  if Right < Left then
  begin
    Temporary := Left;
    Left := Right;
    Right := Temporary;
  end;
  for I := 1 to High(Line.Glyphs) do
  begin
    SegmentLeft := Line.Positions[I].X;
    SegmentRight := SegmentLeft + Line.Advances[I];
    if SegmentRight < SegmentLeft then
    begin
      Temporary := SegmentLeft;
      SegmentLeft := SegmentRight;
      SegmentRight := Temporary;
    end;
    Left := Min(Left, SegmentLeft);
    Right := Max(Right, SegmentRight);
  end;
end;

procedure IncludeSkiaLineDecorationBounds(const Line: TSkiaTextLine;
  FontStyle: TTextRenderFontStyle; const Metrics: TSkiaDecorationMetrics; var Bounds: TRectF);
var
  DecorationBounds: TRectF;
  HasBounds: Boolean;
  Left: Single;
  Right: Single;
begin
  if not ((TTextRenderFontStyleItem.Underline in FontStyle) or
    (TTextRenderFontStyleItem.StrikeOut in FontStyle)) then
    Exit;
  SkiaDecorationRange(Line, -1, Left, Right);
  HasBounds := (Bounds.Width <> 0) or (Bounds.Height <> 0);
  if TTextRenderFontStyleItem.Underline in FontStyle then
  begin
    DecorationBounds := TRectF.Create(Left,
      Metrics.UnderlinePosition - Metrics.UnderlineThickness * 0.5, Right,
      Metrics.UnderlinePosition + Metrics.UnderlineThickness * 0.5);
    IncludeSkiaBounds(Bounds, HasBounds, DecorationBounds);
  end;
  if TTextRenderFontStyleItem.StrikeOut in FontStyle then
  begin
    DecorationBounds := TRectF.Create(Left,
      Metrics.StrikeoutPosition - Metrics.StrikeoutThickness * 0.5, Right,
      Metrics.StrikeoutPosition + Metrics.StrikeoutThickness * 0.5);
    IncludeSkiaBounds(Bounds, HasBounds, DecorationBounds);
  end;
end;

procedure DrawSkiaLineDecorations(const Canvas: ISkCanvas; const Line: TSkiaTextLine;
  X, Y: Single; GlyphIndex: Integer; FontStyle: TTextRenderFontStyle;
  const Metrics: TSkiaDecorationMetrics; const FillPaint: ISkPaint);
var
  Left: Single;
  Right: Single;
begin
  SkiaDecorationRange(Line, GlyphIndex, Left, Right);
  if Right <= Left then
    Exit;
  if TTextRenderFontStyleItem.Underline in FontStyle then
    Canvas.DrawRect(TRectF.Create(X + Left,
      Y + Metrics.UnderlinePosition - Metrics.UnderlineThickness * 0.5, X + Right,
      Y + Metrics.UnderlinePosition + Metrics.UnderlineThickness * 0.5), FillPaint);
  if TTextRenderFontStyleItem.StrikeOut in FontStyle then
    Canvas.DrawRect(TRectF.Create(X + Left,
      Y + Metrics.StrikeoutPosition - Metrics.StrikeoutThickness * 0.5, X + Right,
      Y + Metrics.StrikeoutPosition + Metrics.StrikeoutThickness * 0.5), FillPaint);
end;

end.
