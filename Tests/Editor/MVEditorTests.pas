unit MVEditorTests;

// 非表示の編集フォームで終了時確定と描画を検証し、確認用PNGを生成する。
interface

// 作業文書の独立性と閉じる経路を検証する。ユーザーのホスト画面は操作しない。
procedure RunEditorTests;

implementation

uses System.SysUtils, System.Types, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  MVDocument, MVTextUnits, MVEditorForm, MVEditorCanvas, MVPlacementToolbar, MVBackgroundFrame, MVTestAssert,
  MVLayout, TextRendererSkiaBootstrap, TextRendererSkiaRuntime;

procedure RunEditorTests;
var D, Saved: TMVDocument; Form: TMVEditorForm; Count, I: Integer; CanClose, HasExtraControls: Boolean;
  Bitmap: TBitmap; PNG: TPngImage;
  Background: TMVBackgroundFrame; Canvas: TMVEditorCanvas;
  Layout: TMVLayout; Point: TPointF;
begin
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  try
    D := DefaultMVDocument;
    SetMVText(D, '響く歌に' + #10 + '想いをのせて');
    D.Entrance := 2;
    D.Hold := 3;
    D.ExitEffect := 1;
    Count := 0;
    Form := TMVEditorForm.CreateEditor(D, 1920, 1080, 5, 0.3, 0.3,
      function(const Document: TMVDocument): string
      begin
        Inc(Count);
        Saved := CloneMVDocument(Document);
        Result := '';
      end);
    try
      Background.Width := 960;
      Background.Height := 540;
      SetLength(Background.Pixels, Background.Width * Background.Height * 4);
      for I := 0 to Background.Width * Background.Height - 1 do
      begin
        Background.Pixels[I * 4] := 25;
        if I mod Background.Width < Background.Width div 2 then Background.Pixels[I * 4 + 1] := 55
        else Background.Pixels[I * 4 + 1] := 110;
        Background.Pixels[I * 4 + 2] := 90;
        Background.Pixels[I * 4 + 3] := 255;
      end;
      Form.SetBackground(Background);
      Background.Pixels := nil;
      Canvas := nil;
      for I := 0 to Form.ComponentCount - 1 do
        if Form.Components[I] is TMVEditorCanvas then Canvas := TMVEditorCanvas(Form.Components[I]);
      Check((Canvas <> nil) and (Canvas.OutputWidth = 960) and (Canvas.OutputHeight = 540),
        'editor coordinates use captured input dimensions');
      Form.Position := poDesigned;
      Form.Left := -30000;
      Form.Top := -30000;
      Form.ShowInTaskBar := False;
      Form.Show;
      Form.Update;
      D.Units[0].X := 700;
      CanClose := False;
      Form.OnCloseQuery(Form, CanClose);
      Check(CanClose and (Count = 1), 'window close validates and commits once');
      Check(Saved.Units[0].X = 0, 'editor uses isolated working copy');
      Bitmap := TBitmap.Create;
      PNG := TPngImage.Create;
      try
        Bitmap.SetSize(Canvas.ClientWidth, Canvas.ClientHeight);
        Canvas.PaintTo(Bitmap.Canvas, 0, 0);
        Check(Bitmap.Canvas.Pixels[Canvas.ClientWidth div 4, Canvas.ClientHeight div 4] =
          TColor(RGB(25, 55, 90)), 'editor paints independent background copy behind lyrics');
        Layout := TMVLayout.Create(Saved);
        try Point := Canvas.DocumentToScreen(Layout.Units[0].Position); finally Layout.Free; end;
        Canvas.Perform(WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(Round(Point.X), Round(Point.Y)));
        Canvas.Perform(WM_LBUTTONUP, 0, MakeLParam(Round(Point.X), Round(Point.Y)));
        Check(Canvas.Selected = 0, 'character click selects bounding box for preview');
        Bitmap.SetSize(Form.ClientWidth, Form.ClientHeight);
        Form.PaintTo(Bitmap.Canvas, 0, 0);
        PNG.Assign(Bitmap);
        PNG.SaveToFile(ExtractFilePath(ParamStr(0)) + 'editor-preview.png');
      finally PNG.Free; Bitmap.Free; end;
      HasExtraControls := False;
      for I := 0 to Form.ComponentCount - 1 do
      begin
        HasExtraControls := HasExtraControls or (Form.Components[I] is TLabel) or (Form.Components[I] is TMemo) or
          (Form.Components[I] is TComboBox);
        if (Form.Components[I] is TMVPlacementButton) and
          (TMVPlacementButton(Form.Components[I]).Tag = Ord(mpcClose)) then
          TMVPlacementButton(Form.Components[I]).Click;
      end;
      Check(not HasExtraControls, 'editor has no bottom status labels or lyric input on main form');
      Check(Count = 2, 'close button uses same commit path');
      Check(Saved.Text = D.Text, 'placement editor preserves host lyric');
    finally Form.Free; end;
  finally TTextRendererSkiaRuntime.Release; end;
  Writeln('Editor close and snapshot: OK');
end;

end.
