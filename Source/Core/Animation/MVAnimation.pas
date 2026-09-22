unit MVAnimation;

// 時間区間と文字ごとの遅延を計算し、登録済み演出へ評価を委譲する。
interface

uses MVDocument, MVAnimationTypes, MVAnimationTime;

type
  TMVMotion = MVAnimationTypes.TMVMotion;

// 固定IDに対応する登場・退場名。未登録なら「なし」を返す。
function MVTransitionName(ID: Integer): string;
// 固定IDに対応する表示中演出名。未登録なら「静止」を返す。
function MVHoldName(ID: Integer): string;
// 文字遅延込みの区間を作る。ForShapeでは文字演出が「なし」でも図形用の所要時間を残す。
function MVDocumentSchedule(const Document: TMVDocument; Duration, EntranceTime, ExitTime: Double;
  UnitCount: Integer; ForShape: Boolean = False): TMVAnimationSchedule;
// 全要素が遅延対象の場合の簡易評価。空白を含む描画には区間とDelayIndexを渡す版を使う。
function EvaluateMVMotion(const Document: TMVDocument; Time, Duration, EntranceTime, ExitTime: Double;
  UnitIndex, UnitCount: Integer): TMVMotion; overload;
// 登場・退場が同じ開始段の場合の簡易評価。順番の変換済みのDelayIndexを渡す。
function EvaluateMVMotion(const Document: TMVDocument; Time, Duration: Double;
  const Schedule: TMVAnimationSchedule; UnitIndex, DelayIndex: Integer): TMVMotion; overload;
// 描画用。模様の種と登場・退場それぞれの開始段を渡し、全体区間を再計算しない。
function EvaluateMVMotion(const Document: TMVDocument; Time, Duration: Double;
  const Schedule: TMVAnimationSchedule; UnitIndex, EntranceRank, ExitRank: Integer): TMVMotion; overload;

implementation

uses System.Math, MVAnimationCatalog, MVTransitionTiming, MVAnimationSequence;

function MVTransitionName(ID: Integer): string;
var Item: TMVAnimationDescriptor;
begin
  if FindMVAnimation(makTransition, ID, Item) then Result := Item.Name else Result := 'なし';
end;

function MVHoldName(ID: Integer): string;
var Item: TMVAnimationDescriptor;
begin
  if FindMVAnimation(makHold, ID, Item) then Result := Item.Name else Result := '静止';
end;

procedure ApplyTransition(var Motion: TMVMotion; ID: Integer; P: Double;
  const Document: TMVDocument; var Input: TMVAnimationInput);
var Item: TMVAnimationDescriptor; Timing: Integer; Strength: Double;
begin
  if not FindMVAnimation(makTransition, ID, Item) or not Assigned(Item.Evaluate) then Exit;
  if Input.Leaving then Timing := Document.ExitTiming else Timing := Document.EntranceTiming;
  Input.CustomTiming := Timing <> MV_TIMING_DEFAULT;
  Input.Progress := EnsureRange(P, 0.0, 1.0);
  if Input.CustomTiming then
    Input.Progress := EvaluateMVTiming(Timing, Input.Progress);
  Item.Evaluate(Motion, Input);
  if Input.Leaving then Strength := Document.ExitStrength else Strength := Document.EntranceStrength;
  // 表示・消去の役割は残し、移動・回転・拡縮・ぼかしの変化量だけを状態別に調整する。
  Motion.X := Motion.X * Strength;
  Motion.Y := Motion.Y * Strength;
  Motion.Angle := Motion.Angle * Strength;
  Motion.Tracking := Motion.Tracking * Strength;
  Motion.Scale := 1 + (Motion.Scale - 1) * Strength;
  Motion.ScaleX := 1 + (Motion.ScaleX - 1) * Strength;
  Motion.ScaleY := 1 + (Motion.ScaleY - 1) * Strength;
  Motion.BlurSigma := Motion.BlurSigma * Strength;
  Motion.GlitchAmount := Motion.GlitchAmount * Strength;
  // 位置・角度・字間には引きや行き過ぎを残し、画像の値域と反転しない倍率だけを制限する。
  Motion.Opacity := EnsureRange(Motion.Opacity, Single(0), Single(1));
  Motion.Scale := Max(Single(0), Motion.Scale);
  Motion.ScaleX := Max(Single(0), Motion.ScaleX);
  Motion.ScaleY := Max(Single(0), Motion.ScaleY);
  Motion.BlurSigma := EnsureRange(Motion.BlurSigma, Single(0), Single(40));
  Motion.GlitchAmount := EnsureRange(Motion.GlitchAmount, Single(0), Single(40));
  Motion.ClipLeft := EnsureRange(Motion.ClipLeft, Single(0), Single(1));
  Motion.ClipRight := EnsureRange(Motion.ClipRight, Single(0), Single(1));
  Motion.ClipTop := EnsureRange(Motion.ClipTop, Single(0), Single(1));
  Motion.ClipBottom := EnsureRange(Motion.ClipBottom, Single(0), Single(1));
  Motion.MaskVisibility := EnsureRange(Motion.MaskVisibility, Single(0), Single(1));
