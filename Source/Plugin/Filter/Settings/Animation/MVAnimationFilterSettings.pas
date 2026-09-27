unit MVAnimationFilterSettings;

// 登場・表示中・退場のホスト項目と選択肢の寿命を管理し、文書へ今回の値だけを複写する。
interface

uses MVDocument;

// 共通・前・同期の項目を順に登録する。
procedure RegisterMVAnimationSettings;
// 非同期の後に、後の項目を登録する。
procedure RegisterMVExitAnimationSettings;
// 初期化済み文書の文字演出だけを更新し、ホスト管理の登場・退場所要秒数を返す。
procedure ReadMVAnimationSettings(var Document: TMVDocument; out EntranceTime, ExitTime: Double);

implementation

uses AviUtl2FilterTypes, PluginFilterTable, MVAnimationTypes, MVAnimationCatalog,
  MVTransitionTiming, MVAnimationSequence, MVTransitionParts;

var
  HoldItem: TFILTER_ITEM_SELECT; // 表示中の固定IDは従来どおり保持する。
  InMotionItem, OutMotionItem: TFILTER_ITEM_SELECT; // 登場・退場の位置・回転・拡縮・字間。
  InVisibilityItem, OutVisibilityItem: TFILTER_ITEM_SELECT; // 登場・退場の不透明度・ぼかし・部分表示。
  InDirectionItem, OutDirectionItem: TFILTER_ITEM_SELECT; // 各演出の登場元・退場先または変形軸。
  InTimingItem, OutTimingItem: TFILTER_ITEM_SELECT; // 短い文章で選ぶ登場・退場の進み方。
  InOrderItem, OutOrderItem: TFILTER_ITEM_SELECT; // 開始順。
  InUnitItem, HoldUnitItem, OutUnitItem: TFILTER_ITEM_SELECT; // 状態ごとの動作単位。
  InTimeItem, OutTimeItem, AmountItem, TempoItem: TFILTER_ITEM_TRACK; // 秒数・共通振幅・全演出のBPM。
  InStrengthItem, HoldStrengthItem, OutStrengthItem: TFILTER_ITEM_TRACK; // 各状態の強さ倍率。100%が従来値。
  CurveAmountItem: TFILTER_ITEM_TRACK; // 波・S字・ジグザグ軌道の膨らみ。
  InDelayItem, OutDelayItem: TFILTER_ITEM_TRACK; // 動作単位の開始間隔。0なら同時に動く。
  MotionGroup, InGroup, HoldGroup, OutGroup: TFILTER_ITEM_GROUP; // 次のgroupまでの項目を折りたたむ見出し。
  MotionOptions, VisibilityOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // 2要素を分けた公開用一覧。
  MotionNames, VisibilityNames: TArray<string>; // 各要素の名前をDLL寿命中保持する。
  HoldOptions: TArray<TFILTER_ITEM_SELECT_ITEM>; // カタログから生成するnil終端の表示中一覧。
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

// 分類内の選択肢だけを公開する。0は「なし」。
procedure BuildPartChoices(Kind: TMVTransitionPartKind; out Items: TArray<TFILTER_ITEM_SELECT_ITEM>;
  out Names: TArray<string>);
