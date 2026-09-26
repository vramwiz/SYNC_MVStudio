unit MVEditorCanvasView;

// 編集文書との関連付け、組版と背景の寿命、表示座標と連続書式編集を管理する。
// マウス捕捉とキー入力の状態遷移は派生クラスMVEditorCanvasが担当する。
interface

uses System.Classes, System.SysUtils, System.Types, System.Skia, Vcl.Controls, MVEditSession, MVLayout,
  MVBackgroundFrame, MVDocument, MVCanvasViewport, MVTransformGeometry, MVSelection, MVStyleTypes, MVStyleGesture;

type
  TMVEditorCanvasView = class abstract(TCustomControl)
  private
    FSelectionChanged: TNotifyEvent; // 選択または連続書式編集の終了後にUIの同期を依頼する。
    // 生成途中・解放時でも連続編集中かを安全に参照する。
    function GetStyleEditing: Boolean;
    // 未選択なら-1。単一書式の表示では選択集合の先頭を使う。
    function GetSelected: Integer;
    // 複数文字の操作UIを切り替えるための選択数。
    function GetSelectionCount: Integer;
  protected
    FSession: TMVEditSession; // フォーム所有の作業文書。キャンバスは解放しない。
    FLayout: TMVLayout; // 現在の組版を所有する。書式の連続編集中はGestureが退避画像を管理する。
    FSelection: TMVSelection; // 選択と一括変形を所有する。組版の置換後はAttachで参照を同期する。
    FView: TMVViewport; // 文書へ保存しない画面倍率と移動量。
    FBuffer: TBytes; // 描画サイズに合わせて再利用するBGRA転送バッファ。
    FBackground: ISkImage; // ホスト入力から複写した静止背景。元フレームとは寿命を共有しない。
    FStyleGesture: TMVStyleGesture; // 連続編集の退避文書とUndo確定を管理する。
    FStyleIndices: TArray<Integer>; // 連続編集開始時に固定した対象文字。
    // 選択を読み取るUIへ通知する。文書やUndoは変更しない。
    procedure NotifySelection;
    // 最新のクライアント寸法を反映する。手動ズーム・パンの指定は保持する。
    procedure ViewTransform;
  public
    OutputWidth, OutputHeight: Integer; // 編集対象シーンの解像度。
    Time, Duration, EntranceTime, ExitTime: Double; // Time=-1なら静止編集。
    // 選択・書式編集の管理オブジェクトを所有し、表示状態を初期化する。
    constructor Create(AOwner: TComponent); override;
    // 背景・組版・選択を解放する。派生クラスは先に未確定の入力操作を取り消す。
    destructor Destroy; override;
    // 作業用文書を関連付けて最初の組版を行う。
    procedure Attach(Session: TMVEditSession);
    // 入力背景をSkia画像へ複写し、キャンバスを入力寸法に合わせる。空なら無地へ戻す。
    procedure SetBackground(const Frame: TMVBackgroundFrame);
    // 文書変更後に組版を更新する。
    procedure RefreshDocument;
    // 候補の組版成功後だけ文書を置き換え、1操作のUndoを記録する。
    procedure CommitDocument(const Candidate: TMVDocument);
    // 色と装飾の連続変更を開始する。対象と組版を退避する。
    procedure BeginStyleEdit;
    // 退避文書の指定書式だけを更新し、途中のUndoを作らずプレビューする。
    procedure PreviewStyle(const Style: TMVStyle; Fields: TMVStyleFields);
    // 連続編集の確定または取消。停止前の組版へ戻せるため取消時は再生成しない。
    procedure FinishStyleEdit(Cancel: Boolean);
    // 選択先頭の実効書式。未選択なら共通書式。
    function SelectedStyle: TMVStyle;
    property StyleEditing: Boolean read GetStyleEditing;
    // 表示だけをフィットまたは100%へ戻す。
    procedure ResetView(ActualSize: Boolean = False);
    // 入力層が未確定操作を取り消す。書式編集・グループ選択は対象を固定する前に呼ぶ。
    procedure CancelInteraction(Deselect: Boolean = False); virtual; abstract;
    // 自動配置の文字も含め、現在の選択点を画面座標で返す。
    function SelectionHandles: TMVHandlePoints;
    // 保存座標を画面へ変換する。表示検証と補助UIにも使う。
    function DocumentToScreen(const Point: TPointF): TPointF;
    // 選択のコピーを返す。書式・整列コマンドは内部配列を直接変更しない。
    function SelectedIndices: TArray<Integer>;
    // 現在の選択を、登録済みの動作グループ全体へ広げる。文書やUndoは変更しない。
    procedure SelectAnimationGroups;
    property Selected: Integer read GetSelected;
    property SelectionCount: Integer read GetSelectionCount;
    property Layout: TMVLayout read FLayout;
    property OnSelectionChanged: TNotifyEvent read FSelectionChanged write FSelectionChanged;
  end;

implementation

uses MVGrouping;

constructor TMVEditorCanvasView.Create(AOwner: TComponent);
begin
  inherited;
  FSelection := TMVSelection.Create;
  FStyleGesture := TMVStyleGesture.Create;
  Time := -1;
  Duration := 5;
  OutputWidth := 1920;
  OutputHeight := 1080;
