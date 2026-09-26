unit MVGlyphEffects;

// 演出が返すぼかし・表示範囲・分割模様をSkiaへ適用する。時刻と種類IDの分岐は持たない。
interface

uses System.Types, System.Skia, MVAnimationTypes, MVLayout, MVAppearanceRenderer;

// 現在の座標系で表示範囲と模様を切り抜く。文字にも、まとまり全体の矩形にも使用する。
procedure ClipMVAnimatedBounds(const Canvas: ISkCanvas; const Bounds: TRectF; const Motion: TMVMotion);

// 変形済みCanvasへ文字画像を描く。共有Paintのフィルターは次の文字へ持ち越さない。
procedure DrawMVAnimatedGlyph(const Canvas: ISkCanvas; const Image: ISkImage; const Bounds: TRectF;
  const Motion: TMVMotion; const Paint: ISkPaint);
// 時間装飾を含めた文字を描く。無効なら従来の焼き込み画像をそのまま使う。
procedure DrawMVStyledGlyph(const Canvas: ISkCanvas; const Glyph: TMVLayoutUnit;
  const Motion: TMVMotion; const Context: TMVAppearanceContext; const Paint: ISkPaint);

implementation

uses MVGlyphPatterns;

procedure DrawMVStyledGlyph(const Canvas: ISkCanvas; const Glyph: TMVLayoutUnit;
  const Motion: TMVMotion; const Context: TMVAppearanceContext; const Paint: ISkPaint);
var Bounds, LayerBounds: TRectF; I: Integer;
begin
  if not HasMVAppearance(Context.Frame) then
  begin
    DrawMVAnimatedGlyph(Canvas, Glyph.Image, Glyph.Bounds, Motion, Paint);
    Exit;
  end;
  if (Motion.ClipRight <= Motion.ClipLeft) or (Motion.ClipBottom <= Motion.ClipTop) or
    ((Motion.Mask <> mamNone) and (Motion.MaskVisibility <= 0)) then Exit;
  Bounds := MVAppearanceBounds(Glyph, Context.Frame);
  Canvas.Save;
  try
    ClipMVAnimatedBounds(Canvas, Bounds, Motion);
    Paint.AlphaF := Motion.Opacity;
    if Motion.BlurSigma > 0.01 then
      Paint.ImageFilter := TSkImageFilter.MakeBlur(Motion.BlurSigma, Motion.BlurSigma);
    LayerBounds := Bounds;
    LayerBounds.Inflate(Motion.BlurSigma * 3 + Motion.GlitchAmount, Motion.BlurSigma * 3);
    // 各装飾に透明度を別々に掛けず、一度合成した文字像へまとめて適用する。
    Canvas.SaveLayer(LayerBounds, Paint);
    try
      if Motion.GlitchAmount <= 0.01 then DrawMVAppearance(Canvas, Glyph, Context)
      else
        for I := 0 to MV_GLITCH_BANDS - 1 do
        begin
          Canvas.Save;
          try
            Canvas.ClipRect(MVGlitchBandBounds(Bounds, I, Motion.GlitchAmount), TSkClipOp.Intersect, False);
            Canvas.Translate(MVGlitchBandOffset(I, Motion), 0);
            DrawMVAppearance(Canvas, Glyph, Context);
          finally
            Canvas.Restore;
          end;
        end;
    finally
      Canvas.Restore;
    end;
  finally
    Paint.ImageFilter := nil;
    Canvas.Restore;
  end;
end;

procedure ClipMVAnimatedBounds(const Canvas: ISkCanvas; const Bounds: TRectF; const Motion: TMVMotion);
var Clip: TRectF;
begin
  if (Motion.ClipLeft > 0) or (Motion.ClipRight < 1) or (Motion.ClipTop > 0) or (Motion.ClipBottom < 1) then
  begin
    Clip := RectF(Bounds.Left + Bounds.Width * Motion.ClipLeft, Bounds.Top + Bounds.Height * Motion.ClipTop,
      Bounds.Left + Bounds.Width * Motion.ClipRight, Bounds.Top + Bounds.Height * Motion.ClipBottom);
    Canvas.ClipRect(Clip, TSkClipOp.Intersect, True);
  end;
  ClipMVGlyphPattern(Canvas, Bounds, Motion);
end;

procedure DrawMVAnimatedGlyph(const Canvas: ISkCanvas; const Image: ISkImage; const Bounds: TRectF;
  const Motion: TMVMotion; const Paint: ISkPaint);
begin
  if (Motion.ClipRight <= Motion.ClipLeft) or (Motion.ClipBottom <= Motion.ClipTop) then Exit;
  if (Motion.Mask <> mamNone) and (Motion.MaskVisibility <= 0) then Exit;
  Canvas.Save;
  try
    ClipMVAnimatedBounds(Canvas, Bounds, Motion);
    Paint.AlphaF := Motion.Opacity;
    if Motion.BlurSigma > 0.01 then
      Paint.ImageFilter := TSkImageFilter.MakeBlur(Motion.BlurSigma, Motion.BlurSigma);
    DrawMVGlitchedGlyph(Canvas, Image, Bounds, Motion, Paint);
  finally
    Paint.ImageFilter := nil;
    Canvas.Restore;
  end;
end;

end.
