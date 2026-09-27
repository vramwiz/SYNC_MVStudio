unit MVDocumentJson;

// フレーズをバージョン付きJSONへ保存する。ポインタとホスト側の登場・退場所要時間は保存しない。
interface

uses MVDocument;

// 検証済みの単行JSONを返す。上限超過や不正値は例外とし部分保存しない。
function EncodeMVDocument(const Document: TMVDocument): string;
// 未知形式・破損データを拒否する。失敗時は呼び出し側のDocumentを変更しない。
function TryDecodeMVDocument(const Value: string; var Document: TMVDocument; out Error: string): Boolean;

implementation

uses System.SysUtils, System.JSON, System.Generics.Collections, MVTextUnits, MVAnimationTypes,
  MVStyleTypes, MVStyleJson, MVAppearanceJson, MVPositionMotionJson;

procedure AddNumber(Obj: TJSONObject; const Key: string; Value: Double);
begin
  Obj.AddPair(Key, TJSONNumber.Create(Value));
end;

procedure AddInteger(Obj: TJSONObject; const Key: string; Value: Int64);
begin
  // DelphiのJSON型変換は1.0をIntegerへ変換しないため、IDと色は整数表記で保存する。
  Obj.AddPair(Key, TJSONNumber.Create(Value));
end;

function EncodeMVDocument(const Document: TMVDocument): string;
var
  Root, Anim, Shape, UnitObject: TJSONObject;
  Units: TJSONArray;
  Item: TMVPlacement;
begin
  ValidateMVDocument(Document);
  Root := TJSONObject.Create;
  try
    AddInteger(Root, 'version', MV_DOCUMENT_VERSION);
    Root.AddPair('editorSettings', TJSONBool.Create(Document.EditorSettings));
    Root.AddPair('text', Document.Text);
    Root.AddPair('style', EncodeMVStyle(Document.Style, [], True));
    Root.AddPair('appearance', EncodeMVAppearance(Document.Appearance));
    Root.AddPair('positionMotion', EncodeMVPositionMotion(Document.PositionMotion));
    Anim := TJSONObject.Create;
    Root.AddPair('animation', Anim);
    AddInteger(Anim, 'hold', Document.Hold);
    AddInteger(Anim, 'inMotion', Document.EntranceMotion);
    AddInteger(Anim, 'outMotion', Document.ExitMotion);
    AddInteger(Anim, 'inVisibility', Document.EntranceVisibility);
    AddInteger(Anim, 'outVisibility', Document.ExitVisibility);
    AddInteger(Anim, 'inDirection', Document.EntranceDirection);
    AddInteger(Anim, 'outDirection', Document.ExitDirection);
    if Document.EntranceTiming <> 0 then AddInteger(Anim, 'inTiming', Document.EntranceTiming);
    if Document.ExitTiming <> 0 then AddInteger(Anim, 'outTiming', Document.ExitTiming);
    AddNumber(Anim, 'amount', Document.Amount);
    AddInteger(Anim, 'inOrder', Document.EntranceOrder);
    AddInteger(Anim, 'outOrder', Document.ExitOrder);
    AddInteger(Anim, 'inUnit', Document.EntranceUnit);
    AddInteger(Anim, 'holdUnit', Document.HoldUnit);
    AddInteger(Anim, 'outUnit', Document.ExitUnit);
    AddNumber(Anim, 'inStrength', Document.EntranceStrength);
    AddNumber(Anim, 'holdStrength', Document.HoldStrength);
    AddNumber(Anim, 'outStrength', Document.ExitStrength);
    AddNumber(Anim, 'curveAmount', Document.CurveAmount);
    AddNumber(Anim, 'period', Document.Period);
    AddNumber(Anim, 'inDelay', Document.EntranceDelay);
    AddNumber(Anim, 'outDelay', Document.ExitDelay);
    Shape := TJSONObject.Create;
    Root.AddPair('shape', Shape);
    AddInteger(Shape, 'effect', Document.Shape.EffectID);
    AddInteger(Shape, 'color', Document.Shape.Color);
    AddNumber(Shape, 'opacity', Document.Shape.Opacity);
    AddNumber(Shape, 'padding', Document.Shape.Padding);
    AddNumber(Shape, 'lineWidth', Document.Shape.LineWidth);
    AddNumber(Shape, 'period', Document.Shape.Period);
    AddInteger(Shape, 'direction', Document.Shape.Direction);
    Shape.AddPair('foreground', TJSONBool.Create(Document.Shape.Foreground));
    Units := TJSONArray.Create;
    Root.AddPair('placements', Units);
    // 自動配置かつ変形のない文字はnullで表し、歌詞から復元してデータ量を抑える。
    for Item in Document.Units do
    begin
      if Item.Positioned or (Item.Scale <> 1) or (Item.ScaleX <> 1) or (Item.ScaleY <> 1) or
        (Item.Angle <> 0) or (Item.Shear <> 0) or (Item.StyleFields <> []) or (Item.AnimationGroup <> 0) then
      begin
        UnitObject := TJSONObject.Create;
        AddNumber(UnitObject, 'x', Item.X);
        AddNumber(UnitObject, 'y', Item.Y);
        AddNumber(UnitObject, 'scale', Item.Scale);
        AddNumber(UnitObject, 'scaleX', Item.ScaleX);
        AddNumber(UnitObject, 'scaleY', Item.ScaleY);
        AddNumber(UnitObject, 'angle', Item.Angle);
        if Item.Shear <> 0 then AddNumber(UnitObject, 'shear', Item.Shear);
        if Item.AnimationGroup <> 0 then AddInteger(UnitObject, 'group', Item.AnimationGroup);
        UnitObject.AddPair('positioned', TJSONBool.Create(Item.Positioned));
        if Item.StyleFields <> [] then
          UnitObject.AddPair('style', EncodeMVStyle(Item.Style, Item.StyleFields, False));
        Units.AddElement(UnitObject);
      end
      else Units.AddElement(TJSONNull.Create);
    end;
    Result := Root.ToJSON;
    if Length(Result) > MV_MAX_DATA_LENGTH then
      raise EArgumentException.Create('配置データが保存上限を超えています。');
  finally
    Root.Free;
  end;
