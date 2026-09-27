unit MVFontCombo;

// フォント一覧の候補と閉じた状態を、OSテーマに依存せず暗色で描く。

interface

uses
  System.Classes,
  System.Types,
  Winapi.Messages,
  Vcl.StdCtrls;

type
  TMVDarkFontCombo = class(TComboBox)
  protected
    // Handle再生成時も標準テーマを外し、確定した高さで親ツールバー内へ置く。
    procedure CreateWnd; override;
    // 候補の選択状態を暗色の背景と文字で表示する。
    procedure DrawItem(Index: Integer; Rect: TRect; State: TOwnerDrawState); override;
    // 閉じた状態の文字と矢印も候補と同じ配色へ揃える。
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.UxTheme,
  System.Math,
  Vcl.Graphics;

const
  MV_COMBO_BACKGROUND = TColor($00383838); // 一覧と閉じた状態の背景。
  MV_COMBO_SELECTED   = TColor($00504438); // 選択候補の背景。
  MV_COMBO_BORDER     = TColor($00606060); // 閉じた状態の外枠。
  MV_COMBO_TEXT       = TColor($00E8E8E8); // 有効時の文字と矢印。

procedure TMVDarkFontCombo.CreateWnd;
begin
  inherited;
  SetWindowTheme(Handle, '', '');
  if Parent <> nil then
    Top := Max(0, (Parent.ClientHeight - Height) div 2);
end;

procedure TMVDarkFontCombo.DrawItem(Index: Integer; Rect: TRect; State: TOwnerDrawState);
begin
  if odSelected in State then
    Canvas.Brush.Color := MV_COMBO_SELECTED
  else
    Canvas.Brush.Color := MV_COMBO_BACKGROUND;
  Canvas.FillRect(Rect);
  Canvas.Font := Font;
  Canvas.Font.Color := MV_COMBO_TEXT;
  if (Index >= 0) and (Index < Items.Count) then
    Canvas.TextOut(Rect.Left + MulDiv(5, CurrentPPI, 96),
      Rect.Top + Max(0, (Rect.Height - Canvas.TextHeight(Items[Index])) div 2), Items[Index]);
end;

procedure TMVDarkFontCombo.WMPaint(var Message: TWMPaint);
var
  ArrowX: Integer;
  ArrowY: Integer;
  DC: HDC;
  PaintCanvas: TCanvas;
  R: TRect;
begin
  inherited;
  DC := GetDC(Handle);
  PaintCanvas := TCanvas.Create;
  try
    PaintCanvas.Handle := DC;
    R := ClientRect;
    PaintCanvas.Brush.Color := MV_COMBO_BACKGROUND;
    PaintCanvas.Pen.Color := MV_COMBO_BORDER;
    PaintCanvas.Rectangle(R);
    PaintCanvas.Font := Font;
    if Enabled then
      PaintCanvas.Font.Color := MV_COMBO_TEXT
    else
      PaintCanvas.Font.Color := clGray;
    if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    begin
      R.Right := R.Right - MulDiv(20, CurrentPPI, 96);
      PaintCanvas.TextRect(R, MulDiv(5, CurrentPPI, 96),
        Max(0, (ClientHeight - PaintCanvas.TextHeight(Items[ItemIndex])) div 2), Items[ItemIndex]);
    end;
    ArrowX := ClientWidth - MulDiv(11, CurrentPPI, 96);
    ArrowY := ClientHeight div 2;
    PaintCanvas.Pen.Color := PaintCanvas.Font.Color;
    PaintCanvas.MoveTo(ArrowX - MulDiv(4, CurrentPPI, 96), ArrowY - MulDiv(2, CurrentPPI, 96));
    PaintCanvas.LineTo(ArrowX, ArrowY + MulDiv(2, CurrentPPI, 96));
    PaintCanvas.LineTo(ArrowX + MulDiv(4, CurrentPPI, 96), ArrowY - MulDiv(2, CurrentPPI, 96));
  finally
    PaintCanvas.Handle := 0;
    PaintCanvas.Free;
    ReleaseDC(Handle, DC);
  end;
end;

end.
