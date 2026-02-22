import Foundation
import CoreGraphics

// MARK: - Render Pipeline Factory

/// Factory responsible for creating FrameEvaluator and Renderer instances
/// Shared by ExportEngine and PreviewEngine
struct RenderPipelineFactory {

    // MARK: - FrameEvaluator Creation

    /// Create a FrameEvaluator from project data
    static func createEvaluator(
        project: ScreenizeProject,
        rawMousePositions: [RenderMousePosition],
        smoothedMousePositions: [RenderMousePosition],
        clickEvents: [RenderClickEvent],
        frameRate: Double
    ) -> FrameEvaluator {
        FrameEvaluator(
            timeline: project.timeline,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: clickEvents,
            frameRate: frameRate,
            scaleFactor: project.captureMeta.scaleFactor,
            screenBoundsPixel: project.captureMeta.sizePixel,
            isWindowMode: project.isWindowMode
        )
    }

    /// Create a FrameEvaluator from an updated timeline
    static func createEvaluator(
        timeline: Timeline,
        project: ScreenizeProject,
        rawMousePositions: [RenderMousePosition],
        smoothedMousePositions: [RenderMousePosition],
        clickEvents: [RenderClickEvent],
        frameRate: Double
    ) -> FrameEvaluator {
        FrameEvaluator(
            timeline: timeline,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: clickEvents,
            frameRate: frameRate,
            scaleFactor: project.captureMeta.scaleFactor,
            screenBoundsPixel: project.captureMeta.sizePixel,
            isWindowMode: project.isWindowMode
        )
    }

    // MARK: - Renderer Creation (Preview)

    /// Create a preview renderer
    static func createPreviewRenderer(
        project: ScreenizeProject,
        sourceSize: CGSize,
        scale: CGFloat = 0.5
    ) -> Renderer {
        Renderer.forPreview(
            sourceSize: sourceSize,
            scale: scale,
            motionBlurSettings: project.renderSettings.motionBlur,
            isWindowMode: project.isWindowMode,
            renderSettings: project.renderSettings
        )
    }

    /// Create a preview renderer when render settings change
    static func createPreviewRenderer(
        renderSettings: RenderSettings,
        captureMeta: CaptureMeta,
        sourceSize: CGSize,
        scale: CGFloat = 0.5
    ) -> Renderer {
        let isWindowMode = captureMeta.displayID == nil

        return Renderer.forPreview(
            sourceSize: sourceSize,
            scale: scale,
            motionBlurSettings: renderSettings.motionBlur,
            isWindowMode: isWindowMode,
            renderSettings: renderSettings
        )
    }

    // MARK: - Renderer Creation (Export)

    /// Create a renderer for export
    static func createExportRenderer(
        project: ScreenizeProject,
        sourceSize: CGSize,
        outputSize: CGSize? = nil
    ) -> Renderer {
        Renderer.forExport(
            sourceSize: sourceSize,
            outputSize: outputSize,
            motionBlurSettings: project.renderSettings.motionBlur,
            isWindowMode: project.isWindowMode,
            renderSettings: project.renderSettings
        )
    }

    // MARK: - Combined Pipeline Creation

    /// Build the preview pipeline (Evaluator + Renderer)
    static func createPreviewPipeline(
        project: ScreenizeProject,
        rawMousePositions: [RenderMousePosition],
        smoothedMousePositions: [RenderMousePosition],
        clickEvents: [RenderClickEvent],
        frameRate: Double,
        sourceSize: CGSize,
        scale: CGFloat = 0.5
    ) -> (evaluator: FrameEvaluator, renderer: Renderer) {
        let evaluator = createEvaluator(
            project: project,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: clickEvents,
            frameRate: frameRate
        )
        let renderer = createPreviewRenderer(
            project: project,
            sourceSize: sourceSize,
            scale: scale
        )
        return (evaluator, renderer)
    }

    /// Build the export pipeline (Evaluator + Renderer)
    static func createExportPipeline(
        project: ScreenizeProject,
        rawMousePositions: [RenderMousePosition],
        smoothedMousePositions: [RenderMousePosition],
        clickEvents: [RenderClickEvent],
        frameRate: Double,
        sourceSize: CGSize,
        outputSize: CGSize? = nil
    ) -> (evaluator: FrameEvaluator, renderer: Renderer) {
        let evaluator = createEvaluator(
            project: project,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: clickEvents,
            frameRate: frameRate
        )
        let renderer = createExportRenderer(
            project: project,
            sourceSize: sourceSize,
            outputSize: outputSize
        )
        return (evaluator, renderer)
    }
}
