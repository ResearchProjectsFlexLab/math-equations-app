//
//  AlpineScene.swift
//  biometricTracker
//
//  The rest scene for the baseline and recovery minutes: a quiet alpine valley in winter.
//  Snow-covered peaks rise ahead, a soft bank of cloud fills the valley below them, dark
//  pine forest climbs the lower slopes, and snow-laden pine trees stand around the
//  participant. Everything is drawn in code from a fixed seed, so every participant sees
//  exactly the same scene. A soft light behind the peaks follows a normal breathing pace.
//
//  Layers, back to front (all centred on the participant):
//    sky dome (90 m) · sun glow · peaks (70 m) · valley cloud (55 m) · forested ridge (40 m)
//    · pine trees (15 m) · snowy ground · falling snow
//

import CoreGraphics
import RealityKit
import SwiftUI

@MainActor
final class AlpineScene {
    /// Where the participant is asked to look: the tallest peak, straight ahead.
    static let fixationPoint = SIMD3<Float>(0, 24, -70)

    let root = Entity()

    private let glow: ModelEntity
    private var cloud: Entity?
    private let drawOrder = ModelSortGroup()

    init() {
        // Soft light behind the peaks; it brightens and fades with the breathing pace.
        glow = ModelEntity(mesh: .generatePlane(width: 60, height: 60),
                           materials: [Self.material(Self.texture(width: 256, height: 256, draw: Self.drawGlow), see: true)])
        glow.position = [0, 26, -82]
        glow.components.set(OpacityComponent(opacity: 0.6))

        // Sky: symmetric top-to-bottom, so it looks right whichever way the sphere maps it.
        // The snowy ground hides the lower half anyway.
        let sky = ModelEntity(mesh: .generateSphere(radius: 90),
                              materials: [Self.material(Self.texture(width: 16, height: 512, draw: Self.drawSky), see: false)])
        sky.scale = SIMD3<Float>(-1, 1, 1)
        add(sky, order: 0)

        add(glow, order: 1)

        // Snow-covered peaks all around, tallest straight ahead.
        if let mesh = Self.band(radius: 70, bottom: -2, height: 34, segments: 160) {
            add(ModelEntity(mesh: mesh, materials: [Self.material(Self.texture(width: 4096, height: 1024, draw: Self.drawPeaks), see: true)]),
                order: 2)
        }

        // A bank of cloud resting in the valley, covering the foot of the mountains.
        if let mesh = Self.band(radius: 55, bottom: -1, height: 10, segments: 120) {
            let bank = ModelEntity(mesh: mesh, materials: [Self.material(Self.texture(width: 4096, height: 512, draw: Self.drawCloud), see: true)])
            bank.components.set(OpacityComponent(opacity: 0.92))
            add(bank, order: 3)
            cloud = bank
        }

        // Nearer forested ridges, low in front so the view stays open.
        if let mesh = Self.band(radius: 40, bottom: -0.5, height: 9, segments: 120) {
            add(ModelEntity(mesh: mesh, materials: [Self.material(Self.texture(width: 4096, height: 512, draw: Self.drawRidge), see: true)]),
                order: 4)
        }

        // Snow-laden pine trees around the participant, with a clear view straight ahead.
        if let mesh = Self.band(radius: 15, bottom: 0, height: 10, segments: 120) {
            add(ModelEntity(mesh: mesh, materials: [Self.material(Self.texture(width: 4096, height: 1024, draw: Self.drawTrees), see: true)]),
                order: 5)
        }

        // Snowy ground.
        var groundMaterial = UnlitMaterial()
        if let ground = Self.texture(width: 512, height: 512, draw: Self.drawGround) {
            groundMaterial.color = .init(tint: .white, texture: .init(ground))
        } else {
            groundMaterial.color = .init(tint: UIColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1))
        }
        let ground = ModelEntity(mesh: .generatePlane(width: 160, depth: 160, cornerRadius: 80), materials: [groundMaterial])
        ground.position.y = -0.01
        root.addChild(ground)

