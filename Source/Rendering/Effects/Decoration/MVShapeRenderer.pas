unit MVShapeRenderer;

// フレーズの外接矩形へ帯・下線・波紋・小図形を合成する。歌詞画像や保存値は変更しない。
interface

uses System.Types, System.Skia, MVShapeTypes, MVShapeAnimation;

// Boundsは出力座標。時間評価済みの図形を描き、Canvasの変形状態を保持する。
procedure DrawMVShape(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Settings: TMVShapeSettings; const Motion: TMVShapeMotion);

implementation

uses System.Math, MVAnimationTypes;

procedure DrawBand(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Settings: TMVShapeSettings; Visible: Single; const Paint: ISkPaint);
var R: TRectF;
begin
  R := Bounds;
  R.Inflate(Settings.Padding, Settings.Padding);
  case TMVAnimationDirection(Settings.Direction) of
    madUp: R.Bottom := R.Top + R.Height * Visible;
    madDown: R.Top := R.Bottom - R.Height * Visible;
    madLeft: R.Right := R.Left + R.Width * Visible;
    madRight: R.Left := R.Right - R.Width * Visible;
  end;
  Canvas.DrawRect(R, Paint);
end;

procedure DrawUnderline(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Settings: TMVShapeSettings; Visible: Single; const Paint: ISkPaint);
var R: TRectF; Y: Single;
begin
  R := Bounds;
  R.Inflate(Settings.Padding, 0);
  Y := R.Bottom + Settings.Padding + Settings.LineWidth / 2;
  // 下線は常に水平。上・左を左起点、下・右を右起点に対応させる。
  if TMVAnimationDirection(Settings.Direction) in [madUp, madLeft] then
    R.Right := R.Left + R.Width * Visible
  else R.Left := R.Right - R.Width * Visible;
  Paint.Style := TSkPaintStyle.Stroke;
  Canvas.DrawLine(R.Left, Y, R.Right, Y, Paint);
end;

procedure DrawRings(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Settings: TMVShapeSettings; Cycle: Double; const Paint: ISkPaint);
var I: Integer; P, Extra: Double; Alpha: Single; R: TRectF;
begin
  Alpha := Paint.AlphaF;
  Paint.Style := TSkPaintStyle.Stroke;
  for I := 0 to 1 do
  begin
    P := Frac(Cycle + I * 0.5);
    Extra := Settings.Padding + Max(12.0, Settings.Padding * 2) * P;
    R := Bounds;
    R.Inflate(Extra, Extra);
    // 周期境界の半径の巻き戻しは、透明になる瞬間に行う。
    Paint.AlphaF := Alpha * Sqr(Sin(Pi * P));
    Canvas.DrawOval(R, Paint);
  end;
end;

procedure DrawBurst(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Settings: TMVShapeSettings; Cycle: Double; const Paint: ISkPaint);
const Count = 12;
var I: Integer; P, Angle, Extra, Radius, CX, CY: Double; Alpha: Single; Center: TPointF;
begin
  Alpha := Paint.AlphaF;
  Center := Bounds.CenterPoint;
  Paint.Style := TSkPaintStyle.Stroke;
  for I := 0 to Count - 1 do
  begin
    P := Frac(Cycle + (I mod 3) / 3);
    Angle := 2 * Pi * I / Count;
    Extra := Settings.Padding + 8 + (24 + Settings.Padding * 2) * P;
    Radius := (3 + Settings.LineWidth) * (1 - 0.5 * P);
    // 四角いフレーズの辺より外側へ配置し、斜め方向でも文字へ重なりにくくする。
    CX := Cos(Angle);
    CY := Sin(Angle);
    if Abs(CX) > 0.0001 then CX := Sign(CX) * Bounds.Width / 2 + CX * Extra else CX := 0;
    if Abs(CY) > 0.0001 then CY := Sign(CY) * Bounds.Height / 2 + CY * Extra else CY := 0;
    Paint.AlphaF := Alpha * Sqr(Sin(Pi * P));
    if (I and 1) = 0 then Canvas.DrawCircle(Center.X + CX, Center.Y + CY, Radius, Paint)
    else
    begin
      Canvas.Save;
      try
        Canvas.Translate(Center.X + CX, Center.Y + CY);
        Canvas.Rotate(P * 90 + I * 30);
        Canvas.DrawRect(RectF(-Radius, -Radius, Radius, Radius), Paint);
      finally
        Canvas.Restore;
      end;
    end;
  end;
end;

procedure DrawShards(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Settings: TMVShapeSettings; Cycle: Double; const Paint: ISkPaint);
var I: Integer; P, A, Radius, RX, RY: Single; Alpha: Single; Builder: ISkPathBuilder; Path: ISkPath;
begin
  Alpha := Paint.AlphaF;
  Paint.Style := TSkPaintStyle.Fill;
  for I := 0 to 11 do
  begin
    P := Frac(Cycle + I * 0.381966);
    A := I * 2.399963 + P * 0.4;
    RX := Bounds.Width / 2 + Settings.Padding + 12 + P * 48;
    RY := Bounds.Height / 2 + Settings.Padding + 12 + P * 48;
    Radius := 4 + Settings.LineWidth * 1.5 + (I mod 3) * 2;
    Paint.AlphaF := Alpha * Sqr(Sin(Pi * P));
    Builder := TSkPathBuilder.Create;
    Builder.MoveTo(-Radius, Radius * 0.6);
    Builder.LineTo(0, -Radius * (1 + (I mod 2)));
    Builder.LineTo(Radius * 0.7, Radius);
    Builder.Close;
    Path := Builder.Detach;
    Canvas.Save;
    try
      Canvas.Translate(Bounds.CenterPoint.X + Cos(A) * RX, Bounds.CenterPoint.Y + Sin(A) * RY);
      Canvas.Rotate(I * 31 + P * 70);
      Canvas.DrawPath(Path, Paint);
    finally Canvas.Restore; end;
  end;
end;

procedure DrawMVShape(const Canvas: ISkCanvas; const Bounds: TRectF;
  const Settings: TMVShapeSettings; const Motion: TMVShapeMotion);
var Paint: ISkPaint;
begin
  if (Settings.EffectID = MV_SHAPE_NONE) or (Settings.Opacity <= 0) or (Motion.Visibility <= 0) then Exit;
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := Settings.Color;
  Paint.AlphaF := Paint.AlphaF * Settings.Opacity * Motion.Visibility;
  Paint.StrokeWidth := Settings.LineWidth;
  case Settings.EffectID of
    MV_SHAPE_BAND: DrawBand(Canvas, Bounds, Settings, Motion.Visibility, Paint);
    MV_SHAPE_UNDERLINE: DrawUnderline(Canvas, Bounds, Settings, Motion.Visibility, Paint);
    MV_SHAPE_RING: DrawRings(Canvas, Bounds, Settings, Motion.Cycle, Paint);
    MV_SHAPE_BURST: DrawBurst(Canvas, Bounds, Settings, Motion.Cycle, Paint);
    MV_SHAPE_SHARDS: DrawShards(Canvas, Bounds, Settings, Motion.Cycle, Paint);
  end;
end;

end.