end;

destructor TMVEditorCanvasView.Destroy;
begin
  FStyleGesture.Free;
  FBackground := nil;
  FSelection.Free;
  FLayout.Free;
  inherited;
end;

procedure TMVEditorCanvasView.SetBackground(const Frame: TMVBackgroundFrame);
begin
  FBackground := nil;
  if Frame.IsValid then
  begin
    FBackground := TSkImage.MakeRasterCopy(TSkImageInfo.Create(Frame.Width, Frame.Height,
      TSkColorType.RGBA8888, TSkAlphaType.Unpremul), @Frame.Pixels[0], Frame.Width * 4);
    OutputWidth := Frame.Width;
    OutputHeight := Frame.Height;
  end;
  Invalidate;
end;

procedure TMVEditorCanvasView.Attach(Session: TMVEditSession);
begin
  FSession := Session;
  RefreshDocument;
end;

procedure TMVEditorCanvasView.RefreshDocument;
var NewLayout: TMVLayout;
begin
  NewLayout := TMVLayout.Create(FSession.Document);
  FLayout.Free;
  FLayout := NewLayout;
  FSelection.Attach(FSession, FLayout);
  Invalidate;
end;

procedure TMVEditorCanvasView.ViewTransform;
begin
  FView.Update(ClientWidth, ClientHeight, OutputWidth, OutputHeight);
end;

function TMVEditorCanvasView.GetSelected: Integer;
begin Result := FSelection.First; end;

function TMVEditorCanvasView.GetSelectionCount: Integer;
begin Result := FSelection.Count; end;

function TMVEditorCanvasView.SelectedIndices: TArray<Integer>;
begin Result := FSelection.Snapshot; end;

procedure TMVEditorCanvasView.SelectAnimationGroups;
begin
  CancelInteraction;
  FSelection.Restore(ExpandMVAnimationGroups(FSession.Document, SelectedIndices));
  FSelection.Attach(FSession, FLayout);
  NotifySelection;
  Invalidate;
end;

procedure TMVEditorCanvasView.NotifySelection;
begin
  if Assigned(FSelectionChanged) then FSelectionChanged(Self);
end;

procedure TMVEditorCanvasView.CommitDocument(const Candidate: TMVDocument);
var NewLayout: TMVLayout; Prepared: TMVDocument;
begin
  Prepared := CloneMVDocument(Candidate);
  NewLayout := TMVLayout.Create(Prepared);
  try
    FSession.BeginChange;
    FSession.Document := Prepared;
    FLayout.Free;
    FLayout := NewLayout;
    NewLayout := nil;
    FSelection.Attach(FSession, FLayout);
    Invalidate;
  finally NewLayout.Free; end;
end;

function TMVEditorCanvasView.GetStyleEditing: Boolean;
begin Result := (FStyleGesture <> nil) and FStyleGesture.Active; end;

function TMVEditorCanvasView.SelectedStyle: TMVStyle;
begin
  Result := FSession.Document.Style;
  if Selected >= 0 then Result := ResolveMVStyle(Result, FSession.Document.Units[Selected]);
end;

procedure TMVEditorCanvasView.BeginStyleEdit;
begin
  CancelInteraction;
  FStyleIndices := SelectedIndices;
  FStyleGesture.BeginEdit(FSession, FLayout);
end;

procedure TMVEditorCanvasView.PreviewStyle(const Style: TMVStyle; Fields: TMVStyleFields);
begin
  if not StyleEditing then Exit;
  FStyleGesture.Preview(MVDocumentWithStyle(FStyleGesture.Before, FStyleIndices, Style, Fields), FLayout);
  FSelection.Attach(FSession, FLayout);
  Invalidate;
end;

procedure TMVEditorCanvasView.FinishStyleEdit(Cancel: Boolean);
begin
  if not StyleEditing then Exit;
  FStyleGesture.Finish(Cancel, FLayout);
  FStyleIndices := nil;
  FSelection.Attach(FSession, FLayout);
  Invalidate;
  NotifySelection;
end;

function TMVEditorCanvasView.DocumentToScreen(const Point: TPointF): TPointF;
begin
  ViewTransform;
  Result := FView.ToScreen(Point, OutputWidth, OutputHeight);
end;

function TMVEditorCanvasView.SelectionHandles: TMVHandlePoints;
var H: TMVHandle; Item: TMVPlacement; Bounds: TRectF;
begin
  Result := Default(TMVHandlePoints);
  if Selected < 0 then Exit;
  ViewTransform;
  FSelection.Frame(Item, Bounds);
  Result := MVHandles(Item, Bounds, 28 * CurrentPPI / 96 / FView.Zoom);
  for H := mhNW to mhRotate do Result[H] := FView.ToScreen(Result[H], OutputWidth, OutputHeight);
end;

procedure TMVEditorCanvasView.ResetView(ActualSize: Boolean);
begin
  FView.Manual := False;
  ViewTransform;
  if ActualSize then FView.ZoomAt(PointF(ClientWidth / 2, ClientHeight / 2), 1 / FView.Zoom);
  Invalidate;
end;

end.
