unit TextRendererSkia;

// System.Skiaを使い、文字と装飾を直接RGBA画像へ描画する。

interface

uses
  System.Skia,
  TextRenderer,
  TextRendererTypes;

type
  TSkiaTextRenderer = class(TCustomTextRenderer)
  private
    function CreateTypeface(const AFontFamilies: TArray<string>;
      const AFontStyle: TTextRenderFontStyle): ISkTypeface;
  public
    // 指定フォントファミリーをSkiaが解決できるか返す。
    class function IsFontFamilyAvailable(const AFontFamily: string): Boolean; static;
    // 診断表示用のSkiaバックエンド名を返す。
    function BackendName: string; override;
    // 文字配置を測定し、装飾と文字単位情報を含むRGBA画像を生成する。
    function Render(const ARequest: TTextRenderRequest;
      out AMetrics: TTextRenderMetrics): TTextRenderImage; override;
  end;

implementation

uses
  System.Diagnostics,
  System.Math,
  System.SysUtils,
  System.Types,
  System.UITypes,
  TextRendererSkiaRuntime, TextRendererSkiaGeometry, TextRendererSkiaPaints,
  TextRendererSkiaUnits;

const
  ANTI_ALIAS_PADDING = 2; // 透明境界でアンチエイリアス画素を失わないための余白。

function CreateSkiaFontStyle(const AStyle: TTextRenderFontStyle): TSkFontStyle;
var
  Slant: TSkFontSlant;
  Weight: TSkFontWeight;
begin
  if TTextRenderFontStyleItem.Bold in AStyle then
    Weight := TSkFontWeight.Bold
  else
    Weight := TSkFontWeight.Normal;
  if TTextRenderFontStyleItem.Italic in AStyle then
    Slant := TSkFontSlant.Italic
  else
    Slant := TSkFontSlant.Upright;
  Result := TSkFontStyle.Create(Weight, TSkFontWidth.Normal, Slant);
end;

function CountNonTransparentPixels(const AImage: TTextRenderImage): NativeUInt;
var
  I: NativeInt;
  Pixel: PTextRenderPixel;
begin
  Result := 0;
  Pixel := AImage.Data;
  for I := 0 to AImage.PixelCount - 1 do
  begin
    if Pixel^.A <> 0 then
      Inc(Result);
    Inc(Pixel);
  end;
end;

{ TSkiaTextRenderer }

function TSkiaTextRenderer.BackendName: string;
begin
  Result := 'Skia raster-direct';
end;

class function TSkiaTextRenderer.IsFontFamilyAvailable(
  const AFontFamily: string): Boolean;
begin
  Result := (Trim(AFontFamily) <> '') and
    (TSkTypeface.MakeFromName(AFontFamily, TSkFontStyle.Normal) <> nil);
end;

function TSkiaTextRenderer.CreateTypeface(
  const AFontFamilies: TArray<string>;
  const AFontStyle: TTextRenderFontStyle): ISkTypeface;
var
  FamilyName: string;
  SkiaStyle: TSkFontStyle;
begin
  SkiaStyle := CreateSkiaFontStyle(AFontStyle);
  for FamilyName in AFontFamilies do
  begin
    Result := TSkTypeface.MakeFromName(FamilyName, SkiaStyle);
    if Result <> nil then
      Exit;
  end;
  Result := TSkTypeface.MakeDefault;
  if Result = nil then
    raise EInvalidOp.Create('No usable typeface is available');
end;

function TSkiaTextRenderer.Render(const ARequest: TTextRenderRequest;
  out AMetrics: TTextRenderMetrics): TTextRenderImage;
var
  Bounds: TRect;
  Canvas: ISkCanvas;
  FillPaint: ISkPaint;
  FloatBounds: TRectF;
  Font: ISkFont;
  FontMetrics: TSkFontMetrics;
  HasBounds: Boolean;
  HasLayoutBounds: Boolean;
  I: Integer;
  ImageInfo: TSkImageInfo;
  J: Integer;
  LineAdvance: Single;
  LineBounds: TRectF;
  Lines: TArray<TSkiaTextLine>;
  LayoutStopwatch: TStopwatch;
  LayoutBounds: TRect;
  LineLayoutBounds: TArray<TRect>;
  LayoutFloatBounds: TRectF;
  MaxLineWidth: Single;
  MeasuredBounds: TRectF;
  NormalizedText: string;
  Paints: TSkiaTextPaints;
  OutlineLayoutPaints: TArray<ISkPaint>;
  OutlinePaints: TArray<ISkPaint>;
  ShadowBounds: TRectF;
  ShadowPaints: TArray<ISkPaint>;
  Surface: ISkSurface;
  TextLines: TArray<string>;
  TotalStopwatch: TStopwatch;
  Typeface: ISkTypeface;
  DrawStopwatch: TStopwatch;
  UnderlinePosition: Single;
  UnderlineThickness: Single;
  StrikeoutPosition: Single;
  StrikeoutThickness: Single;
  Decoration: TSkiaDecorationMetrics;
