unit MVColorPanel;

// ScreenLayoutのHue/SV部品を使う埋め込みピッカー。色UIと連続編集の境界を右側へ集約する。
interface

uses System.Classes, System.UITypes, Winapi.Messages, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  ColorPickerHueBar, ColorPickerSVArea, MVEditorCanvas, MVStyleTypes, MVColorTargets;

type
  TMVColorPanel = class(TScrollBox)
  private
    FEditor: TMVEditorCanvas; // 文書と連続編集の所有元。
    FTargets: array[TMVColorTarget] of TMVColorTargetButton; // 色の固定切替。
    FTarget: TMVColorTarget; // 現在の適用先。
    FHue: TColorPickerHueBar; // 参考元から複写した色相バー。
    FSV: TColorPickerSVArea; // 参考元から複写した彩度・明度面。
    FHex, FAlpha: TEdit; // RGBコードと色ごとの不透明度。
    FColor: TAlphaColor; // 編集中のARGB色。
    FCurrentHue: Double; // 無彩色でも色相の選択を失わない。
    FBaseStyle: TMVStyle; // 色以外の混在書式を上書きしない開始値。
    FPicker: TControl; // 手動マウス捕捉を保持する色部品。
    FDragging, FUpdating: Boolean; // 連続変更と同期による再入を区別する。
    procedure TargetClick(Sender: TObject);
    procedure ColorDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ColorUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HueChanged(Sender: TObject);
    procedure SVChanged(Sender: TObject);
    procedure SyncPicker;
    procedure PreviewColor;
    procedure EditExit(Sender: TObject);
    procedure EditKey(Sender: TObject; var Key: Word; Shift: TShiftState);
  protected
    // 捕捉を失った色ドラッグは取り消し、開始時の色へ戻す。
    procedure WndProc(var Message: TMessage); override;
  public
    // 固定の対象ボタンとピッカーを同じパネルへ作る。
    constructor CreatePanel(Owner: TComponent; Parent: TWinControl; Editor: TMVEditorCanvas);
    // 編集中のピッカーを停止してから子部品を破棄する。
    destructor Destroy; override;
    // 選択変更・Undo後の値を同期する。ドラッグ中の色相は上書きしない。
    procedure RefreshStyle;
    // マウス操作全体を確定または取消する。Escと終了処理にも共用する。
    procedure FinishColor(Cancel: Boolean);
    property Editing: Boolean read FDragging;
  end;

implementation

uses System.SysUtils, System.Math, Winapi.Windows, Vcl.Graphics, Vcl.ExtCtrls, ColorPickerColorMath;

type TPickerAccess = class(TControl);

