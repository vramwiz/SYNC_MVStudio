unit MVShapeAnimation;

// 文字の演出IDに依存せず、図形の伸縮・不透明度・周期位相を直接評価する。
interface

uses MVShapeTypes;

type
  TMVShapeMotion = record
    Visibility: Single; // 登場・退場で伸縮と透明度へ使う0..1の進行。
    Cycle: Double; // 波紋・飛散の周期内位置。0以上1未満。
  end;

// フレーズ全体の登場・退場区間を図形へ適用する。文字遅延分は呼出し側で加算。Time<0は静止編集用。
function EvaluateMVShape(const Settings: TMVShapeSettings; Time, Duration,
  EntranceTime, ExitTime: Double): TMVShapeMotion;

implementation

uses System.Math, MVAnimationTime;

function EvaluateMVShape(const Settings: TMVShapeSettings; Time, Duration,
  EntranceTime, ExitTime: Double): TMVShapeMotion;
var A, B, P: Double;
begin
  Result := Default(TMVShapeMotion);
  if (Settings.EffectID = MV_SHAPE_NONE) or IsNan(Time) or IsInfinite(Time) then Exit;
  if Time < 0 then
  begin
    Result.Visibility := 1;
    Result.Cycle := 0.25;
    Exit;
  end;
  if IsNan(Duration) or IsInfinite(Duration) or (Duration <= 0) or (Time >= Duration) then Exit;
  A := EntranceTime;
  B := ExitTime;
  NormalizeMVDurations(Duration, A, B);
  Result.Visibility := 1;
  if (A > 0) and (Time < A) then
  begin
    P := Time / A;
    Result.Visibility := P * P * (3 - 2 * P);
  end
  else if (B > 0) and (Time >= Duration - B) then
  begin
    P := (Duration - Time) / B;
    Result.Visibility := P * P * (3 - 2 * P);
  end;
  Result.Cycle := Frac(Time / Max(0.05, Settings.Period));
end;

end.
