unit PluginFilterTable;

// AviUtl2 Filterテーブルと設定項目の順次登録を一か所で管理する。
// Syncroh2の同名ユニットを基に、SYNC_MVStudioが使用するSDK型だけへ絞っている。

interface

uses
  AviUtl2FilterTypes;

// 項目登録をリセットし、DLL寿命中に有効な名前とコールバックを登録する。
procedure SetupPluginTable(Flag: Integer; Name, Label_, Information: PWideChar;
  VideoProc: TFuncProcVideo; AudioProc: TFuncProcAudio);
// ファイル項目を初期化し登録する。渡す文字列はDLL寿命中に有効であること。
procedure AddFile(var Item: TFILTER_ITEM_FILE; Name, Value,
  FileFilter: PWideChar);
// ボタン項目を登録する。新形式のCallback2は登録後に別途設定できる。
procedure AddButton(var Item: TFILTER_ITEM_BUTTON; Name: PWideChar;
  Callback: TFilterItemButtonCallback);
// ホストが以後Valueを更新する単行文字列項目を登録する。
procedure AddString(var Item: TFILTER_ITEM_STRING; Name, Value: PWideChar);
// BGR順の初期色で項目を登録する。Xは予約領域。
procedure AddColor(var Item: TFILTER_ITEM_COLOR; Name: PWideChar;
  B, G, R: Byte; X: Byte = 255);
// 現在値・範囲・刻みを指定して数値トラックを登録する。
procedure AddTrack(var Item: TFILTER_ITEM_TRACK; Name: PWideChar;
  Value, S, E, Step: Double);
// C bool相当の0/1でチェック項目を登録する。
procedure AddCheck(var Item: TFILTER_ITEM_CHECK; Name: PWideChar;
  Value: Byte);
// Name=nil終端の選択肢配列を使って選択項目を登録する。
procedure AddSelect(var Item: TFILTER_ITEM_SELECT; Name: PWideChar;
  Value: Integer; List: Pointer);
// 後続項目の折りたたみグループを登録する。空のNameはグループ終端。
procedure AddGroup(var Item: TFILTER_ITEM_GROUP; Name: PWideChar;
  DefaultVisible: Byte);

// 指定した選択値のときだけ既存項目を隠す。保存名と値は維持する。
procedure AddHideRule(var Item: TFILTER_ITEM_HIDE_RULE; Name, Condition: PWideChar; Value: Integer);

// 本体が対応する場合だけhideruleを公開する。項目の値や保存名は変更しない。
// 初期状態は無効にし、バージョン通知前のテーブル取得も旧本体で安全にする。
procedure SetFilterHideRulesEnabled(Enabled: Boolean);

// 別ユニットで初期化済みの項目も同じ登録順へ組み込めるようにする。
procedure AddFilterItem(var Item: TFILTER_ITEM_TRACK); overload;
// 初期化済みチェック項目を登録順の末尾へ追加する。
procedure AddFilterItem(var Item: TFILTER_ITEM_CHECK); overload;
// 初期化済みグループ見出しを登録順の末尾へ追加する。
procedure AddFilterItem(var Item: TFILTER_ITEM_GROUP); overload;
// 初期化済み選択項目を登録順の末尾へ追加する。
procedure AddFilterItem(var Item: TFILTER_ITEM_SELECT); overload;
// 初期化済み色項目を登録順の末尾へ追加する。
procedure AddFilterItem(var Item: TFILTER_ITEM_COLOR); overload;

// DLL寿命中に有効なホスト公開テーブルを返す。
function GetPluginTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.SysUtils;

const
  MAX_GUI_ITEMS = 100;

var
  GTable: TFILTER_PLUGIN_TABLE;
  GItems: array[0..MAX_GUI_ITEMS - 1] of Pointer;
  GItemIndex: Integer;
  GPublishedItems: array[0..MAX_GUI_ITEMS - 1] of Pointer; // 対応済み項目だけをホストへ渡す配列。
  GHideRulesEnabled: Boolean; // 未知・旧本体へ新しい項目種別を渡さない。

procedure SetFilterHideRulesEnabled(Enabled: Boolean);
var I, Count: Integer;
begin
  GHideRulesEnabled := Enabled;
  Count := 0;
  for I := 0 to GItemIndex - 1 do
    if Enabled or (string(PFILTER_ITEM_STRING(GItems[I])^.ItemType) <> 'hiderule') then
    begin
      GPublishedItems[Count] := GItems[I];
      Inc(Count);
    end;
  GPublishedItems[Count] := nil;
  GTable.Items := @GPublishedItems[0];
