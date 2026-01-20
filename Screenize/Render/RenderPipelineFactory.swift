import Foundation
import CoreGraphics

// MARK: - Render Pipeline Factory

/// Factory responsible for creating FrameEvaluator and Renderer instances
/// Shared by ExportEngine and PreviewEngine
struct RenderPipelineFactory {

    // MARK: - FrameEvaluator Creation

    /// Create a FrameEvaluator from project data
    /// - Parameters:
    ///   - project: Screenize project
    ///   - mousePositions: Mouse positions for rendering
    ///   - clickEvents: Click events for rendering
    ///   - frameRate: Frame rate
    /// - Returns: A configured FrameEvaluator
    static func createEvaluator(
        project: ScreenizeProject,
        mousePositions: [RenderMousePosition],
        clickEvents: [RenderClickEvent],
        frameRate: Double
    ) -> FrameEvaluator {
        FrameEvaluator(
            timeline: project.timeline,
            mousePositions: mousePositions,
            clickEvents: clickEvents,
            frameRate: frameRate,
            scaleFactor: project.captureMeta.scaleFactor,
            screenBoundsPixel: project.captureMeta.sizePixel,
            isWindowMode: project.isWindowMode
        )
    }

    /// Create a FrameEvaluator from an updated timeline
    /// - Parameters:
    ///   - timeline: Updated timeline
    ///   - project: Screenize project (for metadata)
    ///   - mousePositions: Mouse positions for rendering
    ///   - clickEvents: Click events for rendering
    ///   - frameRate: Frame rate
    /// - Returns: A configured FrameEvaluator
    static func createEvaluator(
        timeline: Timeline,
        project: ScreenizeProject,
        mousePositions: [RenderMousePosition],
        clickEvents: [RenderClickEvent],
        frameRate: Double
    ) -> FrameEvaluator {
        FrameEvaluator(
            timeline: timeline,
            mousePositions: mousePositions,
            clickEvents: clickEvents,
            frameRate: frameRate,
            scaleFactor: project.captureMeta.scaleFactor,
            screenBoundsPixel: project.captureMeta.sizePixel,
            isWindowMode: project.isWindowMode
        )
    }

    // MARK: - Renderer Creation (Preview)

    /// Create a preview renderer
    /// - Parameters:
    ///   - project: Screenize project
    ///   - sourceSize: Source video size
    ///   - scale: Preview scale (default 0.5)
    /// - Returns: A configured Renderer
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
            renderSettings: project.isWindowMode ? project.renderSettings : nil
        )
    }

    /// Create a preview renderer when render settings change
    /// - Parameters:
    ///   - renderSettings: Updated render settings
    ///   - captureMeta: Capture metadata
    ///   - sourceSize: Source video size
    ///   - scale: Preview scale (default 0.5)
    /// - Returns: A configured Renderer
    static func createPreviewRenderer(
        renderSettings: RenderSettings,
        captureMeta: CaptureMeta,
        sourceSize: CGSize,
        scale: CGFloat = 0.5
    ) -> Renderer {
        let isWindowMode = renderSettings.backgroundEnabled
        
        return Renderer.forPreview(
            sourceSize: sourceSize,
            scale: scale,
            motionBlurSettings: renderSettings.motionBlur,
            isWindowMode: isWindowMode,
            renderSettings: isWindowMode ? renderSettings : nil
        )
    }

    // MARK: - Renderer Creation (Export)

    /// Create a renderer for export
    /// - Parameters:
    ///   - project: Screenize project
    ///   - sourceSize: Source video size
    ///   - outputSize: Output size (uses source size if nil)
    /// - Returns: A configured Renderer
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
            renderSettings: project.isWindowMode ? project.renderSettings : nil
        )
    }

    // MARK: - Combined Pipeline Creation

    /// Build the preview pipeline (Evaluator + Renderer)
    /// - Parameters:
    ///   - project: Screenize project
    ///   - mousePositions: Mouse positions for rendering
    ///   - clickEvents: Click events for rendering
    ///   - frameRate: Frame rate
    ///   - sourceSize: Source video size
    ///   - scale: Preview scale
    /// - Returns: A (FrameEvaluator, Renderer) tuple
    static func createPreviewPipeline(
        project: ScreenizeProject,
        mousePositions: [RenderMousePosition],
        clickEvents: [RenderClickEvent],
        frameRate: Double,
        sourceSize: CGSize,
        scale: CGFloat = 0.5
    ) -> (evaluator: FrameEvaluator, renderer: Renderer) {
        let evaluator = createEvaluator(
            project: project,
            mousePositions: mousePositions,
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
    /// - Parameters:
    ///   - project: Screenize project
    ///   - mousePositions: Mouse positions for rendering
    ///   - clickEvents: Click events for rendering
    ///   - frameRate: Frame rate
    ///   - sourceSize: Source video size
    ///   - outputSize: Output size
    /// - Returns: A (FrameEvaluator, Renderer) tuple
    static func createExportPipeline(
        project: ScreenizeProject,
        mousePositions: [RenderMousePosition],
        clickEvents: [RenderClickEvent],
        frameRate: Double,
        sourceSize: CGSize,
        outputSize: CGSize? = nil
    ) -> (evaluator: FrameEvaluator, renderer: Renderer) {
        let evaluator = createEvaluator(
            project: project,
            mousePositions: mousePositions,
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
