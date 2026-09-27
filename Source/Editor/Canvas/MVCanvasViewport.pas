unit MVCanvasViewport;

// 編集画面だけのズームとパンを保持し、保存座標へ表示倍率を混ぜない。
interface

uses System.Types;

type
  TMVViewport = record
    Zoom: Single; // 現在の出力ピクセル対画面ピクセル倍率。
    Origin: TPointF; // 出力画像左上の画面座標。
    Manual: Boolean; // ホイールやパン後は自動フィットで上書きしない。
    // 初回・サイズ変更時のフィット。手動表示中は維持する。
    procedure Update(Width, Height: Integer; const VisibleBounds: TRectF);
    // 指定倍率でポインタ下の出力座標を固定してズームする。
    procedure ZoomAt(const Point: TPointF; Factor: Single);
    // 中央原点の保存座標と画面座標を相互変換する。
    function ToDocument(const Point: TPointF; Width, Height: Integer): TPointF;
    function ToScreen(const Point: TPointF; Width, Height: Integer): TPointF;
  end;

implementation

uses System.Math;

procedure TMVViewport.Update(Width, Height: Integer; const VisibleBounds: TRectF);
begin
  if Manual then Exit;
  Zoom := Max(0.001, Min((Width - 24) / Max(1, VisibleBounds.Width),
    (Height - 24) / Max(1, VisibleBounds.Height)));
  Origin := PointF((Width - (VisibleBounds.Left + VisibleBounds.Right) * Zoom) / 2,
    (Height - (VisibleBounds.Top + VisibleBounds.Bottom) * Zoom) / 2);
end;

procedure TMVViewport.ZoomAt(const Point: TPointF; Factor: Single);
var NewZoom: Single;
begin
  NewZoom := EnsureRange(Zoom * Factor, 0.001, 16.0);
  Origin := Point - (Point - Origin) * (NewZoom / Zoom);
  Zoom := NewZoom;
  Manual := True;
end;

function TMVViewport.ToDocument(const Point: TPointF; Width, Height: Integer): TPointF;
begin
  Result := (Point - Origin) * (1 / Zoom) - PointF(Width / 2, Height / 2);
end;

function TMVViewport.ToScreen(const Point: TPointF; Width, Height: Integer): TPointF;
begin
  Result := Origin + (Point + PointF(Width / 2, Height / 2)) * Zoom;
end;

end.
