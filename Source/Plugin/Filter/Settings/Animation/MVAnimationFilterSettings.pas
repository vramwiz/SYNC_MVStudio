unit MVAnimationFilterSettings;

// 登場・表示中・退場のホスト項目と選択肢の寿命を管理し、文書へ今回の値だけを複写する。
interface

uses MVDocument;

// フィルター登録中に1回呼ぶ。各状態へ動き・見え方と共通の時間・方向・曲線を配置する。
procedure RegisterMVAnimationSettings;
// 保存データの閉じたグループ内で1回呼ぶ。旧選択肢名を残し、対応本体では常時非表示にする。
procedure RegisterMVLegacyTransitionSettings;
// 初期化済み文書の文字演出だけを更新し、ホスト管理の登場・退場所要秒数を返す。
procedure ReadMVAnimationSettings(var Document: TMVDocument; out EntranceTime, ExitTime: Double);

implementation

uses AviUtl2FilterTypes, PluginFilterTable, MVAnimationTypes, MVAnimationCatalog,
  MVTransitionTiming, MVAnimationSequence, MVTransitionParts;

var
  InItem, OutItem: TFILTER_ITEM_SELECT; // 旧複合演出の復元専用。値を描画コールバックから書き戻さない。
  HoldItem: TFILTER_ITEM_SELECT; // 表示中の固定IDは従来どおり保持する。
  InMotionItem, OutMotionItem: TFILTER_ITEM_SELECT; // 登場・退場の位置・回転・拡縮・字間。
  InVisibilityItem, OutVisibilityItem: TFILTER_ITEM_SELECT; // 登場・退場の不透明度・ぼかし・部分表示。
  LegacyHide: array[0..1] of TFILTER_ITEM_HIDE_RULE; // 旧2項目は名前による保存復元のためだけに登録する。
  InDirectionItem, OutDirectionItem: TFILTER_ITEM_SELECT; // 各演出の登場元・退場先または変形軸。
  InTimingItem, OutTimingItem: TFILTER_ITEM_SELECT; // 短い文章で選ぶ登場・退場の進み方。
  InOrderItem, OutOrderItem, UnitItem: TFILTER_ITEM_SELECT; // 開始順と動かすまとまり。
  InTimeItem, OutTimeItem, AmountItem, PeriodItem: TFILTER_ITEM_TRACK; // 秒数・共通振幅・表示中の周期。
  InStrengthItem, HoldStrengthItem, OutStrengthItem: TFILTER_ITEM_TRACK; // 各状態の強さ倍率。100%が従来値。
  CurveAmountItem: TFILTER_ITEM_TRACK; // 波・S字・ジグザグ軌道の膨らみ。
  InDelayItem, OutDelayItem: TFILTER_ITEM_TRACK; // 動作単位の開始間隔。0なら同時に動く。
  MotionGroup, InGroup, HoldGroup, OutGroup: TFILTER_ITEM_GROUP; // 次のgroupまでの項目を折りたたむ見出し。
  TransitionOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // 旧項目の保存名を復元するnil終端一覧。
  MotionOptions, VisibilityOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // 2要素を分けた公開用一覧。
  MotionNames, VisibilityNames: TArray<string>; // 引継ぎと各要素の名前をDLL寿命中保持する。
  HoldOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // カタログから生成するnil終端の表示中一覧。
  TransitionNames: TArray<string>; // ホストが参照する名前をDLL寿命中保持する。
  HoldNames: TArray<string>; // 表示中の名前もホストへ渡した後は変更しない。
  TimingOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // 登場と退場が共有するnil終端の曲線一覧。
  TimingNames: TArray<string>; // ホストへ渡した文章をDLL寿命中保持する。
  DirectionOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM; // 上下左右とnil終端。
  DirectionNames: array[TMVAnimationDirection] of string; // ホストへ渡す名前の寿命を保持する。
  OrderOptions: array[0..5] of TFILTER_ITEM_SELECT_ITEM; // 5種類の開始順とnil終端。
  OrderNames: array[TMVAnimationOrder] of string; // 選択肢の名前をDLL寿命中保持する。
  UnitOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM; // 4種類の動作単位とnil終端。
  UnitNames: array[TMVAnimationUnit] of string; // 選択肢の名前をDLL寿命中保持する。

// カタログの文字列を複写する。項目のPCharが参照する配列は登録後に再確保しない。
procedure BuildAnimationChoices(Kind: TMVAnimationKind; out Items: TArray<TFILTER_ITEM_SELECT_ITEM>;
  out Names: TArray<string>);
