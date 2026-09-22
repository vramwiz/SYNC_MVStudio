unit MVSelectionOverlay;

// 選択枠とハンドルを画面座標で描き、ズーム中も操作点の大きさを維持する。
interface

uses System.Types, System.Skia, MVTransformGeometry;

// Pointsは画面座標。HandleSizeはDPIへ合わせた画面ピクセル数。
procedure DrawMVSelection(const Canvas: ISkCanvas; const Points: TMVHandlePoints; HandleSize: Single);

// 範囲選択中の矩形を半透明の塗りと細い枠で表示する。
procedure DrawMVMarquee(const Canvas: ISkCanvas; const Start, Finish: TPointF);

implementation

uses System.Math;

procedure DrawMVSelection(const Canvas: ISkCanvas; const Points: TMVHandlePoints; HandleSize: Single);
var Paint: ISkPaint; H: TMVHandle; Next: TMVHandle; R: Single;
begin
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := $FF60BEFF;
  Paint.StrokeWidth := 1.5;
  for H := mhNW to mhW do
  begin
    if H = mhW then Next := mhNW else Next := Succ(H);
    Canvas.DrawLine(Points[H], Points[Next], Paint);
  end;
  if HandleSize <= 0 then Exit;
  Canvas.DrawLine(Points[mhN], Points[mhRotate], Paint);
  R := HandleSize / 2;
  for H := mhNW to mhRotate do
  begin
    Paint.Style := TSkPaintStyle.Fill;
    Paint.Color := $FFFFFFFF;
    if H = mhRotate then Canvas.DrawCircle(Points[H], R, Paint)
    else Canvas.DrawRect(RectF(Points[H].X - R, Points[H].Y - R, Points[H].X + R, Points[H].Y + R), Paint);
    Paint.Style := TSkPaintStyle.Stroke;
    Paint.Color := $FF2196F3;
    if H = mhRotate then Canvas.DrawCircle(Points[H], R, Paint)
    else Canvas.DrawRect(RectF(Points[H].X - R, Points[H].Y - R, Points[H].X + R, Points[H].Y + R), Paint);
  end;
end;

procedure DrawMVMarquee(const Canvas: ISkCanvas; const Start, Finish: TPointF);
var P: ISkPaint; R: TRectF;
begin
  P := TSkPaint.Create;
  R := RectF(Min(Start.X, Finish.X), Min(Start.Y, Finish.Y), Max(Start.X, Finish.X), Max(Start.Y, Finish.Y));
  P.Color := $3060BEFF; Canvas.DrawRect(R, P);
  P.Color := $FF60BEFF; P.Style := TSkPaintStyle.Stroke; P.StrokeWidth := 1;
  Canvas.DrawRect(R, P);
end;

end.