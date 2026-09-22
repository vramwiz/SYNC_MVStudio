unit MVStyleDialog;

// 選択範囲または共通書式の静的装飾を編集する。変更した項目だけ呼出元へ返す。
interface

uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, MVStyleTypes;

// 取消時はStyleを変更しない。Fieldsは実際に操作した項目で、混在した他の書式を保持する。
function EditMVDecoration(var Style: TMVStyle; out Fields: TMVStyleFields): Boolean;

implementation

uses Winapi.Windows, System.SysUtils, System.Math, System.UITypes, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.Graphics;

type
  TMVStyleDialog = class(TForm)
  private
    FStyle: TMVStyle; // 確定まで文書に反映しない作業コピー。
    FFields: TMVStyleFields; // ユーザーが操作した項目。
    FEdits: array[0..7] of TEdit; // 幅・透明度・距離の数値入力。
    FFill: TComboBox; // 塗りと縁の組合せ。
    procedure Changed(Sender: TObject);
    procedure ColorClick(Sender: TObject);
    procedure ShowColor(Button: TButton);
    procedure Accept(Sender: TObject);
  public
    constructor CreateStyle(const Style: TMVStyle);
  end;

const
  NumberFields: array[0..7] of TMVStyleField = (msfOutlineWidth, msfOpacity, msfGlowRadius, msfGlowStrength, msfChromaticOffset, msfChromaticAngle, msfFrameWidth, msfFramePadding);
  NumberLabels: array[0..7] of string = ('縁の幅', '文字の不透明度（%）', '発光の広がり', '発光の強さ（%）', '色ずれの距離', '色ずれの方向（度）', '囲み枠の幅（0で無効）', '囲み枠の余白');
  NumberMin: array[0..7] of Double = (0, 0, 0, 0, 0, -180, 0, 0);
  NumberMax: array[0..7] of Double = (32, 100, 64, 100, 64, 180, 16, 128);
  ColorFields: array[0..3] of TMVStyleField = (msfGlowColor, msfChromaticColor1, msfChromaticColor2, msfFrameColor);
  ColorLabels: array[0..3] of string = ('発光の色', '色ずれの色1', '色ずれの色2', '囲み枠の色');

constructor TMVStyleDialog.CreateStyle(const Style: TMVStyle);
var I: Integer; LabelControl: TLabel; B: TButton; Values: array[0..7] of Double;
    Scroll: TScrollBox; Footer: TPanel;
begin
  inherited CreateNew(nil);
  PixelsPerInch := 96;
  Caption := '文字装飾（変更した項目だけ適用）'; Position := poOwnerFormCenter; BorderStyle := bsDialog;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  ClientWidth := 440; ClientHeight := 540;
  FStyle := Style;
  Footer := TPanel.Create(Self); Footer.Parent := Self; Footer.Align := alBottom;
  Footer.Height := 48; Footer.BevelOuter := bvNone;
  B := TButton.Create(Self); B.Parent := Footer; B.SetBounds(232, 10, 90, 28);
  B.Caption := '適用'; B.Default := True; B.OnClick := Accept;
  B := TButton.Create(Self); B.Parent := Footer; B.SetBounds(332, 10, 90, 28);
  B.Caption := 'キャンセル'; B.Cancel := True; B.ModalResult := mrCancel;
  Scroll := TScrollBox.Create(Self); Scroll.Parent := Self; Scroll.Align := alClient;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Scroll;
  LabelControl.SetBounds(16, 14, 200, 24); LabelControl.Caption := '塗り方';
  FFill := TComboBox.Create(Self); FFill.Parent := Scroll; FFill.SetBounds(240, 10, 168, 28);
  FFill.Style := csDropDownList;
  FFill.Items.Add('塗り＋縁'); FFill.Items.Add('塗りだけ'); FFill.Items.Add('縁だけ');
  FFill.ItemIndex := Style.FillMode; FFill.Tag := Ord(msfFillMode); FFill.OnChange := Changed;
  Values[0] := Style.OutlineWidth * 1;
  Values[1] := Style.Opacity * 100;
  Values[2] := Style.GlowRadius * 1;
  Values[3] := Style.GlowStrength * 100;
  Values[4] := Style.ChromaticOffset * 1;
  Values[5] := Style.ChromaticAngle * 1;
  Values[6] := Style.FrameWidth * 1;
  Values[7] := Style.FramePadding * 1;
  for I := 0 to High(FEdits) do
  begin
    LabelControl := TLabel.Create(Self); LabelControl.Parent := Scroll;
    LabelControl.SetBounds(16, 50 + I * 34, 218, 24); LabelControl.Caption := NumberLabels[I];
    FEdits[I] := TEdit.Create(Self); FEdits[I].Parent := Scroll;
    FEdits[I].SetBounds(240, 46 + I * 34, 168, 26);
    FEdits[I].Text := FloatToStr(Values[I]); FEdits[I].Tag := Ord(NumberFields[I]);
    FEdits[I].OnChange := Changed;
  end;
  for I := 0 to High(ColorFields) do
  begin
    B := TButton.Create(Self); B.Parent := Scroll;
    B.SetBounds(16, 324 + I * 36, 392, 28); B.Caption := ColorLabels[I];
    B.Tag := Ord(ColorFields[I]); B.OnClick := ColorClick;
    ShowColor(B);
  end;
  ScaleForPPI(Screen.PixelsPerInch);
