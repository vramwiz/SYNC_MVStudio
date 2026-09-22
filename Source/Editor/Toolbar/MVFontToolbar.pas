unit MVFontToolbar;

// 選択文字の書式を1段のツールバーで編集する。未選択なら共通書式を変更する。
interface

uses System.Classes, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Buttons, MVDocument, MVEditSession, MVStyleTypes, MVEditorCanvas;

type
  TMVFontAction = (mfaBold, mfaItalic, mfaOutline, mfaShadow, mfaColor, mfaOutlineColor);
  TMVFontButton = class(TSpeedButton)
  public
    Swatch: Cardinal; // 色選択アイコン下端のRGB色。
  protected
    // 親DCの原点を維持し、選択色と装飾を独立ビットマップに描く。
    procedure Paint; override;
  end;

  TMVFontToolbar = class(TPanel)
  private
    FCanvas: TMVEditorCanvas; // 選択集合の参照元。
    FSession: TMVEditSession; // フォームが所有する書式とUndo履歴。
    FChanged: TNotifyEvent; // 書式を確定した後に再組版を依頼する。
    FUpdating: Boolean; // 同期による再入を防ぐ。
    FFamily: TComboBox; // インストール済み書体を選択する一覧。
    FButtons: array[TMVFontAction] of TMVFontButton; // 独立した装飾切替と色選択。
    FOutlineWidth: Single; // 縁の再有効化時に戻す幅。
    procedure FamilyChanged(Sender: TObject);
    procedure ActionClick(Sender: TObject);
    function CurrentStyle: TMVStyle;
    procedure Apply(const Style: TMVStyle; Fields: TMVStyleFields);
  public
    // コンボ直後へ装飾アイコンを並べる。演出は扱わない。
    constructor CreateToolbar(Owner: TComponent; Parent: TWinControl; Session: TMVEditSession;
      Changed: TNotifyEvent; EditorCanvas: TMVEditorCanvas);
    // Undo/Redo後の文書を書式コントロールへ反映する。
    procedure RefreshStyle;
  end;

implementation

uses Winapi.Windows, System.SysUtils, System.Types, System.UITypes, System.Math,
  Vcl.Forms, Vcl.Graphics, Vcl.Dialogs;