        root.addChild(Self.makeSnowfall())
    }

    /// Called every frame while the scene is showing. `breath`: 0 = fully out, 1 = fully in.
    func update(breath: Float, now: Date) {
        glow.components.set(OpacityComponent(opacity: 0.45 + 0.45 * breath))
        let s: Float = 1 + 0.12 * breath
        glow.scale = SIMD3<Float>(s, s, 1)
        // The cloud bank drifts very slowly around the valley.
        let seconds = Float(now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000))
        cloud?.orientation = simd_quatf(angle: seconds * 0.004, axis: [0, 1, 0])
    }

    private func add(_ entity: ModelEntity, order: Int32) {
        // Draw the see-through layers strictly back to front.
        entity.components.set(ModelSortGroupComponent(group: drawOrder, order: order))
        root.addChild(entity)
    }

    // MARK: - Snowfall

    private static func makeSnowfall() -> Entity {
        let entity = Entity()
        entity.position = [0, 2.6, 0]
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = [10, 5, 10]
        emitter.birthLocation = .volume
        emitter.emissionDirection = [0, -1, 0]
        emitter.speed = 0.3
        emitter.speedVariation = 0.1
        emitter.mainEmitter.birthRate = 260
        emitter.mainEmitter.lifeSpan = 9
        emitter.mainEmitter.size = 0.022
        emitter.mainEmitter.sizeVariation = 0.01
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.blendMode = .alpha
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.color = .constant(.single(UIColor(white: 1, alpha: 0.9)))
        emitter.mainEmitter.noiseStrength = 0.05
        emitter.mainEmitter.noiseScale = 1
        entity.components.set(emitter)
        return entity
    }

    // MARK: - Geometry

    /// A ring around the participant with no top or bottom. Texture x runs once around it with
    /// the middle of the image straight ahead; texture y runs from the bottom edge up.
    private static func band(radius: Float, bottom: Float, height: Float, segments: Int) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for i in 0...segments {
            let u = Float(i) / Float(segments)
            let angle = (u - 0.5) * 2 * Float.pi
            let x = sin(angle) * radius, z = -cos(angle) * radius
            positions.append([x, bottom, z])
            positions.append([x, bottom + height, z])
            uvs.append([u, 0])
            uvs.append([u, 1])
        }
        for i in 0..<segments {
            let a = UInt32(i * 2)
            indices += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
        }
        var descriptor = MeshDescriptor(name: "band")
        descriptor.positions = MeshBuffer(positions)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    // MARK: - Materials

    private static func material(_ texture: TextureResource?, see: Bool) -> UnlitMaterial {
        var material = UnlitMaterial()
        if let texture {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        if see {
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
        }
        material.faceCulling = .none
        return material
    }

    /// Draws into a bitmap in ordinary CoreGraphics coordinates: y = 0 is the bottom.
    private static func texture(width: Int, height: Int, draw: (CGContext, CGFloat, CGFloat) -> Void) -> TextureResource? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(ctx, CGFloat(width), CGFloat(height))
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    // MARK: - Drawing

    private static func drawSky(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        // Overcast winter sky: soft blue-grey overhead, almost white at the horizon (the middle).
        let zenith = rgb(0.58, 0.67, 0.79), high = rgb(0.76, 0.82, 0.89), horizon = rgb(0.95, 0.96, 0.97)
        gradient(ctx, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: h),
                 colors: [zenith, high, horizon, horizon, high, zenith], locations: [0, 0.3, 0.47, 0.53, 0.7, 1])
    }

    private static func drawGlow(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        let c = CGPoint(x: w / 2, y: h / 2)
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [rgb(1, 0.98, 0.94, 0.85), rgb(1, 0.97, 0.92, 0.25), rgb(1, 1, 1, 0)] as CFArray,
                                 locations: [0, 0.3, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: w / 2, options: [])
    }

    private static func drawGround(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        let c = CGPoint(x: w / 2, y: h / 2)
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [rgb(0.96, 0.97, 0.99), rgb(0.90, 0.92, 0.96), rgb(0.84, 0.88, 0.94)] as CFArray,
                                 locations: [0, 0.5, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: w / 2,
                               options: [.drawsAfterEndLocation])
    }

    /// Two ranges of snowy peaks: a pale, hazy far range and the main range in front of it.
    private static func drawPeaks(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        var rng = SeededRandom(seed: 7)
        let base: CGFloat = h * 0.06

        // Far range, softened by distance.
        for _ in 0..<26 {
            let x = rng.next() * w
            let height = h * (0.42 + 0.30 * rng.next())
            drawPeak(ctx, apexX: x, baseY: base, height: height,
                     halfWidth: height * (0.9 + 0.7 * rng.next()), width: w, rng: &rng,
                     lit: rgb(0.96, 0.97, 0.99), shade: rgb(0.78, 0.83, 0.90),
                     forest: nil, forestLine: 0)
        }
        mist(ctx, w: w, from: base, to: base + h * 0.35, alpha: 0.55)

        // Main range, with the tallest peak straight ahead (the middle of the image).
        var peaks: [(x: CGFloat, height: CGFloat)] = [(w * 0.5, h * 0.86)]
        for _ in 0..<22 {
            peaks.append((rng.next() * w, h * (0.30 + 0.42 * rng.next())))
        }
        for p in peaks.sorted(by: { $0.height > $1.height }) {
            drawPeak(ctx, apexX: p.x, baseY: base, height: p.height,
                     halfWidth: p.height * (0.85 + 0.6 * rng.next()), width: w, rng: &rng,
                     lit: rgb(0.99, 0.99, 1.0), shade: rgb(0.63, 0.70, 0.81),
                     forest: rgb(0.20, 0.25, 0.28), forestLine: 0.26)
        }
        mist(ctx, w: w, from: 0, to: base + h * 0.14, alpha: 0.75)
    }

    /// One mountain: jagged outline, a sunlit face and a face in blue shadow split by a
    /// slanted ridge line, gullies and bands of rock showing through the snow, and dark
    /// forest climbing the lower slopes. Wraps around the 360° seam.
    private static func drawPeak(_ ctx: CGContext, apexX: CGFloat, baseY: CGFloat, height: CGFloat,
                                 halfWidth: CGFloat, width w: CGFloat, rng: inout SeededRandom,
                                 lit: CGColor, shade: CGColor, forest: CGColor?, forestLine: CGFloat) {
        let skew = 0.75 + rng.next() * 0.5
        let left = halfWidth * skew, right = halfWidth / skew
        let ridgeShift = (rng.next() - 0.5) * 0.7
        let seed = UInt64(rng.next() * 1_000_000)
        for shift in [-w, 0, w] {
            let x = apexX + shift
            guard x + right > 0, x - left < w else { continue }
            var local = SeededRandom(seed: seed)
            drawPeakShape(ctx, apex: CGPoint(x: x, y: baseY + height), baseY: baseY,
                          left: left, right: right, ridgeShift: ridgeShift, rng: &local,
                          lit: lit, shade: shade, forest: forest, forestLine: forestLine)
        }
    }

    private static func drawPeakShape(_ ctx: CGContext, apex: CGPoint, baseY: CGFloat,
                                      left: CGFloat, right: CGFloat, ridgeShift: CGFloat,
                                      rng: inout SeededRandom, lit: CGColor, shade: CGColor,
                                      forest: CGColor?, forestLine: CGFloat) {
        let height = apex.y - baseY
        let floor = baseY - 4

        // Outline: steep near the summit, easing out toward the valley, with a ragged edge.
        func flank(_ dir: CGFloat, _ span: CGFloat) -> [CGPoint] {
            (1...14).map { i in
                let t = CGFloat(i) / 14
                let along = pow(t, 1.35)
                var p = CGPoint(x: apex.x + dir * span * along, y: apex.y - height * t)
                if i < 14 {
                    p.y += (rng.next() - 0.5) * height * 0.07
                    p.x += (rng.next() - 0.5) * span * 0.03
                }
                return p
            }
        }
        let leftSide = flank(-1, left), rightSide = flank(1, right)
        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: apex.x - left, y: floor))
        for p in leftSide.reversed() { outline.addLine(to: p) }
        outline.addLine(to: apex)
        for p in rightSide { outline.addLine(to: p) }
        outline.addLine(to: CGPoint(x: apex.x + right, y: floor))
        outline.closeSubpath()

        ctx.saveGState()
        ctx.addPath(outline)
        ctx.clip()

        // Shadowed snow everywhere, then the sunlit face on the left of the ridge line.
        gradient(ctx, from: CGPoint(x: 0, y: apex.y), to: CGPoint(x: 0, y: baseY),
                 colors: [shade, mix(shade, rgb(0.45, 0.52, 0.64), 0.25)], locations: [0, 1])
        let foot = CGPoint(x: apex.x + ridgeShift * (ridgeShift < 0 ? left : right), y: floor)
        let litFace = CGMutablePath()
        litFace.addLines(between: [apex, foot, CGPoint(x: apex.x - left - 10, y: floor),
                                   CGPoint(x: apex.x - left - 10, y: apex.y + 10), CGPoint(x: apex.x, y: apex.y + 10)])
        litFace.closeSubpath()
        ctx.saveGState()
        ctx.addPath(litFace)
        ctx.clip()
        gradient(ctx, from: CGPoint(x: 0, y: apex.y), to: CGPoint(x: 0, y: baseY),
                 colors: [lit, mix(lit, shade, 0.3)], locations: [0, 1])
        ctx.restoreGState()

        // Gullies and rock showing through the snow: soft, tapering dark slivers down the faces.
        for _ in 0..<Int(14 + rng.next() * 10) {
            let side: CGFloat = rng.next() < 0.5 ? -1 : 1
            let t = 0.06 + rng.next() * 0.5
            let start = CGPoint(x: apex.x + side * (side < 0 ? left : right) * pow(t, 1.35) * (0.2 + 0.7 * rng.next()),
                                y: apex.y - height * t)
            let length = height * (0.10 + 0.25 * rng.next())
            let drift = side * length * (0.10 + 0.30 * rng.next())
            let wide = 1.5 + rng.next() * 4
            let mid = CGPoint(x: start.x + drift * 0.5 + (rng.next() - 0.5) * wide * 2, y: start.y - length * 0.5)
            let end = CGPoint(x: start.x + drift, y: start.y - length)
            let sliver = CGMutablePath()
            sliver.move(to: start)
            sliver.addQuadCurve(to: end, control: CGPoint(x: mid.x - wide, y: mid.y))
            sliver.addQuadCurve(to: start, control: CGPoint(x: mid.x + wide, y: mid.y))
            ctx.addPath(sliver)
            ctx.setFillColor(rgb(0.32, 0.38, 0.48, 0.18 + 0.22 * rng.next()))
            ctx.fillPath()
        }

        // Forest on the lower slopes, with a ragged tree line.
        if let forest {
            let line = baseY + height * forestLine
            let band = CGMutablePath()
            band.move(to: CGPoint(x: apex.x - left - 10, y: floor))
            var x = apex.x - left - 10
            while x <= apex.x + right + 10 {
                band.addLine(to: CGPoint(x: x, y: line + (rng.next() - 0.5) * height * 0.08))
                x += 3 + rng.next() * 5
            }
            band.addLine(to: CGPoint(x: apex.x + right + 10, y: floor))
            band.closeSubpath()
            ctx.addPath(band)
            ctx.setFillColor(forest)
            ctx.fillPath()
            // Snow dusting the forest.
            for _ in 0..<Int((left + right) / 3) {
                let px = apex.x - left + rng.next() * (left + right)
                let py = baseY + rng.next() * height * forestLine
                ctx.setFillColor(rgb(0.85, 0.89, 0.94, 0.35))
                ctx.fill(CGRect(x: px, y: py, width: 1.5, height: 1.5))
            }
        }
        ctx.restoreGState()
    }

    /// Soft, lumpy cloud lying in the valley.
    private static func drawCloud(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        var rng = SeededRandom(seed: 11)
        for _ in 0..<520 {
            let x = rng.next() * w
            // Thicker in front and to the sides, thinner behind.
            let around = abs(x / w - 0.5) * 2         // 0 ahead, 1 behind
            let top = h * (0.35 + 0.35 * rng.next()) * (1 - 0.35 * around)
            let r = h * (0.10 + 0.22 * rng.next())
            let c = CGPoint(x: x, y: top - r * 0.4)
            for dx in [-w, 0, w] {
                puff(ctx, at: CGPoint(x: c.x + dx, y: c.y), radius: r, alpha: 0.30 + 0.25 * rng.next())
            }
        }
        // A smooth floor of mist under the puffs.
        gradient(ctx, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: h * 0.45),
                 colors: [rgb(0.95, 0.96, 0.98, 0.95), rgb(0.95, 0.96, 0.98, 0)], locations: [0, 1])
    }

    private static func puff(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, alpha: CGFloat) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [rgb(0.98, 0.98, 0.99, alpha), rgb(0.95, 0.96, 0.98, 0)] as CFArray,
                                 locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }

    /// Forested ridges with snowy clearings, low ahead and higher to the sides.
    private static func drawRidge(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        var rng = SeededRandom(seed: 23)
        let phases = (0..<3).map { _ in rng.next() * 2 * .pi }
        func ridge(_ x: CGFloat) -> CGFloat {
            let t = x / w * 2 * .pi
            let around = abs(x / w - 0.5) * 2           // 0 ahead, 1 behind
            let wave = 0.5 + 0.25 * sin(3 * t + phases[0]) + 0.15 * sin(7 * t + phases[1]) + 0.07 * sin(17 * t + phases[2])
            let envelope = 0.18 + 0.82 * min(1, around * 1.6)
            return h * (0.08 + 0.62 * wave * envelope)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        var x: CGFloat = 0
        while x <= w { path.addLine(to: CGPoint(x: x, y: ridge(x))); x += 4 }
        path.addLine(to: CGPoint(x: w, y: 0))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(rgb(0.16, 0.21, 0.23))
        ctx.fillPath()

        // Snow dusting the forest, heavier low down where the valley mist sits.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        for _ in 0..<9000 {
            let cx = rng.next() * w
            let cy = ridge(cx) * rng.next()
            ctx.setFillColor(rgb(0.85, 0.89, 0.94, 0.25 + 0.3 * rng.next()))
            ctx.fill(CGRect(x: cx, y: cy, width: 1.5 + rng.next() * 2, height: 1.2))
        }
        gradient(ctx, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: h * 0.4),
                 colors: [rgb(0.92, 0.94, 0.97, 0.7), rgb(0.92, 0.94, 0.97, 0)], locations: [0, 1])
        ctx.restoreGState()

        // Pine tops along the ridge line.
        x = 0
        while x < w {
            let ground = ridge(x)
            let th = h * (0.05 + 0.07 * rng.next())
            pine(ctx, x: x, ground: ground - th * 0.3, height: th, rng: &rng, dark: rgb(0.13, 0.18, 0.20), snow: 0.4)
            x += 4 + rng.next() * 10
        }
    }

    /// Tall, snow-laden pines around the participant, leaving the view ahead open.
    private static func drawTrees(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        var rng = SeededRandom(seed: 41)
        var trees: [(x: CGFloat, height: CGFloat)] = []
        var x: CGFloat = 0
        while x < w {
            let offAhead = abs(x / w - 0.5) * 360       // degrees away from straight ahead
            if offAhead > 38 {
                let scale = min(1, (offAhead - 38) / 40)    // shorter near the opening
                trees.append((x, h * (0.35 + 0.6 * rng.next()) * (0.45 + 0.55 * scale)))
            }
            x += 22 + rng.next() * 70
        }
        // Back trees first so nearer-looking (taller) ones overlap them.
        for t in trees.sorted(by: { $0.height < $1.height }) {
            pine(ctx, x: t.x, ground: 0, height: t.height, rng: &rng, dark: rgb(0.09, 0.15, 0.14), snow: 0.75)
        }
    }

    /// A pine tree: a thin trunk and layered, drooping boughs with snow resting on top.
    private static func pine(_ ctx: CGContext, x: CGFloat, ground: CGFloat, height: CGFloat,
                             rng: inout SeededRandom, dark: CGColor, snow: CGFloat) {
        let width = height * (0.30 + 0.12 * rng.next())
        ctx.setFillColor(rgb(0.10, 0.08, 0.07))
        ctx.fill(CGRect(x: x - width * 0.03, y: ground, width: width * 0.06, height: height * 0.2))

        let tiers = 7
        for i in 0..<tiers {
            let t = CGFloat(i) / CGFloat(tiers)
            let tierBase = ground + height * (0.12 + 0.80 * t)
            let tierWidth = width * (1 - 0.85 * t) * (0.9 + 0.2 * rng.next())
            let tierTop = tierBase + height * 0.22
            let droop = height * 0.03
            // Bough: a wide triangle with drooping tips.
            let bough = CGMutablePath()
            bough.move(to: CGPoint(x: x - tierWidth / 2, y: tierBase - droop))
            bough.addQuadCurve(to: CGPoint(x: x, y: tierTop),
                               control: CGPoint(x: x - tierWidth * 0.18, y: tierBase + height * 0.05))
            bough.addQuadCurve(to: CGPoint(x: x + tierWidth / 2, y: tierBase - droop),
                               control: CGPoint(x: x + tierWidth * 0.18, y: tierBase + height * 0.05))
            bough.addQuadCurve(to: CGPoint(x: x - tierWidth / 2, y: tierBase - droop),
                               control: CGPoint(x: x, y: tierBase + droop))
            ctx.addPath(bough)
            ctx.setFillColor(dark)
            ctx.fillPath()

            // Snow lying along the upper edge of the bough.
            guard snow > 0 else { continue }
            let snowPath = CGMutablePath()
            // Uneven: some boughs carry more snow than others.
            let sw = tierWidth * (0.18 + 0.2 * rng.next())
            let sy = tierBase + height * (0.05 + 0.04 * rng.next())
            snowPath.move(to: CGPoint(x: x - sw, y: sy))
            snowPath.addQuadCurve(to: CGPoint(x: x, y: tierTop - height * 0.02),
                                  control: CGPoint(x: x - sw * 0.35, y: sy + height * 0.07))
            snowPath.addQuadCurve(to: CGPoint(x: x + sw, y: sy),
                                  control: CGPoint(x: x + sw * 0.35, y: sy + height * 0.07))
            snowPath.addQuadCurve(to: CGPoint(x: x - sw, y: sy),
                                  control: CGPoint(x: x, y: sy + height * 0.035))
            ctx.addPath(snowPath)
            ctx.setFillColor(rgb(0.93, 0.95, 0.98, snow))
            ctx.fillPath()
        }
    }

    private static func mist(_ ctx: CGContext, w: CGFloat, from: CGFloat, to: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.sourceAtop)          // only over what's already drawn, not empty sky
        gradient(ctx, from: CGPoint(x: 0, y: from), to: CGPoint(x: 0, y: to),
                 colors: [rgb(0.93, 0.94, 0.97, alpha), rgb(0.93, 0.94, 0.97, 0)], locations: [0, 1])
        ctx.restoreGState()
    }

    // MARK: - Helpers

    private static func gradient(_ ctx: CGContext, from: CGPoint, to: CGPoint, colors: [CGColor], locations: [CGFloat]) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                 locations: locations) else { return }
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
        let ca = a.components ?? [0, 0, 0, 1], cb = b.components ?? [0, 0, 0, 1]
        return CGColor(srgbRed: ca[0] + (cb[0] - ca[0]) * t, green: ca[1] + (cb[1] - ca[1]) * t,
                       blue: ca[2] + (cb[2] - ca[2]) * t, alpha: 1)
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
