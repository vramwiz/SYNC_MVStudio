unit TextRendererSkiaUnits;

// 組版済みグリフから文字単位の外接範囲と独立したRGBA画像を作る。

interface

uses
  System.Types,
  System.Skia,
  TextRendererTypes,
  TextRendererSkiaGeometry;

// 文字ごとの画像と位置情報をImageへ登録する。失敗時は作成途中の子画像を解放する。
procedure CaptureSkiaTextUnits(Image: TTextRenderImage; const Lines: TArray<TSkiaTextLine>;
  const Font: ISkFont; const Request: TTextRenderRequest; const FillPaint: ISkPaint;
  const OutlinePaints, OutlineLayoutPaints, ShadowPaints: TArray<ISkPaint>;
  const Bounds: TRect; const Decoration: TSkiaDecorationMetrics);

implementation

uses
  System.Math,
  System.SysUtils,
  System.UITypes;

const
  ANTI_ALIAS_PADDING = 2; // 文字単位画像の端で半透明画素を切らないための余白。

procedure IncludeUnitPaintBounds(const Font: ISkFont; const Line: TSkiaTextLine;
  const Paint: ISkPaint; OffsetX, OffsetY, InflateBy: Single;
  var LineBounds: TArray<TRectF>; var HasBounds: TArray<Boolean>);
var
  GlyphBounds: TArray<TRectF>;
  I: Integer;
  R: TRectF;
begin
  GlyphBounds := Font.GetBounds(Line.Glyphs, Paint);
  for I := 0 to Min(High(GlyphBounds), High(LineBounds)) do
  begin
    R := GlyphBounds[I];
    if (R.Width <= 0) and (R.Height <= 0) then
      Continue;
    R.Offset(Line.Positions[I].X + Line.X + OffsetX,
      Line.Positions[I].Y + Line.BaselineY + OffsetY);
    if InflateBy > 0 then
      R.Inflate(InflateBy, InflateBy);
    IncludeSkiaBounds(LineBounds[I], HasBounds[I], R);
  end;
end;

procedure IncludeUnitDecorationBounds(const Line: TSkiaTextLine;
  FontStyle: TTextRenderFontStyle; const Decoration: TSkiaDecorationMetrics;
  var LineBounds: TArray<TRectF>; var HasBounds: TArray<Boolean>);
var
  I: Integer;
  Left: Single;
  R: TRectF;
  Right: Single;
begin
  for I := 0 to High(LineBounds) do
  begin
    SkiaDecorationRange(Line, I, Left, Right);
    if Right <= Left then
      Continue;
    if TTextRenderFontStyleItem.Underline in FontStyle then
    begin
      R := TRectF.Create(Line.X + Left,
        Line.BaselineY + Decoration.UnderlinePosition - Decoration.UnderlineThickness * 0.5,
        Line.X + Right,
        Line.BaselineY + Decoration.UnderlinePosition + Decoration.UnderlineThickness * 0.5);
      IncludeSkiaBounds(LineBounds[I], HasBounds[I], R);
    end;
    if TTextRenderFontStyleItem.StrikeOut in FontStyle then
    begin
      R := TRectF.Create(Line.X + Left,
        Line.BaselineY + Decoration.StrikeoutPosition - Decoration.StrikeoutThickness * 0.5,
        Line.X + Right,
        Line.BaselineY + Decoration.StrikeoutPosition + Decoration.StrikeoutThickness * 0.5);
      IncludeSkiaBounds(LineBounds[I], HasBounds[I], R);
    end;
  end;
end;

function RenderSkiaLineUnit(const Line: TSkiaTextLine; GlyphIndex: Integer;
  const UnitRect, Bounds: TRect; const Font: ISkFont; const Request: TTextRenderRequest;
  const FillPaint: ISkPaint; const OutlinePaints, ShadowPaints: TArray<ISkPaint>;
  const Decoration: TSkiaDecorationMetrics): TTextRenderImage;
var
  Glyph: TArray<Word>;
  LocalCanvas: ISkCanvas;
  LocalImageInfo: TSkImageInfo;
  LocalPosition: TArray<TPointF>;
  LocalSurface: ISkSurface;
  OriginX, OriginY: Single;
  PaintIndex: Integer;
begin
  Result := TTextRenderImage.Create(UnitRect, UnitRect);
  try
    LocalImageInfo := TSkImageInfo.Create(Result.Width, Result.Height,
      TSkColorType.RGBA8888, TSkAlphaType.Unpremul);
    LocalSurface := TSkSurface.MakeRasterDirect(LocalImageInfo, Result.Data, Result.Stride);
    if LocalSurface = nil then
      raise EInvalidOp.Create('Cannot create text-unit raster surface');
    LocalCanvas := LocalSurface.Canvas;
    LocalCanvas.Clear(TAlphaColorRec.Null);
    Glyph := [Line.Glyphs[GlyphIndex]];
    LocalPosition := [Line.Positions[GlyphIndex]];
    OriginX := Line.X - Bounds.Left - UnitRect.Left;
    OriginY := Line.BaselineY - Bounds.Top - UnitRect.Top;
    for PaintIndex := 0 to High(ShadowPaints) do
      LocalCanvas.DrawGlyphs(Glyph, LocalPosition,
        PointF(OriginX + Request.Shadows[PaintIndex].Offset.X,
          OriginY + Request.Shadows[PaintIndex].Offset.Y), Font, ShadowPaints[PaintIndex]);
    for PaintIndex := 0 to High(OutlinePaints) do
      LocalCanvas.DrawGlyphs(Glyph, LocalPosition, PointF(OriginX, OriginY),
        Font, OutlinePaints[PaintIndex]);
    LocalCanvas.DrawGlyphs(Glyph, LocalPosition, PointF(OriginX, OriginY), Font, FillPaint);
    DrawSkiaLineDecorations(LocalCanvas, Line, OriginX, OriginY, GlyphIndex,
      Request.FontStyle, Decoration, FillPaint);
    LocalSurface.Flush;
  except
    Result.Free;
    raise;
  end;
