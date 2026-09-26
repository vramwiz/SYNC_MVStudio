unit MVEditSession;

// 拡張画面だけの作業用文書とUndo履歴を所有する。ホストへの確定は担当しない。
interface

uses System.Generics.Collections, MVDocument;

type
  TMVEditSession = class
  private
    FUndo, FRedo: TList<TMVDocument>; // 各要素は独立した配置配列を所有する。
  public
    Document: TMVDocument; // 編集画面だけが変更する作業用文書。
    // 呼出元の文書から独立した編集セッションを作る。
    constructor Create(const Source: TMVDocument);
    // 履歴を含む編集データを解放する。
    destructor Destroy; override;
    // 1操作の開始時に呼ぶ。ドラッグの各移動では呼ばない。
    procedure BeginChange;
    // プレビュー済みの連続編集を、退避した開始文書から1回のUndoとして確定する。
    procedure RecordChange(const Before: TMVDocument);
    // 文書を1操作戻す。履歴がない場合は変更しない。
    procedure Undo;
    // 戻した文書を1操作進める。
    procedure Redo;
  end;

implementation

constructor TMVEditSession.Create(const Source: TMVDocument);
begin
  inherited Create;
  Document := CloneMVDocument(Source);
  FUndo := TList<TMVDocument>.Create;
  FRedo := TList<TMVDocument>.Create;
end;

destructor TMVEditSession.Destroy;
begin
  FRedo.Free;
  FUndo.Free;
  inherited;
end;

procedure TMVEditSession.BeginChange;
begin
  RecordChange(Document);
end;

procedure TMVEditSession.RecordChange(const Before: TMVDocument);
begin
  if FUndo.Count >= 50 then FUndo.Delete(0);
  FUndo.Add(CloneMVDocument(Before));
  FRedo.Clear;
end;

procedure TMVEditSession.Undo;
begin
  if FUndo.Count = 0 then Exit;
  FRedo.Add(CloneMVDocument(Document));
  Document := FUndo.Last;
  FUndo.Delete(FUndo.Count - 1);
end;

procedure TMVEditSession.Redo;
begin
  if FRedo.Count = 0 then Exit;
  FUndo.Add(CloneMVDocument(Document));
  Document := FRedo.Last;
  FRedo.Delete(FRedo.Count - 1);
end;

end.
