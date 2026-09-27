unit MVEditorHost;

// ボタンが指定したオブジェクト・エフェクトへ編集文書を保存するホスト境界。
interface

uses AviUtl2FilterTypes;

// 編集対象を引数で固定し、閉じる際の保存失敗は画面を保持する。例外をDLL境界へ出さない。
procedure OpenMVEditor(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR); cdecl;

implementation

uses System.SysUtils, System.Math, System.UITypes, Vcl.Dialogs, MVDocument, MVTextUnits,
  MVStoredDocument, MVPlacementDocument, MVFilterSettings, MVLayout, MVEditorForm, MVEditorCommit,
  MVBackgroundFrame, MVHostText, SYNC_MVStudio_FilterPlugin;

type
  PEditInfoPrefix = ^TEditInfoPrefix;
  TEditInfoPrefix = record
    Width, Height: Integer; // SDK EDIT_INFOの先頭2int。シーンの出力寸法。
    Rate, Scale: Integer; // 同じSDK先頭に続くフレームレートの分子・分母。
  end;

function ReadItem(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; const Effect, Item: string): string;
var Value: PAnsiChar;
begin
  Value := Edit^.GetObjectItemValue(Obj, PChar(Effect), PChar(Item));
  if Value = nil then raise EInvalidOp.Create('対象の設定を取得できません。');
  Result := string(UTF8String(Value));
end;

procedure OpenMVEditor(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR);
var
  Settings: TMVSettings;
  Document: TMVDocument;
  Form: TMVEditorForm;
  Layout: TMVLayout;
  EffectName, OldData, Error: string;
  I, Width, Height: Integer;
  Duration: Double;
  Location: TOBJECT_LAYER_FRAME;
  Save: TMVSaveDocument;
  Commit: TMVEditorCommit;
  Background: TMVBackgroundFrame;
begin
  try
    if (Edit = nil) or (Obj = nil) or (Effect = nil) or
      not Assigned(Edit^.GetObjectItemValue) or not Assigned(Edit^.SetObjectItemValue) then
      raise EInvalidOp.Create('AviUtl2の編集APIが利用できません。');
    EffectName := string(Effect);
    Settings := ReadMVSettings;
    // 他対象の描画で共有項目が更新されても、歌詞は指定された対象から直接取得する。
    Settings.Document.Text := DecodeMVHostText(ReadItem(Edit, Obj, EffectName, '歌詞'));
    OldData := ReadItem(Edit, Obj, EffectName, MV_DATA_ITEM);
    CopyMVStudioBackground(Edit, Obj, EffectName, Background);
    Width := 1920;
    Height := 1080;
    Duration := 5;
    if Edit^.Info <> nil then
    begin
      Width := PEditInfoPrefix(Edit^.Info)^.Width;
      Height := PEditInfoPrefix(Edit^.Info)^.Height;
      if Assigned(Edit^.GetObjectLayerFrame) and (PEditInfoPrefix(Edit^.Info)^.Rate > 0) and
        (PEditInfoPrefix(Edit^.Info)^.Scale > 0) then
      begin
        Location := Edit^.GetObjectLayerFrame(Obj);
        Duration := (Location.EndFrame - Location.StartFrame + 1) *
          PEditInfoPrefix(Edit^.Info)^.Scale / PEditInfoPrefix(Edit^.Info)^.Rate;
      end;
    end;
    if OldData <> '' then
    begin
      if not TryDecodeMVStoredDocument(OldData, Document, Error) then raise EInvalidOp.Create(Error);
      ApplyMVHostDocument(Document, Settings.Document);
    end
    else
    begin
      Document := Settings.Document;
      SetMVText(Document, Document.Text);
      FitMVInitialStyle(Document, Max(1, Width), Max(1, Height));
      Layout := TMVLayout.Create(Document);
      try
        for I := 0 to High(Document.Units) do
        begin
          Document.Units[I].X := Layout.Units[I].Position.X;
          Document.Units[I].Y := Layout.Units[I].Position.Y;
          Document.Units[I].Positioned := True;
        end;
      finally Layout.Free; end;
    end;
    Commit := TMVEditorCommit.Create(Edit, Obj, EffectName, OldData);
    try
      Save :=
        function(const Edited: TMVDocument): string
        begin
          Result := Commit.Save(Edited);
        end;
      Form := TMVEditorForm.CreateEditor(Document, Max(1, Width), Max(1, Height), Duration,
        Settings.EntranceTime, Settings.ExitTime, Save);
      try
        Form.SetBackground(Background);
        Form.ShowModal;
      finally Form.Free; end;
    finally Commit.Free; end;
  except
    on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

end.
