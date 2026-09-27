unit MVPlacementToolbar;

// ScreenLayoutのコード描画パレットに倣い、配置操作をアイコンと選択色で示す。
interface

uses System.Classes, Vcl.Controls, Vcl.Buttons, Vcl.ExtCtrls;

type
  TMVPlacementCommand = (mpcSnap, mpcFit, mpcUndo, mpcRedo, mpcReset,
    mpcArrangeVertical, mpcArrangeHorizontal, mpcArrangeDiagonal, mpcGroup, mpcUngroup, mpcSelectGroup);

  TMVPlacementButton = class(TSpeedButton)
  protected
    // DPIに合わせて描き、フォントや外部画像に依存しないアイコンを表示する。
    procedure Paint; override;
  end;

// 操作アイコンを上段へ生成する。スナップは切替、変形はキャンバスのハンドルで行う。
function CreateMVPlacementToolbar(Owner: TComponent; Parent: TWinControl; Click: TNotifyEvent): TPanel;

implementation

uses Winapi.Windows, System.Types, System.Math, System.UITypes, Vcl.Graphics;

procedure TMVPlacementButton.Paint;
var SavedDC, X, Y, Side: Integer; Buffer: TBitmap;
begin
  Buffer := TBitmap.Create;
  try
    Buffer.SetSize(Width, Height);
    Buffer.Canvas.Brush.Color := $00303030;
    if Down then Buffer.Canvas.Brush.Color := $00744A28
    else if MouseInControl then Buffer.Canvas.Brush.Color := $004A4A4A;
    Buffer.Canvas.FillRect(ClientRect);
    SavedDC := SaveDC(Buffer.Canvas.Handle);
    try
      Side := Min(Width, Height) * 24 div 44;
      X := (Width - Side) div 2;
      Y := (Height - Side) div 2;
      SetMapMode(Buffer.Canvas.Handle, MM_ANISOTROPIC);
      SetWindowExtEx(Buffer.Canvas.Handle, 24, 24, nil);
      SetViewportExtEx(Buffer.Canvas.Handle, Side, Side, nil);
      SetViewportOrgEx(Buffer.Canvas.Handle, X, Y, nil);
      Buffer.Canvas.Pen.Color := $00E8E8E8;
      if not Enabled then Buffer.Canvas.Pen.Color := $00686868;
      Buffer.Canvas.Pen.Width := 2;
      Buffer.Canvas.Brush.Style := bsClear;
      case TMVPlacementCommand(Tag) of
        mpcSnap:
          begin
            Buffer.Canvas.Polyline([Point(4, 3), Point(4, 15), Point(8, 21), Point(16, 21),
              Point(20, 15), Point(20, 3)]);
            Buffer.Canvas.Polyline([Point(9, 3), Point(9, 14), Point(15, 14), Point(15, 3)]);
            Buffer.Canvas.Polyline([Point(4, 8), Point(9, 8)]);
            Buffer.Canvas.Polyline([Point(15, 8), Point(20, 8)]);
          end;
        mpcFit:
          begin
            Buffer.Canvas.Rectangle(3, 5, 21, 19);
            Buffer.Canvas.Rectangle(8, 9, 16, 15);
          end;
        mpcUndo, mpcRedo:
          begin
            if TMVPlacementCommand(Tag) = mpcUndo then
            begin
              Buffer.Canvas.Polyline([Point(9, 3), Point(3, 9), Point(9, 15)]);
              Buffer.Canvas.Polyline([Point(3, 9), Point(16, 9), Point(21, 14), Point(21, 21)]);
            end
            else
            begin
              Buffer.Canvas.Polyline([Point(15, 3), Point(21, 9), Point(15, 15)]);
              Buffer.Canvas.Polyline([Point(21, 9), Point(8, 9), Point(3, 14), Point(3, 21)]);
            end;
          end;
        mpcReset:
          begin
            Buffer.Canvas.Polyline([Point(2, 21), Point(22, 21)]);
            Buffer.Canvas.Rectangle(3, 8, 8, 18);
            Buffer.Canvas.Rectangle(10, 8, 15, 18);
            Buffer.Canvas.Rectangle(17, 8, 22, 18);
          end;
        mpcArrangeVertical:
          begin
            Buffer.Canvas.Rectangle(8, 1, 16, 6);
            Buffer.Canvas.Rectangle(8, 9, 16, 14);
            Buffer.Canvas.Rectangle(8, 17, 16, 22);
          end;
        mpcArrangeHorizontal:
          begin
            Buffer.Canvas.Rectangle(1, 8, 6, 16);
            Buffer.Canvas.Rectangle(9, 8, 14, 16);
            Buffer.Canvas.Rectangle(17, 8, 22, 16);
          end;
        mpcArrangeDiagonal:
          begin
            Buffer.Canvas.Rectangle(1, 1, 7, 7);
            Buffer.Canvas.Rectangle(9, 9, 15, 15);
            Buffer.Canvas.Rectangle(17, 17, 23, 23);
          end;
        mpcGroup, mpcUngroup, mpcSelectGroup:
          begin
            Buffer.Canvas.Rectangle(4, 5, 11, 15);
            Buffer.Canvas.Rectangle(13, 9, 20, 19);
            if TMVPlacementCommand(Tag) <> mpcUngroup then
            begin
              Buffer.Canvas.Pen.Width := 1;
              Buffer.Canvas.Rectangle(1, 2, 23, 22);
            end;
            if TMVPlacementCommand(Tag) = mpcUngroup then
              Buffer.Canvas.Polyline([Point(2, 22), Point(22, 2)])
            else if TMVPlacementCommand(Tag) = mpcSelectGroup then
            begin
              Buffer.Canvas.Brush.Style := bsSolid;
              Buffer.Canvas.Brush.Color := Buffer.Canvas.Pen.Color;
              Buffer.Canvas.Rectangle(0, 0, 4, 4);
              Buffer.Canvas.Rectangle(20, 20, 24, 24);
            end;
          end;
      end;
    finally
      Buffer.Canvas.Brush.Style := bsSolid;
      RestoreDC(Buffer.Canvas.Handle, SavedDC);
    end;
    // 親DCの子コントロール原点を変更しない。クリップ位置もVCLに委ねる。
    Canvas.Draw(0, 0, Buffer);
  finally Buffer.Free; end;