var I, Count: Integer; Item: TMVAnimationDescriptor;
begin
  Count := MVAnimationCount(Kind);
  SetLength(Names, Count);
  SetLength(Items, Count + 1);
  for I := 0 to Count - 1 do
  begin
    Item := MVAnimationAt(Kind, I);
    Names[I] := Item.Name;
    Items[I].Name := PChar(Names[I]);
    Items[I].Value := Item.ID;
  end;
  // SDKが末尾を読み越さないよう、未使用の最終項目を明示的に終端とする。
  Items[Count] := Default(TFILTER_ITEM_SELECT_ITEM);
end;

// 引継ぎを明示したうえで分類内の選択肢だけを公開する。0の「なし」は旧設定も無効化する。
procedure BuildPartChoices(Kind: TMVTransitionPartKind; out Items: TArray<TFILTER_ITEM_SELECT_ITEM>;
  out Names: TArray<string>);
var I, Count: Integer; Item: TMVAnimationDescriptor;
begin
  Count := MVTransitionPartCount(Kind);
  SetLength(Names, Count + 1);
  SetLength(Items, Count + 2);
  Names[0] := '引き継ぐ';
  Items[0].Name := PChar(Names[0]);
  Items[0].Value := MV_TRANSITION_INHERIT;
  for I := 0 to Count - 1 do
  begin
    Item := MVTransitionPartAt(Kind, I);
    Names[I + 1] := Item.Name;
    Items[I + 1].Name := PChar(Names[I + 1]);
    Items[I + 1].Value := Item.ID;
  end;
  Items[Count + 1] := Default(TFILTER_ITEM_SELECT_ITEM);
end;

// 文章表現の曲線名をDLL寿命中保持し、登場・退場で同じ固定番号を共有する。
procedure BuildTimingChoices;
var I: Integer;
begin
  SetLength(TimingNames, MVTimingCount);
  SetLength(TimingOptions, MVTimingCount + 1);
  for I := 0 to MVTimingCount - 1 do
  begin
    TimingNames[I] := MVTimingName(I);
    TimingOptions[I].Name := PChar(TimingNames[I]);
    TimingOptions[I].Value := I;
  end;
  TimingOptions[MVTimingCount] := Default(TFILTER_ITEM_SELECT_ITEM);
end;

