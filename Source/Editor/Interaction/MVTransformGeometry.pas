unit MVTransformGeometry;

// 回転した文字の8点ハンドル・回転点・対辺固定の拡縮を出力座標で計算する。
interface

uses System.Types, MVDocument;

type
  TMVHandle = (mhNone, mhMove, mhNW, mhN, mhNE, mhE, mhSE, mhS, mhSW, mhW, mhRotate);
  TMVHandlePoints = array[mhNW..mhRotate] of TPointF;

// 文字のローカル座標を角度で回転する。倍率は呼出側で適用する。
function MVRotate(const P: TPointF; Angle: Single): TPointF;
// 文字中心・倍率・角度から8点と上部回転点を求める。Gapは出力座標単位。
function MVHandles(const Item: TMVPlacement; const Bounds: TRectF; Gap: Single): TMVHandlePoints;
// 画面倍率から決めた半径内のハンドルを優先して探す。
function MVHitHandle(const Points: TMVHandlePoints; const P: TPointF; Radius: Single): TMVHandle;
// 回転と縦横倍率を戻して文字矩形内か判定する。
function MVHitBody(const Item: TMVPlacement; const Bounds: TRectF; const P: TPointF): Boolean;
// 開始値から変形を計算する。四隅は比率維持、辺は独立拡縮。対向ハンドルを固定する。
function MVTransform(const Original: TMVPlacement; const Bounds: TRectF; Handle: TMVHandle;
  const Start, Current: TPointF; SnapAngle, ConstrainAngle: Boolean): TMVPlacement;

implementation

uses System.Math;

function MVRotate(const P: TPointF; Angle: Single): TPointF;
var S, C: Extended;
begin
  SinCos(DegToRad(Angle), S, C);
  Result := PointF(P.X * C - P.Y * S, P.X * S + P.Y * C);
end;

function LocalHandle(const Bounds: TRectF; Handle: TMVHandle): TPointF;
begin
  Result := Bounds.CenterPoint;
  case Handle of
    mhNW, mhW, mhSW: Result.X := Bounds.Left;
    mhNE, mhE, mhSE: Result.X := Bounds.Right;
  end;
  case Handle of
    mhNW, mhN, mhNE, mhRotate: Result.Y := Bounds.Top;
    mhSW, mhS, mhSE: Result.Y := Bounds.Bottom;
  end;
end;

function MVHandles(const Item: TMVPlacement; const Bounds: TRectF; Gap: Single): TMVHandlePoints;
var H: TMVHandle; P: TPointF;
begin
  for H := mhNW to mhRotate do
  begin
    P := LocalHandle(Bounds, H);
    P := PointF(P.X * Item.Scale * Item.ScaleX, P.Y * Item.Scale * Item.ScaleY);
    P.X := P.X + Item.Shear * P.Y;
    if H = mhRotate then P.Y := P.Y - Gap;
    Result[H] := PointF(Item.X, Item.Y) + MVRotate(P, Item.Angle);
  end;
end;

function MVHitHandle(const Points: TMVHandlePoints; const P: TPointF; Radius: Single): TMVHandle;
var H: TMVHandle;
begin
  Result := mhNone;
  for H := mhRotate downto mhNW do
    if (Points[H] - P).Length <= Radius then Exit(H);
end;

function MVHitBody(const Item: TMVPlacement; const Bounds: TRectF; const P: TPointF): Boolean;
var Local: TPointF;
begin
  Local := MVRotate(P - PointF(Item.X, Item.Y), -Item.Angle);
  Local.X := Local.X - Item.Shear * Local.Y;
  Local := PointF(Local.X / (Item.Scale * Item.ScaleX), Local.Y / (Item.Scale * Item.ScaleY));
  Result := Bounds.Contains(Local);
end;

function MVTransform(const Original: TMVPlacement; const Bounds: TRectF; Handle: TMVHandle;
  const Start, Current: TPointF; SnapAngle, ConstrainAngle: Boolean): TMVPlacement;
var P, Anchor, Moving, Delta, NewCenter, AnchorWorld: TPointF;
  SX, SY, Factor, Denominator, Angle, StepAngle: Double;
  Corners: Boolean;
begin
  Result := Original;
  if Handle = mhNone then Exit;
  Result.Positioned := True;
  if Handle = mhMove then
  begin
    Result.X := EnsureRange(Original.X + Current.X - Start.X, -32768.0, 32768.0);
    Result.Y := EnsureRange(Original.Y + Current.Y - Start.Y, -32768.0, 32768.0);
    Exit;
  end;
  if Handle = mhRotate then
  begin
    P := PointF(Original.X, Original.Y);
    Angle := RadToDeg(ArcTan2(Current.Y - P.Y, Current.X - P.X) - ArcTan2(Start.Y - P.Y, Start.X - P.X));
    while Angle > 180 do Angle := Angle - 360;
    while Angle < -180 do Angle := Angle + 360;
    Angle := Original.Angle + Angle;
    StepAngle := Round(Angle / 15) * 15;
    if ConstrainAngle or (SnapAngle and (Abs(Angle - StepAngle) <= 3)) then Angle := StepAngle;
    Result.Angle := EnsureRange(Angle, -3600.0, 3600.0);
    Exit;
  end;
  Moving := LocalHandle(Bounds, Handle);
  Anchor := Bounds.CenterPoint * 2 - Moving;
  SX := Original.Scale * Original.ScaleX;
  SY := Original.Scale * Original.ScaleY;
  AnchorWorld := PointF(Original.X, Original.Y) + MVRotate(PointF(Anchor.X * SX + Original.Shear * Anchor.Y * SY, Anchor.Y * SY), Original.Angle);
  Delta := MVRotate(Current - Start, -Original.Angle);
  Delta.X := Delta.X - Original.Shear * Delta.Y;
  P := PointF((Moving.X - Anchor.X) * SX, (Moving.Y - Anchor.Y) * SY);
  Corners := Handle in [mhNW, mhNE, mhSE, mhSW];
  if Corners then
  begin
    Denominator := Sqr(P.X) + Sqr(P.Y);
    if Denominator < 0.00001 then Exit;
    Factor := ((P.X + Delta.X) * P.X + (P.Y + Delta.Y) * P.Y) / Denominator;
    Factor := EnsureRange(Factor, Max(0.05 / Original.ScaleX, 0.05 / Original.ScaleY),
      Min(10 / Original.ScaleX, 10 / Original.ScaleY));
    Result.ScaleX := Original.ScaleX * Factor;
    Result.ScaleY := Original.ScaleY * Factor;
  end
  else if Handle in [mhW, mhE] then
    Result.ScaleX := EnsureRange(Original.ScaleX * (P.X + Delta.X) / P.X, 0.05, 10.0)
  else
    Result.ScaleY := EnsureRange(Original.ScaleY * (P.Y + Delta.Y) / P.Y, 0.05, 10.0);
  NewCenter := AnchorWorld - MVRotate(PointF(Anchor.X * Original.Scale * Result.ScaleX + Original.Shear * Anchor.Y * Original.Scale * Result.ScaleY,
    Anchor.Y * Original.Scale * Result.ScaleY), Original.Angle);
  Result.X := EnsureRange(NewCenter.X, -32768.0, 32768.0);
  Result.Y := EnsureRange(NewCenter.Y, -32768.0, 32768.0);
end;

end.
