unit MVArrangeDialog;

// 文字の整列方向と間隔を設定する小画面。確定まで配置は変更しない。
interface

// 取消ならFalse。斜めの横ずらしは1文字ごとの出力ピクセル数。
function ChooseMVArrangement(out Mode: Integer; out Gap, SideStep: Single): Boolean;

implementation

uses System.Classes, System.SysUtils, System.Math, System.UITypes, Vcl.Forms,
  Vcl.Controls, Vcl.StdCtrls, Vcl.Dialogs;

type
  TMVArrangeDialog = class(TForm)
  private
    FMode: TComboBox; // 縦・横・斜め。
    FGap, FSide: TEdit; // 字間と斜めの横ずらし。
    FGapValue, FSideValue: Single; // 検証済みの確定値。
    procedure Accept(Sender: TObject);
  public
    constructor CreateArrange;
  end;

constructor TMVArrangeDialog.CreateArrange;
var L: TLabel; B: TButton;
begin
  inherited CreateNew(nil);
  PixelsPerInch := 96;
  Caption := '文字を整列'; BorderStyle := bsDialog; Position := poOwnerFormCenter;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10; ClientWidth := 390; ClientHeight := 210;
  L := TLabel.Create(Self); L.Parent := Self; L.SetBounds(16, 16, 330, 22);
  L.Caption := '選択文字を整列（未選択なら全ての文字）';
  FMode := TComboBox.Create(Self); FMode.Parent := Self; FMode.SetBounds(16, 46, 350, 28);
  FMode.Style := csDropDownList; FMode.Items.Add('縦に並べる');
  FMode.Items.Add('横に並べる'); FMode.Items.Add('斜めに並べる'); FMode.ItemIndex := 0;
  L := TLabel.Create(Self); L.Parent := Self; L.SetBounds(16, 86, 220, 22); L.Caption := '文字の間隔（-512～512）';
  FGap := TEdit.Create(Self); FGap.Parent := Self; FGap.SetBounds(254, 82, 112, 26); FGap.Text := '12';
  L := TLabel.Create(Self); L.Parent := Self; L.SetBounds(16, 120, 236, 22); L.Caption := '斜めの横ずらし（-512～512）';
  FSide := TEdit.Create(Self); FSide.Parent := Self; FSide.SetBounds(254, 116, 112, 26); FSide.Text := '40';
  B := TButton.Create(Self); B.Parent := Self; B.SetBounds(172, 164, 90, 28);
  B.Caption := '整列'; B.Default := True; B.OnClick := Accept;
  B := TButton.Create(Self); B.Parent := Self; B.SetBounds(276, 164, 90, 28);
  B.Caption := 'キャンセル'; B.Cancel := True; B.ModalResult := mrCancel;
  ScaleForPPI(Screen.PixelsPerInch);
end;

procedure TMVArrangeDialog.Accept(Sender: TObject);
var Gap, Side: Double;
begin
  if not TryStrToFloat(FGap.Text, Gap) or not TryStrToFloat(FSide.Text, Side) or
    IsNan(Gap) or IsInfinite(Gap) or IsNan(Side) or IsInfinite(Side) or
    (Abs(Gap) > 512) or (Abs(Side) > 512) then
  begin MessageDlg('間隔と横ずらしは-512～512で指定してください。', mtError, [mbOK], 0); Exit; end;
  FGapValue := Gap; FSideValue := Side; ModalResult := mrOk;
end;

function ChooseMVArrangement(out Mode: Integer; out Gap, SideStep: Single): Boolean;
var Dialog: TMVArrangeDialog;
begin
  Mode := 0; Gap := 12; SideStep := 40;
  Dialog := TMVArrangeDialog.CreateArrange;
  try
    Result := Dialog.ShowModal = mrOk;
    if Result then begin Mode := Dialog.FMode.ItemIndex; Gap := Dialog.FGapValue; SideStep := Dialog.FSideValue; end;
  finally Dialog.Free; end;
end;

end.
