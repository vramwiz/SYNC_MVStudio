library SYNC_MVStudio_Filter;

// MVスタジオフィルターのAviUtl2 DLL境界。

{$ALIGN 8}

uses
  System.Skia in 'Win64\SkiaOverride\System.Skia.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  SYNC_MVStudio_FilterPlugin in 'Source\Plugin\Filter\SYNC_MVStudio_FilterPlugin.pas',
  TextRenderer in 'Source\Lib\TextRenderer\TextRenderer.pas',
  TextRendererSkia in 'Source\Lib\TextRenderer\TextRendererSkia.pas',
  TextRendererSkiaBootstrap in 'Source\Lib\TextRenderer\TextRendererSkiaBootstrap.pas',
  TextRendererSkiaRuntime in 'Source\Lib\TextRenderer\TextRendererSkiaRuntime.pas',
  TextRendererTypes in 'Source\Lib\TextRenderer\TextRendererTypes.pas',
  MVAnimationTypes in 'Source\Core\Animation\Model\MVAnimationTypes.pas',
  MVAnimationTime in 'Source\Core\Animation\Model\MVAnimationTime.pas',
  MVAnimationSequence in 'Source\Core\Animation\Model\MVAnimationSequence.pas',
  MVAppearanceTypes in 'Source\Core\Animation\Model\MVAppearanceTypes.pas',
  MVPositionMotionTypes in 'Source\Core\Animation\Model\MVPositionMotionTypes.pas',
  MVPositionMotion in 'Source\Core\Animation\MVPositionMotion.pas',
  MVPositionMotionJson in 'Source\Core\Storage\MVPositionMotionJson.pas',
  MVPositionMotionFilterSettings in 'Source\Plugin\Filter\Settings\MVPositionMotionFilterSettings.pas',
  MVAppearanceJson in 'Source\Core\Storage\MVAppearanceJson.pas',
  MVAppearanceFilterSettings in 'Source\Plugin\Filter\Settings\MVAppearanceFilterSettings.pas',
  MVAppearanceRenderer in 'Source\Rendering\Effects\MVAppearanceRenderer.pas',
  MVTransitionTiming in 'Source\Core\Animation\Model\MVTransitionTiming.pas',
  MVShapeTypes in 'Source\Core\Animation\Shapes\MVShapeTypes.pas',
  MVShapeAnimation in 'Source\Core\Animation\Shapes\MVShapeAnimation.pas',
  MVShapeRenderer in 'Source\Rendering\Effects\MVShapeRenderer.pas',
  MVAnimatedBounds in 'Source\Rendering\Effects\MVAnimatedBounds.pas',
  MVShapeFilterSettings in 'Source\Plugin\Filter\Settings\MVShapeFilterSettings.pas',
  MVAnimationCatalog in 'Source\Core\Animation\MVAnimationCatalog.pas',
  MVTransitionBasic in 'Source\Core\Animation\Transitions\MVTransitionBasic.pas',
  MVTransitionExtended in 'Source\Core\Animation\Transitions\MVTransitionExtended.pas',
  MVHoldBasic in 'Source\Core\Animation\Holds\MVHoldBasic.pas',
  MVHoldExtended in 'Source\Core\Animation\Holds\MVHoldExtended.pas',
  MVGlyphEffects in 'Source\Rendering\Effects\MVGlyphEffects.pas',
  MVTransitionMovement in 'Source\Core\Animation\Transitions\MVTransitionMovement.pas',
  MVTransitionScale in 'Source\Core\Animation\Transitions\MVTransitionScale.pas',
  MVTransitionMasks in 'Source\Core\Animation\Transitions\MVTransitionMasks.pas',
  MVTransitionScatter in 'Source\Core\Animation\Transitions\MVTransitionScatter.pas',
  MVTransitionKinetic in 'Source\Core\Animation\Transitions\MVTransitionKinetic.pas',
  MVTransitionPattern in 'Source\Core\Animation\Transitions\MVTransitionPattern.pas',
  MVTransitionPath in 'Source\Core\Animation\Transitions\MVTransitionPath.pas',
  MVHoldKinetic in 'Source\Core\Animation\Holds\MVHoldKinetic.pas',
  MVHoldAccent in 'Source\Core\Animation\Holds\MVHoldAccent.pas',
  MVGlyphPatterns in 'Source\Rendering\Effects\MVGlyphPatterns.pas',
  MVAnimation in 'Source\Core\Animation\MVAnimation.pas',
  MVBackgroundFrame in 'Source\Core\Model\MVBackgroundFrame.pas',
  MVStyleTypes in 'Source\Core\Model\MVStyleTypes.pas',
  MVStyleJson in 'Source\Core\Storage\MVStyleJson.pas',
  MVGlyphDecoration in 'Source\Rendering\Effects\MVGlyphDecoration.pas',
  MVArrangement in 'Source\Editor\Interaction\MVArrangement.pas',
  MVDocument in 'Source\Core\Model\MVDocument.pas',
  MVGrouping in 'Source\Core\Model\MVGrouping.pas',
  MVTextUnits in 'Source\Core\Model\MVTextUnits.pas',
  MVStoredDocument in 'Source\Core\Storage\MVStoredDocument.pas',
  MVEditorCommit in 'Source\Plugin\Filter\Editor\MVEditorCommit.pas',
  MVDocumentJson in 'Source\Core\Storage\MVDocumentJson.pas',
  MVLayout in 'Source\Rendering\MVLayout.pas',
  MVAnimationGroups in 'Source\Rendering\MVAnimationGroups.pas',
  MVGroupEffects in 'Source\Rendering\Effects\MVGroupEffects.pas',
  MVRenderer in 'Source\Rendering\MVRenderer.pas',
  MVSelection in 'Source\Editor\Interaction\MVSelection.pas',
  MVTransformGeometry in 'Source\Editor\Interaction\MVTransformGeometry.pas',
  MVCanvasPainter in 'Source\Editor\Canvas\MVCanvasPainter.pas',
  MVCanvasViewport in 'Source\Editor\Canvas\MVCanvasViewport.pas',
  MVSelectionOverlay in 'Source\Editor\Canvas\MVSelectionOverlay.pas',
  MVFontToolbar in 'Source\Editor\Toolbar\MVFontToolbar.pas',
  MVEditorCanvas in 'Source\Editor\Canvas\MVEditorCanvas.pas',
  MVEditSession in 'Source\Editor\Model\MVEditSession.pas',
  MVPlacementToolbar in 'Source\Editor\Toolbar\MVPlacementToolbar.pas',
  MVPlacementDocument in 'Source\Core\Model\MVPlacementDocument.pas',
  MVEditorForm in 'Source\Editor\Shell\MVEditorForm.pas',
  MVContextRegistry in 'Source\Plugin\Filter\Context\MVContextRegistry.pas',
  MVFilterContext in 'Source\Plugin\Filter\Context\MVFilterContext.pas',
  MVFilterSettings in 'Source\Plugin\Filter\Settings\MVFilterSettings.pas',
  MVEditorBackground in 'Source\Plugin\Filter\Editor\MVEditorBackground.pas',
  MVEditorLegacy in 'Source\Plugin\Filter\Editor\MVEditorLegacy.pas',
  MVHostText in 'Source\Plugin\Filter\Editor\MVHostText.pas',
  MVEditorHost in 'Source\Plugin\Filter\Editor\MVEditorHost.pas';

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    InitializeMVStudioFilter(Version);
    Result := 1;
  except
    // Exceptions must not cross AviUtl2's C callback boundary.
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  try
    FinalizeMVStudioFilter;
  except
    // DLL unload must continue even if Skia cleanup fails.
  end;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetMVStudioFilterTable;
  except
    // The host treats a missing table as plugin initialization failure.
  end;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
