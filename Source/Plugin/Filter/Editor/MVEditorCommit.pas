unit MVEditorCommit;

// 編集対象を固定し、保存データの確定と競合検出を担当する。
interface

uses AviUtl2FilterTypes, MVDocument;

type
  TMVEditorCommit = class
  private
    FEdit: PEDIT_SECTION; // ボタンコールバック中だけ有効な編集セクション。
    FObject: OBJECT_HANDLE; // 選択変更に追従しない確定対象。
    FEffect: string; // SDKが渡した添字付きエフェクト名。
    FData: string; // 開始時または確定後の競合検出用保存値。
    function WriteItem(const Item, Value: string): Boolean;
  public
    // SDK対象と開始時データを固定する。編集コールバック外へ保持してはならない。
    constructor Create(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; const Effect, Data: string);
    // 対象のホスト値を直ちに複写する。対象消失・取得失敗は例外にする。
    function ReadItem(const Item: string): string;
    // 閉じる際に呼ぶ。成功時は空文字、失敗時は画面へ表示する理由を返す。
    function Save(const Document: TMVDocument): string;
  end;

implementation

uses System.SysUtils, MVStoredDocument, MVFilterSettings;

constructor TMVEditorCommit.Create(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; const Effect, Data: string);
begin
  inherited Create;
  FEdit := Edit;
  FObject := Obj;
  FEffect := Effect;
  FData := Data;
end;

function TMVEditorCommit.ReadItem(const Item: string): string;
var Value: PAnsiChar;
begin
  Value := FEdit^.GetObjectItemValue(FObject, PChar(FEffect), PChar(Item));
  if Value = nil then raise EInvalidOp.Create('対象の設定を取得できません。');
  Result := string(UTF8String(Value));
end;

function TMVEditorCommit.WriteItem(const Item, Value: string): Boolean;
var Encoded: UTF8String;
begin
  Encoded := UTF8String(Value);
  Result := FEdit^.SetObjectItemValue(FObject, PChar(FEffect), PChar(Item), PAnsiChar(Encoded));
end;

function TMVEditorCommit.Save(const Document: TMVDocument): string;
var NewData: string;
begin
  Result := '';
  NewData := EncodeMVStoredDocument(Document);
  if ReadItem(MV_DATA_ITEM) <> FData then
    Exit('編集中に対象の設定が変更されました。編集内容は画面内に保持しています。');
  if NewData = FData then Exit;
  if not WriteItem(MV_DATA_ITEM, NewData) then
    Exit('編集データを保存できません。編集内容は画面内に保持しています。');
  FData := NewData;
end;

end.