procedure TMVFontButton.Paint;
const Letters: array[TMVFontAction] of string = ('B', 'I', 'A', 'A', 'A', 'A');
var B: TBitmap; R: TRect; Kind: TMVFontAction;
begin
  B := TBitmap.Create;
  try
    B.SetSize(Width, Height);
    B.Canvas.Brush.Color := $00303030;
    if Down then B.Canvas.Brush.Color := $00744A28
    else if MouseInControl then B.Canvas.Brush.Color := $004A4A4A;
    B.Canvas.FillRect(ClientRect);
    Kind := TMVFontAction(Tag);
    B.Canvas.Font.Name := 'Segoe UI';
    B.Canvas.Font.Height := -Height * 2 div 3;
    B.Canvas.Font.Color := $00E8E8E8;
    B.Canvas.Font.Style := [];
    if Kind = mfaBold then B.Canvas.Font.Style := [fsBold];
    if Kind = mfaItalic then B.Canvas.Font.Style := [fsItalic];
    R := ClientRect;
    if Kind = mfaShadow then
    begin
      OffsetRect(R, 3, 3);
      B.Canvas.Font.Color := $00777777;
      DrawText(B.Canvas.Handle, 'A', 1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
      R := ClientRect;
      B.Canvas.Font.Color := $00E8E8E8;
    end;
    DrawText(B.Canvas.Handle, PChar(Letters[Kind]), 1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    B.Canvas.Pen.Color := $00E8E8E8;
    B.Canvas.Brush.Style := bsClear;
    if Kind = mfaOutline then B.Canvas.Rectangle(3, 3, Width - 3, Height - 3);
    if Kind in [mfaColor, mfaOutlineColor] then
    begin
      B.Canvas.Pen.Color := TColor(Swatch);
      B.Canvas.Pen.Width := Max(2, Height div 10);
      B.Canvas.MoveTo(6, Height - 5); B.Canvas.LineTo(Width - 6, Height - 5);
      if Kind = mfaOutlineColor then B.Canvas.Rectangle(3, 3, Width - 3, Height - 9);
    end;
    Canvas.Draw(0, 0, B);
  finally B.Free; end;
end;

constructor TMVFontToolbar.CreateToolbar(Owner: TComponent; Parent: TWinControl; Session: TMVEditSession;
  Changed: TNotifyEvent; EditorCanvas: TMVEditorCanvas);
const
  Hints: array[TMVFontAction] of string = ('太字', '斜体', '縁取り', '影', '文字色', '縁の色');
var Kind: TMVFontAction;
begin
  inherited Create(Owner);
  Self.Parent := Parent;
  Align := alTop;
  Top := 0;
  Height := MulDiv(42, CurrentPPI, 96);
  BevelOuter := bvNone;
  Color := $00282828;
  ParentBackground := False;
  FSession := Session;
  FCanvas := EditorCanvas;
  FChanged := Changed;
  FOutlineWidth := 2;
  FFamily := TComboBox.Create(Self);
  FFamily.Parent := Self;
  FFamily.SetBounds(MulDiv(8, CurrentPPI, 96), MulDiv(7, CurrentPPI, 96),
    MulDiv(240, CurrentPPI, 96), MulDiv(28, CurrentPPI, 96));
  FFamily.Style := csDropDownList;
  FFamily.DropDownCount := 20;
  FFamily.Items.Assign(Screen.Fonts);
  FFamily.Sorted := True;
  FFamily.Color := $00383838;
  FFamily.Font.Color := $00E8E8E8;
  FFamily.Hint := 'フォント'; FFamily.ShowHint := True;
  FFamily.OnChange := FamilyChanged;
  for Kind := Low(TMVFontAction) to High(TMVFontAction) do
  begin
    FButtons[Kind] := TMVFontButton.Create(Self);
    with FButtons[Kind] do
    begin
      Parent := Self;
      Tag := Ord(Kind);
      SetBounds(MulDiv(256 + Ord(Kind) * 38, CurrentPPI, 96), MulDiv(3, CurrentPPI, 96),
        MulDiv(34, CurrentPPI, 96), MulDiv(34, CurrentPPI, 96));
      Hint := Hints[Kind] + ''; ShowHint := True;
      if Kind <= mfaShadow then begin GroupIndex := Ord(Kind) + 1; AllowAllUp := True; end;
      OnClick := ActionClick;
    end;
  end;
  RefreshStyle;
end;

procedure TMVFontToolbar.RefreshStyle;
var S: TMVStyle; I: Integer;
begin
  FUpdating := True;
  try
    S := CurrentStyle;
    if FCanvas.SelectionCount = 0 then FFamily.Hint := 'フォント（未選択のため共通書式に適用）'
    else FFamily.Hint := 'フォント（選択文字に適用。値が混在する場合は先頭文字を表示）';
    I := FFamily.Items.IndexOf(S.FontName);
    // 未導入書体の名前も保持し、画面を開くだけで代替書体へ書き換えない。
    if I < 0 then I := FFamily.Items.Add(S.FontName);
    FFamily.ItemIndex := I;
    FButtons[mfaBold].Down := S.Bold; FButtons[mfaItalic].Down := S.Italic;
    FButtons[mfaOutline].Down := (S.OutlineWidth > 0) and (S.FillMode <> 1);
    FButtons[mfaShadow].Down := S.Shadow;
    if S.OutlineWidth > 0 then FOutlineWidth := S.OutlineWidth;
    FButtons[mfaColor].Swatch := RGB((S.Color shr 16) and $FF, (S.Color shr 8) and $FF, S.Color and $FF);
    FButtons[mfaOutlineColor].Swatch := RGB((S.OutlineColor shr 16) and $FF,
      (S.OutlineColor shr 8) and $FF, S.OutlineColor and $FF);
    FButtons[mfaColor].Invalidate; FButtons[mfaOutlineColor].Invalidate;
  finally FUpdating := False; end;
end;

function TMVFontToolbar.CurrentStyle: TMVStyle;
begin
  Result := FSession.Document.Style;
  if FCanvas.Selected >= 0 then
    Result := ResolveMVStyle(Result, FSession.Document.Units[FCanvas.Selected]);
end;

procedure TMVFontToolbar.Apply(const Style: TMVStyle; Fields: TMVStyleFields);
var Candidate: TMVDocument; I: Integer;
begin
  try
    FCanvas.CancelInteraction;
    Candidate := CloneMVDocument(FSession.Document);
    if FCanvas.SelectionCount > 0 then
      for I in FCanvas.SelectedIndices do
      begin
        ApplyMVStyleFields(Candidate.Units[I].Style, Style, Fields);
        Candidate.Units[I].StyleFields := Candidate.Units[I].StyleFields + Fields;
      end
    else ApplyMVStyleFields(Candidate.Style, Style, Fields);
    ValidateMVDocument(Candidate);
    FCanvas.CommitDocument(Candidate);
    RefreshStyle;
    if Assigned(FChanged) then FChanged(Self);
  except
    on E: Exception do
    begin
      RefreshStyle;
      MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  end;
end;
procedure TMVFontToolbar.FamilyChanged(Sender: TObject);
var S: TMVStyle;
begin
  if FUpdating or (FFamily.ItemIndex < 0) then Exit;
  S := CurrentStyle;

  S.FontName := FFamily.Text; Apply(S, [msfFontName]);
end;

procedure TMVFontToolbar.ActionClick(Sender: TObject);
var S: TMVStyle; Kind: TMVFontAction; Dialog: TColorDialog; C: Cardinal; Fields: TMVStyleFields;
begin
  S := CurrentStyle;
  Kind := TMVFontAction(TControl(Sender).Tag);
  Fields := [];
  case Kind of
    mfaBold: Fields := [msfBold];
    mfaItalic: Fields := [msfItalic];
    mfaOutline: Fields := [msfOutlineWidth];
    mfaShadow: Fields := [msfShadow];
    mfaColor: Fields := [msfColor];
    mfaOutlineColor: Fields := [msfOutlineColor];
  end;
  case Kind of
    mfaBold: S.Bold := FButtons[Kind].Down;
    mfaItalic: S.Italic := FButtons[Kind].Down;
    mfaOutline:
      begin
        if FButtons[Kind].Down then
        begin
          S.OutlineWidth := FOutlineWidth;
          if S.FillMode = 1 then begin S.FillMode := 0; Include(Fields, msfFillMode); end;
        end
        else
        begin
          S.OutlineWidth := 0;
          if S.FillMode = 2 then begin S.FillMode := 1; Include(Fields, msfFillMode); end;
        end;
      end;
    mfaShadow: S.Shadow := FButtons[Kind].Down;
  else
    Dialog := TColorDialog.Create(Self);
    try
      if Kind = mfaColor then C := S.Color else C := S.OutlineColor;
      Dialog.Color := RGB((C shr 16) and $FF, (C shr 8) and $FF, C and $FF);
      if not Dialog.Execute then Exit;
      C := ColorToRGB(Dialog.Color);
      C := $FF000000 or Cardinal(GetRValue(C)) shl 16 or Cardinal(GetGValue(C)) shl 8 or GetBValue(C);
      if Kind = mfaColor then S.Color := C else S.OutlineColor := C;
    finally Dialog.Free; end;
  end;
  Apply(S, Fields);
end;

end.
