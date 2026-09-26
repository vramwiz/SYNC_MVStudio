unit MVColorTargets;

// 右側ピッカーの適用色を固定アイコンで選ぶ。保存の色項目との対応を一元化する。
interface

uses Vcl.Buttons, MVStyleTypes, System.UITypes;

type
  TMVColorTarget = (mctText, mctOutline, mctShadow, mctGlow, mctChromatic1, mctChromatic2, mctFrame);
  TMVColorTargetButton = class(TSpeedButton)
  public
    Swatch: TAlphaColor; // 現在の対象色。
  protected
    // 選択色と対象名を同じボタンへ描き、別の色選択画面は開かない。
    procedure Paint; override;
  end;

// 対象の名称、保存フィールド、現在のARGB色を返す。
function MVColorTargetName(Target: TMVColorTarget): string;
function MVColorTargetField(Target: TMVColorTarget): TMVStyleField;
function MVTargetColor(const Style: TMVStyle; Target: TMVColorTarget): TAlphaColor;
// 指定された1色だけを変更する。効果の有効・無効には触れない。
procedure SetMVTargetColor(var Style: TMVStyle; Target: TMVColorTarget; Color: TAlphaColor);

implementation

uses Winapi.Windows, Vcl.Graphics, System.Types;

function MVColorTargetName(Target: TMVColorTarget): string;
const Names: array[TMVColorTarget] of string = ('文字', '縁', '影', '発光', '色ずれ1', '色ずれ2', '囲み枠');
begin Result := Names[Target]; end;

function MVColorTargetField(Target: TMVColorTarget): TMVStyleField;
const Fields: array[TMVColorTarget] of TMVStyleField = (msfColor, msfOutlineColor, msfShadowColor,
  msfGlowColor, msfChromaticColor1, msfChromaticColor2, msfFrameColor);
begin Result := Fields[Target]; end;

function MVTargetColor(const Style: TMVStyle; Target: TMVColorTarget): TAlphaColor;
begin
  case Target of
    mctText: Result := Style.Color;
    mctOutline: Result := Style.OutlineColor;
    mctShadow: Result := Style.ShadowColor;
    mctGlow: Result := Style.GlowColor;
    mctChromatic1: Result := Style.ChromaticColor1;
    mctChromatic2: Result := Style.ChromaticColor2;
  else Result := Style.FrameColor;
  end;
end;

procedure SetMVTargetColor(var Style: TMVStyle; Target: TMVColorTarget; Color: TAlphaColor);
begin
  case Target of
    mctText: Style.Color := Color;
    mctOutline: Style.OutlineColor := Color;
    mctShadow: Style.ShadowColor := Color;
    mctGlow: Style.GlowColor := Color;
    mctChromatic1: Style.ChromaticColor1 := Color;
    mctChromatic2: Style.ChromaticColor2 := Color;
    mctFrame: Style.FrameColor := Color;
  end;
end;

procedure TMVColorTargetButton.Paint;
var B: TBitmap; R: TRect; D: Integer;
begin
  B := TBitmap.Create;
  try
    B.SetSize(Width, Height);
    B.Canvas.Brush.Color := $00343434;
    if Down then B.Canvas.Brush.Color := $00744A28;
    B.Canvas.FillRect(ClientRect);
    D := Height div 5;
    B.Canvas.Brush.Color := RGB((Swatch shr 16) and $FF, (Swatch shr 8) and $FF, Swatch and $FF);
    B.Canvas.Pen.Color := clSilver;
    B.Canvas.Rectangle(D, D, Height - D, Height - D);
    B.Canvas.Font.Assign(Font);
    B.Canvas.Font.Color := $00EEEEEE;
    B.Canvas.Brush.Style := bsClear;
    R := Rect(Height, 0, Width, Height);
    DrawText(B.Canvas.Handle, PChar(Caption), Length(Caption), R, DT_SINGLELINE or DT_VCENTER or DT_LEFT);
    Canvas.Draw(0, 0, B);
  finally B.Free; end;
end;

end.