end;

procedure CaptureSkiaTextUnits(Image: TTextRenderImage; const Lines: TArray<TSkiaTextLine>;
  const Font: ISkFont; const Request: TTextRenderRequest; const FillPaint: ISkPaint;
  const OutlinePaints, OutlineLayoutPaints, ShadowPaints: TArray<ISkPaint>;
  const Bounds: TRect; const Decoration: TSkiaDecorationMetrics);
var
  I, J, UnitIndex: Integer;
  HasUnitBounds: TArray<Boolean>;
  LineUnitBounds: TArray<TRectF>;
  TextUnitAdvances: TArray<Single>;
  TextUnitBounds: TArray<TRect>;
  TextUnitImages: TArray<TTextRenderImage>;
  TextUnitOrigins: TArray<TPointF>;
  UnitRect: TRect;
begin
  try
    for I := 0 to High(Lines) do
    begin
      if Length(Lines[I].Glyphs) = 0 then
      begin
        UnitIndex := Length(TextUnitBounds);
        SetLength(TextUnitAdvances, UnitIndex + 1);
        SetLength(TextUnitBounds, UnitIndex + 1);
        SetLength(TextUnitImages, UnitIndex + 1);
        SetLength(TextUnitOrigins, UnitIndex + 1);
        TextUnitAdvances[UnitIndex] := 0;
        TextUnitBounds[UnitIndex] := TRect.Empty;
        TextUnitImages[UnitIndex] := nil;
        TextUnitOrigins[UnitIndex] := PointF(0, 0);
        Continue;
      end;
      SetLength(LineUnitBounds, Length(Lines[I].Glyphs));
      SetLength(HasUnitBounds, Length(Lines[I].Glyphs));
      for J := 0 to High(HasUnitBounds) do
      begin
        LineUnitBounds[J] := TRectF.Empty;
        HasUnitBounds[J] := False;
      end;
      IncludeUnitPaintBounds(Font, Lines[I], FillPaint, 0, 0, 0,
        LineUnitBounds, HasUnitBounds);
      for J := 0 to High(OutlineLayoutPaints) do
        IncludeUnitPaintBounds(Font, Lines[I], OutlineLayoutPaints[J], 0, 0,
          Request.Outlines[J].BlurRadius * 3, LineUnitBounds, HasUnitBounds);
      for J := 0 to High(ShadowPaints) do
        IncludeUnitPaintBounds(Font, Lines[I], ShadowPaints[J],
          Request.Shadows[J].Offset.X, Request.Shadows[J].Offset.Y,
          Request.Shadows[J].BlurRadius * 3, LineUnitBounds, HasUnitBounds);
      IncludeUnitDecorationBounds(Lines[I], Request.FontStyle, Decoration,
        LineUnitBounds, HasUnitBounds);
      UnitIndex := Length(TextUnitBounds);
      SetLength(TextUnitAdvances, UnitIndex + Length(LineUnitBounds));
      SetLength(TextUnitBounds, UnitIndex + Length(LineUnitBounds));
      SetLength(TextUnitImages, UnitIndex + Length(LineUnitBounds));
      SetLength(TextUnitOrigins, UnitIndex + Length(LineUnitBounds));
      for J := 0 to High(LineUnitBounds) do
      begin
        TextUnitAdvances[UnitIndex + J] := Lines[I].Advances[J];
        TextUnitOrigins[UnitIndex + J] := PointF(
          Lines[I].X + Lines[I].Positions[J].X - Bounds.Left,
          Lines[I].BaselineY + Lines[I].Positions[J].Y - Bounds.Top);
        if HasUnitBounds[J] then
        begin
          UnitRect := TRect.Create(
            Floor(LineUnitBounds[J].Left) - Bounds.Left - ANTI_ALIAS_PADDING,
            Floor(LineUnitBounds[J].Top) - Bounds.Top - ANTI_ALIAS_PADDING,
            Ceil(LineUnitBounds[J].Right) - Bounds.Left + ANTI_ALIAS_PADDING,
            Ceil(LineUnitBounds[J].Bottom) - Bounds.Top + ANTI_ALIAS_PADDING);
          UnitRect.Intersect(TRect.Create(0, 0, Image.Width, Image.Height));
          TextUnitBounds[UnitIndex + J] := UnitRect;
          TextUnitImages[UnitIndex + J] := RenderSkiaLineUnit(Lines[I], J,
            UnitRect, Bounds, Font, Request, FillPaint, OutlinePaints, ShadowPaints, Decoration);
        end
        else
        begin
          TextUnitBounds[UnitIndex + J] := TRect.Empty;
          TextUnitImages[UnitIndex + J] := nil;
        end;
      end;
    end;
    Image.TextUnitAdvances := TextUnitAdvances;
    Image.TextUnitBounds := TextUnitBounds;
    Image.TextUnitOrigins := TextUnitOrigins;
    Image.SetTextUnitImages(TextUnitImages);
    TextUnitImages := nil;
  except
    for I := 0 to High(TextUnitImages) do
      TextUnitImages[I].Free;
    raise;
  end;
end;

end.
