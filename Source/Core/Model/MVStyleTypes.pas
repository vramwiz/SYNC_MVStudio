unit MVStyleTypes;

// 共通書式と文字単位の上書き項目を定義する。描画資源は保持しない。
interface

uses System.UITypes;

type
  TMVStyleField = (msfFontName, msfColor, msfOutlineColor, msfOutlineWidth, msfShadow, msfBold, msfItalic, msfFillMode, msfOpacity, msfGlowColor, msfGlowRadius, msfGlowStrength, msfChromaticOffset, msfChromaticAngle, msfChromaticColor1, msfChromaticColor2, msfFrameColor, msfFrameWidth, msfFramePadding, msfOutlineBlur, msfShadowColor, msfShadowX, msfShadowY, msfShadowSpread, msfShadowBlur);
  TMVStyleFields = set of TMVStyleField;
  TMVStyle = record
    FontName: string; // 書体名。
    Color: TAlphaColor; // 塗りのARGB色。
    OutlineColor: TAlphaColor; // 縁のARGB色。
    OutlineWidth: Single; // 縁のピクセル幅。
    Shadow: Boolean; // 影を有効にする。
    OutlineBlur: Single; // 縁のぼかし半径。0なら従来の硬い縁。
    ShadowColor: TAlphaColor; // 影のARGB色。アルファは影だけの不透明度。
    ShadowX, ShadowY: Single; // 字形ローカル座標での影の位置。
    ShadowSpread: Single; // 影を外側へ太らせる半径。
    ShadowBlur: Single; // 影のぼかし半径。
    Bold: Boolean; // 太字。
    Italic: Boolean; // 斜体。
    FillMode: Integer; // 0=塗りと縁、1=塗りのみ、2=縁のみ。
    Opacity: Single; // 文字全体の不透明度。0..1。
    GlowColor: TAlphaColor; // 発光のARGB色。
    GlowRadius: Single; // 発光のぼかし半径。
    GlowStrength: Single; // 発光の強さ。0..1。
    ChromaticOffset: Single; // 2色を逆方向へずらす距離。
    ChromaticAngle: Single; // 色ずれの方向。度単位。
    ChromaticColor1: TAlphaColor; // 色ずれの正方向の色。
    ChromaticColor2: TAlphaColor; // 色ずれの逆方向の色。
    FrameColor: TAlphaColor; // 囲み枠のARGB色。
    FrameWidth: Single; // 囲み枠の幅。0なら無効。
    FramePadding: Single; // 囲み枠の余白。
    FontSize: Single; // 共通の基準サイズ。個別の大小は配置倍率で設定する。
    Spacing: Single; // 共通の字間。
    LineSpacing: Single; // 共通の行間。
  end;

// 旧版と同じ白文字・黒縁を基本とし、新しい装飾は無効にする。
function DefaultMVStyle: TMVStyle;
// 指定項目だけをコピーする。他の項目や基準サイズ・字間は保持する。
procedure ApplyMVStyleFields(var Target: TMVStyle; const Source: TMVStyle; Fields: TMVStyleFields);
// UIで変更された項目を返す。複数文字で未編集の混在項目を上書きしない。
function MVStyleDifferences(const A, B: TMVStyle): TMVStyleFields;
// 保存・画像生成へ渡せる書式かを検証し、不正なら例外にする。
procedure ValidateMVStyle(const Style: TMVStyle);

implementation

uses System.SysUtils, System.Math;

function DefaultMVStyle: TMVStyle;
begin
  Result := Default(TMVStyle);
  Result.FontName := 'Yu Gothic UI';
  Result.Color := $FFFFFFFF;
  Result.OutlineColor := $FF000000;
  Result.OutlineWidth := 2;
  Result.Shadow := False;
  Result.OutlineBlur := 0;
  Result.ShadowColor := $A0000000;
  Result.ShadowX := 3;
  Result.ShadowY := 3;
  Result.ShadowSpread := 0;
  Result.ShadowBlur := 4;
  Result.Bold := False;
  Result.Italic := False;
  Result.FillMode := 0;
  Result.Opacity := 1;
  Result.GlowColor := $FF88CCFF;
  Result.GlowRadius := 8;
  Result.GlowStrength := 0;
  Result.ChromaticOffset := 0;
  Result.ChromaticAngle := 0;
  Result.ChromaticColor1 := $FFFF5050;
  Result.ChromaticColor2 := $FF50BFFF;
  Result.FrameColor := $FFFFFFFF;
  Result.FrameWidth := 0;
  Result.FramePadding := 8;
  Result.FontSize := 100;
end;

