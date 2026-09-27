unit MVTransitionMovement;

// 文字順を使う交互移動演出。登場・退場は同じ基準位置へ接続する。
interface

uses MVAnimationTypes;

// 指定側と反対側を文字順で交互に切り替えて、集合／分離する。
procedure MVAlternatingSlide(var Motion: TMVMotion; const Input: TMVAnimationInput);

implementation

uses MVTransitionBasic;

procedure MVAlternatingSlide(var Motion: TMVMotion; const Input: TMVAnimationInput);
var DirectedInput: TMVAnimationInput;
begin
  DirectedInput := Input;
  if Odd(Input.UnitIndex) then DirectedInput.Direction := OppositeMVDirection(Input.Direction);
  MVSlide(Motion, DirectedInput);
end;

end.