procedure RegisterMVAnimationSettings;
var Direction: TMVAnimationDirection; Order: TMVAnimationOrder; MotionUnit: TMVAnimationUnit;
begin
  BuildAnimationChoices(makTransition, TransitionOptions, TransitionNames);
  BuildAnimationChoices(makHold, HoldOptions, HoldNames);
  BuildPartChoices(mtpMotion, MotionOptions, MotionNames);
  BuildPartChoices(mtpVisibility, VisibilityOptions, VisibilityNames);
  BuildTimingChoices;
  for Order := Low(TMVAnimationOrder) to High(TMVAnimationOrder) do
  begin
    OrderNames[Order] := MVAnimationOrderName(Order);
    OrderOptions[Ord(Order)].Name := PChar(OrderNames[Order]);
    OrderOptions[Ord(Order)].Value := Ord(Order);
  end;
  for MotionUnit := Low(TMVAnimationUnit) to High(TMVAnimationUnit) do
  begin
    UnitNames[MotionUnit] := MVAnimationUnitName(MotionUnit);
    UnitOptions[Ord(MotionUnit)].Name := PChar(UnitNames[MotionUnit]);
    UnitOptions[Ord(MotionUnit)].Value := Ord(MotionUnit);
  end;
  for Direction := Low(TMVAnimationDirection) to High(TMVAnimationDirection) do
  begin
    DirectionNames[Direction] := MVAnimationDirectionName(Direction);
    DirectionOptions[Ord(Direction)].Name := PChar(DirectionNames[Direction]);
    DirectionOptions[Ord(Direction)].Value := Ord(Direction);
  end;
  // SDKのgroupは入れ子ではなく、次の見出しまでをまとめる。共通値を各状態へ重複登録しない。
  AddGroup(MotionGroup, '共通のアニメーション', 1);
  AddSelect(UnitItem, '動かす単位', Ord(mauCharacter), @UnitOptions[0]);
  AddTrack(AmountItem, '強さ', 60, 0, 2000, 1);
  AddTrack(CurveAmountItem, '曲がりの強さ', MV_DEFAULT_CURVE_AMOUNT, 0, 2000, 1);
  // 新項目の未保存状態を引継ぎ値で区別する。両要素は同じ時間・方向・曲線・遅延を使う。
  AddGroup(InGroup, '登場', 1);
  AddTrack(InTimeItem, '登場時間', 0.3, 0, 10, 0.01);
  AddSelect(InMotionItem, '登場の動き', MV_TRANSITION_INHERIT, @MotionOptions[0]);
  AddSelect(InVisibilityItem, '登場の見え方', MV_TRANSITION_INHERIT, @VisibilityOptions[0]);
  AddSelect(InDirectionItem, '登場方向', Ord(madDown), @DirectionOptions[0]);
  AddSelect(InTimingItem, '登場の動き方', MV_TIMING_DEFAULT, @TimingOptions[0]);
  AddTrack(InDelayItem, '登場の文字遅延', 0, 0, 1, 0.01);
  AddSelect(InOrderItem, '登場順', Ord(maoForward), @OrderOptions[0]);
  AddTrack(InStrengthItem, '登場の強さ(%)', 100, 0, 1000, 1);
  AddGroup(HoldGroup, '表示中', 1);
  AddSelect(HoldItem, '標準の表示中', 0, @HoldOptions[0]);
  AddTrack(HoldStrengthItem, '表示中の強さ(%)', 100, 0, 1000, 1);
  AddTrack(PeriodItem, '周期', 2, 0.05, 60, 0.01);
  AddGroup(OutGroup, '退場', 1);
  AddTrack(OutTimeItem, '退場時間', 0.3, 0, 10, 0.01);
  AddSelect(OutMotionItem, '退場の動き', MV_TRANSITION_INHERIT, @MotionOptions[0]);
  AddSelect(OutVisibilityItem, '退場の見え方', MV_TRANSITION_INHERIT, @VisibilityOptions[0]);
  AddSelect(OutDirectionItem, '退場方向', Ord(madUp), @DirectionOptions[0]);
  AddSelect(OutTimingItem, '退場の動き方', MV_TIMING_DEFAULT, @TimingOptions[0]);
  AddTrack(OutDelayItem, '退場の文字遅延', 0, 0, 1, 0.01);
  AddSelect(OutOrderItem, '退場順', Ord(maoForward), @OrderOptions[0]);
  AddTrack(OutStrengthItem, '退場の強さ(%)', 100, 0, 1000, 1);
end;

procedure RegisterMVLegacyTransitionSettings;
begin
  // 旧プロジェクトは選択肢名で復元するため、複合名も含めた一覧を保持する。
  // hiderule未対応の本体では呼出し側の閉じた保存データグループ内に残る。
  AddSelect(InItem, '標準の登場', 0, @TransitionOptions[0]);
  AddSelect(OutItem, '標準の退場', 0, @TransitionOptions[0]);
  AddHideRule(LegacyHide[0], '標準の登場', nil, 0);
  AddHideRule(LegacyHide[1], '標準の退場', nil, 0);
end;

procedure ReadMVAnimationSettings(var Document: TMVDocument; out EntranceTime, ExitTime: Double);
begin
  Document.Entrance := InItem.Value;
  Document.ExitEffect := OutItem.Value;
  Document.EntranceMotion := InMotionItem.Value;
  Document.ExitMotion := OutMotionItem.Value;
  Document.EntranceVisibility := InVisibilityItem.Value;
  Document.ExitVisibility := OutVisibilityItem.Value;
  Document.EntranceDirection := InDirectionItem.Value;
  Document.ExitDirection := OutDirectionItem.Value;
  Document.EntranceTiming := InTimingItem.Value;
  Document.ExitTiming := OutTimingItem.Value;
  NormalizeMVDirection(Document.Entrance, Document.EntranceDirection, False);
  NormalizeMVDirection(Document.ExitEffect, Document.ExitDirection, True);
  Document.Hold := HoldItem.Value;
  Document.EntranceDelay := InDelayItem.Value;
  Document.ExitDelay := OutDelayItem.Value;
  Document.EntranceOrder := InOrderItem.Value;
  Document.ExitOrder := OutOrderItem.Value;
  Document.AnimationUnit := UnitItem.Value;
  Document.EntranceStrength := InStrengthItem.Value / 100;
  Document.HoldStrength := HoldStrengthItem.Value / 100;
  Document.ExitStrength := OutStrengthItem.Value / 100;
  Document.Amount := AmountItem.Value;
  Document.CurveAmount := CurveAmountItem.Value;
  Document.Period := PeriodItem.Value;
  EntranceTime := InTimeItem.Value;
  ExitTime := OutTimeItem.Value;
end;

end.
