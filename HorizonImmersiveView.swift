import SwiftUI
import RealityKit
import UIKit
import CoreText
import simd

struct HorizonImmersiveView: View {
    private static let globeCenterY: Float = 1.02
    private static let globeScale: Float = 1.5
    private static let globeOverlayScale: Float = 4.0 / globeScale
    private static let globeMarkerScale: Float = globeOverlayScale * 0.01
    private static let routeStringScale: Float = globeOverlayScale * 0.1
    private static let panelScale: Float = 4.0 * 2.0 / 3.0
    private static let compactPanelScale: Float = panelScale * 2.0 / 3.0
    private static let dashboardDepth: Float = -1.08

    @Environment(AppModel.self) private var appModel
    @Bindable var viewModel: CommodityIntelligenceViewModel
    @State private var globeDragStartRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var isDraggingGlobe = false

    var body: some View {
        RealityView { content, attachments in
            let sceneRoot = Entity()
            sceneRoot.name = EntityNames.root
            content.add(sceneRoot)

            sceneRoot.addChild(Self.makeTradingArena())
            sceneRoot.addChild(Self.makeLightRig())
            sceneRoot.addChild(Self.makeGlobeSystem(viewModel: viewModel))
            Self.placeAttachments(in: sceneRoot, attachments: attachments)
        } update: { content, attachments in
            guard let sceneRoot = content.entities.first(where: { $0.name == EntityNames.root }) else { return }
            if let globeSystem = sceneRoot.findEntity(named: EntityNames.globeSystem) {
                if viewModel.isRotatingGlobeInteractively {
                    globeSystem.orientation = viewModel.rotationToFocusedCoordinate()
                } else {
                    content.animate {
                        globeSystem.orientation = viewModel.rotationToFocusedCoordinate()
                    }
                    if let dynamic = globeSystem.findEntity(named: EntityNames.dynamic) {
                        dynamic.removeFromParent()
                    }
                    globeSystem.addChild(Self.makeDynamicContent(viewModel: viewModel))
                }
            }
            Self.placeAttachments(in: sceneRoot, attachments: attachments)
        } attachments: {
            Attachment(id: AttachmentID.ribbon) {
                CommodityRibbonView(viewModel: viewModel)
                    .frame(width: 1260)
            }
            Attachment(id: AttachmentID.news) {
                NewsStreamView(viewModel: viewModel)
                    .frame(width: 430)
            }
            Attachment(id: AttachmentID.chart) {
                MarketChartView(viewModel: viewModel)
                    .frame(width: 520)
            }
            Attachment(id: AttachmentID.slider) {
                PredictiveScenarioSlider(viewModel: viewModel)
                    .frame(width: 1260)
            }
            Attachment(id: AttachmentID.callout) {
                EventCalloutView(event: viewModel.selectedEvent)
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let event = viewModel.currentEvents.first(where: { value.entity.name == EntityNames.pinName(for: $0) }) else { return }
                    withAnimation(.smooth(duration: 0.45)) {
                        viewModel.focus(on: event)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard EntityNames.isGlobeRotationTarget(value.entity.name) else { return }
                    if !isDraggingGlobe {
                        isDraggingGlobe = true
                        viewModel.isRotatingGlobeInteractively = true
                        globeDragStartRotation = viewModel.manualGlobeRotation
                    }
                    viewModel.rotateGlobe(from: globeDragStartRotation, translation: value.translation)
                }
                .onEnded { _ in
                    isDraggingGlobe = false
                    viewModel.isRotatingGlobeInteractively = false
                    globeDragStartRotation = viewModel.manualGlobeRotation
                }
        )
    }

    private static func placeAttachments(in root: Entity, attachments: RealityViewAttachments) {
        let controlScale = compactPanelScale * 2.0 / 3.0
        attach(AttachmentID.ribbon, from: attachments, to: root, position: [0, 1.74, dashboardDepth], scale: [controlScale, controlScale, controlScale])
        attach(AttachmentID.news, from: attachments, to: root, position: [-1.38, 1.08, dashboardDepth], scale: [panelScale, panelScale, panelScale])
        attach(AttachmentID.chart, from: attachments, to: root, position: [1.44, 1.08, dashboardDepth], scale: [panelScale, panelScale, panelScale])
        attach(AttachmentID.slider, from: attachments, to: root, position: [0, 0.36, dashboardDepth], scale: [controlScale, controlScale, controlScale])
        attach(AttachmentID.callout, from: attachments, to: root, position: [0, 1.08, dashboardDepth], scale: [panelScale, panelScale, panelScale])
    }

    private static func attach(_ id: String, from attachments: RealityViewAttachments, to root: Entity, position: SIMD3<Float>, scale: SIMD3<Float>) {
        guard let entity = attachments.entity(for: id) else { return }
        if entity.parent == nil {
            root.addChild(entity)
        }
        entity.position = position
        entity.scale = scale
        entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    }

    private static func makeGlobeSystem(viewModel: CommodityIntelligenceViewModel) -> Entity {
        let root = Entity()
        root.name = EntityNames.globeSystem
        root.position.y = globeCenterY
        root.scale = [globeScale, globeScale, globeScale]
        root.orientation = viewModel.rotationToFocusedCoordinate()
        root.addChild(makeGlobeEntity())
        root.addChild(makeAtmosphereEntity())
        root.addChild(makeDynamicContent(viewModel: viewModel))
        return root
    }

    private static func makeGlobeEntity() -> Entity {
        let globe = Entity()
        globe.name = EntityNames.globe

        let ocean = ModelEntity(mesh: earthMesh(radius: 0.21), materials: [earthMaterial()])
        ocean.name = EntityNames.globeTouchTarget
        ocean.components.set(InputTargetComponent())
        ocean.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.214)]))
        ocean.components.set(HoverEffectComponent())
        globe.addChild(ocean)

        for land in landMasses {
            let marker = ModelEntity(mesh: .generateSphere(radius: land.radius * 0.5), materials: [landMaterial()])
            marker.position = GlobeMath.latLongTo3D(latitude: land.coordinate.latitude, longitude: land.coordinate.longitude, radius: 0.212)
            marker.scale = land.scale
            globe.addChild(marker)
        }

        for label in geoLabels {
            globe.addChild(makeGeoLabel(label))
        }
        return globe
    }

    private static func makeAtmosphereEntity() -> Entity {
        let atmosphere = ModelEntity(mesh: .generateSphere(radius: 0.221), materials: [atmosphereMaterial()])
        atmosphere.name = EntityNames.atmosphere
        atmosphere.components.set(InputTargetComponent())
        atmosphere.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.224)]))
        return atmosphere
    }

    private static func makeDynamicContent(viewModel: CommodityIntelligenceViewModel) -> Entity {
        let root = Entity()
        root.name = EntityNames.dynamic
        let arcColor = routeColor(for: viewModel.scenarioSeverity)

        for route in viewModel.currentRoutes {
            let points = GlobeMath.sphericalArc(from: route.originCoordinate, to: route.destinationCoordinate, radius: 0.225, lift: route.isChoked ? 0.10 : 0.07)
            let routeRoot = Entity()
            routeRoot.name = "Route \(route.id.uuidString)"
            for pair in zip(points.dropLast(), points.dropFirst()) {
                routeRoot.addChild(cylinderBetween(pair.0, pair.1, radius: (route.isChoked ? 0.003 : 0.002) * routeStringScale, color: arcColor))
            }
            root.addChild(routeRoot)
        }

        for (index, event) in viewModel.currentEvents.enumerated() {
            let pin = makePin(for: event, tileIndex: index)
            root.addChild(pin)
            if event == viewModel.selectedEvent {
                root.addChild(makeShockPulse(for: event, scenarioSeverity: viewModel.scenarioSeverity))
            }
        }
        return root
    }

    private static func makePin(for event: CommodityEvent, tileIndex: Int) -> Entity {
        let pinRoot = Entity()
        pinRoot.name = EntityNames.pinName(for: event)
        let position = GlobeMath.latLongTo3D(latitude: event.coordinate.latitude, longitude: event.coordinate.longitude, radius: 0.24)
        pinRoot.position = position

        let color = eventColor(event)
        let normal = normalize(position)
        let pin = ModelEntity(mesh: .generateSphere(radius: 0.0048 * globeMarkerScale), materials: [emissiveMaterial(color: color, alpha: 1.0)])
        pin.components.set(InputTargetComponent())
        pin.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.014 * globeOverlayScale)]))
        pin.name = pinRoot.name
        pinRoot.addChild(pin)

        let halo = ModelEntity(mesh: .generateSphere(radius: 0.011 * globeMarkerScale), materials: [emissiveMaterial(color: color, alpha: 0.24)])
        halo.name = "Event Halo \(event.id.uuidString)"
        pinRoot.addChild(halo)

        let glyph = makeEventGlyph(for: event, normal: normal)
        glyph.name = pinRoot.name
        pinRoot.addChild(glyph)

        let newsTile = makeEventNewsTile(for: event, normal: normal, tileIndex: tileIndex)
        pinRoot.addChild(newsTile)

        let stem = cylinderBetween([0, 0, 0], normal * -0.012, radius: 0.0009 * globeMarkerScale, color: color)
        pinRoot.addChild(stem)
        return pinRoot
    }

    private static func makeEventGlyph(for event: CommodityEvent, normal: SIMD3<Float>) -> Entity {
        let glyph = Entity()
        glyph.components.set(ViewAttachmentComponent(rootView: EventMapMarkerView(event: event)))
        glyph.position = normal * 0.018
        glyph.orientation = simd_quatf(from: [0, 0, 1], to: normal)
        let markerScale = Float(0.62) * globeOverlayScale
        glyph.scale = [markerScale, markerScale, markerScale]
        glyph.components.set(InputTargetComponent())
        glyph.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.016 * globeOverlayScale)]))
        return glyph
    }

    private static func makeEventNewsTile(for event: CommodityEvent, normal: SIMD3<Float>, tileIndex: Int) -> Entity {
        let flag = Entity()
        flag.name = "News Pin Flag \(event.id.uuidString)"

        let mast = cylinderBetween(normal * 0.006, normal * 0.070, radius: 0.0008 * globeOverlayScale, color: eventColor(event))
        flag.addChild(mast)

        let tile = Entity()
        tile.name = "News Tile \(event.id.uuidString)"
        tile.components.set(ViewAttachmentComponent(rootView: EventMapNewsTileView(event: event)))

        let tangent = stableTangent(for: normal)
        let vertical = normalize(simd_cross(normal, tangent))
        let horizontalOffset = Float(tileIndex % 2 == 0 ? -0.022 : 0.022)
        let verticalOffset = Float(tileIndex / 2) * 0.020
        tile.position = normal * 0.074 + tangent * horizontalOffset + vertical * (0.026 + verticalOffset)
        tile.orientation = simd_quatf(from: [0, 0, 1], to: -tangent)
        let tileScale = Float(0.26) * globeOverlayScale
        tile.scale = [tileScale, tileScale, tileScale]
        flag.addChild(tile)
        return flag
    }

    private static func stableTangent(for normal: SIMD3<Float>) -> SIMD3<Float> {
        let up = SIMD3<Float>(0, 1, 0)
        let east = simd_cross(up, normal)
        if simd_length(east) > 0.001 {
            return normalize(east)
        }
        return normalize(simd_cross(SIMD3<Float>(1, 0, 0), normal))
    }

    private static func makeShockPulse(for event: CommodityEvent, scenarioSeverity: Double) -> Entity {
        let root = Entity()
        root.name = EntityNames.shock
        let position = GlobeMath.latLongTo3D(latitude: event.coordinate.latitude, longitude: event.coordinate.longitude, radius: 0.242)
        root.position = position
        let pulseScale = Float(1.0 + abs(scenarioSeverity) / 90)
        for index in 0..<3 {
            let shell = ModelEntity(mesh: .generateSphere(radius: (0.0048 + Float(index) * 0.0015) * globeMarkerScale), materials: [emissiveMaterial(color: UIColor(red: 1, green: 0.09, blue: 0.27, alpha: 1), alpha: 0.16 - CGFloat(index) * 0.035)])
            shell.scale = [pulseScale, pulseScale, pulseScale]
            root.addChild(shell)
        }
        return root
    }

    private static func makeTradingArena() -> Entity {
        let root = Entity()
        root.name = "Midnight Trading Arena"

        let wallMaterial = emissiveMaterial(color: UIColor(red: 0.008, green: 0.02, blue: 0.045, alpha: 1), alpha: 0.94)
        let floorMaterial = emissiveMaterial(color: UIColor(red: 0.002, green: 0.006, blue: 0.014, alpha: 1), alpha: 0.96)

        let backdrop = ModelEntity(mesh: .generateBox(size: [3.8, 2.2, 0.02]), materials: [wallMaterial])
        backdrop.position = [0, 1.10, -1.72]
        root.addChild(backdrop)

        let leftWall = ModelEntity(mesh: .generateBox(size: [0.02, 2.2, 2.5]), materials: [wallMaterial])
        leftWall.position = [-1.9, 1.10, -0.52]
        root.addChild(leftWall)

        let rightWall = ModelEntity(mesh: .generateBox(size: [0.02, 2.2, 2.5]), materials: [wallMaterial])
        rightWall.position = [1.9, 1.10, -0.52]
        root.addChild(rightWall)

        let floor = ModelEntity(mesh: .generateBox(size: [3.8, 0.02, 2.55]), materials: [floorMaterial])
        floor.position = [0, 0.0, -0.50]
        root.addChild(floor)

        for index in 0..<18 {
            let x = Float(index - 9) * 0.18
            let height = Float((index % 5) + 1) * 0.052
            let color = index % 3 == 0 ? UIColor(red: 0.25, green: 1.0, blue: 0.66, alpha: 1) : UIColor(red: 1.0, green: 0.28, blue: 0.42, alpha: 1)
            let candle = ModelEntity(mesh: .generateBox(size: [0.022, height, 0.005]), materials: [emissiveMaterial(color: color, alpha: 0.12)])
            candle.position = [x, 0.46 + height / 2, -1.56 - Float(index % 4) * 0.035]
            root.addChild(candle)
        }
        return root
    }

    private static func makeLightRig() -> Entity {
        let root = Entity()
        let sun = DirectionalLight()
        sun.name = "Procedural Sun Terminator Light"
        sun.light.intensity = 2600
        sun.light.color = .white
        sun.orientation = simd_quatf(angle: -.pi / 5, axis: [1, 0, 0]) * simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
        root.addChild(sun)

        let cyan = PointLight()
        cyan.name = "Cyan Rim Light"
        cyan.light.intensity = 1600
        cyan.light.color = UIColor(red: 0, green: 0.90, blue: 1, alpha: 1)
        cyan.position = [-0.6, 0.5, 0.2]
        root.addChild(cyan)
        return root
    }

    private static func cylinderBetween(_ start: SIMD3<Float>, _ end: SIMD3<Float>, radius: Float, color: UIColor) -> ModelEntity {
        let delta = end - start
        let length = simd_length(delta)
        let cylinder = ModelEntity(mesh: .generateCylinder(height: max(length, 0.001), radius: radius), materials: [emissiveMaterial(color: color, alpha: color.cgColor.alpha)])
        cylinder.position = (start + end) / 2
        cylinder.orientation = simd_quatf(from: [0, 1, 0], to: normalize(delta))
        return cylinder
    }

    private static func earthMesh(radius: Float) -> MeshResource {
        let latitudeSegments = 48
        let longitudeSegments = 96
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for latIndex in 0...latitudeSegments {
            let v = Float(latIndex) / Float(latitudeSegments)
            let latitude = 90 - Double(v) * 180

            for lonIndex in 0...longitudeSegments {
                let u = Float(lonIndex) / Float(longitudeSegments)
                let longitude = -180 + Double(u) * 360
                let position = GlobeMath.latLongTo3D(latitude: latitude, longitude: longitude, radius: radius)
                positions.append(position)
                normals.append(normalize(position))
                textureCoordinates.append([u, 1 - v])
            }
        }

        for latIndex in 0..<latitudeSegments {
            for lonIndex in 0..<longitudeSegments {
                let current = UInt32(latIndex * (longitudeSegments + 1) + lonIndex)
                let next = UInt32((latIndex + 1) * (longitudeSegments + 1) + lonIndex)
                indices.append(contentsOf: [
                    current, next, current + 1,
                    current + 1, next, next + 1
                ])
            }
        }

        var descriptor = MeshDescriptor(name: "LatLong Blue Marble Earth")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        descriptor.primitives = .triangles(indices)

        return (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: radius)
    }

    private static func earthMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let blueMarble = try? TextureResource.load(named: "EarthBlueMarble") {
            material.baseColor = .init(tint: .white, texture: .init(blueMarble))
        } else {
            material.baseColor = .init(tint: UIColor(red: 0.02, green: 0.17, blue: 0.34, alpha: 1))
        }
        material.roughness = .init(floatLiteral: 0.24)
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: 0.78)
        return material
    }

    private static func landMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.08, green: 0.34, blue: 0.24, alpha: 1))
        material.roughness = .init(floatLiteral: 0.82)
        material.metallic = .init(floatLiteral: 0.0)
        return material
    }

    private static func atmosphereMaterial() -> SimpleMaterial {
        SimpleMaterial(color: UIColor(red: 0, green: 0.90, blue: 1, alpha: 0.18), isMetallic: false)
    }

    private static func emissiveMaterial(color: UIColor, alpha: CGFloat) -> UnlitMaterial {
        UnlitMaterial(color: color.withAlphaComponent(alpha))
    }

    private static func eventColor(_ event: CommodityEvent) -> UIColor {
        switch event.category {
        case .weather: UIColor(red: 1, green: 0.70, blue: 0, alpha: 1)
        case .geopolitical, .macro: UIColor(red: 0, green: 0.90, blue: 1, alpha: 1)
        case .supplyChain: event.severity >= 0 ? UIColor(red: 1, green: 0.09, blue: 0.27, alpha: 1) : UIColor(red: 0, green: 0.90, blue: 0.46, alpha: 1)
        }
    }

    private static func eventGlyph(for event: CommodityEvent) -> String {
        let headline = event.headline.lowercased()
        if headline.contains("hurricane") {
            return "🌀"
        }
        if headline.contains("drought") || headline.contains("heat") {
            return "☀️"
        }
        if headline.contains("naval") || headline.contains("blockade") {
            return "⚓️"
        }
        if headline.contains("port") || headline.contains("rerouting") || headline.contains("corridor") {
            return "🚢"
        }
        if headline.contains("mine") || headline.contains("power grid") {
            return "⚡️"
        }
        if headline.contains("central bank") || headline.contains("reserve") {
            return "🏦"
        }
        if headline.contains("currency") || headline.contains("hedge") {
            return "💱"
        }

        switch event.category {
        case .weather: return "☀️"
        case .supplyChain: return "🚢"
        case .geopolitical: return "⚠️"
        case .macro: return "◆"
        }
    }

    private static func routeColor(for scenarioSeverity: Double) -> UIColor {
        scenarioSeverity >= 0 ? UIColor(red: 1, green: 0.09, blue: 0.27, alpha: 0.78) : UIColor(red: 0, green: 0.90, blue: 0.46, alpha: 0.78)
    }

    private static func makeGeoLabel(_ label: GeoLabel) -> Entity {
        let normal = normalize(GlobeMath.latLongTo3D(latitude: label.coordinate.latitude, longitude: label.coordinate.longitude, radius: 1))
        let text = Entity()
        text.components.set(ViewAttachmentComponent(rootView: GlobeMapLabelView(label: label)))
        text.name = "Geo Label \(label.title)"
        text.position = normal * label.radius
        text.orientation = simd_quatf(from: [0, 0, 1], to: normal)
        let labelScale = label.scale * globeOverlayScale
        text.scale = [labelScale, labelScale, labelScale]
        return text
    }

    private struct GeoLabel {
        let title: String
        let coordinate: GeoCoordinate
        let radius: Float
        let fontSize: Float
        let scale: Float
        let color: UIColor
        let alpha: CGFloat
    }

    private struct GlobeMapLabelView: View {
        let label: GeoLabel

        var body: some View {
            Text(label.title)
                .font(.system(size: CGFloat(label.fontSize), weight: .bold, design: .rounded))
                .foregroundStyle(Color(uiColor: label.color).opacity(label.alpha))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(width: 124, height: 24)
                .background(.black.opacity(0.42), in: Capsule())
                .overlay(Capsule().stroke(Color(uiColor: label.color).opacity(0.52), lineWidth: 0.8))
        }
    }

    private struct EventMapMarkerView: View {
        let event: CommodityEvent

        var body: some View {
            VStack(spacing: 2) {
                Text(HorizonImmersiveView.eventGlyph(for: event))
                    .font(.system(size: 26, weight: .black))
                    .frame(width: 38, height: 38)
                    .background(markerColor.opacity(0.46), in: Circle())
                    .background(.black.opacity(0.58), in: Circle())
                    .overlay(Circle().stroke(markerColor.opacity(1.0), lineWidth: 1.8))
                    .shadow(color: markerColor.opacity(0.92), radius: 8)

                Text(event.commodity.symbol)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(markerColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.62), in: Capsule())
            }
            .frame(width: 44, height: 50)
        }

        private var markerColor: Color {
            event.mapAccentColor
        }
    }

    private struct EventMapNewsTileView: View {
        let event: CommodityEvent

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(HorizonImmersiveView.eventGlyph(for: event))
                        .font(.system(size: 13, weight: .bold))
                    Text(event.commodity.symbol)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(event.mapAccentColor)
                    Spacer(minLength: 4)
                    Text(event.volumeImpact)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(event.severity >= 0 ? Color(red: 1, green: 0.20, blue: 0.32) : Color(red: 0, green: 0.95, blue: 0.52))
                }

                Text(event.headline)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(event.metricImpact)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(8)
            .frame(width: 164, height: 78, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
            .background(Color(red: 0.02, green: 0.05, blue: 0.08).opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(event.mapAccentColor.opacity(0.74), lineWidth: 1))
            .shadow(color: event.mapAccentColor.opacity(0.30), radius: 10)
        }
    }

    private static let landMasses: [(coordinate: GeoCoordinate, radius: Float, scale: SIMD3<Float>)] = [
        (GeoCoordinate(latitude: 39, longitude: -98), 0.055, [1.8, 0.35, 1.0]),
        (GeoCoordinate(latitude: -14, longitude: -52), 0.060, [1.3, 0.42, 1.0]),
        (GeoCoordinate(latitude: 50, longitude: 15), 0.052, [1.5, 0.34, 1.0]),
        (GeoCoordinate(latitude: 23, longitude: 45), 0.060, [1.6, 0.38, 1.0]),
        (GeoCoordinate(latitude: 5, longitude: 20), 0.070, [1.4, 0.46, 1.0]),
        (GeoCoordinate(latitude: 35, longitude: 103), 0.070, [1.8, 0.38, 1.0]),
        (GeoCoordinate(latitude: -25, longitude: 134), 0.052, [1.6, 0.34, 1.0])
    ]

    private static let geoLabels: [GeoLabel] = {
        let land = UIColor(white: 0.96, alpha: 1)
        let water = UIColor(red: 0, green: 0.90, blue: 1, alpha: 1)
        let sea = UIColor(red: 0.58, green: 0.96, blue: 1, alpha: 1)
        return [
            GeoLabel(title: "North America", coordinate: GeoCoordinate(latitude: 48, longitude: -101), radius: 0.236, fontSize: 12, scale: 0.58, color: land, alpha: 0.90),
            GeoLabel(title: "South America", coordinate: GeoCoordinate(latitude: -15, longitude: -60), radius: 0.236, fontSize: 12, scale: 0.58, color: land, alpha: 0.90),
            GeoLabel(title: "Europe", coordinate: GeoCoordinate(latitude: 52, longitude: 12), radius: 0.236, fontSize: 11, scale: 0.52, color: land, alpha: 0.92),
            GeoLabel(title: "Africa", coordinate: GeoCoordinate(latitude: 2, longitude: 21), radius: 0.236, fontSize: 12, scale: 0.54, color: land, alpha: 0.92),
            GeoLabel(title: "Asia", coordinate: GeoCoordinate(latitude: 45, longitude: 90), radius: 0.236, fontSize: 13, scale: 0.58, color: land, alpha: 0.92),
            GeoLabel(title: "Australia", coordinate: GeoCoordinate(latitude: -25, longitude: 134), radius: 0.236, fontSize: 11, scale: 0.52, color: land, alpha: 0.90),
            GeoLabel(title: "Antarctica", coordinate: GeoCoordinate(latitude: -78, longitude: 25), radius: 0.236, fontSize: 10, scale: 0.50, color: land, alpha: 0.78),
            GeoLabel(title: "Pacific Ocean", coordinate: GeoCoordinate(latitude: 0, longitude: -155), radius: 0.238, fontSize: 11, scale: 0.54, color: water, alpha: 0.82),
            GeoLabel(title: "Atlantic Ocean", coordinate: GeoCoordinate(latitude: 2, longitude: -35), radius: 0.238, fontSize: 11, scale: 0.54, color: water, alpha: 0.82),
            GeoLabel(title: "Indian Ocean", coordinate: GeoCoordinate(latitude: -18, longitude: 82), radius: 0.238, fontSize: 11, scale: 0.54, color: water, alpha: 0.82),
            GeoLabel(title: "Arctic Ocean", coordinate: GeoCoordinate(latitude: 78, longitude: -10), radius: 0.238, fontSize: 10, scale: 0.50, color: water, alpha: 0.74),
            GeoLabel(title: "Southern Ocean", coordinate: GeoCoordinate(latitude: -60, longitude: 115), radius: 0.238, fontSize: 10, scale: 0.50, color: water, alpha: 0.74),
            GeoLabel(title: "Mediterranean", coordinate: GeoCoordinate(latitude: 36, longitude: 16), radius: 0.239, fontSize: 9, scale: 0.42, color: sea, alpha: 0.86),
            GeoLabel(title: "Black Sea", coordinate: GeoCoordinate(latitude: 43.5, longitude: 34), radius: 0.239, fontSize: 9, scale: 0.42, color: sea, alpha: 0.86),
            GeoLabel(title: "Red Sea", coordinate: GeoCoordinate(latitude: 20, longitude: 38), radius: 0.239, fontSize: 9, scale: 0.42, color: sea, alpha: 0.88),
            GeoLabel(title: "Arabian Sea", coordinate: GeoCoordinate(latitude: 15, longitude: 64), radius: 0.239, fontSize: 9, scale: 0.42, color: sea, alpha: 0.88),
            GeoLabel(title: "South China Sea", coordinate: GeoCoordinate(latitude: 12, longitude: 114), radius: 0.239, fontSize: 9, scale: 0.42, color: sea, alpha: 0.88),
            GeoLabel(title: "Gulf of Mexico", coordinate: GeoCoordinate(latitude: 24, longitude: -90), radius: 0.239, fontSize: 9, scale: 0.42, color: sea, alpha: 0.88)
        ]
    }()
}

