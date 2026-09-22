unit MVEditorBackground;

// 編集対象のIDまたは旧SDKの配置区間を解決する。新APIは本体バージョンで保護する。
interface

uses AviUtl2FilterTypes;

// 新SDKはEffectID、旧SDKは一意な効果の配置区間を返す。取得不能時はFalse。
function ResolveMVBackgroundTarget(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; const Effect: string;
  Version: Cardinal; out EffectID: Int64; out Location: TOBJECT_LAYER_FRAME): Boolean;

implementation

uses MVFilterSettings;

function ResolveMVBackgroundTarget(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; const Effect: string;
  Version: Cardinal; out EffectID: Int64; out Location: TOBJECT_LAYER_FRAME): Boolean;
var Handle: Pointer;
begin
  Result := False;
  EffectID := 0;
  Location := Default(TOBJECT_LAYER_FRAME);
  if (Edit = nil) or (Obj = nil) then Exit;
  if Version >= 2011000 then
  begin
    if not Assigned(Edit^.FindEffect) or not Assigned(Edit^.GetEffectID) then Exit;
    Handle := Edit^.FindEffect(Obj, PChar(Effect));
    if Handle = nil then Exit;
    EffectID := Edit^.GetEffectID(Handle);
    Result := EffectID <> 0;
  end
  else
  begin
    if not Assigned(Edit^.GetObjectLayerFrame) or not Assigned(Edit^.CountObjectEffect) then Exit;
    if Edit^.CountObjectEffect(Obj, MV_EFFECT_NAME) <> 1 then Exit;
    Location := Edit^.GetObjectLayerFrame(Obj);
    Result := True;
  end;
end;

end.