end;

function CreateMVPlacementToolbar(Owner: TComponent; Parent: TWinControl; Click: TNotifyEvent): TPanel;
const
  Hints: array[TMVPlacementCommand] of string = ('スナップ切替（Altで一時解除／Shiftで15度回転）', '全体を表示（Ctrl+0）',
    '元に戻す（Ctrl+Z）', 'やり直す（Ctrl+Y）', '全ての文字を自動整列へ戻す',
    '縦に整列（間隔12px。未選択なら全文字）',
    '横に整列（間隔12px。未選択なら全文字）',
    '斜めに整列（間隔12px・横ずらし40px。未選択なら全文字）',
    '選択文字をアニメーショングループに登録（Ctrl+G）。ホストの各「単位」で「選択グループ」を指定',
    '選択文字をアニメーショングループから外す（Ctrl+Shift+G）',
    '同じアニメーショングループの文字も選択');
var Command: TMVPlacementCommand; Button: TMVPlacementButton;
begin
  Result := TPanel.Create(Owner);
  Result.Parent := Parent;
  Result.Align := alTop;
  Result.Height := MulDiv(54, Result.CurrentPPI, 96);
  Result.BevelOuter := bvNone;
  Result.Color := $00282828;
  Result.ParentBackground := False;
  for Command := Low(TMVPlacementCommand) to High(TMVPlacementCommand) do
  begin
    Button := TMVPlacementButton.Create(Owner);
    Button.Parent := Result;
    Button.SetBounds(MulDiv(8 + Ord(Command) * 48, Result.CurrentPPI, 96),
      MulDiv(5, Result.CurrentPPI, 96), MulDiv(44, Result.CurrentPPI, 96), MulDiv(44, Result.CurrentPPI, 96));
    Button.Tag := Ord(Command);
    Button.Hint := Hints[Command];
    Button.ShowHint := True;
    Button.Flat := True;
    Button.OnClick := Click;
    if Command = mpcSnap then
    begin
      Button.GroupIndex := 1;
      Button.AllowAllUp := True;
      Button.Down := True;
    end;
    if Command = mpcGroup then
    begin
      Button.GroupIndex := 2;
      Button.AllowAllUp := True;
    end;
  end;
end;

end.