begin
  AMetrics := System.Default(TTextRenderMetrics);
  TotalStopwatch := TStopwatch.StartNew;
  if not TTextRendererSkiaRuntime.IsAcquired then
    raise EInvalidOp.Create('Skia runtime is not acquired');
  if ARequest.FontSize <= 0 then
    raise EArgumentOutOfRangeException.Create('FontSize must be greater than zero');
  if ARequest.Direction <> TTextRenderDirection.Horizontal then
    raise ENotSupportedException.Create('Vertical text is not implemented yet');
  if (ARequest.MaxWidth <> 0) or (ARequest.MaxHeight <> 0) then
    raise ENotSupportedException.Create('Constrained layout is not implemented yet');
  if not ARequest.TrimTransparentBounds then
    raise ENotSupportedException.Create('Untrimmed output is not implemented yet');
  if ARequest.Text = '' then
  begin
    Result := TTextRenderImage.Create(TRect.Empty);
    AMetrics.TotalMilliseconds := TotalStopwatch.Elapsed.TotalMilliseconds;
    Exit;
  end;

  LayoutStopwatch := TStopwatch.StartNew;
  Typeface := CreateTypeface(ARequest.FontFamilies, ARequest.FontStyle);
  Font := TSkFont.Create(Typeface, ARequest.FontSize);
  Font.Edging := TSkFontEdging.AntiAlias;

  Paints := CreateSkiaTextPaints(ARequest);
  FillPaint := Paints.Fill;
  OutlinePaints := Paints.Outlines;
  OutlineLayoutPaints := Paints.OutlineLayout;
  ShadowPaints := Paints.Shadows;

  NormalizedText := StringReplace(ARequest.Text, #13#10, #10,
    [rfReplaceAll]);
  NormalizedText := StringReplace(NormalizedText, #13, #10,
    [rfReplaceAll]);
  TextLines := NormalizedText.Split([#10], TStringSplitOptions.None);
  SetLength(Lines, Length(TextLines));
  Font.GetMetrics(FontMetrics);
  if (TSkFontMetricsFlag.UnderlinePositionIsValid in FontMetrics.Flags) then
    UnderlinePosition := FontMetrics.UnderlinePosition
  else
    UnderlinePosition := Max(1, ARequest.FontSize * 0.08);
  if (TSkFontMetricsFlag.UnderlineThicknessIsValid in FontMetrics.Flags) and
    (FontMetrics.UnderlineThickness > 0) then
    UnderlineThickness := FontMetrics.UnderlineThickness
  else
    UnderlineThickness := Max(1, ARequest.FontSize * 0.06);
  if (TSkFontMetricsFlag.StrikeoutPositionIsValid in FontMetrics.Flags) then
    StrikeoutPosition := FontMetrics.StrikeoutPosition
  else
    StrikeoutPosition := FontMetrics.XHeight * -0.5;
  if (TSkFontMetricsFlag.StrikeoutThicknessIsValid in FontMetrics.Flags) and
    (FontMetrics.StrikeoutThickness > 0) then
    StrikeoutThickness := FontMetrics.StrikeoutThickness
  else
    StrikeoutThickness := UnderlineThickness;
  Decoration.UnderlinePosition := UnderlinePosition;
  Decoration.UnderlineThickness := UnderlineThickness;
  Decoration.StrikeoutPosition := StrikeoutPosition;
  Decoration.StrikeoutThickness := StrikeoutThickness;
  LineAdvance := Max(1, Font.GetSpacing + ARequest.LineSpacing);
  MaxLineWidth := 0;
  for I := 0 to High(Lines) do
  begin
    Lines[I].Text := TextLines[I];
    Lines[I].BaselineY := I * LineAdvance;
    if Lines[I].Text <> '' then
    begin
      Lines[I].Glyphs := Font.GetGlyphs(Lines[I].Text);
      Lines[I].Positions := Font.GetPositions(Lines[I].Glyphs);
      Lines[I].Advances := Font.GetWidths(Lines[I].Glyphs);
      // 本体と文字単位レイヤーを同じグリフ座標から描く。これにより可変幅、
      // 句読点、空白を等分推測せず、拡大・ジャンプ時にも位置が一致する。
      Lines[I].Positioned := True;
      for J := 0 to High(Lines[I].Positions) do
      begin
        Lines[I].Positions[J].X := Lines[I].Positions[J].X +
          J * ARequest.LetterSpacing;
        if J < High(Lines[I].Advances) then
          Lines[I].Advances[J] := Lines[I].Advances[J] +
            ARequest.LetterSpacing;
      end;
      MeasureSkiaLine(Font, Lines[I], FillPaint, LineBounds);
      for J := 0 to High(OutlineLayoutPaints) do
      begin
        MeasureSkiaLine(Font, Lines[I], OutlineLayoutPaints[J], MeasuredBounds);
        LineBounds.Left := Min(LineBounds.Left, MeasuredBounds.Left);
        LineBounds.Top := Min(LineBounds.Top, MeasuredBounds.Top);
        LineBounds.Right := Max(LineBounds.Right, MeasuredBounds.Right);
        LineBounds.Bottom := Max(LineBounds.Bottom, MeasuredBounds.Bottom);
      end;
      IncludeSkiaLineDecorationBounds(Lines[I], ARequest.FontStyle, Decoration, LineBounds);
    end
    else
      LineBounds := TRectF.Create(0, FontMetrics.Ascent, 0,
        FontMetrics.Descent);
    Lines[I].LayoutBounds := LineBounds;
    MaxLineWidth := Max(MaxLineWidth, LineBounds.Width);
  end;

  HasLayoutBounds := False;
  for I := 0 to High(Lines) do
  begin
    case ARequest.Alignment of
      TTextRenderAlignment.Center:
        Lines[I].X := (MaxLineWidth - Lines[I].LayoutBounds.Width) * 0.5 -
          Lines[I].LayoutBounds.Left;
      TTextRenderAlignment.Trailing:
        Lines[I].X := MaxLineWidth - Lines[I].LayoutBounds.Width -
          Lines[I].LayoutBounds.Left;
    else
      Lines[I].X := -Lines[I].LayoutBounds.Left;
    end;
    LineBounds := Lines[I].LayoutBounds;
    LineBounds.Offset(Lines[I].X, Lines[I].BaselineY);
    Lines[I].LayoutBounds := LineBounds;
    IncludeSkiaBounds(LayoutFloatBounds, HasLayoutBounds, LineBounds);
  end;

  FloatBounds := LayoutFloatBounds;
  HasBounds := HasLayoutBounds;
  for I := 0 to High(Lines) do
    if Lines[I].Text <> '' then
      for J := 0 to High(OutlinePaints) do
        if ARequest.Outlines[J].BlurRadius > 0 then
        begin
          MeasureSkiaLine(Font, Lines[I], OutlineLayoutPaints[J], MeasuredBounds);
          MeasuredBounds.Offset(Lines[I].X, Lines[I].BaselineY);
          MeasuredBounds.Inflate(ARequest.Outlines[J].BlurRadius * 3,
            ARequest.Outlines[J].BlurRadius * 3);
          IncludeSkiaBounds(FloatBounds, HasBounds, MeasuredBounds);
        end;
  for I := 0 to High(Lines) do
    if Lines[I].Text <> '' then
      for J := 0 to High(ShadowPaints) do
      begin
        MeasureSkiaLine(Font, Lines[I], ShadowPaints[J], ShadowBounds);
        ShadowBounds.Offset(Lines[I].X + ARequest.Shadows[J].Offset.X,
          Lines[I].BaselineY + ARequest.Shadows[J].Offset.Y);
        ShadowBounds.Inflate(ARequest.Shadows[J].BlurRadius * 3,
          ARequest.Shadows[J].BlurRadius * 3);
        IncludeSkiaBounds(FloatBounds, HasBounds, ShadowBounds);
      end;

  LayoutBounds := TRect.Create(
    Floor(LayoutFloatBounds.Left) - ANTI_ALIAS_PADDING,
    Floor(LayoutFloatBounds.Top) - ANTI_ALIAS_PADDING,
    Ceil(LayoutFloatBounds.Right) + ANTI_ALIAS_PADDING,
    Ceil(LayoutFloatBounds.Bottom) + ANTI_ALIAS_PADDING);
  Bounds := TRect.Create(
    Floor(FloatBounds.Left) - ANTI_ALIAS_PADDING,
    Floor(FloatBounds.Top) - ANTI_ALIAS_PADDING,
    Ceil(FloatBounds.Right) + ANTI_ALIAS_PADDING,
    Ceil(FloatBounds.Bottom) + ANTI_ALIAS_PADDING);
  Result := TTextRenderImage.Create(Bounds, LayoutBounds);
  SetLength(LineLayoutBounds, Length(Lines));
  for I := 0 to High(Lines) do
    if Lines[I].Text = '' then
      LineLayoutBounds[I] := TRect.Create(
        Round(Lines[I].LayoutBounds.Left),
        Floor(Lines[I].LayoutBounds.Top) - ANTI_ALIAS_PADDING,
        Round(Lines[I].LayoutBounds.Left),
        Ceil(Lines[I].LayoutBounds.Bottom) + ANTI_ALIAS_PADDING)
    else
      LineLayoutBounds[I] := TRect.Create(
        Floor(Lines[I].LayoutBounds.Left) - ANTI_ALIAS_PADDING,
        Floor(Lines[I].LayoutBounds.Top) - ANTI_ALIAS_PADDING,
        Ceil(Lines[I].LayoutBounds.Right) + ANTI_ALIAS_PADDING,
        Ceil(Lines[I].LayoutBounds.Bottom) + ANTI_ALIAS_PADDING);
  Result.LineLayoutBounds := LineLayoutBounds;
  if ARequest.CaptureTextUnits then
    try
      CaptureSkiaTextUnits(Result, Lines, Font, ARequest, FillPaint,
        OutlinePaints, OutlineLayoutPaints, ShadowPaints, Bounds, Decoration);
    except
      Result.Free;
      raise;
    end;
  LayoutStopwatch.Stop;
  AMetrics.LayoutMilliseconds := LayoutStopwatch.Elapsed.TotalMilliseconds;

  try
    DrawStopwatch := TStopwatch.StartNew;
    ImageInfo := TSkImageInfo.Create(Result.Width, Result.Height,
      TSkColorType.RGBA8888, TSkAlphaType.Unpremul);
    Surface := TSkSurface.MakeRasterDirect(ImageInfo, Result.Data, Result.Stride);
    if Surface = nil then
      raise EInvalidOp.Create('Cannot create raster-direct surface');
    Canvas := Surface.Canvas;
    Canvas.Clear(TAlphaColorRec.Null);
    for I := 0 to High(Lines) do
      if Lines[I].Text <> '' then
      begin
        for J := 0 to High(ShadowPaints) do
          DrawSkiaLine(Canvas, Font, Lines[I],
            Lines[I].X - Bounds.Left + ARequest.Shadows[J].Offset.X,
            Lines[I].BaselineY - Bounds.Top + ARequest.Shadows[J].Offset.Y,
            ShadowPaints[J]);
        for J := 0 to High(OutlinePaints) do
          DrawSkiaLine(Canvas, Font, Lines[I], Lines[I].X - Bounds.Left,
            Lines[I].BaselineY - Bounds.Top, OutlinePaints[J]);
        DrawSkiaLine(Canvas, Font, Lines[I], Lines[I].X - Bounds.Left,
          Lines[I].BaselineY - Bounds.Top, FillPaint);
        DrawSkiaLineDecorations(Canvas, Lines[I], Lines[I].X - Bounds.Left,
          Lines[I].BaselineY - Bounds.Top, -1, ARequest.FontStyle, Decoration, FillPaint);
      end;
    Surface.Flush;
    DrawStopwatch.Stop;
    AMetrics.DrawMilliseconds := DrawStopwatch.Elapsed.TotalMilliseconds;
    AMetrics.NonTransparentPixelCount := CountNonTransparentPixels(Result);
    AMetrics.TotalMilliseconds := TotalStopwatch.Elapsed.TotalMilliseconds;
  except
    Result.Free;
    raise;
  end;
end;

end.
