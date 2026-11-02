import MetalKit
import SpaceCore
import simd

/// Shared by the wallpaper and the snapshot tool.
@MainActor
final class Renderer: NSObject, MTKViewDelegate {
    private static let artPixel: Float = 2
    private static let planetSecondsPerRedraw: Float = 0.1
    private static let longestStep: Float = 0.25
    private static let flameLength: Float = 7
    /// The engine's row in the rocket art, counted from the top.
    private static let nozzleHeight: Float = 10.5
    private static let turningFlame: Float = 3
    private static let flickerSeconds: Float = 0.12
    private static let flickerSteps = 3
    /// Radians of tilt still drawn as level.
    private static let levelEnough = 0.035

    private let commandQueue: MTLCommandQueue
    private let spritePipeline: MTLRenderPipelineState
    private let shipPipeline: MTLRenderPipelineState
    private let flamePipeline: MTLRenderPipelineState
    private let rocketTexture: MTLTexture
    private let planets: PlanetField
    private let stars: StarField
    private let sights: Sights
    private let shootingStars: ShootingStars
    private let dust: DustClouds
    private let speedDust: SpeedDust
    private let flight: Flight
    private var untilPlanetRedraw: Float = 0
    private var lastFrame = CACurrentMediaTime()
    private var clock: Float = 0
    private let remembersJourney: Bool
    var flightSpeed = 1.0

