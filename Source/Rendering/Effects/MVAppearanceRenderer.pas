unit MVAppearanceRenderer;

// キャッシュ済み文字から時間装飾を合成する。組版や文字画像の再生成は行わない。
interface

uses System.Types, System.Math.Vectors, System.Skia, MVLayout, MVAppearanceTypes;

type
  TMVAppearanceContext = record
    Frame: TMVAppearanceFrame; // 今回描く時刻の装飾値。残像ではその過去時刻を使う。
    Tint: ISkColorFilter; // フレーズ全体で共用する今回の色変化。
    Sweep: ISkShader; // 出力画像の座標で定義した走査光。
    OutputToDevice: TMatrix; // プレビューの倍率等を含む出力座標からCanvasへの変換。
    Ink: ISkPaint; // この描画パス内で共用する装飾用Paint。
  end;

// 時間装飾で必要となる最大矩形。位相で中心やクリップ範囲が揺れないよう振幅で確保する。
function MVAppearanceBounds(const Glyph: TMVLayoutUnit; const Frame: TMVAppearanceFrame): TRectF;
// 焼き込み画像から動的な描画へ切り替える必要があるかを返す。
function HasMVAppearance(const Frame: TMVAppearanceFrame): Boolean;
// 出力座標のフレーズ矩形から共通の光を作る。Paintと今回の色もパス内で共有する。
function CreateMVAppearanceContext(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Frame: TMVAppearanceFrame): TMVAppearanceContext;
// 変形済みCanvasへ発光・色ずれ・枠・文字・走査光を描く。不透明度と動作のぼかしは呼出し側で適用する。
procedure DrawMVAppearance(const Canvas: ISkCanvas; const Glyph: TMVLayoutUnit;
  const Context: TMVAppearanceContext);

implementation

uses System.Math, System.UITypes;

function HasMVAppearance(const Frame: TMVAppearanceFrame): Boolean;
begin
  Result := Frame.Active and Frame.Dynamic;
end;

function MVAppearanceBounds(const Glyph: TMVLayoutUnit; const Frame: TMVAppearanceFrame): TRectF;
var Extra: Single;
begin
  Result := Glyph.Bounds;
  if not Frame.Active or ((Frame.GlowMix <= 0) and (Frame.ChromaticMargin <= 0)) then Exit;
  Extra := Glyph.Style.ChromaticOffset + Frame.ChromaticMargin;
  if Frame.GlowMix > 0 then Extra := Max(Extra, Glyph.Style.GlowRadius * 3);
  Result.Left := Min(Result.Left, Glyph.HitBounds.Left - Ceil(Extra) - 1);
  Result.Top := Min(Result.Top, Glyph.HitBounds.Top - Ceil(Extra) - 1);
  Result.Right := Max(Result.Right, Glyph.HitBounds.Right + Ceil(Extra) + 1);
  Result.Bottom := Max(Result.Bottom, Glyph.HitBounds.Bottom + Ceil(Extra) + 1);
end;

function CreateMVAppearanceContext(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Frame: TMVAppearanceFrame): TMVAppearanceContext;
var Direction, Center, Start, Finish: TPointF; Extent, Offset: Single;
begin
  Result := Default(TMVAppearanceContext);
  Result.Frame := Frame;
  Result.OutputToDevice := Canvas.GetLocalToDeviceAs3x3;
  if not HasMVAppearance(Frame) then Exit;
  Result.Ink := TSkPaint.Create;
  Result.Ink.AntiAlias := True;
  if Frame.TintColor shr 24 <> 0 then
    Result.Tint := TSkColorFilter.MakeBlend(Frame.TintColor, TSkBlendMode.SrcATop);
  if Frame.SweepVisible and not Bounds.IsEmpty then
  begin
    Direction := PointF(Cos(DegToRad(Frame.SweepAngle)), Sin(DegToRad(Frame.SweepAngle)));
    Extent := (Abs(Direction.X) * Bounds.Width + Abs(Direction.Y) * Bounds.Height) / 2;
    Offset := (2 * Frame.SweepProgress - 1) * (Extent + Frame.SweepWidth);
    Center := Bounds.CenterPoint + Direction * Offset;
    Start := Center - Direction * Frame.SweepWidth;
    Finish := Center + Direction * Frame.SweepWidth;
    Result.Sweep := TSkShader.MakeGradientLinear(Start, Finish,
      [TAlphaColor(0), Frame.SweepColor, TAlphaColor(0)], [Single(0), Single(0.5), Single(1)], TSkTileMode.Decal);
  end;
