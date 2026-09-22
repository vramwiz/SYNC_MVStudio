unit MVAnimatedBounds;

// 個別配置と文字演出の変形を出力座標へ写し、追従図形の基準矩形を求める。
interface

uses System.Types, MVDocument, MVAnimationTypes;

// 描画と同じ拡縮→せん断→回転→移動の順で4隅を変換する。Opacityやクリップでは縮めない。
function MVAnimatedGlyphBounds(const Item: TMVPlacement; const Bounds: TRectF;
  const Position: TPointF; TrackingIndex: Single; const Motion: TMVMotion): TRectF;
// 静止時の矩形をまとまり共通の中心で変換する。文字間の配置関係も同じ変換を受ける。
function MVAnimatedGroupBounds(const Bounds: TRectF; const Pivot: TPointF;
  TrackingIndex: Single; const Motion: TMVMotion): TRectF;

implementation

uses System.Math;

function MVAnimatedGroupBounds(const Bounds: TRectF; const Pivot: TPointF;
  TrackingIndex: Single; const Motion: TMVMotion): TRectF;
var Local: TRectF; Item: TMVPlacement; Transform: TMVMotion;
begin
  Local := Bounds;
  Local.Inflate(Motion.GlitchAmount, 0);
  Local.Offset(-Pivot.X, -Pivot.Y);
  Item := Default(TMVPlacement);
  Item.Scale := 1;
  Item.ScaleX := 1;
  Item.ScaleY := 1;
  Transform := Motion;
  Transform.BlurSigma := 0; // 個別変形に依存するぼかし範囲は呼出し側で静止矩形へ反映済み。
  Transform.GlitchAmount := 0;
  Result := MVAnimatedGlyphBounds(Item, Local, Pivot, TrackingIndex, Transform);
end;

function MVAnimatedGlyphBounds(const Item: TMVPlacement; const Bounds: TRectF;
  const Position: TPointF; TrackingIndex: Single; const Motion: TMVMotion): TRectF;
var
  I: Integer;
  Local: TRectF;
  P: TPointF;
  PX, PY, SX, SY, Angle, S, C: Double;
begin
  Local := Bounds;
  Local.Inflate(Motion.BlurSigma * 3 + Motion.GlitchAmount, Motion.BlurSigma * 3);
  SX := Item.Scale * Item.ScaleX * Motion.Scale * Motion.ScaleX;
  SY := Item.Scale * Item.ScaleY * Motion.Scale * Motion.ScaleY;
  Angle := DegToRad(Item.Angle + Motion.Angle);
  S := Sin(Angle);
  C := Cos(Angle);
  Result := TRectF.Empty;
  for I := 0 to 3 do
  begin
    if (I and 1) = 0 then PX := Local.Left else PX := Local.Right;
    if (I and 2) = 0 then PY := Local.Top else PY := Local.Bottom;
    PY := PY * SY;
    PX := PX * SX + Item.Shear * PY;
    P := PointF(Position.X + Motion.X + Motion.Tracking * TrackingIndex + PX * C - PY * S,
      Position.Y + Motion.Y + PX * S + PY * C);
    if I = 0 then Result := RectF(P.X, P.Y, P.X, P.Y)
    else
    begin
      Result.Left := Min(Result.Left, P.X);
      Result.Top := Min(Result.Top, P.Y);
      Result.Right := Max(Result.Right, P.X);
      Result.Bottom := Max(Result.Bottom, P.Y);
    end;
  end;
end;

end.
