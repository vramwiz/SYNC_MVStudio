unit MVGlyphPatterns;

// 文字画像のブラインド・ブロック分割・横帯のずれを描く。時間評価と保存値は扱わない。
interface

uses System.Types, System.Skia, MVAnimationTypes;

const MV_GLITCH_BANDS = 8; // 文字と動作グループで共通の横帯数。

// 現在の模様から横帯のずれを返す。文字描画とグループ描画で同じ計算を共有する。
function MVGlitchBandOffset(Index: Integer; const Motion: TMVMotion): Single;
// ずれ幅を含む1本の帯のクリップ範囲を返す。
function MVGlitchBandBounds(const Bounds: TRectF; Index: Integer; Amount: Single): TRectF;

// 現在のCanvasへ部分表示のクリップを追加する。呼出し側でSave/Restoreする。
procedure ClipMVGlyphPattern(const Canvas: ISkCanvas; const Bounds: TRectF; const Motion: TMVMotion);
// 不透明度・ぼかし設定済みのPaintで文字を描く。帯のずれがなければ1回だけ描画する。
procedure DrawMVGlitchedGlyph(const Canvas: ISkCanvas; const Image: ISkImage; const Bounds: TRectF;
  const Motion: TMVMotion; const Paint: ISkPaint);

implementation

uses System.Math;

function MVGlitchBandOffset(Index: Integer; const Motion: TMVMotion): Single;
begin
  Result := Sin((Index + 1) * 12.9898 + Motion.GlitchStep * 7.233 + Motion.EffectSeed * 1.713);
  Result := Result * Motion.GlitchAmount;
end;

function MVGlitchBandBounds(const Bounds: TRectF; Index: Integer; Amount: Single): TRectF;
begin
  Result := RectF(Bounds.Left - Amount, Bounds.Top + Bounds.Height * Index / MV_GLITCH_BANDS,
    Bounds.Right + Amount, Bounds.Top + Bounds.Height * (Index + 1) / MV_GLITCH_BANDS);
end;

function BlockRank(Index, Seed: Integer): Integer;
var Value: Integer;
begin
  // 0..63の並べ替えなので、毎フレームの乱数生成も配列確保も必要ない。
  Value := (Index + (Seed and 63)) and 63;
  Value := Value xor (Value shr 3);
  Value := (Value * 37) and 63;
  Result := Value xor (Value shr 2);
end;

procedure ClipMVGlyphPattern(const Canvas: ISkCanvas; const Bounds: TRectF; const Motion: TMVMotion);
const Bands = 8; Columns = 8; Rows = 8;
var
  Path: ISkPathBuilder;
  Cell: TRectF;
  I, Row, Column: Integer;
  Visible: Single;
begin
  if (Motion.Mask = mamNone) or (Motion.MaskVisibility >= 1) then Exit;
  Visible := EnsureRange(Motion.MaskVisibility, Single(0), Single(1));
  Path := TSkPathBuilder.Create;
  if Visible > 0 then
    case Motion.Mask of
      mamBlinds:
        for I := 0 to Bands - 1 do
        begin
          Cell := Bounds;
          if Motion.MaskDirection in [madUp, madDown] then
          begin
            Cell.Top := Bounds.Top + Bounds.Height * I / Bands;
            Cell.Bottom := Bounds.Top + Bounds.Height * (I + 1) / Bands;
            if Motion.MaskDirection = madUp then Cell.Bottom := Cell.Top + Cell.Height * Visible
            else Cell.Top := Cell.Bottom - Cell.Height * Visible;
          end
          else
          begin
            Cell.Left := Bounds.Left + Bounds.Width * I / Bands;
            Cell.Right := Bounds.Left + Bounds.Width * (I + 1) / Bands;
            if Motion.MaskDirection = madLeft then Cell.Right := Cell.Left + Cell.Width * Visible
            else Cell.Left := Cell.Right - Cell.Width * Visible;
          end;
          Path.AddRect(Cell);
        end;
      mamDissolve:
        for Row := 0 to Rows - 1 do
          for Column := 0 to Columns - 1 do
            if BlockRank(Row * Columns + Column, Motion.EffectSeed) + 0.5 < Visible * Rows * Columns then
            begin
              Cell := RectF(Bounds.Left + Bounds.Width * Column / Columns,
                Bounds.Top + Bounds.Height * Row / Rows,
                Bounds.Left + Bounds.Width * (Column + 1) / Columns,
                Bounds.Top + Bounds.Height * (Row + 1) / Rows);
              Path.AddRect(Cell);
            end;
    end;
  // 1つのクリップとして描き、隣接する帯・ブロックの重ね描きによる濃淡差を避ける。
  Canvas.ClipPath(Path.Detach, TSkClipOp.Intersect, False);
end;

procedure DrawMVGlitchedGlyph(const Canvas: ISkCanvas; const Image: ISkImage; const Bounds: TRectF;
  const Motion: TMVMotion; const Paint: ISkPaint);
var I: Integer; Band, Dest: TRectF; Offset: Single;
begin
  if Motion.GlitchAmount <= 0.01 then
  begin
    Canvas.DrawImageRect(Image, Bounds, TSkSamplingOptions.High, Paint);
    Exit;
  end;
  for I := 0 to MV_GLITCH_BANDS - 1 do
  begin
    Offset := MVGlitchBandOffset(I, Motion);
    Band := MVGlitchBandBounds(Bounds, I, Motion.GlitchAmount);
    Dest := Bounds;
    Dest.Offset(Offset, 0);
    Canvas.Save;
    try
      Canvas.ClipRect(Band, TSkClipOp.Intersect, False);
      Canvas.DrawImageRect(Image, Dest, TSkSamplingOptions.High, Paint);
    finally
      Canvas.Restore;
    end;
  end;
end;

end.
