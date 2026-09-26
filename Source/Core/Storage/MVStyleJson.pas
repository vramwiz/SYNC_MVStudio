unit MVStyleJson;

// 共通書式と選択文字の差分書式を同じキーで保存・復元する。
interface

uses System.JSON, MVStyleTypes;

// Common=Trueでは全項目と組版値を保存する。戻り値の所有権は呼出元へ渡す。
function EncodeMVStyle(const Style: TMVStyle; Fields: TMVStyleFields; Common: Boolean): TJSONObject;
// 存在する上書き項目をFieldsへ返す。Common=Trueでは旧版からの必須項目も検証する。
procedure DecodeMVStyle(Obj: TJSONObject; var Style: TMVStyle; out Fields: TMVStyleFields; Common: Boolean);

implementation

uses System.SysUtils;

function EncodeMVStyle(const Style: TMVStyle; Fields: TMVStyleFields; Common: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    if Common then Fields := [Low(TMVStyleField)..High(TMVStyleField)];
    if msfFontName in Fields then Result.AddPair('font', Style.FontName);
    if msfColor in Fields then Result.AddPair('color', TJSONNumber.Create(Int64(Style.Color)));
    if msfOutlineColor in Fields then Result.AddPair('outlineColor', TJSONNumber.Create(Int64(Style.OutlineColor)));
    if msfOutlineWidth in Fields then Result.AddPair('outline', TJSONNumber.Create(Double(Style.OutlineWidth)));
    if msfShadow in Fields then Result.AddPair('shadow', TJSONBool.Create(Style.Shadow));
    if msfOutlineBlur in Fields then Result.AddPair('outlineBlur', TJSONNumber.Create(Double(Style.OutlineBlur)));
    if msfShadowColor in Fields then Result.AddPair('shadowColor', TJSONNumber.Create(Int64(Style.ShadowColor)));
    if msfShadowX in Fields then Result.AddPair('shadowX', TJSONNumber.Create(Double(Style.ShadowX)));
    if msfShadowY in Fields then Result.AddPair('shadowY', TJSONNumber.Create(Double(Style.ShadowY)));
    if msfShadowSpread in Fields then Result.AddPair('shadowSpread', TJSONNumber.Create(Double(Style.ShadowSpread)));
    if msfShadowBlur in Fields then Result.AddPair('shadowBlur', TJSONNumber.Create(Double(Style.ShadowBlur)));
    if msfBold in Fields then Result.AddPair('bold', TJSONBool.Create(Style.Bold));
    if msfItalic in Fields then Result.AddPair('italic', TJSONBool.Create(Style.Italic));
    if msfFillMode in Fields then Result.AddPair('fillMode', TJSONNumber.Create(Int64(Style.FillMode)));
    if msfOpacity in Fields then Result.AddPair('opacity', TJSONNumber.Create(Double(Style.Opacity)));
    if msfGlowColor in Fields then Result.AddPair('glowColor', TJSONNumber.Create(Int64(Style.GlowColor)));
    if msfGlowRadius in Fields then Result.AddPair('glowRadius', TJSONNumber.Create(Double(Style.GlowRadius)));
    if msfGlowStrength in Fields then Result.AddPair('glowStrength', TJSONNumber.Create(Double(Style.GlowStrength)));
    if msfChromaticOffset in Fields then Result.AddPair('chromaticOffset', TJSONNumber.Create(Double(Style.ChromaticOffset)));
    if msfChromaticAngle in Fields then Result.AddPair('chromaticAngle', TJSONNumber.Create(Double(Style.ChromaticAngle)));
    if msfChromaticColor1 in Fields then Result.AddPair('chromaticColor1', TJSONNumber.Create(Int64(Style.ChromaticColor1)));
    if msfChromaticColor2 in Fields then Result.AddPair('chromaticColor2', TJSONNumber.Create(Int64(Style.ChromaticColor2)));
    if msfFrameColor in Fields then Result.AddPair('frameColor', TJSONNumber.Create(Int64(Style.FrameColor)));
    if msfFrameWidth in Fields then Result.AddPair('frameWidth', TJSONNumber.Create(Double(Style.FrameWidth)));
    if msfFramePadding in Fields then Result.AddPair('framePadding', TJSONNumber.Create(Double(Style.FramePadding)));
    if Common then
    begin
      Result.AddPair('size', TJSONNumber.Create(Double(Style.FontSize)));
      Result.AddPair('spacing', TJSONNumber.Create(Double(Style.Spacing)));
      Result.AddPair('lineSpacing', TJSONNumber.Create(Double(Style.LineSpacing)));
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure DecodeMVStyle(Obj: TJSONObject; var Style: TMVStyle; out Fields: TMVStyleFields; Common: Boolean);
begin
  if Obj = nil then raise EArgumentException.Create('文字書式の形式が不正です。');
  Fields := [];
  if Common or (Obj.GetValue('font') <> nil) then
  begin
    Style.FontName := Obj.GetValue<string>('font');
    Include(Fields, msfFontName);
  end;
  if Common or (Obj.GetValue('color') <> nil) then
  begin
    Style.Color := Obj.GetValue<Cardinal>('color');
    Include(Fields, msfColor);
  end;
  if Common or (Obj.GetValue('outlineColor') <> nil) then
  begin
    Style.OutlineColor := Obj.GetValue<Cardinal>('outlineColor');
    Include(Fields, msfOutlineColor);
  end;
  if Common or (Obj.GetValue('outline') <> nil) then
  begin
    Style.OutlineWidth := Obj.GetValue<Double>('outline');
    Include(Fields, msfOutlineWidth);
  end;
  if Common or (Obj.GetValue('shadow') <> nil) then
  begin
    Style.Shadow := Obj.GetValue<Boolean>('shadow');
    Include(Fields, msfShadow);
  end;
  if Obj.GetValue('outlineBlur') <> nil then
  begin
    Style.OutlineBlur := Obj.GetValue<Double>('outlineBlur');
    Include(Fields, msfOutlineBlur);
  end;
  if Obj.GetValue('shadowColor') <> nil then
  begin
    Style.ShadowColor := Obj.GetValue<Cardinal>('shadowColor');
    Include(Fields, msfShadowColor);
  end;
  if Obj.GetValue('shadowX') <> nil then
  begin
    Style.ShadowX := Obj.GetValue<Double>('shadowX');
    Include(Fields, msfShadowX);
  end;
  if Obj.GetValue('shadowY') <> nil then
  begin
    Style.ShadowY := Obj.GetValue<Double>('shadowY');
    Include(Fields, msfShadowY);
  end;
  if Obj.GetValue('shadowSpread') <> nil then
  begin
    Style.ShadowSpread := Obj.GetValue<Double>('shadowSpread');
    Include(Fields, msfShadowSpread);
  end;
  if Obj.GetValue('shadowBlur') <> nil then
  begin
    Style.ShadowBlur := Obj.GetValue<Double>('shadowBlur');
    Include(Fields, msfShadowBlur);
  end;
  if Common or (Obj.GetValue('bold') <> nil) then
  begin
    Style.Bold := Obj.GetValue<Boolean>('bold');
    Include(Fields, msfBold);
  end;
  if Common or (Obj.GetValue('italic') <> nil) then
  begin
    Style.Italic := Obj.GetValue<Boolean>('italic');
    Include(Fields, msfItalic);
  end;
  if (Obj.GetValue('fillMode') <> nil) then
  begin
    Style.FillMode := Obj.GetValue<Integer>('fillMode');
    Include(Fields, msfFillMode);
  end;
  if (Obj.GetValue('opacity') <> nil) then
  begin
    Style.Opacity := Obj.GetValue<Double>('opacity');
    Include(Fields, msfOpacity);
  end;
  if (Obj.GetValue('glowColor') <> nil) then
  begin
    Style.GlowColor := Obj.GetValue<Cardinal>('glowColor');
    Include(Fields, msfGlowColor);
  end;
  if (Obj.GetValue('glowRadius') <> nil) then
  begin
    Style.GlowRadius := Obj.GetValue<Double>('glowRadius');
    Include(Fields, msfGlowRadius);
  end;
  if (Obj.GetValue('glowStrength') <> nil) then
  begin
    Style.GlowStrength := Obj.GetValue<Double>('glowStrength');
    Include(Fields, msfGlowStrength);
  end;
  if (Obj.GetValue('chromaticOffset') <> nil) then
  begin
    Style.ChromaticOffset := Obj.GetValue<Double>('chromaticOffset');
    Include(Fields, msfChromaticOffset);
  end;
  if (Obj.GetValue('chromaticAngle') <> nil) then
  begin
    Style.ChromaticAngle := Obj.GetValue<Double>('chromaticAngle');
    Include(Fields, msfChromaticAngle);
  end;
  if (Obj.GetValue('chromaticColor1') <> nil) then
  begin
    Style.ChromaticColor1 := Obj.GetValue<Cardinal>('chromaticColor1');
    Include(Fields, msfChromaticColor1);
  end;
  if (Obj.GetValue('chromaticColor2') <> nil) then
  begin
    Style.ChromaticColor2 := Obj.GetValue<Cardinal>('chromaticColor2');
    Include(Fields, msfChromaticColor2);
  end;
  if (Obj.GetValue('frameColor') <> nil) then
  begin
    Style.FrameColor := Obj.GetValue<Cardinal>('frameColor');
    Include(Fields, msfFrameColor);
  end;
  if (Obj.GetValue('frameWidth') <> nil) then
  begin
    Style.FrameWidth := Obj.GetValue<Double>('frameWidth');
    Include(Fields, msfFrameWidth);
  end;
  if (Obj.GetValue('framePadding') <> nil) then
  begin
    Style.FramePadding := Obj.GetValue<Double>('framePadding');
    Include(Fields, msfFramePadding);
  end;
  if Common then
  begin
    Style.FontSize := Obj.GetValue<Double>('size');
    Style.Spacing := Obj.GetValue<Double>('spacing');
    Style.LineSpacing := Obj.GetValue<Double>('lineSpacing');
  end;
end;

end.
