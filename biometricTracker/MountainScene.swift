//
//  MountainScene.swift
//  biometricTracker
//
//  A calm, 360° snowy mountain range shown around the participant during the
//  1-minute rests. The panorama is drawn in code (no image files), and its random
//  shapes come from a fixed seed, so every participant sees exactly the same scene.
//

import CoreGraphics
import Foundation
import RealityKit
import UIKit

enum MountainScene {

    static let entityName = "MountainScene"

    /// Builds the whole scene: the panorama sphere plus gentle falling snow.
    @MainActor
    static func make() async -> Entity {
        let root = Entity()
        root.name = entityName

        if let image = drawPanorama(),
           let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) {
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            let mesh = MeshResource.generateSphere(radius: 40)
            let sky = ModelEntity(mesh: mesh, materials: [material])
            sky.scale = SIMD3<Float>(-1, 1, 1)   // inside-out so we see the inner surface
            sky.position = [0, 1.4, 0]           // horizon at about eye level
            sky.orientation = facingForward(u: sunU, on: mesh, scale: sky.scale)
            root.addChild(sky)
        }

        root.addChild(makeSnowfall())
        return root
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

    /// Slow, sparse flakes drifting down around the participant.
    private static func makeSnowfall() -> Entity {
        let entity = Entity()
        entity.position = [0, 5, 0]

        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .plane
        emitter.emitterShapeSize = [12, 0, 12]
        emitter.birthLocation = .surface
        emitter.emissionDirection = [0, -1, 0]
        emitter.speed = 0.22
        emitter.speedVariation = 0.08
        emitter.mainEmitter.birthRate = 70
        emitter.mainEmitter.lifeSpan = 22
        emitter.mainEmitter.size = 0.012
        emitter.mainEmitter.sizeVariation = 0.006
        emitter.mainEmitter.blendMode = .alpha
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.color = .constant(.single(UIColor(white: 1, alpha: 0.85)))
        emitter.mainEmitter.noiseStrength = 0.03
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

        // CoreGraphics draws from the bottom; flip so y = 0 is the top of the sky.
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)

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
