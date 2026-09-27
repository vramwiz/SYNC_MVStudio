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
// 前と後それぞれの単位数で文字遅延込みの区間を作る。ForShapeでは演出なしでも所要時間を残す。
function MVDocumentSchedule(const Document: TMVDocument; Duration, EntranceTime, ExitTime: Double;
  EntranceCount, ExitCount: Integer; ForShape: Boolean = False): TMVAnimationSchedule;
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

uses System.Math, MVAnimationCatalog, MVAnimationSequence, MVTransitionParts, MVTransitionComposition;

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

function EvaluateMVMotion(const Document: TMVDocument; Time, Duration, EntranceTime, ExitTime: Double;
  UnitIndex, UnitCount: Integer): TMVMotion;
begin
  Result := EvaluateMVMotion(Document, Time, Duration,
    MVDocumentSchedule(Document, Duration, EntranceTime, ExitTime, UnitCount, UnitCount), UnitIndex,
    MVAnimationOrderRank(Document.EntranceOrder, UnitIndex, UnitCount),
    MVAnimationOrderRank(Document.ExitOrder, UnitIndex, UnitCount));
end;

function MVDocumentSchedule(const Document: TMVDocument; Duration, EntranceTime, ExitTime: Double;
  EntranceCount, ExitCount: Integer; ForShape: Boolean): TMVAnimationSchedule;
var InDelay, OutDelay: Double;
begin
  InDelay := Document.EntranceDelay;
  OutDelay := Document.ExitDelay;
  if not HasMVTransitionParts(Document.EntranceMotion, Document.EntranceVisibility) then
  begin
    InDelay := 0;
    if not ForShape then EntranceTime := 0;
  end;
  if not HasMVTransitionParts(Document.ExitMotion, Document.ExitVisibility) then
  begin
    OutDelay := 0;
    if not ForShape then ExitTime := 0;
  end;
  Result := BuildMVAnimationSchedule(Duration, EntranceTime, ExitTime, InDelay, OutDelay,
    MVAnimationOrderSteps(Document.EntranceOrder, EntranceCount),
    MVAnimationOrderSteps(Document.ExitOrder, ExitCount));
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
    // 見え方「なし」や弾性曲線でも、開始時刻前の文字は表示しない。
    if Time < StartTime then
    begin
      Result.Opacity := 0;
      Exit;
    end;
    P := UnitProgress(Time, StartTime, Schedule.EntranceTime);
    Input.Direction := TMVAnimationDirection(Document.EntranceDirection);
    ApplyMVTransition(Result, Document.EntranceMotion, Document.EntranceVisibility,
      Document.EntranceTiming, P, Document.EntranceStrength, Input);
    Input.Envelope := P;
  end
  else if (Schedule.ExitSpan > 0) and (Time >= Duration - Schedule.ExitSpan) then
  begin
    StartTime := Duration - Schedule.ExitSpan + Max(0, ExitRank) * Schedule.ExitDelay;
    // 消去済みの文字は表示中の演出を重ねる前に除外し、曲線の跳ね返りによる再表示を防ぐ。
    if Time >= StartTime + Schedule.ExitTime then
    begin
      Result.Opacity := 0;
      Exit;
    end;
    P := UnitProgress(Time, StartTime, Schedule.ExitTime);
    Input.Leaving := True;
    Input.Direction := TMVAnimationDirection(Document.ExitDirection);
    ApplyMVTransition(Result, Document.ExitMotion, Document.ExitVisibility,
      Document.ExitTiming, P, Document.ExitStrength, Input);
    Input.Envelope := 1 - P;
  end;
  // 既存の振幅演出は端で弱める。連続回転などの適用方法は各演出が決める。
  Input.Strength := Document.HoldStrength;
  Input.Amount := Document.Amount * Input.Strength;
  Input.Phase := 2 * Pi * Time / Max(0.05, Document.Period);
  if FindMVAnimation(makHold, Document.Hold, Hold) and Assigned(Hold.Evaluate) then Hold.Evaluate(Result, Input);
end;

end.
