import DailyFlowCore
import Metal
import MetalKit
import QuartzCore
import SwiftUI
import UIKit
import simd

// The Metal renderer for the 3D skeleton watch. One pass per job:
//   shadow   the key light's depth map, for the parts that cast shadows
//   scene    opaque parts, then the printed overlay, then the crystal, into 4x MSAA half-float colour
//   bloom    bright bits (lume, jewels, glints) shrunk to a quarter and blurred
//   compose  tone mapping (ACES), the bloom, the soft shadow on the background, into the drawable
// Everything that can fail in setup returns nil from `make`, and the app then shows the 2D watch instead.

/// What the renderer needs from SwiftUI, refreshed whenever the watch's inputs change.
struct WatchRenderInput {
    var frame: WatchFrame
    var clock: DFClock
    /// The app background, linear light, that the render fades into at the edges.
    var background: SIMD3<Float>
    var reduceMotion: Bool
    /// The fixed-clock screenshot mode: a fixed tilt, time zero, nothing animating.
    var isDemo: Bool
}

// MARK: GPU layouts (mirrored in WatchShaders.metal)

private struct WatchGPUFrame {
    var viewProj: simd_float4x4
    var root: simd_float4x4
    var lightViewProj: simd_float4x4
    var cameraPosition: SIMD4<Float>
    var lightDirection: SIMD4<Float>
    var lightColor: SIMD4<Float>
    var envTint: SIMD4<Float>
    var timing: SIMD4<Float>
    var flags: SIMD4<Float>
    var background: SIMD4<Float>
    var motion: SIMD4<Float>
}

private struct WatchGPUDraw {
    var model: simd_float4x4
    var material: WatchGPUMaterial
}

private struct MeshRange {
    let baseVertex: Int
    let firstIndex: Int
    let indexCount: Int
}

private enum WatchRenderError: Error {
    case missingFunction(String)
    case missingResource(String)
}

/// A colour from SwiftUI as linear light, for the shaders.
private extension SIMD3 where Scalar == Float {
    init(color: Color) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ value: CGFloat) -> Float {
            let c = Float(value)
            return c <= 0.04045 ? c / 12.92 : Float(pow(Double((c + 0.055) / 1.055), 2.4))
        }
        self.init(linear(r), linear(g), linear(b))
    }
}

extension WatchRenderInput {
    /// The app background as the renderer wants it.
    static func linearColor(_ color: Color) -> SIMD3<Float> {
        SIMD3<Float>(color: color)
    }
}

// MARK: Renderer

@MainActor
final class WatchRenderer: NSObject, MTKViewDelegate {
    // The camera: slight perspective, filling the width like the 2D watch (its 360 x 440 composition).
    private static let cameraDistance: Float = 7.8
    private static let halfWidth: Float = 1.475
    private static let shadowSize = 2048
    private static let keyLight = simd_normalize(SIMD3<Float>(-0.5, 0.55, 0.62))
    /// The tilt used for the deterministic screenshot: the face turned a little up and to the left.
    private static let demoTilt = SIMD2<Float>(-0.16, -0.24)

    // GPU objects.
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let samples: Int
    private let shadowPipeline: MTLRenderPipelineState
    private let opaquePipeline: MTLRenderPipelineState
    private let overlayPipeline: MTLRenderPipelineState
    private let glassPipeline: MTLRenderPipelineState
    private let brightPipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let depthWrite: MTLDepthStencilState
    private let depthTest: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private let ranges: [MeshRange]
    private let shadowMap: MTLTexture
    private let clearTexture: MTLTexture
    private let whiteTexture: MTLTexture
    private let loader: MTKTextureLoader

    // Textures that change.
    private var ringsTexture: MTLTexture
    private var progressTexture: MTLTexture
    private var leatherUpper: MTLTexture
    private var leatherLower: MTLTexture
    private var targets: Targets?

