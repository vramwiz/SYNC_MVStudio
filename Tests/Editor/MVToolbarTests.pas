unit MVToolbarTests;

// 子コントロールの原点・クリップ付きDCで、全アイコンの描画と実クリック通知を検証する。
interface

// 96/144/192 DPI相当のボタン寸法を使い、ユーザーの画面は操作しない。
procedure RunToolbarTests;

implementation

uses Winapi.Windows, Winapi.Messages, System.Classes, System.SysUtils, System.Types,
  Vcl.Forms, Vcl.ExtCtrls, Vcl.Controls, Vcl.Buttons, MVFontToolbar, MVEditSession, MVDocument, Vcl.Graphics, MVPlacementToolbar, MVTestAssert;

type
  TClickProbe = class
    LastCommand: Integer; // 最後のマウス操作が通知したツール。
    procedure Click(Sender: TObject);
  end;

procedure TClickProbe.Click(Sender: TObject);
begin
  LastCommand := TControl(Sender).Tag;
end;

procedure CheckToolbar(PPI: Integer; Fonts: Boolean = False);
var Form: TForm; Bitmap: TBitmap; Probe: TClickProbe;
  Button: TSpeedButton; Owner: TComponent; Session: TMVEditSession; I, X, Y, SavedDC, Lit: Integer;
  BeforeOrigin, AfterOrigin: TPoint; Bounds: TRect; OriginsIntact: Boolean;
begin
  Form := TForm.CreateNew(nil);
  Bitmap := TBitmap.Create;
  Probe := TClickProbe.Create;
  Session := nil;
  try
    if Fonts then
    begin
      Session := TMVEditSession.Create(DefaultMVDocument);
      Owner := TMVFontToolbar.CreateToolbar(Form, Form, Session, nil);
    end
    else begin Owner := Form; CreateMVPlacementToolbar(Form, Form, Probe.Click); end;
    Bitmap.SetSize(MulDiv(400, PPI, 96), MulDiv(80, PPI, 96));
    Bitmap.Canvas.Brush.Color := clBlack;
    Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
    OriginsIntact := True;
    for I := 0 to Owner.ComponentCount - 1 do
      if Owner.Components[I] is TSpeedButton then
      begin
        Button := TSpeedButton(Owner.Components[I]);
        Button.SetBounds(MulDiv(8 + Button.Tag * 48, PPI, 96), MulDiv(5, PPI, 96),
          MulDiv(44, PPI, 96), MulDiv(44, PPI, 96));
        Button.OnClick := Probe.Click;
        Bounds := Button.BoundsRect;
        SavedDC := SaveDC(Bitmap.Canvas.Handle);
        try
          // VCL PaintControlsと同様に親DCへ子の原点とクリップを設定する。
          SetViewportOrgEx(Bitmap.Canvas.Handle, Bounds.Left, Bounds.Top, nil);
          IntersectClipRect(Bitmap.Canvas.Handle, 0, 0, Button.Width, Button.Height);
          GetViewportOrgEx(Bitmap.Canvas.Handle, BeforeOrigin);
          Button.Perform(WM_PAINT, Bitmap.Canvas.Handle, 0);
          GetViewportOrgEx(Bitmap.Canvas.Handle, AfterOrigin);
          OriginsIntact := OriginsIntact and (BeforeOrigin = AfterOrigin);
        finally RestoreDC(Bitmap.Canvas.Handle, SavedDC); end;
        Lit := 0;
        for Y := Bounds.Top + 1 to Bounds.Bottom - 2 do
          for X := Bounds.Left + 1 to Bounds.Right - 2 do
            if ColorToRGB(Bitmap.Canvas.Pixels[X, Y]) = $00E8E8E8 then Inc(Lit);
        Check(Lit > 15, Format('icon %d visible with clipped parent DC at %d DPI', [Button.Tag, PPI]));
        Probe.LastCommand := -1;
        Button.Perform(WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(Button.Width div 2, Button.Height div 2));
        Button.Perform(WM_LBUTTONUP, 0, MakeLParam(Button.Width div 2, Button.Height div 2));
        Check(Probe.LastCommand = Button.Tag, 'mouse click reaches icon command');
        if not Fonts and (Button.Tag = Ord(mpcSnap)) then Check(not Button.Down, 'snap icon toggles off on click');
      end;
    Check(OriginsIntact, 'toolbar preserves parent drawing origin');
    Bitmap.SaveToFile(ExtractFilePath(ParamStr(0)) + Format('toolbar-%d-%d.bmp', [Ord(Fonts), PPI]));
  finally Probe.Free; Bitmap.Free; Form.Free; Session.Free; end;
end;

procedure RunToolbarTests;
begin
  CheckToolbar(96);
  CheckToolbar(144);
  CheckToolbar(192);
  CheckToolbar(96, True);
  CheckToolbar(144, True);
  CheckToolbar(192, True);
  Writeln('Toolbar parent DC and DPI: OK');
end;

end.