constructor TMVColorPanel.CreatePanel(Owner: TComponent; Parent: TWinControl; Editor: TMVEditorCanvas);
var T: TMVColorTarget; L: TLabel;
begin
  inherited Create(Owner);
  Self.Parent := Parent;
  FEditor := Editor;
  Align := alRight;
  Width := MulDiv(224, CurrentPPI, 96);
  BorderStyle := bsNone;
  Color := $00282828;
  ParentBackground := False;
  DoubleBuffered := True;
  TabStop := True;
  HorzScrollBar.Visible := False;
  for T := Low(TMVColorTarget) to High(TMVColorTarget) do
  begin
    FTargets[T] := TMVColorTargetButton.Create(Self);
    with FTargets[T] do
    begin
      Parent := Self;
      SetBounds(MulDiv(8 + (Ord(T) mod 2) * 104, CurrentPPI, 96),
        MulDiv(8 + (Ord(T) div 2) * 28, CurrentPPI, 96), MulDiv(100, CurrentPPI, 96), MulDiv(24, CurrentPPI, 96));
      Caption := MVColorTargetName(T);
      Hint := Caption + 'の色（選択文字、未選択なら共通書式）';
      ShowHint := True;
      Tag := Ord(T); GroupIndex := 1; OnClick := TargetClick;
    end;
  end;
  FHue := TColorPickerHueBar.Create(Self); FHue.Parent := Self;
  FHue.SetBounds(MulDiv(188, CurrentPPI, 96), MulDiv(128, CurrentPPI, 96),
    MulDiv(20, CurrentPPI, 96), MulDiv(140, CurrentPPI, 96));
  FHue.OnChange := HueChanged; FHue.OnMouseDown := ColorDown; FHue.OnMouseUp := ColorUp;
  FSV := TColorPickerSVArea.Create(Self); FSV.Parent := Self;
  FSV.SetBounds(MulDiv(8, CurrentPPI, 96), MulDiv(128, CurrentPPI, 96),
    MulDiv(174, CurrentPPI, 96), MulDiv(140, CurrentPPI, 96));
  FSV.OnChange := SVChanged; FSV.OnMouseDown := ColorDown; FSV.OnMouseUp := ColorUp;
  L := TLabel.Create(Self); L.Parent := Self; L.Caption := 'RGB';
  L.SetBounds(MulDiv(8, CurrentPPI, 96), MulDiv(282, CurrentPPI, 96), MulDiv(66, CurrentPPI, 96), MulDiv(24, CurrentPPI, 96));
  FHex := TEdit.Create(Self); FHex.Parent := Self;
  FHex.SetBounds(MulDiv(80, CurrentPPI, 96), MulDiv(278, CurrentPPI, 96), MulDiv(128, CurrentPPI, 96), MulDiv(26, CurrentPPI, 96));
  FHex.Color := $00383838; FHex.Font.Color := $00E8E8E8;
  FHex.StyleElements := FHex.StyleElements - [seClient];
  FHex.MaxLength := 7; FHex.OnExit := EditExit; FHex.OnKeyDown := EditKey;
  L := TLabel.Create(Self); L.Parent := Self; L.Caption := '不透明度%';
  L.SetBounds(MulDiv(8, CurrentPPI, 96), MulDiv(318, CurrentPPI, 96), MulDiv(74, CurrentPPI, 96), MulDiv(24, CurrentPPI, 96));
  FAlpha := TEdit.Create(Self); FAlpha.Parent := Self;
  FAlpha.SetBounds(MulDiv(88, CurrentPPI, 96), MulDiv(314, CurrentPPI, 96), MulDiv(120, CurrentPPI, 96), MulDiv(26, CurrentPPI, 96));
  FAlpha.Color := $00383838; FAlpha.Font.Color := $00E8E8E8;
  FAlpha.StyleElements := FAlpha.StyleElements - [seClient];
  FAlpha.MaxLength := 6; FAlpha.OnExit := EditExit; FAlpha.OnKeyDown := EditKey;
  RefreshStyle;
end;

destructor TMVColorPanel.Destroy;
begin
  FinishColor(True);
  inherited;
end;

procedure TMVColorPanel.RefreshStyle;
var S: TMVStyle; T: TMVColorTarget; C: TColor; Sat, Value: Double;
begin
  if FDragging or (FEditor = nil) or (FHex = nil) then Exit;
  S := FEditor.SelectedStyle;
  for T := Low(TMVColorTarget) to High(TMVColorTarget) do
  begin
    FTargets[T].Swatch := MVTargetColor(S, T);
    FTargets[T].Down := T = FTarget;
    FTargets[T].Invalidate;
  end;
  FColor := MVTargetColor(S, FTarget);
  C := RGB((FColor shr 16) and $FF, (FColor shr 8) and $FF, FColor and $FF);
  ColorToSv(C, Sat, Value);
  if (Sat > 0) and (Value > 0) then FCurrentHue := ColorHue(C);
  SyncPicker;
end;

procedure TMVColorPanel.SyncPicker;
begin
  FUpdating := True;
  try
    FHue.Color := HsvToColor(FCurrentHue, 1, 1);
    FSV.BaseColor := FHue.Color;
    FSV.Color := RGB((FColor shr 16) and $FF, (FColor shr 8) and $FF, FColor and $FF);
    FHex.Text := Format('#%.6X', [FColor and $FFFFFF]); FHex.Modified := False;
    FAlpha.Text := FormatFloat('0.#', (FColor shr 24) * 100 / 255, TFormatSettings.Invariant);
    FAlpha.Modified := False;
    FHex.Font.Color := $00E8E8E8; FAlpha.Font.Color := $00E8E8E8;
    FTargets[FTarget].Swatch := FColor; FTargets[FTarget].Invalidate;
  finally FUpdating := False; end;
end;

