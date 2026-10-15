import MetalKit
import SwiftUI

/// Native Metal, using the same bounded triple-buffer design as Orbitals.
/// No display link runs while idle: the host owns time and submits snapshots.
struct CosmicMetalView: UIViewRepresentable {
  var scene: CosmicScene
  var onError: (String) -> Void = { _ in }

  final class Coordinator {
    var renderer: CosmicRenderer?
    var lastScene: CosmicScene?
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> MTKView {
    let view = CosmicMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    view.backgroundColor = UIColor(red: 0.024, green: 0.031, blue: 0.071, alpha: 1)
    view.isOpaque = true
    view.framebufferOnly = true
    view.colorPixelFormat = .bgra8Unorm
    view.sampleCount = 1
    view.autoResizeDrawable = true
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    view.isPaused = true
    view.enableSetNeedsDisplay = true
    do {
      let renderer = try CosmicRenderer(view: view, scene: scene)
      context.coordinator.renderer = renderer
      view.delegate = renderer
    } catch {
      Task { @MainActor in onError(error.localizedDescription) }
    }
    updateUIView(view, context: context)
    return view
  }

  func updateUIView(_ view: MTKView, context: Context) {
    guard context.coordinator.lastScene != scene else { return }
    context.coordinator.lastScene = scene
    context.coordinator.renderer?.scene = scene
    view.setNeedsDisplay()
  }

  static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
    view.isPaused = true
    view.delegate = nil
    coordinator.renderer = nil
    coordinator.lastScene = nil
    view.releaseDrawables()
  }
}

private final class CosmicMTKView: MTKView {
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { setNeedsDisplay() }
  }
}

private struct CosmicUniforms {
  var viewport: SIMD4<Float> // width/height in points, content scale, reserved
}

private enum CosmicRendererError: LocalizedError {
  case unavailable, shader, buffer
  var errorDescription: String? {
    switch self {
    case .unavailable: "This device cannot display the Metal sky. Readings and the timeline remain available."
    case .shader: "The sky shaders could not be loaded. Readings and the timeline remain available."
    case .buffer: "The sky could not reserve its display memory. Readings and the timeline remain available."
    }
  }
}

@MainActor
final class CosmicRenderer: NSObject, MTKViewDelegate {
  var scene: CosmicScene
  private let queue: any MTLCommandQueue
  private let tracePipeline: any MTLRenderPipelineState
  private let backgroundPipeline: any MTLRenderPipelineState
  private var buffers: [any MTLBuffer] = []
  private var bufferIndex = 0
  private let inFlight = DispatchSemaphore(value: 3)
  private let geometry = CosmicGeometry()
  private static let capacity = 24_576

  init(view: MTKView, scene: CosmicScene) throws {
    guard let device = view.device, let queue = device.makeCommandQueue() else {
      throw CosmicRendererError.unavailable
    }
    guard let library = device.makeDefaultLibrary(),
      let vertex = library.makeFunction(name: "cosmicVertex"),
      let fragment = library.makeFunction(name: "cosmicFragment"),
      let skyVertex = library.makeFunction(name: "cosmicSkyVertex"),
      let skyFragment = library.makeFunction(name: "cosmicSkyFragment")
    else { throw CosmicRendererError.shader }
    let trace = MTLRenderPipelineDescriptor()
    trace.label = "Tether · orbital light"
    trace.vertexFunction = vertex
    trace.fragmentFunction = fragment
    trace.colorAttachments[0].pixelFormat = view.colorPixelFormat
    trace.colorAttachments[0].isBlendingEnabled = true
    trace.colorAttachments[0].rgbBlendOperation = .add
    trace.colorAttachments[0].alphaBlendOperation = .add
    trace.colorAttachments[0].sourceRGBBlendFactor = .one
    trace.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    trace.colorAttachments[0].sourceAlphaBlendFactor = .one
    trace.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    let background = MTLRenderPipelineDescriptor()
    background.label = "Tether · deep space"
    background.vertexFunction = skyVertex
    background.fragmentFunction = skyFragment
    background.colorAttachments[0].pixelFormat = view.colorPixelFormat
    self.queue = queue
    self.scene = scene
    tracePipeline = try device.makeRenderPipelineState(descriptor: trace)
    backgroundPipeline = try device.makeRenderPipelineState(descriptor: background)
    super.init()
    for index in 0..<3 {
      guard let buffer = device.makeBuffer(
        length: Self.capacity * MemoryLayout<CosmicLineSegment>.stride, options: .storageModeShared
      ) else { throw CosmicRendererError.buffer }
      buffer.label = "Tether · snapshot \(index)"
      buffers.append(buffer)
    }
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    view.setNeedsDisplay()
  }

  func draw(in view: MTKView) {
    guard let window = view.window, !view.isHidden, view.bounds.width > 1, view.bounds.height > 1,
      UIApplication.shared.applicationState != .background else { return }
    let visible = view.convert(view.bounds, to: window).intersection(window.bounds)
    guard !visible.isNull, !visible.isEmpty else { return }
    guard inFlight.wait(timeout: .now()) == .success else {
      // A paused view must retry so the last scrubbed snapshot is never lost.
      DispatchQueue.main.async { [weak view] in view?.setNeedsDisplay() }
      return
    }
    guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
      let command = queue.makeCommandBuffer(),
      let encoder = command.makeRenderCommandEncoder(descriptor: pass)
    else { inFlight.signal(); return }
    geometry.update(scene, size: view.bounds.size, capacity: Self.capacity)
    let buffer = buffers[bufferIndex]
    bufferIndex = (bufferIndex + 1) % buffers.count
    geometry.segments.withUnsafeBytes { bytes in
      if let base = bytes.baseAddress, !bytes.isEmpty {
        buffer.contents().copyMemory(from: base, byteCount: bytes.count)
      }
    }
    var uniforms = CosmicUniforms(viewport: SIMD4(
      Float(view.bounds.width), Float(view.bounds.height), Float(view.contentScaleFactor), 0))
    encoder.label = "Tether · \(scene.mode.title)"
    encoder.setRenderPipelineState(backgroundPipeline)
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<CosmicUniforms>.stride, index: 1)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CosmicUniforms>.stride, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    if !geometry.segments.isEmpty {
      encoder.setRenderPipelineState(tracePipeline)
      encoder.setVertexBuffer(buffer, offset: 0, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                             instanceCount: geometry.segments.count)
    }
    encoder.endEncoding()
    command.present(drawable)
    let semaphore = inFlight
    command.addCompletedHandler { _ in semaphore.signal() }
    command.commit()
  }
}