var I, Count: Integer; Item: TMVAnimationDescriptor;
begin
  Count := MVTransitionPartCount(Kind);
  SetLength(Names, Count);
  SetLength(Items, Count + 1);
  for I := 0 to Count - 1 do
  begin
    Item := MVTransitionPartAt(Kind, I);
    Names[I] := Item.Name;
    Items[I].Name := PChar(Names[I]);
    Items[I].Value := Item.ID;
  end;
  Items[Count] := Default(TFILTER_ITEM_SELECT_ITEM);
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
  AddTrack(TempoItem, 'テンポ(BPM)', 120.00, 1, 1200, 0.01);
  AddTrack(AmountItem, '強さ', 60, 0, 2000, 1);
  AddTrack(CurveAmountItem, '曲がりの強さ', MV_DEFAULT_CURVE_AMOUNT, 0, 2000, 1);
  // 動きと見え方は同じ時間・方向・曲線・遅延を使う。
  AddGroup(InGroup, '前', 1);
  AddTrack(InTimeItem, '前 時間', 0.3, 0, 10, 0.01);
  AddSelect(InMotionItem, '前 動き', 0, @MotionOptions[0]);
  AddSelect(InVisibilityItem, '前 見え方', 0, @VisibilityOptions[0]);
  AddSelect(InUnitItem, '前 単位', Ord(mauCharacter), @UnitOptions[0]);
  AddSelect(InDirectionItem, '前 方向', Ord(madDown), @DirectionOptions[0]);
  AddSelect(InTimingItem, '前 動き方', MV_TIMING_DEFAULT, @TimingOptions[0]);
  AddTrack(InDelayItem, '前 文字遅延', 0, 0, 1, 0.01);
  AddSelect(InOrderItem, '前 順', Ord(maoForward), @OrderOptions[0]);
  AddTrack(InStrengthItem, '前 強さ(%)', 100, 0, 1000, 1);
  AddGroup(HoldGroup, '同期', 1);
  AddSelect(HoldItem, '同期 動き', 0, @HoldOptions[0]);
  AddSelect(HoldUnitItem, '同期 単位', Ord(mauCharacter), @UnitOptions[0]);
  AddTrack(HoldStrengthItem, '同期 強さ(%)', 100, 0, 1000, 1);
end;

procedure RegisterMVExitAnimationSettings;
begin
  AddGroup(OutGroup, '後', 1);
  AddTrack(OutTimeItem, '後 時間', 0.3, 0, 10, 0.01);
  AddSelect(OutMotionItem, '後 動き', 0, @MotionOptions[0]);
  AddSelect(OutVisibilityItem, '後 見え方', 0, @VisibilityOptions[0]);
  AddSelect(OutUnitItem, '後 単位', Ord(mauCharacter), @UnitOptions[0]);
  AddSelect(OutDirectionItem, '後 方向', Ord(madUp), @DirectionOptions[0]);
  AddSelect(OutTimingItem, '後 動き方', MV_TIMING_DEFAULT, @TimingOptions[0]);
  AddTrack(OutDelayItem, '後 文字遅延', 0, 0, 1, 0.01);
  AddSelect(OutOrderItem, '後 順', Ord(maoForward), @OrderOptions[0]);
  AddTrack(OutStrengthItem, '後 強さ(%)', 100, 0, 1000, 1);
end;

function ReadPartValue(Kind: TMVTransitionPartKind; Value: Integer): Integer;
begin
  if IsMVTransitionPartID(Kind, Value) then Result := Value else Result := 0;
end;

procedure ReadMVAnimationSettings(var Document: TMVDocument; out EntranceTime, ExitTime: Double);
begin
  Document.EntranceMotion := ReadPartValue(mtpMotion, InMotionItem.Value);
  Document.ExitMotion := ReadPartValue(mtpMotion, OutMotionItem.Value);
  Document.EntranceVisibility := ReadPartValue(mtpVisibility, InVisibilityItem.Value);
  Document.ExitVisibility := ReadPartValue(mtpVisibility, OutVisibilityItem.Value);
  Document.EntranceDirection := InDirectionItem.Value;
  Document.ExitDirection := OutDirectionItem.Value;
  Document.EntranceTiming := InTimingItem.Value;
  Document.ExitTiming := OutTimingItem.Value;
  Document.Hold := HoldItem.Value;
  Document.EntranceDelay := InDelayItem.Value;
  Document.ExitDelay := OutDelayItem.Value;
  Document.EntranceOrder := InOrderItem.Value;
  Document.ExitOrder := OutOrderItem.Value;
  Document.EntranceUnit := InUnitItem.Value;
  Document.HoldUnit := HoldUnitItem.Value;
  Document.ExitUnit := OutUnitItem.Value;
  Document.EntranceStrength := InStrengthItem.Value / 100;
  Document.HoldStrength := HoldStrengthItem.Value / 100;
  Document.ExitStrength := OutStrengthItem.Value / 100;
  Document.Amount := AmountItem.Value;
  Document.CurveAmount := CurveAmountItem.Value;
  // 1拍で片道、2拍で反復1周とする。120 BPMなら1周1秒。
  Document.Period := 120 / TempoItem.Value;
  EntranceTime := InTimeItem.Value;
  ExitTime := OutTimeItem.Value;
end;

end.