end;

function TryDecodeMVDocument(const Value: string; var Document: TMVDocument; out Error: string): Boolean;
var
  Parsed, ShapeValue, StyleValue: TJSONValue;
  StyleFields: TMVStyleFields;
  Root, Style, Anim, Shape, Placement, OldPositionMotion: TJSONObject;
  Units: TJSONArray;
  Candidate: TMVDocument;
  I, Version: Integer;
begin
  Result := False;
  Error := '';
  Parsed := nil;
  try
    try
      if (Value = '') or (Length(Value) > MV_MAX_DATA_LENGTH) then
        raise EArgumentException.Create('配置データの長さが不正です。');
      Parsed := TJSONObject.ParseJSONValue(Value);
      if not (Parsed is TJSONObject) then
        raise EArgumentException.Create('配置データを読み取れません。');
      Root := TJSONObject(Parsed);
      Version := Root.GetValue<Integer>('version');
      if not (Version in [1..MV_DOCUMENT_VERSION]) then
        raise EArgumentException.Create('未対応の配置データ形式です。');
      Candidate := DefaultMVDocument;
      Candidate.Appearance := DecodeMVAppearance(Root.GetValue('appearance'));
      Candidate.PositionMotion := DecodeMVPositionMotion(Root.GetValue('positionMotion'));
      Candidate.EditorSettings := Root.GetValue<Boolean>('editorSettings', False);
      SetMVText(Candidate, Root.GetValue<string>('text'));
      Style := Root.GetValue<TJSONObject>('style');
      DecodeMVStyle(Style, Candidate.Style, StyleFields, True);
      Anim := Root.GetValue<TJSONObject>('animation');
      Candidate.Hold := Anim.GetValue<Integer>('hold');
      Candidate.EntranceMotion := Anim.GetValue<Integer>('inMotion', 0);
      Candidate.ExitMotion := Anim.GetValue<Integer>('outMotion', 0);
      Candidate.EntranceVisibility := Anim.GetValue<Integer>('inVisibility', 0);
      Candidate.ExitVisibility := Anim.GetValue<Integer>('outVisibility', 0);
      // 旧文書の引継ぎ指定は無効として扱い、配置と書式だけを読み取れるようにする。
      if Version < MV_DOCUMENT_VERSION then
      begin
        if Candidate.EntranceMotion = -1 then Candidate.EntranceMotion := 0;
        if Candidate.ExitMotion = -1 then Candidate.ExitMotion := 0;
        if Candidate.EntranceVisibility = -1 then Candidate.EntranceVisibility := 0;
        if Candidate.ExitVisibility = -1 then Candidate.ExitVisibility := 0;
      end;
      Candidate.EntranceDirection := Anim.GetValue<Integer>('inDirection', Ord(madDown));
      Candidate.ExitDirection := Anim.GetValue<Integer>('outDirection', Ord(madUp));
      Candidate.EntranceTiming := Anim.GetValue<Integer>('inTiming', 0);
      Candidate.ExitTiming := Anim.GetValue<Integer>('outTiming', 0);
      Candidate.Amount := Anim.GetValue<Double>('amount');
      Candidate.EntranceOrder := Anim.GetValue<Integer>('inOrder', 0);
      Candidate.ExitOrder := Anim.GetValue<Integer>('outOrder', 0);
      Candidate.EntranceUnit := Anim.GetValue<Integer>('inUnit', Anim.GetValue<Integer>('unit', 0));
      Candidate.HoldUnit := Anim.GetValue<Integer>('holdUnit', Anim.GetValue<Integer>('unit', 0));
      Candidate.ExitUnit := Anim.GetValue<Integer>('outUnit', Anim.GetValue<Integer>('unit', 0));
      if (Version < 11) and (Root.GetValue('positionMotion') is TJSONObject) then
      begin
        OldPositionMotion := Root.GetValue<TJSONObject>('positionMotion');
        if (OldPositionMotion.GetValue('unit') = nil) and
          (OldPositionMotion.GetValue<Integer>('target', 0) = 0) then
          Candidate.PositionMotion.UnitMode := Anim.GetValue<Integer>('unit', 0);
      end;
      Candidate.EntranceStrength := Anim.GetValue<Double>('inStrength', 1);
      Candidate.HoldStrength := Anim.GetValue<Double>('holdStrength', 1);
      Candidate.ExitStrength := Anim.GetValue<Double>('outStrength', 1);
      Candidate.CurveAmount := Anim.GetValue<Double>('curveAmount', MV_DEFAULT_CURVE_AMOUNT);
      Candidate.Period := Anim.GetValue<Double>('period');
      // 旧チェック項目は秒数へ一意に換算できないため、新項目のない文書は同時開始にする。
      Candidate.EntranceDelay := Anim.GetValue<Double>('inDelay', 0);
      Candidate.ExitDelay := Anim.GetValue<Double>('outDelay', 0);
      // 旧version=1/2/3で図形項目がなければ、既定の「なし」を保つ。
      ShapeValue := Root.GetValue('shape');
      if ShapeValue <> nil then
      begin
        if not (ShapeValue is TJSONObject) then
          raise EArgumentException.Create('図形演出の形式が不正です。');
        Shape := TJSONObject(ShapeValue);
        Candidate.Shape.EffectID := Shape.GetValue<Integer>('effect');
        Candidate.Shape.Color := Shape.GetValue<Cardinal>('color');
        Candidate.Shape.Opacity := Shape.GetValue<Double>('opacity');
        Candidate.Shape.Padding := Shape.GetValue<Double>('padding');
        Candidate.Shape.LineWidth := Shape.GetValue<Double>('lineWidth');
        Candidate.Shape.Period := Shape.GetValue<Double>('period');
        Candidate.Shape.Direction := Shape.GetValue<Integer>('direction');
        Candidate.Shape.Foreground := Shape.GetValue<Boolean>('foreground');
      end;
      Units := Root.GetValue<TJSONArray>('placements');
      if Units.Count <> Length(Candidate.Units) then
        raise EArgumentException.Create('歌詞と配置要素数が一致しません。');
      for I := 0 to Units.Count - 1 do
        if not (Units.Items[I] is TJSONNull) then
        begin
          if not (Units.Items[I] is TJSONObject) then
            raise EArgumentException.Create('文字配置の形式が不正です。');
          Placement := TJSONObject(Units.Items[I]);
          Candidate.Units[I].X := Placement.GetValue<Double>('x');
          Candidate.Units[I].Y := Placement.GetValue<Double>('y');
          Candidate.Units[I].Scale := Placement.GetValue<Double>('scale');
          Candidate.Units[I].ScaleX := Placement.GetValue<Double>('scaleX', 1);
          Candidate.Units[I].ScaleY := Placement.GetValue<Double>('scaleY', 1);
          Candidate.Units[I].Shear := Placement.GetValue<Double>('shear', 0);
          Candidate.Units[I].Angle := Placement.GetValue<Double>('angle');
          Candidate.Units[I].AnimationGroup := Placement.GetValue<Integer>('group', 0);
          Candidate.Units[I].Positioned := Placement.GetValue<Boolean>('positioned', True);
          StyleValue := Placement.GetValue('style');
          if StyleValue <> nil then
          begin
            if not (StyleValue is TJSONObject) then
              raise EArgumentException.Create('文字別書式の形式が不正です。');
            DecodeMVStyle(TJSONObject(StyleValue), Candidate.Units[I].Style, Candidate.Units[I].StyleFields, False);
          end;
        end;
      ValidateMVDocument(Candidate);
      Document := Candidate;
      Result := True;
    except
      on E: Exception do Error := E.Message;
    end;
  finally
    Parsed.Free;
  end;
end;

end.
