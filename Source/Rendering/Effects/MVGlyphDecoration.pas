unit MVGlyphDecoration;

// 組版時に発光・2色のずれ・囲み枠を合成し、フレーム間で再利用する文字画像を作る。
interface

uses System.Types, System.Skia, MVDocument;

// Boundsを装飾込みへ拡張する。BaseBoundsは元文字のローカル矩形。書式と原画像は変更しない。
function DecorateMVGlyph(const Image: ISkImage; const BaseBounds: TRectF;
  const Style: TMVStyle; out Bounds: TRectF): ISkImage;

implementation

uses System.Math, System.SysUtils;

function DecorateMVGlyph(const Image: ISkImage; const BaseBounds: TRectF;
  const Style: TMVStyle; out Bounds: TRectF): ISkImage;
var Surface: ISkSurface; Paint: ISkPaint; R, Frame: TRectF; Extra, DX, DY: Single;
begin
  Result := Image;
  Bounds := BaseBounds;
  if Image = nil then Exit;
  Extra := Style.ChromaticOffset;
  if Style.GlowStrength > 0 then Extra := Max(Extra, Style.GlowRadius * 3);
  if Style.FrameWidth > 0 then Extra := Max(Extra, Style.FramePadding + Style.FrameWidth);
  if Extra <= 0 then Exit;
  Bounds.Inflate(Ceil(Extra) + 1, Ceil(Extra) + 1);
  if (Bounds.Width > 4096) or (Bounds.Height > 4096) or
    (Double(Bounds.Width) * Bounds.Height > 16777216) then
    raise EArgumentException.Create('文字装飾の画像サイズが上限を超えています。');
  Surface := TSkSurface.MakeRaster(Ceil(Bounds.Width), Ceil(Bounds.Height));
  if Surface = nil then raise EOutOfMemory.Create('文字装飾の画像を作成できません。');
  Surface.Canvas.Clear(0);
  R := BaseBounds;
  R.Offset(-Bounds.Left, -Bounds.Top);
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  if Style.GlowStrength > 0 then
  begin
    Paint.ColorFilter := TSkColorFilter.MakeBlend(Style.GlowColor, TSkBlendMode.SrcIn);
    Paint.ImageFilter := TSkImageFilter.MakeBlur(Style.GlowRadius, Style.GlowRadius);
    Paint.AlphaF := Style.GlowStrength;
    Surface.Canvas.DrawImageRect(Image, R, TSkSamplingOptions.High, Paint);
    Paint.ImageFilter := nil;
  end;
  Paint.AlphaF := 1;
  if Style.ChromaticOffset > 0 then
  begin
    DX := Cos(DegToRad(Style.ChromaticAngle)) * Style.ChromaticOffset;
    DY := Sin(DegToRad(Style.ChromaticAngle)) * Style.ChromaticOffset;
    Paint.ColorFilter := TSkColorFilter.MakeBlend(Style.ChromaticColor1, TSkBlendMode.SrcIn);
    R.Offset(DX, DY);
    Surface.Canvas.DrawImageRect(Image, R, TSkSamplingOptions.High, Paint);
    Paint.ColorFilter := TSkColorFilter.MakeBlend(Style.ChromaticColor2, TSkBlendMode.SrcIn);
    R.Offset(-2 * DX, -2 * DY);
    Surface.Canvas.DrawImageRect(Image, R, TSkSamplingOptions.High, Paint);
    R.Offset(DX, DY);
  end;
  Paint.ColorFilter := nil;
  if Style.FrameWidth > 0 then
  begin
    Frame := R;
    Frame.Inflate(Style.FramePadding, Style.FramePadding);
    Paint.Color := Style.FrameColor;
    Paint.Style := TSkPaintStyle.Stroke;
    Paint.StrokeWidth := Style.FrameWidth;
    Surface.Canvas.DrawRect(Frame, Paint);
    Paint.Style := TSkPaintStyle.Fill;
    Paint.Color := $FFFFFFFF;
  end;
  Surface.Canvas.DrawImageRect(Image, R, TSkSamplingOptions.High, Paint);
  Result := Surface.MakeImageSnapshot;
end;

end.
