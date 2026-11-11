//
//  MountainScene.swift
//  biometricTracker
//
//  A calm, snowy mountain scene shown around the participant during the 1-minute rests.
//
//  If the app contains a photo named "MountainView.jpg":
//    • a 360° photo (about twice as wide as tall) is wrapped all the way around;
//    • any other photo becomes a huge curved vista in front of the participant whose
//      edges fade into a soft sky and snowfield coloured to match the photo.
//  Without a photo, a drawn mountain range is used instead. Snow falls in every case.
//

import CoreGraphics
import Foundation
import ImageIO
import RealityKit
import UIKit

enum MountainScene {

    static let entityName = "MountainScene"

    /// Name of the photo file in the app bundle. Replace the file (same name) to change the view.
    static let photoName = "MountainView"

    /// How wide the curved photo appears, in degrees of the participant's view.
    static let photoDegreesWide: Float = 110
    /// Distance from the participant to the photo, in metres.
    static let photoDistance: Float = 14
    /// Which row of the photo sits at eye level (0 = top, 1 = bottom).
    static let photoEyeLevel: Float = 0.55

    /// Eye height used for the horizon.
    private static let eyeHeight: Float = 1.4

    /// Builds the whole scene: the mountains plus gentle falling snow.
    @MainActor
    static func make() async -> Entity {
        let root = Entity()
        root.name = entityName

        if let photo = loadPhoto() {
            let aspect = CGFloat(photo.width) / CGFloat(photo.height)
            if aspect > 1.9 && aspect < 2.1 {
                await addPanoramaSphere(photo: photo, to: root)
            } else {
                await addCurvedVista(photo: photo, to: root)
            }
        } else if let image = drawPanorama(),
                  let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) {
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            let mesh = MeshResource.generateSphere(radius: 40)
            let sky = ModelEntity(mesh: mesh, materials: [material])
            sky.scale = SIMD3<Float>(-1, 1, 1)   // inside-out so we see the inner surface
            sky.position = [0, eyeHeight, 0]     // horizon at about eye level
            sky.orientation = facingForward(u: sunU, on: mesh, scale: sky.scale)
            root.addChild(sky)
        }