    init?(view: MTKView, seed: UInt64? = nil, resourceDirectory: URL? = nil, remembersJourney: Bool = false) {
        let viewWidth = Double(view.drawableSize.width) / Double(Self.artPixel)
        let saved = remembersJourney ? JourneyStore.load() : nil
        let journey = saved ?? Journey(seed: seed ?? UInt64.random(in: .min ... .max), spacing: max(viewWidth, 1))
        let seed = journey.seed
        guard let device = view.device,
              let queue = device.makeCommandQueue() else { return nil }
        let library = resourceDirectory.flatMap { try? device.makeLibrary(URL: $0.appendingPathComponent("default.metallib")) } ?? device.makeDefaultLibrary()
        guard let library,
              let spritePipeline = Pipelines.make(device: device, library: library, vertex: "sprite_vertex", fragment: "sprite_fragment"),
              let shipPipeline = Pipelines.make(device: device, library: library, vertex: "rotated_sprite_vertex", fragment: "rotated_sprite_fragment"),
              let flamePipeline = Pipelines.make(device: device, library: library, vertex: "rotated_sprite_vertex", fragment: "flames_fragment"),
              let planetPipelines = PlanetPipelines(device: device, library: library),
              let stars = StarField(device: device, library: library, seed: seed),
              let sights = Sights(device: device, library: library, seed: seed),
              let shootingStars = ShootingStars(device: device, library: library, seed: seed),
              let dust = DustClouds(device: device, library: library, seed: seed),
              let speedDust = SpeedDust(device: device, library: library, seed: seed),
              let url = resourceDirectory?.appendingPathComponent("rocket.png") ?? Bundle.main.url(forResource: "rocket", withExtension: "png"),
              let texture = try? MTKTextureLoader(device: device).newTexture(URL: url, options: [.SRGB: false]) else { return nil }
        commandQueue = queue
        self.spritePipeline = spritePipeline
        self.shipPipeline = shipPipeline
        self.flamePipeline = flamePipeline
        rocketTexture = texture
        planets = PlanetField(device: device, pipelines: planetPipelines, seed: seed)
        self.stars = stars
        self.sights = sights
        self.shootingStars = shootingStars
        self.dust = dust
        self.speedDust = speedDust
        flight = Flight(journey: journey, viewWidth: viewWidth)
        self.remembersJourney = remembersJourney
        super.init()
        if remembersJourney { JourneyStore.save(journey) }
        let space = SpaceColours.space
        view.clearColor = MTLClearColor(red: Double(space.x), green: Double(space.y), blue: Double(space.z), alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        view.delegate = self
    }

    /// Fixed steps, so a snapshot shows the same route the wallpaper would.
    func seek(to seconds: Double) {
        var remaining = max(0, min(seconds, 3600) - flight.elapsed)
        while remaining > 0 {
            let step = min(remaining, 1.0 / 30)
            flight.advance(by: step)
            remaining -= step
        }
        clock = Float(flight.elapsed)
        planets.setClock(clock)
        untilPlanetRedraw = 0
    }

    func resetFrameClock() { lastFrame = CACurrentMediaTime() }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let delta = min(Float(now - lastFrame), Self.longestStep)
        lastFrame = now
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = commandQueue.makeCommandBuffer() else { return }
        encode(into: buffer, pass: pass, screen: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)), delta: delta)
        buffer.present(drawable)
        buffer.commit()
    }

    func renderOffscreen(into texture: MTLTexture, delta: Float) -> MTLCommandBuffer? {
        guard let buffer = commandQueue.makeCommandBuffer() else { return nil }
        let pass = PlanetTexture.clearPass(texture)
        encode(into: buffer, pass: pass, screen: SIMD2(Float(texture.width), Float(texture.height)), delta: delta)
        buffer.commit()
        return buffer
    }

    private func encode(into buffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, screen: SIMD2<Float>, delta: Float) {
        let space = SpaceColours.space
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(space.x), green: Double(space.y), blue: Double(space.z), alpha: 1)
        clock += delta
        let legBefore = flight.leg
        flight.advance(by: Double(delta) * flightSpeed)
        if remembersJourney, flight.leg != legBefore { JourneyStore.save(flight.journey) }
        let artView = screen / Self.artPixel
        dust.bakeIfNeeded(into: buffer, view: artView)
        let shown = planets.visible(flight: flight, view: artView, delta: delta)
        untilPlanetRedraw -= delta
        let animatePlanets = untilPlanetRedraw <= 0
        if animatePlanets { untilPlanetRedraw = Self.planetSecondsPerRedraw }
        planets.redraw(shown, view: artView, into: buffer, animate: animatePlanets)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        stars.draw(with: encoder, view: artView, camera: flight.camera, artPixel: Self.artPixel, time: clock)
        sights.draw(with: encoder, view: artView, camera: flight.camera, artPixel: Self.artPixel, time: clock)
        shootingStars.draw(with: encoder, screen: screen, artPixel: Self.artPixel, time: clock)
        dust.draw(.behind, flight: flight, with: encoder, view: artView, time: Double(clock))
        encoder.setRenderPipelineState(spritePipeline)
        for item in shown { drawPlanet(item, with: encoder, screen: screen) }
        drawRocket(with: encoder, screen: screen, artView: artView)
        speedDust.draw(with: encoder, view: artView, camera: flight.camera, heading: flight.ship.heading, speed: flight.ship.speed * flightSpeed)
        dust.draw(.inFront, flight: flight, with: encoder, view: artView, time: Double(clock))
        encoder.endEncoding()
    }

    private func drawPlanet(_ item: PlanetField.Visible, with encoder: MTLRenderCommandEncoder, screen: SIMD2<Float>) {
        if item.planet.isTumbling {
            drawTumbling(item, with: encoder, screen: screen)
            return
        }
        let side = item.planet.displaySize * Self.artPixel
        let topLeft = (item.centre * Self.artPixel - side / 2).rounded(.toNearestOrAwayFromZero)
        guard topLeft.x < screen.x, topLeft.y < screen.y, topLeft.x + side > 0, topLeft.y + side > 0 else { return }
        var rect = SIMD4(topLeft.x / screen.x * 2 - 1, 1 - topLeft.y / screen.y * 2, side / screen.x * 2, side / screen.y * 2)
        var brightness = item.brightness
        encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&brightness, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentTexture(item.planet.texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func drawTumbling(_ item: PlanetField.Visible, with encoder: MTLRenderCommandEncoder, screen: SIMD2<Float>) {
        var sprite = RotatedSprite(centre: item.centre * Self.artPixel, size: SIMD2(repeating: item.planet.displaySize * Self.artPixel),
                                   screen: screen, angle: item.angle)
        encoder.setRenderPipelineState(shipPipeline)
        encoder.setVertexBytes(&sprite, length: MemoryLayout<RotatedSprite>.stride, index: 0)
        encoder.setFragmentBytes(&sprite, length: MemoryLayout<RotatedSprite>.stride, index: 0)
        encoder.setFragmentTexture(item.planet.texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.setRenderPipelineState(spritePipeline)
    }

    private func drawRocket(with encoder: MTLRenderCommandEncoder, screen: SIMD2<Float>, artView: SIMD2<Float>) {
        let size = SIMD2(Float(rocketTexture.width), Float(rocketTexture.height))
        let rocketPixel = Self.artPixel * 2.5
        // A hair's tilt only puts a one-pixel step in one side, so nearly level is drawn level,
        // and a level ship sits on whole screen pixels so both halves come out the same.
        let isLevel = abs(flight.ship.heading) < Self.levelEnough
        let heading = isLevel ? 0 : Float(flight.ship.heading)
        let exact = (SIMD2<Float>(flight.ship.position - flight.camera) + artView / 2) * Self.artPixel
        let half = size * rocketPixel / 2
        let centre = isLevel ? (exact - half).rounded(.toNearestOrAwayFromZero) + half : exact
        let flicker = Float(Int(clock / Self.flickerSeconds) % Self.flickerSteps)
        let burn = Self.flameLength + Float(flight.turning) * Self.turningFlame + flicker
        var flames = FlameParams(centre: centre, bounds: size * rocketPixel * 2,
            screen: screen, angle: heading, artPixel: rocketPixel, shipSize: size,
            lengths: SIMD4(burn, 0, 0, 0), nozzleY: SIMD4(Self.nozzleHeight, 0, 0, 0),
            nozzleX: 1, nozzles: 1, width: 2.5)
        encoder.setRenderPipelineState(flamePipeline)
        encoder.setVertexBytes(&flames, length: MemoryLayout<FlameParams>.stride, index: 0)
        encoder.setFragmentBytes(&flames, length: MemoryLayout<FlameParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        var sprite = RotatedSprite(centre: centre, size: size * rocketPixel, screen: screen,
                                   angle: heading)
        encoder.setRenderPipelineState(shipPipeline)
        encoder.setVertexBytes(&sprite, length: MemoryLayout<RotatedSprite>.stride, index: 0)
        encoder.setFragmentBytes(&sprite, length: MemoryLayout<RotatedSprite>.stride, index: 0)
        encoder.setFragmentTexture(rocketTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

private struct RotatedSprite {
    var centre: SIMD2<Float>
    var size: SIMD2<Float>
    var screen: SIMD2<Float>
    var angle: Float
}

private struct FlameParams {
    var centre: SIMD2<Float>
    var bounds: SIMD2<Float>
    var screen: SIMD2<Float>
    var angle: Float
    var artPixel: Float
    var shipSize: SIMD2<Float>
    var lengths: SIMD4<Float>
    var nozzleY: SIMD4<Float>
    var nozzleX: Float
    var nozzles: Int32
    var width: Float
}
