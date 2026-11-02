import Metal

enum Pipelines {
    static func make(device: MTLDevice, library: MTLLibrary, vertex: String, fragment: String) -> MTLRenderPipelineState? {
        let description = MTLRenderPipelineDescriptor()
        description.vertexFunction = library.makeFunction(name: vertex)
        description.fragmentFunction = library.makeFunction(name: fragment)
        let attachment = description.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            return try device.makeRenderPipelineState(descriptor: description)
        } catch {
            NSLog("SpaceWallpaper: could not build \(fragment): \(error)")
            return nil
        }
    }
}