private extension CommodityEvent {
    var mapAccentColor: Color {
        switch category {
        case .weather:
            Color(red: 1, green: 0.72, blue: 0)
        case .geopolitical, .macro:
            Color(red: 0, green: 0.92, blue: 1)
        case .supplyChain:
            severity >= 0 ? Color(red: 1, green: 0.12, blue: 0.28) : Color(red: 0, green: 0.94, blue: 0.50)
        }
    }
}

private enum EntityNames {
    static let root = "CME Horizon Root"
    static let globeSystem = "Globe Coordinate System"
    static let globe = "Photorealistic PBR Globe"
    static let globeTouchTarget = "Globe Rotation Touch Target"
    static let atmosphere = "Fresnel Atmosphere Glow"
    static let dynamic = "Dynamic Commodity Routes and Pins"
    static let shock = "Selected Shock Pulse"

    static func pinName(for event: CommodityEvent) -> String {
        "Pin-\(event.id.uuidString)"
    }

    static func isGlobeRotationTarget(_ name: String) -> Bool {
        name == globeTouchTarget || name == atmosphere
    }
}

private enum AttachmentID {
    static let ribbon = "commodity-ribbon"
    static let news = "news-stream"
    static let chart = "market-chart"
    static let slider = "scenario-slider"
    static let callout = "event-callout"
}
