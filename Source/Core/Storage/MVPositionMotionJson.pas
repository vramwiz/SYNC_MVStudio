unit MVPositionMotionJson;

// 追加の位置モーションの保存変換。項目のない旧文書は無効状態へ復元する。
interface

uses System.JSON, MVPositionMotionTypes;

// 呼出し側が所有権を受け取るJSONオブジェクトを作る。
function EncodeMVPositionMotion(const Value: TMVPositionMotionSettings): TJSONObject;
// 項目がある場合は全フィールドと範囲を検証し、部分的に読み込まない。
function DecodeMVPositionMotion(const Value: TJSONValue): TMVPositionMotionSettings;

implementation

uses System.SysUtils, System.Generics.Collections;

function EncodeMVPositionMotion(const Value: TMVPositionMotionSettings): TJSONObject;
begin
  ValidateMVPositionMotion(Value);
  Result := TJSONObject.Create;
  try
    Result.AddPair('kind', TJSONNumber.Create(Int64(Value.Kind)));
    Result.AddPair('amplitudeX', TJSONNumber.Create(Double(Value.AmplitudeX)));
    Result.AddPair('amplitudeY', TJSONNumber.Create(Double(Value.AmplitudeY)));
    Result.AddPair('period', TJSONNumber.Create(Double(Value.Period)));
    Result.AddPair('direction', TJSONNumber.Create(Double(Value.Direction)));
    Result.AddPair('target', TJSONNumber.Create(Int64(Value.Target)));
    Result.AddPair('inStrength', TJSONNumber.Create(Double(Value.EntranceStrength)));
    Result.AddPair('holdStrength', TJSONNumber.Create(Double(Value.HoldStrength)));
    Result.AddPair('outStrength', TJSONNumber.Create(Double(Value.ExitStrength)));
    Result.AddPair('phaseStep', TJSONNumber.Create(Double(Value.PhaseStep)));
  except
    Result.Free;
    raise;
  end;
end;

function DecodeMVPositionMotion(const Value: TJSONValue): TMVPositionMotionSettings;
var Obj: TJSONObject;
begin
  Result := DefaultMVPositionMotion;
  if Value = nil then Exit;
  if not (Value is TJSONObject) then
    raise EArgumentException.Create('追加の位置モーションの保存形式が不正です。');
  Obj := TJSONObject(Value);
  Result.Kind := Obj.GetValue<Integer>('kind');
  Result.AmplitudeX := Obj.GetValue<Double>('amplitudeX');
  Result.AmplitudeY := Obj.GetValue<Double>('amplitudeY');
  Result.Period := Obj.GetValue<Double>('period');
  Result.Direction := Obj.GetValue<Double>('direction');
  Result.Target := Obj.GetValue<Integer>('target');
  Result.EntranceStrength := Obj.GetValue<Double>('inStrength');
  Result.HoldStrength := Obj.GetValue<Double>('holdStrength');
  Result.ExitStrength := Obj.GetValue<Double>('outStrength');
  Result.PhaseStep := Obj.GetValue<Double>('phaseStep');
  ValidateMVPositionMotion(Result);
end;

end.
