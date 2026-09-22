unit MVLegacyEditorTests;

// 旧ボタンAPIで対象を一意に固定できない場合、誤ったオブジェクトを編集しないことを検証する。
interface

// 対象なし、APIなし、複数効果、別オブジェクトへの切替をメモリ上で検証する。
procedure RunLegacyEditorTests;

implementation

uses AviUtl2FilterTypes, MVEditorLegacy, MVTestAssert;

var Focus: OBJECT_HANDLE; EffectCount: Integer;

function GetFocus: OBJECT_HANDLE; cdecl;
begin
  Result := Focus;
end;

function CountEffects(Obj: OBJECT_HANDLE; Effect: LPCWSTR): Integer; cdecl;
begin
  Result := EffectCount;
end;

procedure RunLegacyEditorTests;
var Edit: TEDIT_SECTION; Obj: OBJECT_HANDLE; Error: string;
begin
  Edit := Default(TEDIT_SECTION);
  Check(not ResolveMVLegacyTarget(nil, Obj, Error), 'legacy nil edit rejected');
  Check(not ResolveMVLegacyTarget(@Edit, Obj, Error), 'legacy missing API rejected');
  Edit.GetFocusObject := GetFocus;
  Edit.CountObjectEffect := CountEffects;
  Focus := nil;
  Check(not ResolveMVLegacyTarget(@Edit, Obj, Error), 'legacy missing object rejected');
  Focus := Pointer(1234);
  EffectCount := 1;
  Check(ResolveMVLegacyTarget(@Edit, Obj, Error) and (Obj = Focus), 'legacy unique effect resolved');
  Focus := Pointer(5678);
  Check(ResolveMVLegacyTarget(@Edit, Obj, Error) and (Obj = Focus), 'legacy second object stays independent');
  EffectCount := 2;
  Check(not ResolveMVLegacyTarget(@Edit, Obj, Error) and (Obj = nil), 'legacy duplicate effects cannot misdirect edit');
  EffectCount := 0;
  Check(not ResolveMVLegacyTarget(@Edit, Obj, Error) and (Obj = nil), 'legacy focus without effect rejected');
  Writeln('Legacy editor target safety: OK');
end;

end.