procedure ApplyMVStyleFields(var Target: TMVStyle; const Source: TMVStyle; Fields: TMVStyleFields);
begin
  if msfFontName in Fields then Target.FontName := Source.FontName;
  if msfColor in Fields then Target.Color := Source.Color;
  if msfOutlineColor in Fields then Target.OutlineColor := Source.OutlineColor;
  if msfOutlineWidth in Fields then Target.OutlineWidth := Source.OutlineWidth;
  if msfShadow in Fields then Target.Shadow := Source.Shadow;
  if msfOutlineBlur in Fields then Target.OutlineBlur := Source.OutlineBlur;
  if msfShadowColor in Fields then Target.ShadowColor := Source.ShadowColor;
  if msfShadowX in Fields then Target.ShadowX := Source.ShadowX;
  if msfShadowY in Fields then Target.ShadowY := Source.ShadowY;
  if msfShadowSpread in Fields then Target.ShadowSpread := Source.ShadowSpread;
  if msfShadowBlur in Fields then Target.ShadowBlur := Source.ShadowBlur;
  if msfBold in Fields then Target.Bold := Source.Bold;
  if msfItalic in Fields then Target.Italic := Source.Italic;
  if msfFillMode in Fields then Target.FillMode := Source.FillMode;
  if msfOpacity in Fields then Target.Opacity := Source.Opacity;
  if msfGlowColor in Fields then Target.GlowColor := Source.GlowColor;
  if msfGlowRadius in Fields then Target.GlowRadius := Source.GlowRadius;
  if msfGlowStrength in Fields then Target.GlowStrength := Source.GlowStrength;
  if msfChromaticOffset in Fields then Target.ChromaticOffset := Source.ChromaticOffset;
  if msfChromaticAngle in Fields then Target.ChromaticAngle := Source.ChromaticAngle;
  if msfChromaticColor1 in Fields then Target.ChromaticColor1 := Source.ChromaticColor1;
  if msfChromaticColor2 in Fields then Target.ChromaticColor2 := Source.ChromaticColor2;
  if msfFrameColor in Fields then Target.FrameColor := Source.FrameColor;
  if msfFrameWidth in Fields then Target.FrameWidth := Source.FrameWidth;
  if msfFramePadding in Fields then Target.FramePadding := Source.FramePadding;
end;

function MVStyleDifferences(const A, B: TMVStyle): TMVStyleFields;
begin
  Result := [];
  if A.FontName <> B.FontName then Include(Result, msfFontName);
  if A.Color <> B.Color then Include(Result, msfColor);
  if A.OutlineColor <> B.OutlineColor then Include(Result, msfOutlineColor);
  if A.OutlineWidth <> B.OutlineWidth then Include(Result, msfOutlineWidth);
  if A.Shadow <> B.Shadow then Include(Result, msfShadow);
  if A.OutlineBlur <> B.OutlineBlur then Include(Result, msfOutlineBlur);
  if A.ShadowColor <> B.ShadowColor then Include(Result, msfShadowColor);
  if A.ShadowX <> B.ShadowX then Include(Result, msfShadowX);
  if A.ShadowY <> B.ShadowY then Include(Result, msfShadowY);
  if A.ShadowSpread <> B.ShadowSpread then Include(Result, msfShadowSpread);
  if A.ShadowBlur <> B.ShadowBlur then Include(Result, msfShadowBlur);
  if A.Bold <> B.Bold then Include(Result, msfBold);
  if A.Italic <> B.Italic then Include(Result, msfItalic);
  if A.FillMode <> B.FillMode then Include(Result, msfFillMode);
  if A.Opacity <> B.Opacity then Include(Result, msfOpacity);
  if A.GlowColor <> B.GlowColor then Include(Result, msfGlowColor);
  if A.GlowRadius <> B.GlowRadius then Include(Result, msfGlowRadius);
  if A.GlowStrength <> B.GlowStrength then Include(Result, msfGlowStrength);
  if A.ChromaticOffset <> B.ChromaticOffset then Include(Result, msfChromaticOffset);
  if A.ChromaticAngle <> B.ChromaticAngle then Include(Result, msfChromaticAngle);
  if A.ChromaticColor1 <> B.ChromaticColor1 then Include(Result, msfChromaticColor1);
  if A.ChromaticColor2 <> B.ChromaticColor2 then Include(Result, msfChromaticColor2);
  if A.FrameColor <> B.FrameColor then Include(Result, msfFrameColor);
  if A.FrameWidth <> B.FrameWidth then Include(Result, msfFrameWidth);
  if A.FramePadding <> B.FramePadding then Include(Result, msfFramePadding);
end;

procedure Check(Value, Minimum, Maximum: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Value < Minimum) or (Value > Maximum) then
    raise EArgumentException.Create('文字装飾の設定値が有効な範囲外です。');
end;

procedure ValidateMVStyle(const Style: TMVStyle);
begin
  if (Style.FontName = '') or (Length(Style.FontName) > 200) then
    raise EArgumentException.Create('フォント名が不正です。');
  Check(Style.FontSize, 4, 512);
  Check(Style.OutlineWidth, 0, 32);
  Check(Style.OutlineBlur, 0, 64);
  Check(Style.ShadowX, -512, 512);
  Check(Style.ShadowY, -512, 512);
  Check(Style.ShadowSpread, 0, 64);
  Check(Style.ShadowBlur, 0, 64);
  Check(Style.Spacing, -256, 512);
  Check(Style.LineSpacing, -256, 512);
  Check(Style.FillMode, 0, 2);
  Check(Style.Opacity, 0, 1);
  Check(Style.GlowRadius, 0, 64);
  Check(Style.GlowStrength, 0, 1);
  Check(Style.ChromaticOffset, 0, 64);
  Check(Style.ChromaticAngle, -180, 180);
  Check(Style.FrameWidth, 0, 16);
  Check(Style.FramePadding, 0, 128);
end;

end.