    // Scene and state.
    private let scene = WatchScene.shared
    private let wheelsByID: [Int: WatchWheel] = Dictionary(
        WatchMovement.allWheels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
    )
    private var visible: [WatchDrawable] = []
    private var input: WatchRenderInput
    private var gearsBySlot: [Int: WatchGear] = [:]
    private var slotColors: [Int: SIMD3<Float>] = [:]
    private var tokens: WatchMaterialTokens
    private var texturesDirty = true
    private var printedSignature: PrintSignature?
    private var lightStrapReady = false

    private let motion = WatchMotion()
    private weak var view: MTKView?
    private var lastTime = CACurrentMediaTime()
    private var lastMatrix = matrix_identity_float4x4
    private var sceneActive = true
    private var mode = RunMode.unset
    private var pollTask: Task<Void, Never>?

    private enum RunMode {
        case unset
        case running
        case onDemand
        case stopped
    }

    private struct PrintSignature: Equatable {
        let theme: ThemeMode
        let arcs: [WatchArc]
        let progress: DayProgress
    }

    private struct Targets {
        let width: Int
        let height: Int
        let msaaColor: MTLTexture?
        let depth: MTLTexture
        let scene: MTLTexture
        let bloomA: MTLTexture
        let bloomB: MTLTexture
    }

    // MARK: Creation

    /// Sets the view up and builds every GPU object, or returns nil if the device cannot do it (the caller then
    /// falls back to the 2D watch). Nothing here traps.
    static func make(view: MTKView, input: WatchRenderInput) -> WatchRenderer? {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { return nil }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.framebufferOnly = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.autoResizeDrawable = true

        do {
            let samples = device.supportsTextureSampleCount(4) ? 4 : 1
            let renderer = try WatchRenderer(
                device: device, queue: queue, library: library, samples: samples,
                outputFormat: view.colorPixelFormat, input: input
            )
            renderer.view = view
            view.delegate = renderer
            return renderer
        } catch {
            return nil
        }
    }