        root.addChild(makeSnowfall())
        return root
    }

    // MARK: - Photo

    private static func loadPhoto() -> CGImage? {
        for ext in ["jpg", "jpeg", "png", "heic"] {
            if let url = Bundle.main.url(forResource: photoName, withExtension: ext),
               let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return image
            }
        }
        return nil
    }

    /// A full 360° photo wrapped around the participant, its centre straight ahead.
    @MainActor
    private static func addPanoramaSphere(photo: CGImage, to root: Entity) async {
        let mesh = MeshResource.generateSphere(radius: 40)
        let image = sphereNeedsFlip(mesh) ? flippedVertically(photo) ?? photo : photo
        guard let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) else { return }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        let sky = ModelEntity(mesh: mesh, materials: [material])
        sky.scale = SIMD3<Float>(-1, 1, 1)
        sky.position = [0, eyeHeight, 0]
        sky.orientation = facingForward(u: 0.5, on: mesh, scale: sky.scale)
        root.addChild(sky)
    }

    /// A regular photo shown as a giant curved wall in front of the participant, fading
    /// softly at its edges into a sky and snowfield sampled from the photo's own colours.
    @MainActor
    private static func addCurvedVista(photo: CGImage, to root: Entity) async {
        let profile = verticalColourProfile(of: photo)

        // Soft sky all around, matched to the photo.
        let skyMesh = MeshResource.generateSphere(radius: 40)
        if let sky = drawSoftSky(top: profile.first ?? rgb(0.8, 0.84, 0.9),
                                 horizon: profile[profile.count / 2],
                                 ground: profile.last ?? rgb(0.85, 0.88, 0.93),
                                 flip: sphereNeedsFlip(skyMesh)),
           let texture = try? await TextureResource(image: sky, options: .init(semantic: .color)) {
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            let dome = ModelEntity(mesh: skyMesh, materials: [material])
            dome.scale = SIMD3<Float>(-1, 1, 1)
            dome.position = [0, eyeHeight, 0]
            root.addChild(dome)
        }

        // The photo itself, on a curved wall with feathered edges.
        guard let feathered = featherEdges(photo),
              let texture = try? await TextureResource(image: feathered, options: .init(semantic: .color)),
              let mesh = curvedWall(aspect: Float(photo.width) / Float(photo.height)) else { return }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.blending = .transparent(opacity: 1.0)
        material.faceCulling = .none
        let wall = ModelEntity(mesh: mesh, materials: [material])
        wall.position = [0, eyeHeight, 0]
        root.addChild(wall)
    }

    /// A section of a cylinder around the participant, centred straight ahead (-z).
    @MainActor
    private static func curvedWall(aspect: Float) -> MeshResource? {
        let span = photoDegreesWide * .pi / 180
        let radius = photoDistance
        let height = radius * span / aspect          // keeps the photo's proportions
        let top = height * photoEyeLevel
        let bottom = top - height
        let topV = planeTopV()                       // match RealityKit's texture orientation
        let columns = 64

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for i in 0...columns {
            let u = Float(i) / Float(columns)
            let a = (u - 0.5) * span
            let x = radius * sin(a), z = -radius * cos(a)
            let inward = SIMD3<Float>(-sin(a), 0, cos(a))
            positions += [[x, top, z], [x, bottom, z]]
            normals += [inward, inward]
            uvs += [[u, topV], [u, 1 - topV]]
        }
        var indices: [UInt32] = []
        for i in 0..<UInt32(columns) {
            let t0 = i * 2, b0 = t0 + 1, t1 = t0 + 2, b1 = t0 + 3
            indices += [t0, b0, t1, t1, b0, b1]
        }
        var descriptor = MeshDescriptor(name: "MountainVista")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// The texture v at the top edge of a plain plane — planes show images upright,
    /// so this tells us which way up to map the photo.
    @MainActor
    private static func planeTopV() -> Float {
        let plane = MeshResource.generatePlane(width: 1, height: 1)
        guard let part = plane.contents.models.first?.parts.first,
              let uvs = part.textureCoordinates?.elements else { return 1 }
        let positions = part.positions.elements
        guard let topIndex = positions.indices.max(by: { positions[$0].y < positions[$1].y }) else { return 1 }
        return uvs[topIndex].y > 0.5 ? 1 : 0
    }

    /// True when the sphere maps the top of an upright image to the bottom.
    @MainActor
    private static func sphereNeedsFlip(_ mesh: MeshResource) -> Bool {
        guard let part = mesh.contents.models.first?.parts.first,
              let uvs = part.textureCoordinates?.elements else { return true }
        let positions = part.positions.elements
        guard let topIndex = positions.indices.max(by: { positions[$0].y < positions[$1].y }) else { return true }
        let sphereTopIsHigh = uvs[topIndex].y > 0.5
        let planeTopIsHigh = planeTopV() > 0.5
        return sphereTopIsHigh != planeTopIsHigh
    }

    /// Fades the photo's left, right, top and bottom edges to transparent.
    private static func featherEdges(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        let W = CGFloat(w), H = CGFloat(h)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setBlendMode(.destinationIn)
        let clear = rgb(1, 1, 1, 0), solid = rgb(1, 1, 1, 1)
        func mask(_ start: CGPoint, _ end: CGPoint, edge: CGFloat) {
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [clear, solid, solid, clear] as CFArray,
                                     locations: [0, edge, 1 - edge, 1]) else { return }
            ctx.drawLinearGradient(g, start: start, end: end, options: [])
        }
        mask(CGPoint(x: 0, y: 0), CGPoint(x: W, y: 0), edge: 0.16)        // left and right
        // Top fades more than the bottom (CG's y = 0 is the bottom of the image).
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [clear, solid, solid, clear] as CFArray,
                                 locations: [0, 0.10, 0.82, 1]) else { return ctx.makeImage() }
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
        return ctx.makeImage()
    }

    /// Average colours down the photo (top to bottom), used to colour the surrounding sky.
    private static func verticalColourProfile(of image: CGImage, samples: Int = 9) -> [CGColor] {
        var pixels = [UInt8](repeating: 0, count: samples * 4)
        guard let ctx = CGContext(data: &pixels, width: 1, height: samples, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: samples))
        // Memory row 0 is the top of the image.
        return (0..<samples).map { r in
            let i = r * 4
            return rgb(CGFloat(pixels[i]) / 255, CGFloat(pixels[i + 1]) / 255, CGFloat(pixels[i + 2]) / 255)
        }
    }

    /// A gentle sky gradient (zenith → misty horizon → snowfield) for the whole sphere.
    private static func drawSoftSky(top: CGColor, horizon: CGColor, ground: CGColor,
                                    flip: Bool, width: Int = 1024, height: Int = 512) -> CGImage? {
        let W = CGFloat(width), H = CGFloat(height)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if !flip {   // draw with y = 0 at the top of the stored image
            ctx.translateBy(x: 0, y: H)
            ctx.scaleBy(x: 1, y: -1)
        }
        let mist = mix(horizon, rgb(1, 1, 1), 0.35)
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [top, mix(top, mist, 0.6), mist, mix(mist, ground, 0.5), ground] as CFArray,
                                 locations: [0, 0.35, 0.5, 0.58, 1]) else { return nil }
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
        _ = W
        return ctx.makeImage()
    }

    private static func flippedVertically(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// Where the sun glow sits across the panorama (0 = left edge, 1 = right edge).
    static let sunU: CGFloat = 0.75

    /// Turns the sky so the point of the panorama at `u` is straight ahead (-z), where
    /// the window opens. Reads the sphere's own texture coordinates, so it doesn't depend
    /// on how RealityKit happens to wrap the texture.
    private static func facingForward(u target: CGFloat, on mesh: MeshResource,
                                      scale: SIMD3<Float>) -> simd_quatf {
        guard let part = mesh.contents.models.first?.parts.first,
              let uvs = part.textureCoordinates?.elements else { return simd_quatf(angle: 0, axis: [0, 1, 0]) }
        let positions = part.positions.elements
        var best: SIMD3<Float>?
        var bestScore = Float.greatestFiniteMagnitude
        for (p, uv) in zip(positions, uvs) {
            let dir = simd_normalize(p)
            // Near the horizon, with u as close as possible to the target.
            let score = abs(uv.x - Float(target)) + abs(dir.y) * 2
            if score < bestScore { bestScore = score; best = p }
        }
        guard let p = best else { return simd_quatf(angle: 0, axis: [0, 1, 0]) }
        let seen = p * scale                           // where it lands after the inside-out flip
        let flat = simd_normalize(SIMD3<Float>(seen.x, 0, seen.z))
        return simd_quatf(from: flat, to: [0, 0, -1])
    }

    // MARK: - Snowfall

    /// Soft flakes drifting slowly down all around the participant. Flakes are born
    /// throughout the space (not only overhead) and fade in, so snow is visible the
    /// moment the rest begins.
    private static func makeSnowfall() -> Entity {
        let entity = Entity()
        entity.position = [0, 2.2, 0]

        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = [9, 4.4, 9]
        emitter.birthLocation = .volume
        emitter.emissionDirection = [0, -1, 0]
        emitter.speed = 0.35
        emitter.speedVariation = 0.12
        emitter.isEmitting = true
        emitter.mainEmitter.birthRate = 450
        emitter.mainEmitter.lifeSpan = 8
        emitter.mainEmitter.size = 0.03
        emitter.mainEmitter.sizeVariation = 0.012
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.blendMode = .alpha
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.color = .constant(.single(UIColor(white: 1, alpha: 0.95)))
        emitter.mainEmitter.noiseStrength = 0.06
        emitter.mainEmitter.noiseScale = 1
        entity.components.set(emitter)
        return entity
    }

    // MARK: - Panorama

    /// Draws an equirectangular (360° × 180°) image: soft dawn sky, three layers of
    /// snow-capped peaks fading into mist, and a quiet snowfield below the horizon.
    static func drawPanorama(width: Int = 4096, height: Int = 2048) -> CGImage? {
        let W = CGFloat(width), H = CGFloat(height)
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Drawing code below treats y = 0 as the top of the sky. CoreGraphics puts y = 0 at
        // the bottom, which stores the image upside down — and that is exactly what the
        // sphere's texture mapping expects, so the mountains appear upright in the headset.

        let horizon = H / 2
        let pxPerDegree = H / 180

        // Sky: deep calm blue overhead, fading to a pale, warm glow at the horizon.
        fillVertical(ctx, top: 0, bottom: horizon, colors: [
            (0.00, rgb(0.33, 0.47, 0.70)),
            (0.55, rgb(0.62, 0.74, 0.88)),
            (0.85, rgb(0.86, 0.88, 0.93)),
            (1.00, rgb(0.97, 0.90, 0.86)),
        ], width: W)

        // A very soft sun glow low in the sky. The sky is turned so it is straight ahead.
        let sunCenter = CGPoint(x: W * sunU, y: horizon - 14 * pxPerDegree)
        if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [rgb(1.0, 0.95, 0.85, 0.55), rgb(1.0, 0.92, 0.85, 0)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawRadialGradient(glow, startCenter: sunCenter, startRadius: 0,
                                   endCenter: sunCenter, endRadius: 40 * pxPerDegree, options: [])
        }

        // Snowfield below the horizon.
        fillVertical(ctx, top: horizon, bottom: H, colors: [
            (0.00, rgb(0.90, 0.92, 0.96)),
            (0.30, rgb(0.84, 0.88, 0.94)),
            (1.00, rgb(0.74, 0.80, 0.90)),
        ], width: W)

        var rng = SeededRandom(seed: 2026)
        let sunX = sunCenter.x

        // Far range: the tallest, Himalaya-like peaks, pale and hazy with distance.
        drawRange(ctx, width: W, horizon: horizon, pxPerDegree: pxPerDegree, rng: &rng, sunX: sunX,
                  peakCount: 16, minHeight: 9, maxHeight: 24, minWidth: 5, maxWidth: 14,
                  snowAltitude: 8, lit: rgb(0.99, 0.99, 1.00), shade: rgb(0.72, 0.78, 0.90),
                  rock: rgb(0.58, 0.65, 0.78))
        drawMist(ctx, width: W, horizon: horizon, height: 6 * pxPerDegree, alpha: 0.45)

        // Middle range.
        drawRange(ctx, width: W, horizon: horizon, pxPerDegree: pxPerDegree, rng: &rng, sunX: sunX,
                  peakCount: 20, minHeight: 5, maxHeight: 13, minWidth: 4, maxWidth: 10,
                  snowAltitude: 5, lit: rgb(1.00, 1.00, 1.00), shade: rgb(0.66, 0.73, 0.87),
                  rock: rgb(0.44, 0.51, 0.65))
        drawMist(ctx, width: W, horizon: horizon, height: 3.5 * pxPerDegree, alpha: 0.45)

        // Near foothills, mostly under snow.
        drawRange(ctx, width: W, horizon: horizon, pxPerDegree: pxPerDegree, rng: &rng, sunX: sunX,
                  peakCount: 24, minHeight: 1.5, maxHeight: 5, minWidth: 4, maxWidth: 9,
                  snowAltitude: 1.0, lit: rgb(1.00, 1.00, 1.00), shade: rgb(0.76, 0.82, 0.92),
                  rock: rgb(0.62, 0.69, 0.82))
        drawMist(ctx, width: W, horizon: horizon, height: 1.5 * pxPerDegree, alpha: 0.3)

        return ctx.makeImage()
    }

    /// One mountain range that wraps seamlessly around 360°. Each peak is drawn as its
    /// own shape: a jagged outline, a slanted ridge line splitting the sunlit face from
    /// the face in soft blue shadow, and rock showing below a ragged snow line.
    private static func drawRange(_ ctx: CGContext, width W: CGFloat, horizon: CGFloat,
                                  pxPerDegree: CGFloat, rng: inout SeededRandom, sunX: CGFloat,
                                  peakCount: Int, minHeight: CGFloat, maxHeight: CGFloat,
                                  minWidth: CGFloat, maxWidth: CGFloat, snowAltitude: CGFloat,
                                  lit: CGColor, shade: CGColor, rock: CGColor) {
        struct Peak { let x, height, left, right, ridgeShift: CGFloat; let seed: UInt64 }
        var peaks: [Peak] = (0..<peakCount).map { _ in
            let half = (minWidth + (maxWidth - minWidth) * rng.next()) * pxPerDegree
            let skew = 0.7 + rng.next() * 0.6
            return Peak(x: rng.next() * W,
                        height: (minHeight + (maxHeight - minHeight) * pow(rng.next(), 1.6)) * pxPerDegree,
                        left: half * skew, right: half / skew,
                        ridgeShift: (rng.next() - 0.5) * 0.8,
                        seed: UInt64(rng.next() * 1_000_000))
        }
        // Tallest first, so smaller peaks sit in front of the big ones.
        peaks.sort { $0.height > $1.height }

        let shadeRock = darken(rock, 0.8)
        for p in peaks {
            let towardSun = wrapped(sunX - p.x, W)   // < 0: sun is to the left
            for shift in [-W, 0, W] {
                let x = p.x + shift
                guard x + p.right > 0, x - p.left < W else { continue }
                var jitter = SeededRandom(seed: p.seed)
                drawPeak(ctx, apexX: x, height: p.height, left: p.left, right: p.right,
                         ridgeShift: p.ridgeShift, sunOnLeft: towardSun < 0, horizon: horizon,
                         snowY: horizon - min(snowAltitude * pxPerDegree, p.height * 0.55),
                         lit: lit, shade: shade, litRock: rock, shadeRock: shadeRock, rng: &jitter)
            }
        }
    }

    private static func drawPeak(_ ctx: CGContext, apexX: CGFloat, height: CGFloat,
                                 left: CGFloat, right: CGFloat, ridgeShift: CGFloat,
                                 sunOnLeft: Bool, horizon: CGFloat, snowY: CGFloat,
                                 lit: CGColor, shade: CGColor, litRock: CGColor, shadeRock: CGColor,
                                 rng: inout SeededRandom) {
        let apex = CGPoint(x: apexX, y: horizon - height)
        let base = horizon + 2

        // Jagged outline: walk down each flank with small random steps.
        func flank(to end: CGPoint, steps: Int) -> [CGPoint] {
            (1...steps).map { i in
                let t = CGFloat(i) / CGFloat(steps)
                // A slight bow so slopes steepen near the top, like real peaks.
                let bow = pow(t, 0.8)
                var pt = CGPoint(x: apex.x + (end.x - apex.x) * bow,
                                 y: apex.y + (end.y - apex.y) * t)
                if i < steps { pt.y += (rng.next() - 0.5) * height * 0.06 }
                return pt
            }
        }
        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: apexX - left, y: base))
        for pt in flank(to: CGPoint(x: apexX - left, y: base), steps: 9).reversed().dropFirst() {
            outline.addLine(to: pt)
        }
        outline.addLine(to: apex)
        for pt in flank(to: CGPoint(x: apexX + right, y: base), steps: 9) { outline.addLine(to: pt) }
        outline.closeSubpath()

        // The ridge line runs from the apex down to a point on the base, slightly off-centre.
        let ridgeFoot = CGPoint(x: apexX + ridgeShift * (ridgeShift < 0 ? left : right), y: base)
        let litSide = CGMutablePath()
        let far: CGFloat = sunOnLeft ? -(left + 20) : (right + 20)
        litSide.addLines(between: [apex, ridgeFoot,
                                   CGPoint(x: apexX + far, y: base),
                                   CGPoint(x: apexX + far, y: apex.y - 10),
                                   CGPoint(x: apexX, y: apex.y - 10)])
        litSide.closeSubpath()

        // Ragged snow line, rock below it.
        let rockBand = CGMutablePath()
        let x0 = apexX - left - 4, x1 = apexX + right + 4
        rockBand.move(to: CGPoint(x: x0, y: base))
        var x = x0
        while x <= x1 {
            rockBand.addLine(to: CGPoint(x: x, y: snowY + (rng.next() - 0.3) * height * 0.12))
            x += max(6, (x1 - x0) / 40)
        }
        rockBand.addLine(to: CGPoint(x: x1, y: base))
        rockBand.closeSubpath()

        ctx.saveGState()
        ctx.addPath(outline); ctx.clip()

        // Shaded snow everywhere, sunlit snow on the sun side of the ridge.
        verticalGradient(ctx, from: apex.y, to: base, colors: [shade, darken(shade, 0.93)])
        ctx.saveGState()
        ctx.addPath(litSide); ctx.clip()
        verticalGradient(ctx, from: apex.y, to: base, colors: [lit, mix(lit, shade, 0.35)])
        ctx.restoreGState()

        // Rock, lit and shaded the same way.
        ctx.addPath(rockBand); ctx.clip()
        ctx.setFillColor(shadeRock); ctx.fill(CGRect(x: x0, y: apex.y, width: x1 - x0, height: base - apex.y))
        ctx.addPath(litSide); ctx.clip()
        ctx.setFillColor(litRock); ctx.fill(CGRect(x: x0, y: apex.y, width: x1 - x0, height: base - apex.y))
        ctx.restoreGState()
    }

    private static func verticalGradient(_ ctx: CGContext, from top: CGFloat, to bottom: CGFloat,
                                         colors: [CGColor]) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors as CFArray, locations: nil) else { return }
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Horizontal distance that wraps around the 360° seam.
    private static func wrapped(_ dx: CGFloat, _ W: CGFloat) -> CGFloat {
        var d = dx.truncatingRemainder(dividingBy: W)
        if d > W / 2 { d -= W }
        if d < -W / 2 { d += W }
        return d
    }

    private static func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
        let ca = a.components ?? [0, 0, 0, 1], cb = b.components ?? [0, 0, 0, 1]
        return CGColor(srgbRed: ca[0] + (cb[0] - ca[0]) * t,
                       green:   ca[1] + (cb[1] - ca[1]) * t,
                       blue:    ca[2] + (cb[2] - ca[2]) * t,
                       alpha:   1)
    }

    private static func darken(_ c: CGColor, _ f: CGFloat) -> CGColor {
        let k = c.components ?? [0, 0, 0, 1]
        return CGColor(srgbRed: k[0] * f, green: k[1] * f, blue: k[2] * f, alpha: 1)
    }

    /// A pale band of haze resting on the horizon, softening each range.
    private static func drawMist(_ ctx: CGContext, width W: CGFloat, horizon: CGFloat,
                                 height: CGFloat, alpha: CGFloat) {
        fillVertical(ctx, top: horizon - height, bottom: horizon + 2, colors: [
            (0, rgb(0.93, 0.94, 0.97, 0)),
            (1, rgb(0.93, 0.94, 0.97, alpha)),
        ], width: W)
    }

    private static func fillVertical(_ ctx: CGContext, top: CGFloat, bottom: CGFloat,
                                     colors: [(CGFloat, CGColor)], width W: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors.map(\.1) as CFArray,
                                        locations: colors.map(\.0)) else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: top, width: W, height: bottom - top))
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top),
                               end: CGPoint(x: 0, y: bottom), options: [])
        ctx.restoreGState()
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// Small deterministic random generator, so the scene is identical every run.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    /// A value in 0..<1.
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 11) & ((1 << 53) - 1)) / CGFloat(1 << 53)
    }
}