procedure TMVColorPanel.TargetClick(Sender: TObject);
begin
  FinishColor(False);
  EditExit(FHex);
  EditExit(FAlpha);
  FTarget := TMVColorTarget(TControl(Sender).Tag);
  RefreshStyle;
end;

procedure TMVColorPanel.ColorDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button <> mbLeft) or FUpdating then Exit;
  SetFocus;
  FEditor.BeginStyleEdit;
  FBaseStyle := FEditor.SelectedStyle;
  FDragging := True;
  FPicker := TControl(Sender);
  TPickerAccess(FPicker).MouseCapture := True;
end;

procedure TMVColorPanel.FinishColor(Cancel: Boolean);
var Picker: TControl;
begin
  if not FDragging then Exit;
  FDragging := False;
  Picker := FPicker; FPicker := nil;
  TPickerAccess(Picker).MouseCapture := False;
  FEditor.FinishStyleEdit(Cancel);
  RefreshStyle;
end;

procedure TMVColorPanel.ColorUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then FinishColor(False);
end;

procedure TMVColorPanel.PreviewColor;
var S: TMVStyle;
begin
  if not FDragging then Exit;
  S := FBaseStyle;
  SetMVTargetColor(S, FTarget, FColor);
  try
    FEditor.PreviewStyle(S, [MVColorTargetField(FTarget)]);
  except
    on E: Exception do begin FinishColor(True); Hint := E.Message; end;
  end;
  SyncPicker;
end;

procedure TMVColorPanel.HueChanged(Sender: TObject);
var C: TColor; S, V: Double;
begin
  if FUpdating or not FDragging then Exit;
  FCurrentHue := ColorHue(FHue.Color);
  ColorToSv(FSV.Color, S, V);
  C := HsvToColor(FCurrentHue, S, V);
  FColor := (FColor and $FF000000) or Cardinal(GetRValue(C)) shl 16 or Cardinal(GetGValue(C)) shl 8 or GetBValue(C);
  PreviewColor;
end;

procedure TMVColorPanel.SVChanged(Sender: TObject);
var C: TColor;
begin
  if FUpdating or not FDragging then Exit;
  C := FSV.Color;
  FColor := (FColor and $FF000000) or Cardinal(GetRValue(C)) shl 16 or Cardinal(GetGValue(C)) shl 8 or GetBValue(C);
  PreviewColor;
end;

procedure TMVColorPanel.EditExit(Sender: TObject);
var Value: Cardinal; Percent: Double; S: TMVStyle; Text: string; Color: TAlphaColor;
begin
  if FUpdating or not TEdit(Sender).Modified then Exit;
  Color := FColor;
  if Sender = FHex then
  begin
    Text := Trim(FHex.Text);
    if Copy(Text, 1, 1) = '#' then Delete(Text, 1, 1);
    if (Length(Text) <> 6) or not TryStrToUInt('$' + Text, Value) then
    begin FHex.Font.Color := clRed; Exit; end;
    Color := (Color and $FF000000) or (Value and $FFFFFF);
  end
  else
  begin
    if not TryStrToFloat(FAlpha.Text, Percent, TFormatSettings.Invariant) or IsNan(Percent) or
      IsInfinite(Percent) or (Percent < 0) or (Percent > 100) then
    begin FAlpha.Font.Color := clRed; Exit; end;
    Color := (Color and $FFFFFF) or Cardinal(Round(Percent * 255 / 100)) shl 24;
  end;
  try
    FEditor.BeginStyleEdit;
    S := FEditor.SelectedStyle;
    SetMVTargetColor(S, FTarget, Color);
    FEditor.PreviewStyle(S, [MVColorTargetField(FTarget)]);
    FEditor.FinishStyleEdit(False);
  except
    on E: Exception do begin FEditor.FinishStyleEdit(True); Hint := E.Message; end;
  end;
  RefreshStyle;
end;

procedure TMVColorPanel.EditKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then begin EditExit(Sender); Key := 0; end;
  if Key = VK_ESCAPE then begin RefreshStyle; Key := 0; end;
end;

procedure TMVColorPanel.WndProc(var Message: TMessage);
begin
  if (Message.Msg = WM_CAPTURECHANGED) and FDragging then FinishColor(True);
  inherited;
end;

end.