end;

procedure DrawMVAppearance(const Canvas: ISkCanvas; const Glyph: TMVLayoutUnit;
  const Context: TMVAppearanceContext);
var
  Paint: ISkPaint;
  R, Frame: TRectF;
  Glow, Distance, DX, DY: Single;
  Matrix: TMatrix;
  Sweep: ISkShader;
begin
  if Glyph.BaseImage = nil then Exit;
  Paint := Context.Ink;
  Paint.Color := $FFFFFFFF;
  Paint.Style := TSkPaintStyle.Fill;
  Paint.AlphaF := 1;
  R := Glyph.HitBounds;
  try
    Glow := Glyph.Style.GlowStrength * (1 - Context.Frame.GlowMix) +
      Context.Frame.GlowWave * Context.Frame.GlowMix;
    if Glow > 0 then
    begin
      Paint.ColorFilter := Glyph.GlowFilter;
      Paint.ImageFilter := Glyph.GlowBlur;
      Paint.AlphaF := Glow;
      Canvas.DrawImageRect(Glyph.BaseImage, R, TSkSamplingOptions.High, Paint);
      Paint.ImageFilter := nil;
      Paint.AlphaF := 1;
    end;
    Distance := Glyph.Style.ChromaticOffset + Context.Frame.ChromaticOffset;
    if Abs(Distance) > 0.001 then
    begin
      DX := Cos(DegToRad(Glyph.Style.ChromaticAngle)) * Distance;
      DY := Sin(DegToRad(Glyph.Style.ChromaticAngle)) * Distance;
      R.Offset(DX, DY);
      Paint.ColorFilter := Glyph.ChromaticFilter1;
      Canvas.DrawImageRect(Glyph.BaseImage, R, TSkSamplingOptions.High, Paint);
      R.Offset(-2 * DX, -2 * DY);
      Paint.ColorFilter := Glyph.ChromaticFilter2;
      Canvas.DrawImageRect(Glyph.BaseImage, R, TSkSamplingOptions.High, Paint);
      R := Glyph.HitBounds;
    end;
    Paint.ColorFilter := nil;
    if Glyph.Style.FrameWidth > 0 then
    begin
      Frame := R;
      Frame.Inflate(Glyph.Style.FramePadding, Glyph.Style.FramePadding);
      Paint.Color := Glyph.Style.FrameColor;
      Paint.Style := TSkPaintStyle.Stroke;
      Paint.StrokeWidth := Glyph.Style.FrameWidth;
      Canvas.DrawRect(Frame, Paint);
      Paint.Style := TSkPaintStyle.Fill;
      Paint.Color := $FFFFFFFF;
    end;
    Paint.ColorFilter := Context.Tint;
    Canvas.DrawImageRect(Glyph.BaseImage, R, TSkSamplingOptions.High, Paint);
    Paint.ColorFilter := nil;
    if Context.Sweep <> nil then
    begin
      Matrix := Canvas.GetLocalToDeviceAs3x3;
      if Abs(Matrix.Determinant) > 1E-12 then
      begin
        // 文字・グループの回転や編集ビュー倍率があっても、1本の光が全フレーズを横切る。
        Sweep := Context.Sweep.MakeWithLocalMatrix(Context.OutputToDevice * Matrix.Inverse);
        if Sweep <> nil then
        begin
          Paint.Shader := TSkShader.MakeBlend(TSkBlendMode.SrcIn, Glyph.BaseShader, Sweep);
          if Paint.Shader <> nil then Canvas.DrawRect(R, Paint);
        end;
      end;
    end;
  finally
    Paint.ColorFilter := nil;
    Paint.ImageFilter := nil;
    Paint.Shader := nil;
    Paint.Color := $FFFFFFFF;
    Paint.Style := TSkPaintStyle.Fill;
  end;
end;

end.