end;

procedure RegisterItem(Item: Pointer);
begin
  // 最後の1要素はAviUtl2が要求するnil終端用に予約する。
  if GItemIndex >= High(GItems) then
    raise ERangeError.CreateFmt(
      'Filter setting item count exceeds the limit (%d)',
      [High(GItems)]);
  GItems[GItemIndex] := Item;
  Inc(GItemIndex);
  GItems[GItemIndex] := nil;
  SetFilterHideRulesEnabled(GHideRulesEnabled);
end;

procedure SetupPluginTable(Flag: Integer; Name, Label_, Information: PWideChar;
  VideoProc: TFuncProcVideo; AudioProc: TFuncProcAudio);
begin
  GItemIndex := 0;
  FillChar(GItems, SizeOf(GItems), 0);
  GTable.Flag := Flag;
  GTable.Name := Name;
  GTable.Label_ := Label_;
  GTable.Information := Information;
  SetFilterHideRulesEnabled(False);
  GTable.Func_Proc_Video := VideoProc;
  GTable.Func_Proc_Audio := AudioProc;
end;

procedure AddFile(var Item: TFILTER_ITEM_FILE; Name, Value,
  FileFilter: PWideChar);
begin
  Item.ItemType := 'file';
  Item.Name := Name;
  Item.Value := Value;
  Item.FileFilter := FileFilter;
  RegisterItem(@Item);
end;

procedure AddButton(var Item: TFILTER_ITEM_BUTTON; Name: PWideChar;
  Callback: TFilterItemButtonCallback);
begin
  Item.ItemType := 'button';
  Item.Name := Name;
  Item.Callback := Callback;
  RegisterItem(@Item);
end;

procedure AddString(var Item: TFILTER_ITEM_STRING; Name, Value: PWideChar);
begin
  Item.ItemType := 'string';
  Item.Name := Name;
  Item.Value := Value;
  RegisterItem(@Item);
end;

procedure AddColor(var Item: TFILTER_ITEM_COLOR; Name: PWideChar;
  B, G, R, X: Byte);
begin
  Item.ItemType := 'color';
  Item.Name := Name;
  Item.B := B;
  Item.G := G;
  Item.R := R;
  Item.X := X;
  RegisterItem(@Item);
end;

procedure AddTrack(var Item: TFILTER_ITEM_TRACK; Name: PWideChar;
  Value, S, E, Step: Double);
begin
  Item.ItemType := 'track';
  Item.Name := Name;
  Item.Value := Value;
  Item.S := S;
  Item.E := E;
  Item.Step := Step;
  RegisterItem(@Item);
end;

procedure AddCheck(var Item: TFILTER_ITEM_CHECK; Name: PWideChar;
  Value: Byte);
begin
  Item.ItemType := 'check';
  Item.Name := Name;
  Item.Value := Value;
  RegisterItem(@Item);
end;

procedure AddSelect(var Item: TFILTER_ITEM_SELECT; Name: PWideChar;
  Value: Integer; List: Pointer);
begin
  Item.ItemType := 'select';
  Item.Name := Name;
  Item.Value := Value;
  Item.List := List;
  RegisterItem(@Item);
end;

procedure AddGroup(var Item: TFILTER_ITEM_GROUP; Name: PWideChar;
  DefaultVisible: Byte);
begin
  Item.ItemType := 'group';
  Item.Name := Name;
  Item.DefaultVisible := DefaultVisible;
  RegisterItem(@Item);
end;

procedure AddHideRule(var Item: TFILTER_ITEM_HIDE_RULE; Name, Condition: PWideChar; Value: Integer);
begin
  Item.ItemType := 'hiderule';
  Item.Name := Name;
  Item.ConditionName := Condition;
  Item.ConditionOperator := 0;
  Item.ConditionValue := Value;
  RegisterItem(@Item);
end;
procedure AddFilterItem(var Item: TFILTER_ITEM_TRACK);
begin
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_CHECK);
begin
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_GROUP);
begin
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_SELECT);
begin
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_COLOR);
begin
  RegisterItem(@Item);
end;

function GetPluginTable: PFILTER_PLUGIN_TABLE;
begin
  Result := @GTable;
end;

end.
