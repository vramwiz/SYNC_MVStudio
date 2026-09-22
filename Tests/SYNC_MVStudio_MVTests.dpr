program SYNC_MVStudio_MVTests;

// MV初期実装のモデル・SDK境界・並行描画・編集終了をまとめて検証する。
{$APPTYPE CONSOLE}
uses
  System.SysUtils, Vcl.Forms,
  System.Skia in '..\Win64\SkiaOverride\System.Skia.pas',
  PluginFilterTable in '..\Source\Lib\FilterTable\PluginFilterTable.pas',
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  TextRenderer in '..\Source\Lib\TextRenderer\TextRenderer.pas',
  TextRendererSkia in '..\Source\Lib\TextRenderer\TextRendererSkia.pas',
  TextRendererSkiaBootstrap in '..\Source\Lib\TextRenderer\TextRendererSkiaBootstrap.pas',
  TextRendererSkiaRuntime in '..\Source\Lib\TextRenderer\TextRendererSkiaRuntime.pas',
  TextRendererTypes in '..\Source\Lib\TextRenderer\TextRendererTypes.pas',
  MVAnimation in '..\Source\Core\Animation\MVAnimation.pas',
  MVBackgroundFrame in '..\Source\Core\Model\MVBackgroundFrame.pas',
  MVDocument in '..\Source\Core\Model\MVDocument.pas',
  MVTextUnits in '..\Source\Core\Model\MVTextUnits.pas',
  MVStoredDocument in '..\Source\Core\Storage\MVStoredDocument.pas',
  MVEditorCommit in '..\Source\Plugin\Filter\Editor\MVEditorCommit.pas',
  MVDocumentJson in '..\Source\Core\Storage\MVDocumentJson.pas',
  MVLayout in '..\Source\Rendering\MVLayout.pas',
  MVRenderer in '..\Source\Rendering\MVRenderer.pas',
  MVSelection in '..\Source\Editor\Interaction\MVSelection.pas',
  MVTransformGeometry in '..\Source\Editor\Interaction\MVTransformGeometry.pas',
  MVCanvasPainter in '..\Source\Editor\Canvas\MVCanvasPainter.pas',
  MVCanvasViewport in '..\Source\Editor\Canvas\MVCanvasViewport.pas',
  MVSelectionOverlay in '..\Source\Editor\Canvas\MVSelectionOverlay.pas',
  MVFontToolbar in '..\Source\Editor\Toolbar\MVFontToolbar.pas',
  MVEditorCanvas in '..\Source\Editor\Canvas\MVEditorCanvas.pas',
  MVEditSession in '..\Source\Editor\Model\MVEditSession.pas',
  MVPlacementToolbar in '..\Source\Editor\Toolbar\MVPlacementToolbar.pas',
  MVPlacementDocument in '..\Source\Core\Model\MVPlacementDocument.pas',
  MVEditorForm in '..\Source\Editor\Shell\MVEditorForm.pas',
  MVContextRegistry in '..\Source\Plugin\Filter\Context\MVContextRegistry.pas',
  MVFilterContext in '..\Source\Plugin\Filter\Context\MVFilterContext.pas',
  MVFilterSettings in '..\Source\Plugin\Filter\Settings\MVFilterSettings.pas',
  MVEditorBackground in '..\Source\Plugin\Filter\Editor\MVEditorBackground.pas',
  MVEditorLegacy in '..\Source\Plugin\Filter\Editor\MVEditorLegacy.pas',
  SYNC_MVStudio_FilterPlugin in '..\Source\Plugin\Filter\SYNC_MVStudio_FilterPlugin.pas',
  MVHostText in '..\Source\Plugin\Filter\Editor\MVHostText.pas',
  MVEditorHost in '..\Source\Plugin\Filter\Editor\MVEditorHost.pas',
  MVTestAssert in 'Support\MVTestAssert.pas',
  MVCoreTests in 'Core\MVCoreTests.pas',
  MVCommitTests in 'Integration\MVCommitTests.pas',
  MVLegacyEditorTests in 'Integration\MVLegacyEditorTests.pas',
  MVPluginEditorTests in 'Integration\MVPluginEditorTests.pas',
  MVPluginTests in 'Integration\MVPluginTests.pas',
  MVBackgroundTests in 'Integration\MVBackgroundTests.pas',
  MVRenderTests in 'Integration\MVRenderTests.pas',
  MVPlacementTests in 'Editor\MVPlacementTests.pas',
  MVToolbarTests in 'Editor\MVToolbarTests.pas',
  MVSelectionTests in 'Editor\MVSelectionTests.pas',
  MVTransformTests in 'Editor\MVTransformTests.pas',
  MVEditorTests in 'Editor\MVEditorTests.pas';

begin
  try
    Application.Initialize;
    RunToolbarTests;
    RunCoreTests;
    RunCommitTests;
    RunLegacyEditorTests;
    RunPluginTests;
    RunRenderTests;
    RunBackgroundTests;
    RunEditorTests;
    RunPlacementTests;
    RunTransformTests;
    RunSelectionTests;
    Writeln('PASS: ', CheckCount, ' checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
