import Metal

/// A world baked into a small surface texture and enlarged with nearest-neighbour sampling.
@MainActor
protocol Planet: AnyObject {
    var texture: MTLTexture { get }
    /// Width on screen in art pixels; the texture behind it can be smaller.
    var displaySize: Float { get }
    var pace: Float { get }
    func draw(into buffer: MTLCommandBuffer, time: Float)
    /// Painted once and turned whole, rather than repainted as time passes.
    var isTumbling: Bool { get }
}

extension Planet {
    var isTumbling: Bool { false }
}

enum PlanetTexture {
    static func surfaceSize(for displaySize: Int) -> Int { max(24, (displaySize + 2) / 3) }

    static func make(device: MTLDevice, size: Int) -> MTLTexture? {
        make(device: device, width: size, height: size)
    }

    static func make(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        description.usage = [.renderTarget, .shaderRead]
        description.storageMode = .private
        return device.makeTexture(descriptor: description)
    }

    @MainActor
    static func tidy(_ painted: MTLTexture, into texture: MTLTexture, buffer: MTLCommandBuffer, pipelines: PlanetPipelines) {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: clearPass(texture)) else { return }
        encoder.setRenderPipelineState(pipelines.tidySpecks)
        encoder.setFragmentTexture(painted, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    static func clearPass(_ texture: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        return pass
    }
}

/// Built once and shared, because compiling a pipeline per planet would stutter.
@MainActor
struct PlanetPipelines {
    let layers: [LayerShader: MTLRenderPipelineState]
    let ringedGas: MTLRenderPipelineState
    let ringedRing: MTLRenderPipelineState
    let tidySpecks: MTLRenderPipelineState
    let asteroid: MTLRenderPipelineState

    init?(device: MTLDevice, library: MTLLibrary) {
        func make(_ fragment: String) -> MTLRenderPipelineState? {
            Pipelines.make(device: device, library: library, vertex: "fullscreen_vertex", fragment: fragment)
        }
        var built: [LayerShader: MTLRenderPipelineState] = [:]
        for shader in LayerShader.allCases {
            guard let pipeline = make(shader.rawValue) else { return nil }
            built[shader] = pipeline
        }
        guard
            let ringedGas = make("ringed_gas_fragment"),
            let ringedRing = make("ringed_ring_fragment"),
            let tidySpecks = make("tidy_specks_fragment"),
            let asteroid = make("asteroid_fragment")
        else { return nil }
        layers = built
        self.ringedGas = ringedGas
        self.ringedRing = ringedRing
        self.tidySpecks = tidySpecks
        self.asteroid = asteroid
    }
}
