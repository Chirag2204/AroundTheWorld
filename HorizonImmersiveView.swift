import SwiftUI
import RealityKit
import UIKit
import simd

struct HorizonImmersiveView: View {
    private static let globeCenterY: Float = 1.02

    @Environment(AppModel.self) private var appModel
    @Bindable var viewModel: CommodityIntelligenceViewModel

    var body: some View {
        RealityView { content, attachments in
            let sceneRoot = Entity()
            sceneRoot.name = EntityNames.root
            content.add(sceneRoot)

            sceneRoot.addChild(Self.makeTradingArena())
            sceneRoot.addChild(Self.makeLightRig())
            sceneRoot.addChild(Self.makeGlobeEntity())
            sceneRoot.addChild(Self.makeAtmosphereEntity())
            sceneRoot.addChild(Self.makeDynamicContent(viewModel: viewModel))
            Self.placeAttachments(in: sceneRoot, attachments: attachments)
        } update: { content, attachments in
            guard let sceneRoot = content.entities.first(where: { $0.name == EntityNames.root }) else { return }
            if let globe = sceneRoot.findEntity(named: EntityNames.globe) {
                content.animate {
                    globe.orientation = viewModel.rotationToFocusedCoordinate()
                }
            }
            if let dynamic = sceneRoot.findEntity(named: EntityNames.dynamic) {
                dynamic.removeFromParent()
            }
            sceneRoot.addChild(Self.makeDynamicContent(viewModel: viewModel))
            Self.placeAttachments(in: sceneRoot, attachments: attachments)
        } attachments: {
            Attachment(id: AttachmentID.ribbon) {
                CommodityRibbonView(viewModel: viewModel)
                    .frame(width: 430)
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
                    .frame(width: 700)
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
    }

    private static func placeAttachments(in root: Entity, attachments: RealityViewAttachments) {
        attach(AttachmentID.ribbon, from: attachments, to: root, position: [0, 1.72, -1.20], scale: [1.0, 1.0, 1.0])
        attach(AttachmentID.news, from: attachments, to: root, position: [-1.18, 0.88, -1.05], scale: [1.0, 1.0, 1.0])
        attach(AttachmentID.chart, from: attachments, to: root, position: [1.24, 0.88, -1.05], scale: [1.0, 1.0, 1.0])
        attach(AttachmentID.slider, from: attachments, to: root, position: [0, 0.16, -1.05], scale: [1.0, 1.0, 1.0])
        attach(AttachmentID.callout, from: attachments, to: root, position: [0.32, 1.18, -0.78], scale: [0.72, 0.72, 0.72])
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

    private static func makeGlobeEntity() -> Entity {
        let globe = Entity()
        globe.name = EntityNames.globe

        globe.position.y = globeCenterY

        let ocean = ModelEntity(mesh: .generateSphere(radius: 0.21), materials: [earthMaterial()])
        ocean.name = "PBR Earth Ocean Base"
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
        atmosphere.position.y = globeCenterY
        return atmosphere
    }

    private static func makeDynamicContent(viewModel: CommodityIntelligenceViewModel) -> Entity {
        let root = Entity()
        root.name = EntityNames.dynamic
        root.position.y = globeCenterY
        let arcColor = routeColor(for: viewModel.scenarioSeverity)

        for route in viewModel.currentRoutes {
            let points = GlobeMath.sphericalArc(from: route.originCoordinate, to: route.destinationCoordinate, radius: 0.225, lift: route.isChoked ? 0.10 : 0.07)
            let routeRoot = Entity()
            routeRoot.name = "Route \(route.id.uuidString)"
            for pair in zip(points.dropLast(), points.dropFirst()) {
                routeRoot.addChild(cylinderBetween(pair.0, pair.1, radius: route.isChoked ? 0.003 : 0.002, color: arcColor))
            }
            root.addChild(routeRoot)
        }

        for event in viewModel.currentEvents {
            let pin = makePin(for: event)
            root.addChild(pin)
            if event == viewModel.selectedEvent {
                root.addChild(makeShockPulse(for: event, scenarioSeverity: viewModel.scenarioSeverity))
            }
        }
        return root
    }

    private static func makePin(for event: CommodityEvent) -> Entity {
        let pinRoot = Entity()
        pinRoot.name = EntityNames.pinName(for: event)
        let position = GlobeMath.latLongTo3D(latitude: event.coordinate.latitude, longitude: event.coordinate.longitude, radius: 0.24)
        pinRoot.position = position

        let color = eventColor(event)
        let pin = ModelEntity(mesh: .generateSphere(radius: 0.013), materials: [emissiveMaterial(color: color, alpha: 0.95)])
        pin.components.set(InputTargetComponent())
        pin.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.02)]))
        pin.name = pinRoot.name
        pinRoot.addChild(pin)

        let stem = cylinderBetween([0, 0, 0], normalize(position) * -0.035, radius: 0.002, color: color)
        pinRoot.addChild(stem)
        return pinRoot
    }

    private static func makeShockPulse(for event: CommodityEvent, scenarioSeverity: Double) -> Entity {
        let root = Entity()
        root.name = EntityNames.shock
        let position = GlobeMath.latLongTo3D(latitude: event.coordinate.latitude, longitude: event.coordinate.longitude, radius: 0.242)
        root.position = position
        let pulseScale = Float(1.0 + abs(scenarioSeverity) / 90)
        for index in 0..<3 {
            let shell = ModelEntity(mesh: .generateSphere(radius: 0.026 + Float(index) * 0.016), materials: [emissiveMaterial(color: UIColor(red: 1, green: 0.09, blue: 0.27, alpha: 1), alpha: 0.22 - CGFloat(index) * 0.05)])
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

    private static func routeColor(for scenarioSeverity: Double) -> UIColor {
        scenarioSeverity >= 0 ? UIColor(red: 1, green: 0.09, blue: 0.27, alpha: 0.78) : UIColor(red: 0, green: 0.90, blue: 0.46, alpha: 0.78)
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
}

private enum EntityNames {
    static let root = "CME Horizon Root"
    static let globe = "Photorealistic PBR Globe"
    static let atmosphere = "Fresnel Atmosphere Glow"
    static let dynamic = "Dynamic Commodity Routes and Pins"
    static let shock = "Selected Shock Pulse"

    static func pinName(for event: CommodityEvent) -> String {
        "Pin-\(event.id.uuidString)"
    }
}

private enum AttachmentID {
    static let ribbon = "commodity-ribbon"
    static let news = "news-stream"
    static let chart = "market-chart"
    static let slider = "scenario-slider"
    static let callout = "event-callout"
}