end;

procedure TMVStyleDialog.Changed(Sender: TObject);
begin
  Include(FFields, TMVStyleField(TControl(Sender).Tag));
end;

procedure TMVStyleDialog.ShowColor(Button: TButton);
var I: Integer; C: Cardinal;
begin
  C := 0;
  case TMVStyleField(Button.Tag) of
    msfGlowColor: C := FStyle.GlowColor;
    msfChromaticColor1: C := FStyle.ChromaticColor1;
    msfChromaticColor2: C := FStyle.ChromaticColor2;
    msfFrameColor: C := FStyle.FrameColor;
  end;
  for I := 0 to High(ColorFields) do
    if Ord(ColorFields[I]) = Button.Tag then
      Button.Caption := ColorLabels[I] + '  #' + IntToHex(C and $FFFFFF, 6);
end;

procedure TMVStyleDialog.ColorClick(Sender: TObject);
var Dialog: TColorDialog; C: Cardinal; Field: TMVStyleField;
begin
  Field := TMVStyleField(TControl(Sender).Tag);
  C := $FFFFFFFF;
  case Field of
    msfGlowColor: C := FStyle.GlowColor;
    msfChromaticColor1: C := FStyle.ChromaticColor1;
    msfChromaticColor2: C := FStyle.ChromaticColor2;
    msfFrameColor: C := FStyle.FrameColor;
  end;
  Dialog := TColorDialog.Create(Self);
  try
    Dialog.Color := RGB((C shr 16) and $FF, (C shr 8) and $FF, C and $FF);
    if not Dialog.Execute then Exit;
    C := ColorToRGB(Dialog.Color);
    C := $FF000000 or Cardinal(GetRValue(C)) shl 16 or Cardinal(GetGValue(C)) shl 8 or GetBValue(C);
    case Field of
      msfGlowColor: FStyle.GlowColor := C;
      msfChromaticColor1: FStyle.ChromaticColor1 := C;
      msfChromaticColor2: FStyle.ChromaticColor2 := C;
      msfFrameColor: FStyle.FrameColor := C;
    end;
    Include(FFields, Field);
    ShowColor(TButton(Sender));
  finally Dialog.Free; end;
end;

procedure TMVStyleDialog.Accept(Sender: TObject);
var I: Integer; V: array[0..7] of Double; Candidate: TMVStyle;
begin
  try
    Candidate := FStyle;
    Candidate.FillMode := FFill.ItemIndex;
    for I := 0 to High(V) do
      if not TryStrToFloat(FEdits[I].Text, V[I]) or IsNan(V[I]) or IsInfinite(V[I]) or
        (V[I] < NumberMin[I]) or (V[I] > NumberMax[I]) then
      begin
        FEdits[I].SetFocus;
        raise EArgumentException.CreateFmt('%sは%g～%gで指定してください。', [NumberLabels[I], NumberMin[I], NumberMax[I]]);
      end;
    Candidate.OutlineWidth := V[0] / 1;
    Candidate.Opacity := V[1] / 100;
    Candidate.GlowRadius := V[2] / 1;
    Candidate.GlowStrength := V[3] / 100;
    Candidate.ChromaticOffset := V[4] / 1;
    Candidate.ChromaticAngle := V[5] / 1;
    Candidate.FrameWidth := V[6] / 1;
    Candidate.FramePadding := V[7] / 1;
    if (msfFillMode in FFields) and (Candidate.FillMode = 2) and (Candidate.OutlineWidth = 0) and
      not (msfOutlineWidth in FFields) then
    begin Candidate.OutlineWidth := 2; Include(FFields, msfOutlineWidth); end;
    ValidateMVStyle(Candidate);
    FStyle := Candidate;
    ModalResult := mrOk;
  except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
end;

function EditMVDecoration(var Style: TMVStyle; out Fields: TMVStyleFields): Boolean;
var Dialog: TMVStyleDialog;
begin
  Fields := [];
  Dialog := TMVStyleDialog.CreateStyle(Style);
  try
    Result := Dialog.ShowModal = mrOk;
    if Result then begin Style := Dialog.FStyle; Fields := Dialog.FFields; end;
  finally Dialog.Free; end;
end;

end.
