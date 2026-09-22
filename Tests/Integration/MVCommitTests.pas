unit MVCommitTests;

// ホスト設定APIを模擬し、対象固定・競合拒否・部分適用の復元を検証する。
interface

// 編集セクションをメモリ上に用意して確定処理の失敗経路まで検証する。
procedure RunCommitTests;

implementation

uses System.SysUtils, AviUtl2FilterTypes, MVDocument, MVTextUnits, MVStoredDocument,
  MVFilterSettings, MVEditorCommit, MVTestAssert;

var
  StoredData, ReturnedValue: UTF8String;
  StoredMode: string;
  FailMode, FailData, FailRollback, WrongTarget: Boolean;
  Writes, DataWrites: Integer;

function ReadItem(Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR): PAnsiChar; cdecl;
begin
  WrongTarget := WrongTarget or (NativeUInt(Obj) <> 1234) or (string(Effect) <> 'MVスタジオ:1');
  if string(Item) = MV_DATA_ITEM then ReturnedValue := StoredData else ReturnedValue := UTF8String(StoredMode);
  Result := PAnsiChar(ReturnedValue);
end;

function WriteItem(Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR; Value: PAnsiChar): Boolean; cdecl;
begin
  Inc(Writes);
  WrongTarget := WrongTarget or (NativeUInt(Obj) <> 1234) or (string(Effect) <> 'MVスタジオ:1');
  if string(Item) = MV_DATA_ITEM then
  begin
    Inc(DataWrites);
    Result := not FailData and not (FailRollback and (DataWrites = 2));
    if Result then StoredData := UTF8String(Value);
  end
  else
  begin
    Result := not FailMode;
    if Result then StoredMode := string(UTF8String(Value));
  end;
end;

function NewCommit(var Edit: TEDIT_SECTION): TMVEditorCommit;
begin
  StoredData := '';
  StoredMode := '標準';
  Writes := 0;
  DataWrites := 0;
  FailMode := False;
  FailData := False;
  FailRollback := False;
  WrongTarget := False;
  Result := TMVEditorCommit.Create(@Edit, Pointer(1234), 'MVスタジオ:1', '', '標準');
end;

procedure RunCommitTests;
var Edit: TEDIT_SECTION; Commit: TMVEditorCommit; D, Restored: TMVDocument; Data, Error: string;
begin
  Edit := Default(TEDIT_SECTION);
  Edit.GetObjectItemValue := ReadItem;
  Edit.SetObjectItemValue := WriteItem;
  D := DefaultMVDocument;
  SetMVText(D, '歌詞 "引用" \ /' + #10 + '次の行🎵');
  Data := EncodeMVStoredDocument(D);
  Check((Pos(#10, Data) = 0) and (Pos('\', Data) = 0) and (Pos('"', Data) = 0),
    'stored envelope contains no line breaks or escape characters');
  Check(TryDecodeMVStoredDocument(Data, Restored, Error), 'host storage envelope decodes');
  Check(Restored.Text = D.Text, 'quotes, slashes, Japanese, linebreak and emoji survive storage');
  Check(not TryDecodeMVStoredDocument('MV2:' + Copy(Data, 5, MaxInt), Restored, Error), 'unknown envelope rejected');
  Commit := NewCommit(Edit);
  try
    Check(Commit.Save(D) = '', 'commit succeeds');
    Check((string(StoredData) = Data) and (StoredMode = '拡張') and not WrongTarget,
      'commit writes data and mode to exact object and second effect');
    Check((Commit.Save(D) = '') and (Writes = 2), 'unchanged close does not create extra writes');
  finally Commit.Free; end;
  Commit := NewCommit(Edit);
  try
    StoredData := 'external change';
    Check((Commit.Save(D) <> '') and (Writes = 0), 'concurrent data change rejected before writes');
  finally Commit.Free; end;
  Commit := NewCommit(Edit);
  try
    StoredMode := '拡張';
    Check((Commit.Save(D) <> '') and (Writes = 0), 'concurrent mode change rejected before writes');
  finally Commit.Free; end;
  Commit := NewCommit(Edit);
  try
    FailData := True;
    Check((Commit.Save(D) <> '') and (StoredData = '') and (StoredMode = '標準'), 'data failure preserves both settings');
  finally Commit.Free; end;
  Commit := NewCommit(Edit);
  try
    FailMode := True;
    Check((Commit.Save(D) <> '') and (StoredData = '') and (StoredMode = '標準'), 'mode failure rolls back data');
    FailMode := False;
    Check(Commit.Save(D) = '', 'retry succeeds after rollback');
  finally Commit.Free; end;
  Commit := NewCommit(Edit);
  try
    FailMode := True;
    FailRollback := True;
    Error := Commit.Save(D);
    Check((Error <> '') and (string(StoredData) = Data) and (StoredMode = '標準'), 'rollback failure is reported');
    FailMode := False;
    FailRollback := False;
    Check(Commit.Save(D) = '', 'partial failure retains a valid retry baseline');
  finally Commit.Free; end;
  Writeln('Host save, conflict and rollback: OK');
end;

end.
