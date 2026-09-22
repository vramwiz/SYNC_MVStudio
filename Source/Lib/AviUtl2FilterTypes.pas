unit AviUtl2FilterTypes;

// AviUtl2 フィルタープラグイン登録に必要な最小ABI定義。

{$ALIGN 8}

interface

type
  LPCWSTR = PWideChar;
  OBJECT_HANDLE = Pointer;

  PEDIT_SECTION = ^TEDIT_SECTION;
  TFilterItemButtonCallback = procedure(Edit: PEDIT_SECTION); cdecl;
  TFilterItemButtonCallback2 = procedure(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE;
    Effect, Item: LPCWSTR); cdecl;
  TCountObjectEffectFunc = function(Obj: OBJECT_HANDLE;
    Effect: LPCWSTR): Integer; cdecl;
  TOBJECT_LAYER_FRAME = record
    Layer: Integer; // SDKのレイヤー番号。
    StartFrame: Integer; // 配置開始フレーム。
    EndFrame: Integer; // 配置終了フレーム。このフレームを含む。
  end;
  TGetObjectLayerFrameFunc = function(
    Obj: OBJECT_HANDLE): TOBJECT_LAYER_FRAME; cdecl;
  TSetObjectItemValueFunc = function(Obj: OBJECT_HANDLE; Effect: LPCWSTR;
    Item: LPCWSTR; Value: PAnsiChar): Boolean; cdecl;
  TGetObjectItemValueFunc = function(Obj: OBJECT_HANDLE; Effect: LPCWSTR;
    Item: LPCWSTR): PAnsiChar; cdecl;
  TGetFocusObjectFunc = function: OBJECT_HANDLE; cdecl;
  TSetObjectNameFunc = procedure(Obj: OBJECT_HANDLE; Name: LPCWSTR); cdecl;

  // ボタンコールバックで、選択中オブジェクトのGUI項目と表示名を変更する編集API。
  TEDIT_SECTION = record
    Info: Pointer; // SDK EDIT_INFO。後続の未使用関数もABI上の位置を維持する。
    CreateObjectFromAlias: Pointer; // 未使用: エイリアスから生成。
    FindObject: Pointer; // 未使用: オブジェクト検索。
    CountObjectEffect: TCountObjectEffectFunc; // 同名エフェクト数。
    GetObjectLayerFrame: TGetObjectLayerFrameFunc; // 対象の配置区間。
    GetObjectAlias: Pointer; // 未使用: エイリアス取得。
    GetObjectItemValue: TGetObjectItemValueFunc; // UTF-8の現在値。取得直後に複写する。
    SetObjectItemValue: TSetObjectItemValueFunc; // UTF-8で保存。C boolは1バイト。
    MoveObject: Pointer; // 未使用: 移動。
    DeleteObject: Pointer; // 未使用: 削除。
    GetFocusObject: TGetFocusObjectFunc; // フォーカス対象取得。
    SetFocusObject: Pointer; // 未使用: フォーカス変更。
    GetProjectFile: Pointer; // 未使用: プロジェクト名。
    GetSelectedObject: Pointer; // 未使用: 選択対象。
    GetSelectedObjectNum: Pointer; // 未使用: 選択数。
    GetMouseLayerFrame: Pointer; // 未使用: マウスの配置区間。
    PosToLayerFrame: Pointer; // 未使用: 座標変換。
    IsSupportMediaFile: Pointer; // 未使用: メディア対応判定。
    GetMediaInfo: Pointer; // 未使用: メディア情報。
    CreateObjectFromMediaFile: Pointer; // 未使用: メディアから生成。
    CreateObject: Pointer; // 未使用: 新規生成。
    SetCursorLayerFrame: Pointer; // 未使用: カーソル位置。
    SetDisplayLayerFrame: Pointer; // 未使用: 表示区間。
    SetSelectRange: Pointer; // 未使用: 選択区間。
    SetGridBpm: Pointer; // 未使用: BPMグリッド。
    GetObjectName: Pointer; // 未使用: 表示名取得。
    SetObjectName: TSetObjectNameFunc; // 表示名設定。
    Reserved27To49: array[27..49] of Pointer; // SDKの未使用関数スロット。Infoがスロット0。
    FindEffect: function(Obj: OBJECT_HANDLE; Effect: LPCWSTR): Pointer; cdecl; // スロット50: 対象効果を検索。
    Reserved51To81: array[51..81] of Pointer; // スロット51～81の未使用関数。旧本体では末尾へ触れない。
    GetEffectID: function(Effect: Pointer): Int64; cdecl; // スロット82。2.1.10以降でだけ使用する。
  end;

  PSCENE_INFO = ^TSCENE_INFO;
  TSCENE_INFO = record
    Width, Height: Integer; // 出力シーンのピクセル寸法。
    Rate, Scale: Integer; // FPSの分子と分母。
    SampleRate: Integer; // 音声サンプリング周波数。
  end;

  POBJECT_INFO = ^TOBJECT_INFO;
  TOBJECT_INFO = record
    ID: Int64; // アプリ起動内で一意のオブジェクトID。
    Frame: Integer; // 対象区間先頭からの現在フレーム。
    FrameTotal: Integer; // 対象区間のフレーム数。
    Time: Double; // 対象区間先頭からの秒数。
    TimeTotal: Double; // 対象区間の秒数。
    Width, Height: Integer; // GetImageDataが返す入力画像の寸法。
    SampleIndex: Int64; // 音声用サンプル位置。MVでは未使用。
    SampleTotal: Int64; // 音声用総サンプル数。
    SampleNum: Integer; // 今回の音声サンプル数。
    ChannelNum: Integer; // 音声チャンネル数。
    EffectID: Int64; // アプリ起動内で一意。同一オブジェクトへの複数追加も区別する。
    Flag: Integer; // SDKのオブジェクトフラグ。
    Layer: Integer; // 配置レイヤー。
    Index: Integer; // 個別オブジェクト時の現在の対象番号。
    Num: Integer; // 個別オブジェクト時の対象数。1は単体、0は不定。
    FrameS: Integer; // シーン基準の配置開始フレーム。
    FrameE: Integer; // シーン基準の配置終了フレーム。後続の未使用SDK項目は省略。
  end;

  TPIXEL_RGBA = packed record
    R, G, B, A: Byte; // SDKの非乗算RGBA8888。4バイト固定。
  end;
  PPIXEL_RGBA = ^TPIXEL_RGBA;

  TFILTER_PROC_VIDEO_GET_TEX2D = function: Pointer; cdecl;
  PFILTER_PROC_VIDEO = ^TFILTER_PROC_VIDEO;
  TFILTER_PROC_VIDEO = record
    Scene: PSCENE_INFO; // シーン情報。
    Object_: POBJECT_INFO; // 今回の対象と時間。
    GetImageData: procedure(Buffer: PPIXEL_RGBA); cdecl; // 対象寸法分の領域が必要。
    SetImageData: procedure(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl; // 完成画像をホストへ渡す。
    GetImageTexture2D: TFILTER_PROC_VIDEO_GET_TEX2D; // 未使用のGPU入力。ABI位置を維持。
    GetFramebufferTexture2D: TFILTER_PROC_VIDEO_GET_TEX2D; // 未使用のGPU背景。
  end;

  TFuncProcVideo = function(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
  TFuncProcAudio = function(Audio: Pointer): Byte; cdecl;

  // AviUtl2が1行のUnicode文字列を保持する文字列項目。
  PFILTER_ITEM_STRING = ^TFILTER_ITEM_STRING;
  TFILTER_ITEM_STRING = record
    ItemType: LPCWSTR; // SDK項目種別の固定値 `string`。
    Name    : LPCWSTR; // GUI表示名兼、設定取得時の項目識別名。
    Value   : LPCWSTR; // AviUtl2が管理する現在の文字列。
  end;

  // AviUtl2が現在値と範囲を管理する数値トラック項目。
  PFILTER_ITEM_TRACK = ^TFILTER_ITEM_TRACK;
  TFILTER_ITEM_TRACK = record
    ItemType : LPCWSTR; // SDK項目種別の固定値 `track`。
    Name     : LPCWSTR; // GUI表示名兼、設定取得時の項目識別名。
    Value    : Double;  // 初期値。配置後はAviUtl2が現在値を保持する。
    S        : Double;  // 最小値。
    E        : Double;  // 最大値。
    Step     : Double;  // GUI上の変更単位。
  end;

  // オン／オフを保持するチェックボックス項目。
  PFILTER_ITEM_CHECK = ^TFILTER_ITEM_CHECK;
  TFILTER_ITEM_CHECK = record
    ItemType: LPCWSTR; // SDK項目種別の固定値 `check`。
    Name    : LPCWSTR; // GUI表示名兼、設定取得時の項目識別名。
    Value   : Byte;    // 0=False、1=True。
  end;

  // 後続の設定項目を折りたたむグループ見出し。
  PFILTER_ITEM_GROUP = ^TFILTER_ITEM_GROUP;
  TFILTER_ITEM_GROUP = record
    ItemType: LPCWSTR;       // SDK項目種別の固定値 `group`。
    Name: LPCWSTR; // グループ名。空文字なら終端。
    DefaultVisible: Byte; // C bool。初期状態で展開するか。
  end;

  // filter2.hの非表示条件。Win64で32バイト、比較演算子はC enumと同じ4バイト。
  PFILTER_ITEM_HIDE_RULE = ^TFILTER_ITEM_HIDE_RULE;
  TFILTER_ITEM_HIDE_RULE = record
    ItemType: LPCWSTR; // 固定値hiderule。
    Name: LPCWSTR; // 非表示にする値項目名。
    ConditionName: LPCWSTR; // 条件を読む選択項目名。nilなら常時非表示。
    ConditionOperator: Integer; // 0は等しい、1は等しくない。
    ConditionValue: Integer; // 条件と比較する整数値。
  end;

  // 列挙値から1つを選ぶ選択項目。ListはName=nilの要素で終端する。
  PFILTER_ITEM_SELECT = ^TFILTER_ITEM_SELECT;
  TFILTER_ITEM_SELECT_ITEM = record
    Name : LPCWSTR; // GUIに表示する選択肢名。
    Value: Integer; // 選択時にValueへ格納される識別値。
  end;
  TFILTER_ITEM_SELECT = record
    ItemType: LPCWSTR;                   // SDK項目種別の固定値 `select`。
    Name    : LPCWSTR;                   // GUI表示名兼、設定取得時の項目識別名。
    Value   : Integer;                   // 現在選択されている識別値。
    List    : ^TFILTER_ITEM_SELECT_ITEM; // nil終端された選択肢配列。
  end;

  // 選択中オブジェクトへ設定を反映する編集コールバック付きボタン。
  PFILTER_ITEM_BUTTON = ^TFILTER_ITEM_BUTTON;
  TFILTER_ITEM_BUTTON = record
    ItemType: LPCWSTR; // SDK項目種別の固定値button。
    Name: LPCWSTR; // ボタン名兼、設定項目の識別名。
    Callback: TFilterItemButtonCallback; // 旧形式の通知。Callback2使用時はnil。
    Callback2: TFilterItemButtonCallback2; // SDK 2026-09-19: 対象とエフェクト添字を直接受け取る。
  end;

  // SDK配置はB,G,R,X。Xは予約領域であり、描画アルファには使用しない。
  PFILTER_ITEM_COLOR = ^TFILTER_ITEM_COLOR;
  TFILTER_ITEM_COLOR = record
    ItemType: LPCWSTR; // SDK項目種別の固定値 `color`。
    Name: LPCWSTR;     // GUI表示名兼、設定取得時の項目識別名。
    B, G, R, X: Byte;  // 青、緑、赤、予約領域。
  end;

  // AviUtl2が選択したファイルパスをValueへ保持するファイル選択項目。
  PFILTER_ITEM_FILE = ^TFILTER_ITEM_FILE;
  TFILTER_ITEM_FILE = record
    ItemType   : LPCWSTR; // SDK項目種別の固定値 `file`。
    Name       : LPCWSTR; // GUI表示名兼、設定取得時の項目識別名。
    Value      : LPCWSTR; // AviUtl2が管理する現在のファイルパス。
    FileFilter : LPCWSTR; // ファイル選択ダイアログ用の二重nil終端フィルター。
  end;

  TFilterCreate = function(EffectID: Int64): Pointer; cdecl;
  TFilterDestroy = procedure(EffectID: Int64; UserData: Pointer); cdecl;
  PFILTER_PLUGIN_TABLE = ^TFILTER_PLUGIN_TABLE;
  TFILTER_PLUGIN_TABLE = record
    Flag: Integer; // C intの後はWin64の8バイト境界へ整列する。
    Name: LPCWSTR; // フィルター名。
    Label_: LPCWSTR; // ホストの分類ラベル。
    Information: LPCWSTR; // プラグイン説明。
    Items: ^Pointer; // nil終端の設定項目ポインタ配列。
    Func_Proc_Video: TFuncProcVideo; // 映像処理。C bool相当を返す。
    Func_Proc_Audio: TFuncProcAudio; // 音声非対応のためnil。
    Func_Create: TFilterCreate; // SDK末尾の生成通知。Cのvoid*を返す。
    Func_Destroy: TFilterDestroy; // Undoを含む全参照解放後の破棄通知。
  end;

const
  FILTER_FLAG_VIDEO = 1;
  FILTER_FLAG_FILTER = 8;
  FILTER_FLAG_USERDATA = 16; // 生成・破棄通知を有効にするSDKフラグ。

implementation

end.
