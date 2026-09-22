unit MVAppearanceJson;

// 時間装飾の保存変換。旧文書で項目がなければ既定の無効状態を保つ。
interface

uses System.JSON, MVAppearanceTypes;

// 呼出し側が所有権を受け取るJSONオブジェクトを作る。
function EncodeMVAppearance(const Value: TMVAppearanceSettings): TJSONObject;
// 任意のルート項目を復元・検証する。存在する場合は全項目を必須とする。
function DecodeMVAppearance(const Value: TJSONValue): TMVAppearanceSettings;

implementation

uses System.SysUtils, System.Generics.Collections;

function EncodeMVAppearance(const Value: TMVAppearanceSettings): TJSONObject;
begin
  ValidateMVAppearance(Value);
  Result := TJSONObject.Create;
  try
    Result.AddPair('colorMode', TJSONNumber.Create(Int64(Value.ColorMode)));
    Result.AddPair('color', TJSONNumber.Create(Int64(Value.Color)));
    Result.AddPair('colorAmount', TJSONNumber.Create(Double(Value.ColorAmount)));
    Result.AddPair('glowPulse', TJSONNumber.Create(Double(Value.GlowPulse)));
    Result.AddPair('chromaticSwing', TJSONNumber.Create(Double(Value.ChromaticSwing)));
    Result.AddPair('period', TJSONNumber.Create(Double(Value.Period)));
    Result.AddPair('sweepMode', TJSONNumber.Create(Int64(Value.SweepMode)));
    Result.AddPair('sweepColor', TJSONNumber.Create(Int64(Value.SweepColor)));
    Result.AddPair('sweepAmount', TJSONNumber.Create(Double(Value.SweepAmount)));
    Result.AddPair('sweepWidth', TJSONNumber.Create(Double(Value.SweepWidth)));
    Result.AddPair('sweepAngle', TJSONNumber.Create(Double(Value.SweepAngle)));
    Result.AddPair('sweepPeriod', TJSONNumber.Create(Double(Value.SweepPeriod)));
    Result.AddPair('echoCount', TJSONNumber.Create(Int64(Value.EchoCount)));
    Result.AddPair('echoInterval', TJSONNumber.Create(Double(Value.EchoInterval)));
    Result.AddPair('echoOpacity', TJSONNumber.Create(Double(Value.EchoOpacity)));
    Result.AddPair('echoDecay', TJSONNumber.Create(Double(Value.EchoDecay)));
  except
    Result.Free;
    raise;
  end;
end;

function DecodeMVAppearance(const Value: TJSONValue): TMVAppearanceSettings;
var Obj: TJSONObject;
begin
  Result := DefaultMVAppearance;
  if Value = nil then Exit;
  if not (Value is TJSONObject) then
    raise EArgumentException.Create('装飾アニメーションの保存形式が不正です。');
  Obj := TJSONObject(Value);
  Result.ColorMode := Obj.GetValue<Integer>('colorMode');
  Result.Color := Obj.GetValue<Cardinal>('color');
  Result.ColorAmount := Obj.GetValue<Double>('colorAmount');
  Result.GlowPulse := Obj.GetValue<Double>('glowPulse');
  Result.ChromaticSwing := Obj.GetValue<Double>('chromaticSwing');
  Result.Period := Obj.GetValue<Double>('period');
  Result.SweepMode := Obj.GetValue<Integer>('sweepMode');
  Result.SweepColor := Obj.GetValue<Cardinal>('sweepColor');
  Result.SweepAmount := Obj.GetValue<Double>('sweepAmount');
  Result.SweepWidth := Obj.GetValue<Double>('sweepWidth');
  Result.SweepAngle := Obj.GetValue<Double>('sweepAngle');
  Result.SweepPeriod := Obj.GetValue<Double>('sweepPeriod');
  Result.EchoCount := Obj.GetValue<Integer>('echoCount');
  Result.EchoInterval := Obj.GetValue<Double>('echoInterval');
  Result.EchoOpacity := Obj.GetValue<Double>('echoOpacity');
  Result.EchoDecay := Obj.GetValue<Double>('echoDecay');
  ValidateMVAppearance(Result);
end;

end.
