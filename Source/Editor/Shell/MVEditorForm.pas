unit MVEditorForm;

// ホスト歌詞の配置・共通書式を編集する画面。確定は保存コールバックへ委譲する。
interface

uses System.Classes, System.SysUtils, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls,
  MVFontToolbar, MVDocument, MVEditSession, MVEditorCanvas, MVBackgroundFrame, MVColorPanel;

type
  TMVSaveDocument = reference to function(const Document: TMVDocument): string;

  TMVEditorForm = class(TForm)
  private
    FSession: TMVEditSession; // 画面内の配置と操作履歴。
    FCanvas: TMVEditorCanvas; // 入力背景と文字の配置キャンバス。
    FFontToolbar: TMVFontToolbar; // 書体一覧と装飾。
    FColorPanel: TMVColorPanel; // 色関係をまとめる右側の埋め込みピッカー。
    FPlacementToolbar: TPanel; // 配置と永続的なアニメーショングループの操作。
    FSave: TMVSaveDocument; // 閉じるときだけ対象へ保存する関数。
    FRuntimeAcquired: Boolean; // 画面を閉じるまでSkiaを保持する。
    procedure StyleChanged(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure ChangeAnimationGroup(Clear: Boolean);
    procedure FitInitialWindow;
    procedure Command(Sender: TObject);
    procedure Shortcut(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
  protected
    // フォームのHandle再生成後もWindowsタイトルバーの暗色指定を保つ。
    procedure CreateWnd; override;
  public
    // 歌詞をホストに残し、独立した配置・書式を編集する。保存成功までは閉じない。
    constructor CreateEditor(const Document: TMVDocument; Width, Height: Integer;
      Duration, EntranceTime, ExitTime: Double; const Save: TMVSaveDocument);
    // 編集状態と描画資源を解放する。
    destructor Destroy; override;
    // ホストの合成前画像を表示する。未取得時は無地にする。
    procedure SetBackground(const Frame: TMVBackgroundFrame);
  end;

implementation

uses Winapi.Windows, Winapi.Dwmapi, System.Types, System.Math, System.UITypes, Vcl.Dialogs, Vcl.StdCtrls, MVPlacementToolbar,
  TextRendererSkiaRuntime, TextRendererSkiaBootstrap, MVArrangement, MVGrouping;

procedure TMVEditorForm.CreateWnd;
const
  DarkModeAttribute = 20;
  OldDarkModeAttribute = 19;
  CaptionColorAttribute = 35;
  TextColorAttribute = 36;
var
  Enabled: BOOL;
  CaptionColor, TextColor: COLORREF;
begin
  inherited;
  Enabled := True;
  if Failed(DwmSetWindowAttribute(Handle, DarkModeAttribute, @Enabled, SizeOf(Enabled))) then
    DwmSetWindowAttribute(Handle, OldDarkModeAttribute, @Enabled, SizeOf(Enabled));
  CaptionColor := $00282828;
  TextColor := $00E8E8E8;
  DwmSetWindowAttribute(Handle, CaptionColorAttribute, @CaptionColor, SizeOf(CaptionColor));
  DwmSetWindowAttribute(Handle, TextColorAttribute, @TextColor, SizeOf(TextColor));
end;

constructor TMVEditorForm.CreateEditor(const Document: TMVDocument; Width, Height: Integer;
  Duration, EntranceTime, ExitTime: Double; const Save: TMVSaveDocument);
var Body: TPanel;
begin
  inherited CreateNew(nil);
  TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
  FRuntimeAcquired := True;
  Caption := 'MVスタジオ - 文字配置';
  Position := poScreenCenter;
  ClientWidth := 1400;
  ClientHeight := 960;
  Constraints.MinWidth := 700;
  Constraints.MinHeight := 480;
  Color := $00282828;
  Font.Color := $00E8E8E8;
  Font.Name := 'Yu Gothic UI';
  Font.Size := 10;
  FSave := Save;
  FSession := TMVEditSession.Create(Document);
  // 保存文書の共通書式は編集画面で管理する。
  FSession.Document.EditorSettings := True;
  FPlacementToolbar := CreateMVPlacementToolbar(Self, Self, Command);
  Body := TPanel.Create(Self);
  Body.Parent := Self;
  Body.Align := alClient;
  Body.BevelOuter := bvNone;
  FCanvas := TMVEditorCanvas.Create(Self);
  FCanvas.Parent := Body;
  FCanvas.Align := alClient;
  FCanvas.OutputWidth := Width;
  FCanvas.OutputHeight := Height;
  FCanvas.Duration := Duration;
  FCanvas.EntranceTime := EntranceTime;
  FCanvas.ExitTime := ExitTime;
  FCanvas.Attach(FSession);
  FColorPanel := TMVColorPanel.CreatePanel(Self, Body, FCanvas);
  FFontToolbar := TMVFontToolbar.CreateToolbar(Self, Self, FSession, StyleChanged, FCanvas);
  FitInitialWindow;
  FCanvas.OnSelectionChanged := SelectionChanged;
  SelectionChanged(Self);
  SetBackground(Default(TMVBackgroundFrame));
  KeyPreview := True;
  OnKeyDown := Shortcut;
  OnCloseQuery := Closing;
end;

procedure TMVEditorForm.FitInitialWindow;
var WorkArea: TRect; I, ToolbarWidth: Integer;
begin
  WorkArea := Monitor.WorkareaRect;
  ToolbarWidth := 0;
  for I := 0 to FPlacementToolbar.ControlCount - 1 do
    ToolbarWidth := Max(ToolbarWidth, FPlacementToolbar.Controls[I].Left + FPlacementToolbar.Controls[I].Width);
  // 高DPIでも右端の固定操作が隠れない最小幅にし、初期ウィンドウは画面内へ収める。
  Constraints.MinWidth := Min(WorkArea.Width, Max(700,
    ToolbarWidth + MulDiv(8, CurrentPPI, 96) + Width - ClientWidth));
  Constraints.MinHeight := Min(WorkArea.Height, 480);
  Width := Min(Width, WorkArea.Width);
  Height := Min(Height, WorkArea.Height);
end;

destructor TMVEditorForm.Destroy;
begin
  if FCanvas <> nil then FCanvas.OnSelectionChanged := nil;
  FColorPanel.Free;
  FFontToolbar.Free;
  FCanvas.Free;
  FSession.Free;
  if FRuntimeAcquired then TTextRendererSkiaRuntime.Release;
  inherited;
end;

procedure TMVEditorForm.SetBackground(const Frame: TMVBackgroundFrame);
begin
  FCanvas.SetBackground(Frame);
end;

procedure TMVEditorForm.SelectionChanged(Sender: TObject);
var I, CommonGroup: Integer; HasGroup, SameGroup: Boolean; Button: TMVPlacementButton;
begin
  FFontToolbar.RefreshStyle;
  FColorPanel.RefreshStyle;
  CommonGroup := 0;
  if FCanvas.Selected >= 0 then CommonGroup := FSession.Document.Units[FCanvas.Selected].AnimationGroup;
  HasGroup := False;
  SameGroup := CommonGroup > 0;
  for I in FCanvas.SelectedIndices do
  begin
    HasGroup := HasGroup or (FSession.Document.Units[I].AnimationGroup > 0);
    SameGroup := SameGroup and (FSession.Document.Units[I].AnimationGroup = CommonGroup);
  end;
  for I := 0 to FPlacementToolbar.ControlCount - 1 do
    if FPlacementToolbar.Controls[I] is TMVPlacementButton then
    begin
      Button := TMVPlacementButton(FPlacementToolbar.Controls[I]);
      case TMVPlacementCommand(Button.Tag) of
        mpcGroup:
          begin
            Button.Enabled := FCanvas.SelectionCount > 1;
            Button.Down := SameGroup;
          end;
        mpcUngroup, mpcSelectGroup: Button.Enabled := HasGroup;
      end;
    end;
end;

procedure TMVEditorForm.ChangeAnimationGroup(Clear: Boolean);
var Candidate: TMVDocument;
begin
  FCanvas.CancelInteraction;
  try
    Candidate := CloneMVDocument(FSession.Document);
    if SetMVAnimationGroup(Candidate, FCanvas.SelectedIndices, Clear) then FCanvas.CommitDocument(Candidate);
  finally
    SelectionChanged(Self);
  end;
end;

procedure TMVEditorForm.StyleChanged(Sender: TObject);
begin
  FCanvas.CancelInteraction;
  FColorPanel.RefreshStyle;
  FCanvas.Invalidate;
end;

procedure TMVEditorForm.Command(Sender: TObject);
var I, ArrangeMode: Integer; Candidate: TMVDocument;
begin
  try
    FCanvas.CancelInteraction;
    case TMVPlacementCommand(TControl(Sender).Tag) of
      mpcSnap: FCanvas.SnapEnabled := TMVPlacementButton(Sender).Down;
      mpcFit: FCanvas.ResetView;
      mpcUndo: FSession.Undo;
      mpcRedo: FSession.Redo;
      mpcGroup: begin ChangeAnimationGroup(False); Exit; end;
      mpcUngroup: begin ChangeAnimationGroup(True); Exit; end;
      mpcSelectGroup: begin FCanvas.SelectAnimationGroups; Exit; end;
      mpcArrangeVertical, mpcArrangeHorizontal, mpcArrangeDiagonal:
        begin
          ArrangeMode := Ord(TMVPlacementCommand(TControl(Sender).Tag)) - Ord(mpcArrangeVertical);
          Candidate := CloneMVDocument(FSession.Document);
          // 各アイコンで固定の整列を直接適用し、追加フォームは開かない。
          ArrangeMVUnits(Candidate, FCanvas.Layout, FCanvas.SelectedIndices, ArrangeMode, 12, 40);
          FCanvas.CommitDocument(Candidate);
          FFontToolbar.RefreshStyle;
          Exit;
        end;
      mpcReset:
        begin
          FSession.BeginChange;
          for I := 0 to High(FSession.Document.Units) do
          begin
            FSession.Document.Units[I].Positioned := False;
            FSession.Document.Units[I].Scale := 1;
            FSession.Document.Units[I].ScaleX := 1;
            FSession.Document.Units[I].ScaleY := 1;
            FSession.Document.Units[I].Angle := 0;
            FSession.Document.Units[I].Shear := 0;
          end;
        end;
    end;
    FCanvas.RefreshDocument;
    SelectionChanged(Self);
  except
    on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMVEditorForm.Shortcut(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and FColorPanel.Editing then
  begin FColorPanel.FinishColor(True); Key := 0; Exit; end;
  if (ActiveControl is TCustomEdit) or (ActiveControl is TCustomComboBox) then Exit;
  if not (ssCtrl in Shift) then Exit;
  try
    if Key = Ord('G') then
    begin
      ChangeAnimationGroup(ssShift in Shift);
      Key := 0;
      Exit;
    end;
    if Key in [Ord('0'), Ord('1')] then
    begin FCanvas.CancelInteraction; FCanvas.ResetView(Key = Ord('1')); Key := 0; Exit; end;
    if not (Key in [Ord('Z'), Ord('Y')]) then Exit;
    FCanvas.CancelInteraction;
    if (Key = Ord('Y')) or (ssShift in Shift) then FSession.Redo else FSession.Undo;
    FCanvas.RefreshDocument;
    SelectionChanged(Self);
    Key := 0;
  except
    on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMVEditorForm.Closing(Sender: TObject; var CanClose: Boolean);
var Error: string;
begin
  CanClose := False;
  try
    FColorPanel.FinishColor(False);
    FCanvas.CancelInteraction;
    ValidateMVDocument(FSession.Document);
    Error := FSave(FSession.Document);
    if Error <> '' then raise EInvalidOp.Create(Error);
    CanClose := True;
  except
    on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

end.