end;

function EvaluateMVMotion(const Document: TMVDocument; Time, Duration, EntranceTime, ExitTime: Double;
  UnitIndex, UnitCount: Integer): TMVMotion;
begin
  Result := EvaluateMVMotion(Document, Time, Duration,
    MVDocumentSchedule(Document, Duration, EntranceTime, ExitTime, UnitCount), UnitIndex,
    MVAnimationOrderRank(Document.EntranceOrder, UnitIndex, UnitCount),
    MVAnimationOrderRank(Document.ExitOrder, UnitIndex, UnitCount));
end;

function MVDocumentSchedule(const Document: TMVDocument; Duration, EntranceTime, ExitTime: Double;
  UnitCount: Integer; ForShape: Boolean): TMVAnimationSchedule;
var InDelay, OutDelay: Double;
begin
  InDelay := Document.EntranceDelay;
  OutDelay := Document.ExitDelay;
  if Document.Entrance = 0 then
  begin
    InDelay := 0;
    if not ForShape then EntranceTime := 0;
  end;
  if Document.ExitEffect = 0 then
  begin
    OutDelay := 0;
    if not ForShape then ExitTime := 0;
  end;
  Result := BuildMVAnimationSchedule(Duration, EntranceTime, ExitTime, InDelay, OutDelay,
    MVAnimationOrderSteps(Document.EntranceOrder, UnitCount), MVAnimationOrderSteps(Document.ExitOrder, UnitCount));
end;

function UnitProgress(Time, StartTime, AnimationTime: Double): Double;
begin
  if AnimationTime > 0 then Result := EnsureRange((Time - StartTime) / AnimationTime, 0.0, 1.0)
  else Result := Ord(Time >= StartTime);
end;

function EvaluateMVMotion(const Document: TMVDocument; Time, Duration: Double;
  const Schedule: TMVAnimationSchedule; UnitIndex, DelayIndex: Integer): TMVMotion;
begin
  Result := EvaluateMVMotion(Document, Time, Duration, Schedule, UnitIndex, DelayIndex, DelayIndex);
end;

function EvaluateMVMotion(const Document: TMVDocument; Time, Duration: Double;
  const Schedule: TMVAnimationSchedule; UnitIndex, EntranceRank, ExitRank: Integer): TMVMotion;
var
  P, StartTime: Double;
  Input: TMVAnimationInput;
  Hold: TMVAnimationDescriptor;
begin
  Result := DefaultMVMotion;
  if IsNan(Time) or IsInfinite(Time) or IsNan(Duration) or IsInfinite(Duration) or
    (Time < 0) or (Duration <= 0) or (Time >= Duration) then
  begin
    Result.Opacity := 0;
    Exit;
  end;
  Input := Default(TMVAnimationInput);
  Input.Amount := Document.Amount;
  Input.CurveAmount := Document.CurveAmount;
  Input.UnitIndex := UnitIndex;
  Input.Envelope := 1;
  if (Schedule.EntranceSpan > 0) and (Time < Schedule.EntranceSpan) then
  begin
    StartTime := Max(0, EntranceRank) * Schedule.EntranceDelay;
    P := UnitProgress(Time, StartTime, Schedule.EntranceTime);
    Input.Direction := TMVAnimationDirection(Document.EntranceDirection);
    ApplyTransition(Result, Document.Entrance, P, Document, Input);
    Input.Envelope := P;
  end
  else if (Schedule.ExitSpan > 0) and (Time >= Duration - Schedule.ExitSpan) then
  begin
    StartTime := Duration - Schedule.ExitSpan + Max(0, ExitRank) * Schedule.ExitDelay;
    P := UnitProgress(Time, StartTime, Schedule.ExitTime);
    Input.Leaving := True;
    Input.Direction := TMVAnimationDirection(Document.ExitDirection);
    ApplyTransition(Result, Document.ExitEffect, P, Document, Input);
    Input.Envelope := 1 - P;
  end;
  // 既存の振幅演出は端で弱める。連続回転などの適用方法は各演出が決める。
  Input.Strength := Document.HoldStrength;
  Input.Amount := Document.Amount * Input.Strength;
  Input.Phase := 2 * Pi * Time / Max(0.05, Document.Period);
  if FindMVAnimation(makHold, Document.Hold, Hold) and Assigned(Hold.Evaluate) then Hold.Evaluate(Result, Input);
end;

end.
