unit MVEditorLegacy;

// 対象を直接渡せない旧SDKのボタン通知を、安全に対象固定できる場合だけ新経路へ接続する。
interface

uses AviUtl2FilterTypes;

// 選択対象に本効果が1つだけある場合、その対象と効果名を返す。曖昧な場合は書き込まない。
function ResolveMVLegacyTarget(Edit: PEDIT_SECTION; out Obj: OBJECT_HANDLE; out Error: string): Boolean;
// AviUtl2 2.1.10未満向けの旧形式ボタン通知。取得した対象を固定して編集する。
procedure OpenMVLegacyEditor(Edit: PEDIT_SECTION); cdecl;

implementation

uses System.SysUtils, System.UITypes, Vcl.Dialogs, MVFilterSettings, MVEditorHost;

function ResolveMVLegacyTarget(Edit: PEDIT_SECTION; out Obj: OBJECT_HANDLE; out Error: string): Boolean;
begin
  Result := False;
  Obj := nil;
  Error := '';
  if (Edit = nil) or not Assigned(Edit^.GetFocusObject) or not Assigned(Edit^.CountObjectEffect) then
  begin
    Error := '編集対象を取得するAPIが利用できません。';
    Exit;
  end;
  Obj := Edit^.GetFocusObject();
  if Obj = nil then
  begin
    Error := '編集対象のオブジェクトを取得できません。';
    Exit;
  end;
  if Edit^.CountObjectEffect(Obj, MV_EFFECT_NAME) <> 1 then
  begin
    Error := 'このAviUtl2では、同じオブジェクトにMVスタジオが複数あると編集対象を区別できません。' +
      sLineBreak + 'オブジェクトごとに1つ配置するか、AviUtl2 2.1.10以降で編集してください。';
    Obj := nil;
    Exit;
  end;
  Result := True;
end;

procedure OpenMVLegacyEditor(Edit: PEDIT_SECTION);
var Obj: OBJECT_HANDLE; Error: string;
begin
  try
    if not ResolveMVLegacyTarget(Edit, Obj, Error) then raise EInvalidOp.Create(Error);
    OpenMVEditor(Edit, Obj, MV_EFFECT_NAME, '拡張編集');
  except
    on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

end.