    private init(
        device: MTLDevice,
        queue: MTLCommandQueue,
        library: MTLLibrary,
        samples: Int,
        outputFormat: MTLPixelFormat,
        input: WatchRenderInput
    ) throws {
        self.device = device
        self.queue = queue
        self.samples = samples
        self.input = input
        self.tokens = input.frame.palette.materials
        self.loader = MTKTextureLoader(device: device)

        // Meshes: one interleaved vertex buffer (position, normal, uv) and one index buffer for everything.
        var vertexData: [Float] = []
        var indices: [UInt32] = []
        var ranges: [MeshRange] = []
        for mesh in WatchScene.shared.meshes {
            let count = min(mesh.positions.count, mesh.normals.count, mesh.uvs.count)
            let base = vertexData.count / 8
            vertexData.reserveCapacity(vertexData.count + count * 8)
            for i in 0..<count {
                let p = mesh.positions[i]
                let n = mesh.normals[i]
                let uv = mesh.uvs[i]
                vertexData.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z, uv.x, uv.y])
            }
            let valid = mesh.indices.filter { Int($0) < count }
            ranges.append(MeshRange(baseVertex: base, firstIndex: indices.count, indexCount: valid.count - valid.count % 3))
            indices.append(contentsOf: valid.prefix(valid.count - valid.count % 3))
        }
        guard !vertexData.isEmpty, !indices.isEmpty,
              let vertexBuffer = device.makeBuffer(
                  bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.stride, options: .storageModeShared
              ),
              let indexBuffer = device.makeBuffer(
                  bytes: indices, length: indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared
              )
        else { throw WatchRenderError.missingResource("mesh buffers") }
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.ranges = ranges

        // Pipelines.
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        func function(_ name: String) throws -> MTLFunction {
            guard let function = library.makeFunction(name: name) else { throw WatchRenderError.missingFunction(name) }
            return function
        }

        let shadowDescriptor = MTLRenderPipelineDescriptor()
        shadowDescriptor.vertexFunction = try function("vs_shadow")
        shadowDescriptor.vertexDescriptor = vertexDescriptor
        shadowDescriptor.depthAttachmentPixelFormat = .depth32Float
        self.shadowPipeline = try device.makeRenderPipelineState(descriptor: shadowDescriptor)

        func scenePipeline(blended: Bool) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = try function("vs_main")
            descriptor.fragmentFunction = try function("fs_main")
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.rasterSampleCount = samples
            descriptor.depthAttachmentPixelFormat = .depth32Float
            if let color = descriptor.colorAttachments[0] {
                color.pixelFormat = .rgba16Float
                if blended {
                    color.isBlendingEnabled = true
                    color.rgbBlendOperation = .add
                    color.alphaBlendOperation = .add
                    color.sourceRGBBlendFactor = .one
                    color.sourceAlphaBlendFactor = .one
                    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        self.opaquePipeline = try scenePipeline(blended: false)
        self.overlayPipeline = try scenePipeline(blended: true)
        self.glassPipeline = try scenePipeline(blended: true)

        func screenPipeline(fragment: String, format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = try function("vs_fullscreen")
            descriptor.fragmentFunction = try function(fragment)
            if let color = descriptor.colorAttachments[0] {
                color.pixelFormat = format
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        self.brightPipeline = try screenPipeline(fragment: "fs_bright", format: .rgba16Float)
        self.blurPipeline = try screenPipeline(fragment: "fs_blur", format: .rgba16Float)
        self.compositePipeline = try screenPipeline(fragment: "fs_composite", format: outputFormat)

        let writeDescriptor = MTLDepthStencilDescriptor()
        writeDescriptor.depthCompareFunction = .lessEqual
        writeDescriptor.isDepthWriteEnabled = true
        let testDescriptor = MTLDepthStencilDescriptor()
        testDescriptor.depthCompareFunction = .lessEqual
        testDescriptor.isDepthWriteEnabled = false
        guard let write = device.makeDepthStencilState(descriptor: writeDescriptor),
              let test = device.makeDepthStencilState(descriptor: testDescriptor)
        else { throw WatchRenderError.missingResource("depth states") }
        self.depthWrite = write
        self.depthTest = test

        // Textures: the shadow map, and 1 x 1 stand-ins until the painted images are ready.
        let shadowDescriptor2 = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: Self.shadowSize, height: Self.shadowSize, mipmapped: false
        )
        shadowDescriptor2.usage = [.renderTarget, .shaderRead]
        shadowDescriptor2.storageMode = .private
        guard let shadow = device.makeTexture(descriptor: shadowDescriptor2),
              let clear = Self.solidTexture(device, [0, 0, 0, 0]),
              let white = Self.solidTexture(device, [255, 255, 255, 255])
        else { throw WatchRenderError.missingResource("textures") }
        self.shadowMap = shadow
        self.clearTexture = clear
        self.whiteTexture = white
        self.ringsTexture = clear
        self.progressTexture = clear
        self.leatherUpper = white
        self.leatherLower = white

        super.init()
        refreshVisible()
        gearsChanged()
        lastMatrix = cameraMatrix(aspect: 360.0 / 440.0) * rootMatrix(tilt: Self.demoTilt)
    }

    private static func solidTexture(_ device: MTLDevice, _ rgba: [UInt8]) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: rgba, bytesPerRow: 4)
        return texture
    }

    // MARK: Updates from SwiftUI

    func update(_ newInput: WatchRenderInput, sceneActive active: Bool) {
        let old = input
        input = newInput
        sceneActive = active
        if old.frame.theme != newInput.frame.theme {
            tokens = newInput.frame.palette.materials
            refreshVisible()
            texturesDirty = true
        }
        let signature = PrintSignature(
            theme: newInput.frame.theme, arcs: newInput.frame.arcs, progress: newInput.frame.progress
        )
        if signature != printedSignature {
            texturesDirty = true
        }
        gearsChanged()
        motion.usesDeviceMotion = !newInput.reduceMotion
        motion.calm = newInput.reduceMotion
        applyMode()
        if mode == .onDemand {
            view?.setNeedsDisplay()
        }
    }

    private func refreshVisible() {
        let theme = input.frame.theme
        visible = scene.drawables.filter { $0.theme == nil || $0.theme == theme }
    }

    private func gearsChanged() {
        gearsBySlot = Dictionary(input.frame.gears.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        let palette = input.frame.palette
        slotColors = Dictionary(
            input.frame.gears.map { ($0.slot, SIMD3<Float>(color: palette.arc($0.category))) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: Running, pausing, stopping

    /// Starts watching whether the view is on screen, so an off-screen watch costs nothing.
    func startObserving() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.applyMode()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        applyMode()
    }

    /// The view joined or left a window: re-check at once instead of waiting for the next poll.
    func viewDidMoveToWindow() {
        applyMode()
    }

    func teardown() {
        pollTask?.cancel()
        pollTask = nil
        motion.stop()
        view?.isPaused = true
        view?.delegate = nil
    }

    private func isOnScreen(_ view: MTKView) -> Bool {
        guard let window = view.window, !view.isHidden, view.alpha > 0.01 else { return false }
        return view.convert(view.bounds, to: window).intersects(window.bounds)
    }

    private func applyMode() {
        guard let view else { return }
        let onScreen = sceneActive && isOnScreen(view)
        let next: RunMode = !onScreen ? .stopped : (input.reduceMotion ? .onDemand : .running)
        if next == .running, let rate = view.window?.windowScene?.screen.maximumFramesPerSecond,
           view.preferredFramesPerSecond != rate {
            view.preferredFramesPerSecond = rate
        }
        guard next != mode else { return }
        mode = next
        switch next {
        case .running:
            view.enableSetNeedsDisplay = false
            view.isPaused = false
            motion.start()
        case .onDemand:
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            motion.stop()
            view.setNeedsDisplay()
        case .stopped, .unset:
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            motion.stop()
        }
    }

    // MARK: Touch

    func dragBegan() {
        motion.beginDrag()
        redrawIfOnDemand()
    }

    func dragChanged(dx: CGFloat, dy: CGFloat) {
        motion.updateDrag(dx: dx, dy: dy)
        redrawIfOnDemand()
    }

    func dragEnded() {
        motion.endDrag()
        redrawIfOnDemand()
    }

    private func redrawIfOnDemand() {
        if mode == .onDemand {
            view?.setNeedsDisplay()
        }
    }

    /// The task gear nearest to a touch, if it is within reach. Small gears get a generous 22 point reach, as in 2D.
    func gearHit(at point: CGPoint, in size: CGSize) -> UUID? {
        guard size.width > 0, size.height > 0 else { return nil }
        var best: UUID?
        var bestDistance = CGFloat.infinity
        for gear in input.frame.gears {
            guard let wheel = WatchMovement.taskWheels.first(where: { $0.taskSlot == gear.slot }) else { continue }
            let top: Float = wheel.layer == 0 ? WatchLevel.wheelLow : WatchLevel.wheelHigh
            let center = SIMD3<Float>(Float(wheel.center.x), -Float(wheel.center.y), top)
            let edge = center + SIMD3<Float>(Float(wheel.tipRadius), 0, 0)
            guard let a = project(center, size: size), let b = project(edge, size: size) else { continue }
            let distance = hypot(point.x - a.x, point.y - a.y)
            let reach = max(hypot(b.x - a.x, b.y - a.y) + 6, 22)
            if distance <= reach, distance < bestDistance {
                best = gear.taskID
                bestDistance = distance
            }
        }
        return best
    }

    private func project(_ point: SIMD3<Float>, size: CGSize) -> CGPoint? {
        let clip = lastMatrix * SIMD4<Float>(point, 1)
        guard clip.w > 0.0001 else { return nil }
        let x = clip.x / clip.w
        let y = clip.y / clip.w
        return CGPoint(x: CGFloat(x * 0.5 + 0.5) * size.width, y: CGFloat(0.5 - y * 0.5) * size.height)
    }

    // MARK: MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Targets are rebuilt lazily in `render` when the drawable's size differs.
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            self.render()
        }
    }

    // MARK: Camera and light

    private func rootMatrix(tilt: SIMD2<Float>) -> simd_float4x4 {
        WatchMat.rotationX(tilt.x) * WatchMat.rotationY(tilt.y)
    }

    /// Projection times view (without the watch's own tilt).
    private func cameraMatrix(aspect: Float) -> simd_float4x4 {
        let distance = Self.cameraDistance
        let fovY = 2 * atan(Self.halfWidth / (aspect * distance))
        let projection = WatchMat.perspective(fovY: fovY, aspect: aspect, near: 3, far: 16)
        return projection * WatchMat.translation(0, 0, -distance)
    }

    // MARK: Textures

    /// Redraws the painted images if the tasks, theme or minute changed. Runs after a frame has been presented,
    /// so the first frame is never held up by it.
    private func refreshTexturesIfNeeded() {
        guard texturesDirty else { return }
        texturesDirty = false
        let frame = input.frame
        printedSignature = PrintSignature(theme: frame.theme, arcs: frame.arcs, progress: frame.progress)
        if let image = WatchTextures.ringsImage(frame), let texture = texture(from: image) {
            ringsTexture = texture
        }
        if let image = WatchTextures.progressImage(frame), let texture = texture(from: image) {
            progressTexture = texture
        }
        if frame.theme == .light, !lightStrapReady {
            if let image = WatchTextures.strapImage(frame, holes: false), let texture = texture(from: image) {
                leatherUpper = texture
            }
            if let image = WatchTextures.strapImage(frame, holes: true), let texture = texture(from: image) {
                leatherLower = texture
            }
            lightStrapReady = true
        }
        view?.setNeedsDisplay()
    }

    private func texture(from image: CGImage) -> MTLTexture? {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: true,
            .generateMipmaps: true,
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        if let texture = try? loader.newTexture(cgImage: image, options: options) {
            return texture
        }
        return plainTexture(from: image)
    }

    /// The same image without mipmaps, drawn into a bitmap by hand, for when the texture loader refuses it.
    private func plainTexture(from image: CGImage) -> MTLTexture? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4
        )
        return texture
    }

    private func auxTexture(_ aux: WatchAux) -> MTLTexture {
        switch aux {
        case .none: whiteTexture
        case .progress: progressTexture
        case .leatherUpper: leatherUpper
        case .leatherLower: leatherLower
        }
    }

    // MARK: Targets

    private func makeTexture(
        _ format: MTLPixelFormat, _ width: Int, _ height: Int, usage: MTLTextureUsage, samples: Int = 1
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
        descriptor.pixelFormat = format
        descriptor.width = width
        descriptor.height = height
        descriptor.sampleCount = samples
        descriptor.usage = usage
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func makeTargets(width: Int, height: Int) -> Targets? {
        let quarterWidth = max(width / 4, 1)
        let quarterHeight = max(height / 4, 1)
        guard let depth = makeTexture(.depth32Float, width, height, usage: .renderTarget, samples: samples),
              let resolved = makeTexture(.rgba16Float, width, height, usage: [.renderTarget, .shaderRead]),
              let bloomA = makeTexture(.rgba16Float, quarterWidth, quarterHeight, usage: [.renderTarget, .shaderRead]),
              let bloomB = makeTexture(.rgba16Float, quarterWidth, quarterHeight, usage: [.renderTarget, .shaderRead])
        else { return nil }
        var msaa: MTLTexture?
        if samples > 1 {
            msaa = makeTexture(.rgba16Float, width, height, usage: .renderTarget, samples: samples)
            if msaa == nil { return nil }
        }
        return Targets(width: width, height: height, msaaColor: msaa, depth: depth, scene: resolved, bloomA: bloomA, bloomB: bloomB)
    }

    // MARK: Frame

    private struct FrameState {
        let time: Double
        let pulse: Float
        let hands: WatchHands
        let tilt: SIMD2<Float>
    }

    private func render() {
        guard let view else { return }
        let width = Int(view.drawableSize.width)
        let height = Int(view.drawableSize.height)
        guard width > 8, height > 8 else { return }
        if targets == nil || targets?.width != width || targets?.height != height {
            targets = makeTargets(width: width, height: height)
        }
        guard let targets, let drawable = view.currentDrawable,
              let finalPass = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer()
        else { return }

        // Time, tilt, hands.
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - lastTime, 0.001), 0.1))
        lastTime = now
        let animating = !input.isDemo && !input.reduceMotion
        let time = animating ? now : 0
        let pulse: Float = animating ? Float(0.55 + 0.45 * sin(5 * now)) : 0.85
        let tilt = input.isDemo ? Self.demoTilt : motion.step(dt: dt, time: now)

        let date = input.clock.now()
        var minute = input.clock.fractionalMinute(of: date)
        if animating, abs(date.timeIntervalSinceNow) < 2 {
            minute += Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1) / 60
        }
        let state = FrameState(time: time, pulse: pulse, hands: WatchGeometry.hands(atMinute: minute), tilt: tilt)

        // Matrices.
        let aspect = Float(width) / Float(height)
        let camera = cameraMatrix(aspect: aspect)
        let root = rootMatrix(tilt: tilt)
        lastMatrix = camera * root
        let light = Self.keyLight
        let rootInverse = simd_inverse(root)
        let lightModel = simd_normalize((rootInverse * SIMD4<Float>(light, 0)).xyz)
        let lightUp: SIMD3<Float> = abs(lightModel.y) > 0.95 ? SIMD3<Float>(0, 0, -1) : SIMD3<Float>(0, 1, 0)
        let lightView = WatchMat.lookAt(eye: lightModel * 4.5, center: SIMD3<Float>(0, 0, 0), up: lightUp)
        let lightViewProj = WatchMat.orthographic(half: 1.6, near: 2.0, far: 7.5) * lightView

        var frame = WatchGPUFrame(
            viewProj: camera,
            root: root,
            lightViewProj: lightViewProj,
            cameraPosition: SIMD4<Float>(0, 0, Self.cameraDistance, 1),
            lightDirection: SIMD4<Float>(light, tokens.keyGain),
            lightColor: SIMD4<Float>(tokens.keyColor, 1),
            envTint: SIMD4<Float>(tokens.envTint, tokens.envGain),
            timing: SIMD4<Float>(Float(time.truncatingRemainder(dividingBy: 3600)), pulse, tokens.exposure, tokens.bloom),
            flags: SIMD4<Float>(input.frame.palette.isDark ? 1 : 0, 1 / Float(Self.shadowSize), 0, tokens.curtain),
            background: SIMD4<Float>(input.background, 1),
            motion: SIMD4<Float>(tilt.x, tilt.y, aspect, 0)
        )

        let context = WatchMaterialContext(tokens: tokens, gears: gearsBySlot, slotColors: slotColors, pulse: pulse)
        let selection = selectionMatrix()

        encodeShadow(into: commandBuffer, frame: &frame, state: state, selection: selection)
        encodeScene(into: commandBuffer, targets: targets, frame: &frame, state: state, context: context, selection: selection)
        encodeBloom(into: commandBuffer, targets: targets)
        encodeComposite(into: commandBuffer, targets: targets, pass: finalPass, frame: &frame)

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // After the frame is away: repaint the printed images if they are stale, and keep an on-demand view
        // redrawing until a released drag has settled.
        refreshTexturesIfNeeded()
        if mode == .onDemand, !motion.isSettled {
            view.setNeedsDisplay()
        }
    }

    // MARK: Per-part transforms

    private func modelMatrix(_ drawable: WatchDrawable, _ state: FrameState, selection: simd_float4x4?) -> simd_float4x4? {
        let radians = Float.pi / 180
        switch drawable.motion {
        case .fixed:
            return drawable.base
        case .wheel(let id):
            guard let wheel = wheelsByID[id] else { return drawable.base }
            let rate = wheel.taskSlot.flatMap { gearsBySlot[$0]?.spinRate } ?? 1
            let angle = Float(wheel.angle(atSeconds: state.time, rateScale: rate))
            return drawable.base * WatchMat.rotationZ(-angle * radians)
        case .balance:
            let angle = Float(WatchMovement.balanceAngle(atSeconds: state.time))
            return drawable.base * WatchMat.rotationZ(-angle * radians)
        case .hairspring:
            let angle = Float(WatchMovement.balanceAngle(atSeconds: state.time))
            return drawable.base * WatchMat.rotationZ(-angle * radians)
        case .fork:
            let fork = WatchMovement.fork
            let angle = Float(fork.tailAngle + WatchMovement.forkAngle(atSeconds: state.time))
            return drawable.base * WatchMat.rotationZ(-angle * radians)
        case .hour:
            return drawable.base * WatchMat.translation(0, 0, WatchLevel.hourHand)
                * WatchMat.rotationZ(-Float(state.hands.hour) * radians)
        case .minute:
            return drawable.base * WatchMat.translation(0, 0, WatchLevel.minuteHand)
                * WatchMat.rotationZ(-Float(state.hands.minute) * radians)
        case .day:
            return drawable.base * WatchMat.translation(0, 0, WatchLevel.dayHand)
                * WatchMat.rotationZ(-Float(state.hands.day) * radians)
        case .seconds:
            return drawable.base * WatchMat.translation(0, 0, WatchLevel.secondsHand)
                * WatchMat.rotationZ(-Float(state.hands.second) * radians)
        case .selection:
            return selection
        }
    }

    /// Places the glowing selection ring on the selected task's gear, or nil when nothing is selected.
    private func selectionMatrix() -> simd_float4x4? {
        guard let selected = input.frame.selected,
              let gear = input.frame.gears.first(where: { $0.taskID == selected }),
              let wheel = WatchMovement.taskWheels.first(where: { $0.taskSlot == gear.slot })
        else { return nil }
        let top: Float = wheel.layer == 0 ? WatchLevel.wheelLow : WatchLevel.wheelHigh
        let size = Float(wheel.tipRadius) * 1.14
        return WatchMat.translation(Float(wheel.center.x), -Float(wheel.center.y), top + 0.012)
            * WatchMat.scale(size, size, 1)
    }

    // MARK: Passes

    private func encodeShadow(
        into commandBuffer: MTLCommandBuffer, frame: inout WatchGPUFrame, state: FrameState, selection: simd_float4x4?
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Shadow"
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setDepthStencilState(depthWrite)
        encoder.setCullMode(.none)
        encoder.setDepthBias(0.0004, slopeScale: 2, clamp: 0.01)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&frame, length: MemoryLayout<WatchGPUFrame>.stride, index: 1)
        let empty = WatchGPUMaterial(baseColor: .zero, emissive: .zero, params: .zero, extra: .zero)
        for drawable in visible where drawable.castsShadow && drawable.layer == .opaque {
            guard let model = modelMatrix(drawable, state, selection: selection), drawable.mesh < ranges.count else { continue }
            var draw = WatchGPUDraw(model: model, material: empty)
            encoder.setVertexBytes(&draw, length: MemoryLayout<WatchGPUDraw>.stride, index: 2)
            drawMesh(encoder, ranges[drawable.mesh])
        }
        encoder.endEncoding()
    }

    private func encodeScene(
        into commandBuffer: MTLCommandBuffer,
        targets: Targets,
        frame: inout WatchGPUFrame,
        state: FrameState,
        context: WatchMaterialContext,
        selection: simd_float4x4?
    ) {
        let pass = MTLRenderPassDescriptor()
        if let msaa = targets.msaaColor {
            pass.colorAttachments[0].texture = msaa
            pass.colorAttachments[0].resolveTexture = targets.scene
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = targets.scene
            pass.colorAttachments[0].storeAction = .store
        }
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = targets.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Watch"
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&frame, length: MemoryLayout<WatchGPUFrame>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<WatchGPUFrame>.stride, index: 1)
        encoder.setFragmentTexture(ringsTexture, index: 0)
        encoder.setFragmentTexture(shadowMap, index: 3)

        let stages: [(WatchDrawable.Layer, MTLRenderPipelineState, MTLDepthStencilState)] = [
            (.opaque, opaquePipeline, depthWrite),
            (.overlay, overlayPipeline, depthTest),
            (.glass, glassPipeline, depthTest)
        ]
        for (layer, pipeline, depthState) in stages {
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(depthState)
            for drawable in visible where drawable.layer == layer {
                guard drawable.mesh < ranges.count,
                      let model = modelMatrix(drawable, state, selection: selection)
                else { continue }
                var draw = WatchGPUDraw(model: model, material: drawable.surface.material(context))
                encoder.setVertexBytes(&draw, length: MemoryLayout<WatchGPUDraw>.stride, index: 2)
                encoder.setFragmentBytes(&draw, length: MemoryLayout<WatchGPUDraw>.stride, index: 2)
                encoder.setFragmentTexture(auxTexture(drawable.aux), index: 1)
                drawMesh(encoder, ranges[drawable.mesh])
            }
        }
        encoder.endEncoding()
    }

    private func drawMesh(_ encoder: MTLRenderCommandEncoder, _ range: MeshRange) {
        guard range.indexCount > 0 else { return }
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: range.indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: range.firstIndex * MemoryLayout<UInt32>.stride,
            instanceCount: 1,
            baseVertex: range.baseVertex,
            baseInstance: 0
        )
    }

    private func encodeBloom(into commandBuffer: MTLCommandBuffer, targets: Targets) {
        // Bright pass into a quarter-size target, then a horizontal and a vertical blur.
        fullScreenPass(commandBuffer, label: "Bright", pipeline: brightPipeline, target: targets.bloomA, source: targets.scene)
        var horizontal = SIMD2<Float>(1, 0)
        fullScreenPass(
            commandBuffer, label: "Blur H", pipeline: blurPipeline, target: targets.bloomB, source: targets.bloomA,
            bytes: &horizontal
        )
        var vertical = SIMD2<Float>(0, 1)
        fullScreenPass(
            commandBuffer, label: "Blur V", pipeline: blurPipeline, target: targets.bloomA, source: targets.bloomB,
            bytes: &vertical
        )
    }

    private func fullScreenPass(
        _ commandBuffer: MTLCommandBuffer,
        label: String,
        pipeline: MTLRenderPipelineState,
        target: MTLTexture,
        source: MTLTexture,
        bytes: UnsafeMutablePointer<SIMD2<Float>>? = nil
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = label
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        if let bytes {
            encoder.setFragmentBytes(bytes, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeComposite(
        into commandBuffer: MTLCommandBuffer,
        targets: Targets,
        pass: MTLRenderPassDescriptor,
        frame: inout WatchGPUFrame
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Composite"
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<WatchGPUFrame>.stride, index: 1)
        encoder.setFragmentTexture(targets.scene, index: 0)
        encoder.setFragmentTexture(targets.bloomA, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
