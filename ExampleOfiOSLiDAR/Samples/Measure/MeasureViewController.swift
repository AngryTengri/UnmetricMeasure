//
//  MeasureViewController.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/02/01.
//

import RealityKit
import ARKit
import Combine
import SceneKit

class MeasureViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    let anchorName = "ball"
    
    // Frame-driven update subscription
    private var updateSubscription: Cancellable?
    private var reusableBall: ModelEntity?
    private var ballAnchor: AnchorEntity?
    
    
    var orientation: UIInterfaceOrientation {
        guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
            fatalError()
        }
        return orientation
    }
    @IBOutlet weak var imageViewHeight: NSLayoutConstraint!
    lazy var imageViewSize: CGSize = {
        CGSize(width: view.bounds.size.width, height: imageViewHeight.constant)
    }()
    
    override func viewDidLoad() {
        func setARViewOptions() {
            arView.environment.sceneUnderstanding.options = []
            // Removed .occlusion to prevent ball from being hidden behind objects
            arView.renderOptions = [.disablePersonOcclusion, .disableDepthOfField, .disableMotionBlur]
            arView.automaticallyConfigureSession = false
        }
        func buildConfigure() -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()
            
            configuration.sceneReconstruction = .mesh
            configuration.environmentTexturing = .automatic
            configuration.planeDetection = [.horizontal]
            if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics = .sceneDepth
            }
            
            return configuration
        }
        func initARView() {
            setARViewOptions()
            let configuration = buildConfigure()
            arView.session.run(configuration)
        }
        func addGesture() {
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            arView.addGestureRecognizer(tapRecognizer)
            
            // Add long press gesture to clear balls
            let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPressRecognizer.minimumPressDuration = 1.0
            arView.addGestureRecognizer(longPressRecognizer)
        }
        func addCrosshair() {
            // Add a simple crosshair overlay to show the center of the screen
            let crosshairView = UIView()
            crosshairView.translatesAutoresizingMaskIntoConstraints = false
            crosshairView.backgroundColor = .clear
            crosshairView.isUserInteractionEnabled = false
            
            arView.addSubview(crosshairView)
            
            // Center the crosshair
            NSLayoutConstraint.activate([
                crosshairView.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
                crosshairView.centerYAnchor.constraint(equalTo: arView.centerYAnchor),
                crosshairView.widthAnchor.constraint(equalToConstant: 100),
                crosshairView.heightAnchor.constraint(equalToConstant: 60)
            ])
        }
        func createReusableBall() {
            // Create a reusable ball that will be transformed to different positions
            let ball = ModelEntity(mesh: sphereMesh,
                                   materials: [whiteMaterial])
            
            // Make the ball always render on top by setting its rendering order
            ball.components[ModelDebugOptionsComponent.self] = ModelDebugOptionsComponent(visualizationMode: .none)
            
            // Create anchor for the ball
            let anchor = AnchorEntity()
            anchor.name = anchorName
            anchor.addChild(ball)
            arView.scene.addAnchor(anchor)
            
            self.reusableBall = ball
            self.ballAnchor = anchor
            
            print("Created reusable ball for automatic raycast")
        }
        
        super.viewDidLoad()
        arView.session.delegate = self
        initARView()
        addGesture()
        addCrosshair()
        createReusableBall()
        // Run automatic raycast once per frame instead of a Timer
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.performAutomaticRaycast()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updateSubscription?.cancel()
        updateSubscription = nil
    }
    
    // MARK: - ARSessionDelegate
    
    // Removed Timer-based updates in favor of frame-driven updates
    
    func getZForward(transform: simd_float4x4) -> SIMD3<Float> {
        return SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
    }
    
    @objc
    func handleLongPress(_ sender: UILongPressGestureRecognizer) {
        if sender.state == .began {
            clearAllBalls()
        }
    }
    
    func clearAllBalls() {
        // Hide the reusable ball instead of removing it
        reusableBall?.isEnabled = false
        print("Cleared reusable ball (hidden)")
    }

    private var lastClone: ModelEntity? = nil
    private var dynamicLine: ModelEntity? = nil
    private var dynamicLineAnchor: AnchorEntity? = nil
    private var planeEntity: ModelEntity? = nil // Track the plane entity directly
    private var sharedAnchor: AnchorEntity? = nil // Shared anchor for both ball and plane
    private var measurementsAnchor: AnchorEntity? = nil // Shared anchor for static measurement entities
    // Removed guidePlane and guidePlaneAnchor

    // Cached meshes and materials to avoid re-allocations
    private lazy var sphereMesh: MeshResource = MeshResource.generateSphere(radius: 0.01)
    private lazy var lineBaseYMesh: MeshResource = MeshResource.generateBox(size: [0.004, 1.0, 0.004])
    private lazy var lineBaseZMesh: MeshResource = MeshResource.generateBox(size: [0.004, 0.004, 0.002]) // dynamic line base along Z
    private let whiteMaterial = SimpleMaterial(color: .white, isMetallic: false)
    private let redMaterial = SimpleMaterial(color: .red, isMetallic: false)
    private let blueMaterial = SimpleMaterial(color: .blue, isMetallic: false)
    private let greenMaterial = SimpleMaterial(color: .green, isMetallic: false)
    private let unlitWhiteMaterial: UnlitMaterial = {
        var m = UnlitMaterial()
        m.baseColor = .color(.white)
        m.blending = .opaque
        return m
    }()
    private let unlitBlackMaterial: UnlitMaterial = {
        var m = UnlitMaterial()
        m.baseColor = .color(.black)
        m.blending = .opaque
        return m
    }()
    private let unlitGreenMaterial: UnlitMaterial = {
        var m = UnlitMaterial()
        m.baseColor = .color(.green)
        m.blending = .opaque
        return m
    }()
    // Bus image plane support (Front_Bus follows center guide)
    private lazy var frontBusTexture: TextureResource? = try? TextureResource.load(named: "Front_Bus")
    private var frontBusEntity: ModelEntity? = nil
    // MeasuringBUS texture for dynamic line
    private lazy var measuringBusTexture: TextureResource? = {
        do {
            let texture = try TextureResource.load(named: "Bus")
            print("Successfully loaded Bus texture for dynamic line")
            return texture
        } catch {
            print("Failed to load Bus texture: \(error)")
            return nil
        }
    }()
    private lazy var guideTexture: TextureResource? = {
        // Restore guide image
        if let cg = UIImage(named: "MeasuringAimGuide 1")?.cgImage {
            return try? TextureResource.generate(from: cg, options: .init(semantic: .color))
        }
        if let cg = UIImage(named: "Guide")?.cgImage {
            return try? TextureResource.generate(from: cg, options: .init(semantic: .color))
        }
        return try? TextureResource.load(named: "Guide")
    }()

    // Smoothing state
    private var filteredBallPosition: SIMD3<Float>? = nil
    private var filteredBallRotation: simd_quatf? = nil
    private let positionSmoothingAlpha: Float = 0.2
    private let rotationSmoothingAlpha: Float = 0.15

    @objc
    func handleTap(_ sender: UITapGestureRecognizer) {
        guard let ball = reusableBall else { return }
        let worldPos = ball.position(relativeTo: nil)

        // Place new clone (unlit white)
        let clone = ModelEntity(mesh: sphereMesh,
                                materials: [unlitWhiteMaterial])
        // Make red sphere 50% smaller
        clone.scale = SIMD3<Float>(repeating: 0.5)
        let cloneAnchor = AnchorEntity(world: worldPos)
        clone.position = .zero
        cloneAnchor.addChild(clone)
        arView.scene.addAnchor(cloneAnchor)

        // Draw a static line between lastClone and this new clone
        if let previous = lastClone {
            let start = previous.position(relativeTo: nil)
            let end = worldPos
            addStaticLine(from: start, to: end)
        }

        // Update last clone
        lastClone = clone

        // No per-point bus spawning. Front_Bus will follow center guide instead.
    }

    private func addStaticLine(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        let direction = end - start
        let distance = length(direction)
        let midPoint = (start + end) / 2

        // Create shared measurements anchor if needed
        if measurementsAnchor == nil {
            let anchor = AnchorEntity()
            arView.scene.addAnchor(anchor)
            measurementsAnchor = anchor
        }
        guard let measurementsAnchor else { return }

        // Container to hold line + text at the midpoint with rotation
        let container = Entity()

        // Rotate container's +Y toward the direction
        let up = SIMD3<Float>(0, 1, 0)
        let dir = normalize(direction)
        let rotation = simd_quatf(from: up, to: dir)
        container.transform = Transform(scale: .one, rotation: rotation, translation: midPoint)

        // Line: unit length along Y, scale Y to the distance (unlit white)
        let line = ModelEntity(mesh: lineBaseYMesh, materials: [unlitWhiteMaterial])
        line.position = .zero
        line.orientation = simd_quatf()
        line.scale = SIMD3<Float>(1, distance, 1)
        container.addChild(line)

        // Text: offset upward in container local space
        // Convert to London bus units (8.38m per bus)
        let busUnits = distance / 8.38
        let text: String
        
        if busUnits < 1.0 {
            // Show as fraction for values less than 1 bus
            let fraction = busUnits
            if fraction >= 0.75 {
                text = "3/4 bus"
            } else if fraction >= 0.67 {
                text = "2/3 bus"
            } else if fraction >= 0.5 {
                text = "1/2 bus"
            } else if fraction >= 0.33 {
                text = "1/3 bus"
            } else if fraction >= 0.25 {
                text = "1/4 bus"
            } else {
                text = String(format: "%.2f bus", busUnits)
            }
        } else {
            // Show as decimal for values 1 bus or greater
            text = String(format: "%.2f bus", busUnits)
        }
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.0001,
            font: .systemFont(ofSize: 0.02),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        // Create white background plane for text - larger than text for visibility
        let backgroundPlane = MeshResource.generatePlane(width: 0.12, depth: 0.025, cornerRadius: 0.003)
        let backgroundEntity = ModelEntity(mesh: backgroundPlane, materials: [SimpleMaterial(color: .white, isMetallic: false)])
        backgroundEntity.position = SIMD3<Float>(0, 0.02, -0.01)
        backgroundEntity.orientation = simd_quatf()
        backgroundEntity.components.set(BillboardComponent())
        container.addChild(backgroundEntity)
        
        let textEntity = ModelEntity(mesh: textMesh, materials: [unlitBlackMaterial])
        textEntity.position = SIMD3<Float>(0, 0.02, 0)
        textEntity.orientation = simd_quatf()
        // Always face the camera
        textEntity.components.set(BillboardComponent())
        container.addChild(textEntity)

        measurementsAnchor.addChild(container)
    }

    private func updateDynamicLine() {
        guard let last = lastClone,
              let ball = reusableBall else { return }

        let start = ball.position(relativeTo: nil)
        let end = last.position(relativeTo: nil)
        let direction = end - start
        let distance = length(direction)
        let midPoint = (start + end) / 2

        // Create once, then update transform/scale each frame
        if dynamicLineAnchor == nil || dynamicLine == nil {
            let anchor = AnchorEntity()
            // Use a plane; set width to match the guide plane (0.1) and stretch along Z
            let baseZ: Float = 0.002
            let planeMesh = MeshResource.generatePlane(width: 0.1, depth: baseZ, cornerRadius: 0)
            
            // Create material with MeasuringBUS texture or fallback to green
            let material: Material
            if let busTexture = measuringBusTexture {
                print("Using Bus texture for dynamic line")
                var unlit = UnlitMaterial()
                unlit.baseColor = .texture(busTexture)
                unlit.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: 1.0))
                material = unlit
            } else {
                print("Bus texture not available, using green material for dynamic line")
                material = unlitGreenMaterial
            }
            
            let line = ModelEntity(mesh: planeMesh, materials: [material])
            line.position = .zero
            anchor.addChild(line)
            arView.scene.addAnchor(anchor)
            dynamicLineAnchor = anchor
            dynamicLine = line
        }

        guard let anchor = dynamicLineAnchor, let line = dynamicLine else { return }

        // Keep anchor at identity so local == world for the line
        anchor.transform = Transform()

        // Position and orient the line in world space.
        // Align local +Z with the segment direction, and twist so the plane's face (+Y) points toward the camera as much as possible.
        line.position = midPoint
        let zAxis = normalize(direction)
        // View direction from the line midpoint to the camera
        let cameraPos = arView.cameraTransform.translation
        var viewDir = SIMD3<Float>(cameraPos.x - midPoint.x, cameraPos.y - midPoint.y, cameraPos.z - midPoint.z)
        viewDir = normalize(viewDir)
        // Remove any component along the segment direction; this is the target for the plane normal
        var targetNormal = viewDir - dot(viewDir, zAxis) * zAxis
        if length_squared(targetNormal) > 1e-6 {
            targetNormal = normalize(targetNormal)
            // Build orthonormal basis: x = y × z, y = z × x to ensure orthogonality
            var xAxis = cross(targetNormal, zAxis)
            if length_squared(xAxis) < 1e-6 {
                // Degenerate case: fall back to some perpendicular
                xAxis = normalize(cross(SIMD3<Float>(0,1,0), zAxis))
            } else {
                xAxis = normalize(xAxis)
            }
            let yAxis = normalize(cross(zAxis, xAxis))
            let rot = float3x3(columns: (xAxis, yAxis, zAxis))
            line.orientation = simd_quatf(rot)
        } else {
            // Fallback to simple look-at if camera is along the segment direction
            line.look(at: end, from: midPoint, relativeTo: nil)
        }

        // Scale Z to match distance (base Z = 0.002)
        let baseZ: Float = 0.002
        line.scale = SIMD3<Float>(1, 1, max(distance / baseZ, 0))
    }

    private func performAutomaticRaycast() {
        // Create shared anchor if needed
        if sharedAnchor == nil {
            let anchor = AnchorEntity()
            arView.scene.addAnchor(anchor)
            sharedAnchor = anchor
            // Add ball and plane as children if they exist
            if let ball = reusableBall { anchor.addChild(ball) }
            if let plane = planeEntity { anchor.addChild(plane) }
        }
        guard let ball = reusableBall, let anchor = sharedAnchor else { return; }
        
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        // Prefer ARKit raycast for performance and stability
        var ballPosition: SIMD3<Float>
        var ballRotation = simd_quatf()
        let results = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any)
        if let hit = results.first {
            let t = hit.worldTransform
            let rawPosition = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            let up = SIMD3<Float>(0, 1, 0)
            let ny = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
            let rawRotation: simd_quatf = simd_length_squared(ny) > 0.000001 ? simd_quatf(from: up, to: simd_normalize(ny)) : simd_quatf()

            // Exponential smoothing for position
            if let prev = filteredBallPosition {
                ballPosition = mix(prev, rawPosition, t: positionSmoothingAlpha)
                filteredBallPosition = ballPosition
            } else {
                ballPosition = rawPosition
                filteredBallPosition = rawPosition
            }

            // Slerp smoothing for rotation
            if let prevR = filteredBallRotation {
                ballRotation = simd_slerp(prevR, rawRotation, rotationSmoothingAlpha)
                filteredBallRotation = ballRotation
            } else {
                ballRotation = rawRotation
                filteredBallRotation = rawRotation
            }
        } else if let ray = arView.ray(through: center) {
            // Fallback: project a point 2m forward from the camera ray
            let dir = simd_normalize(ray.direction)
            let rawPosition = ray.origin + dir * 2.0
            if let prev = filteredBallPosition {
                ballPosition = mix(prev, rawPosition, t: positionSmoothingAlpha)
                filteredBallPosition = ballPosition
            } else {
                ballPosition = rawPosition
                filteredBallPosition = rawPosition
            }
        } else {
            return
        }

        // Move the anchor, so both ball and plane move together
        anchor.transform = Transform(
            scale: SIMD3<Float>(repeating: 1),
            rotation: ballRotation,
            translation: ballPosition
        )
        ball.position = .zero
        ball.orientation = simd_quatf() // No local rotation, handled by anchor
        // Keep the white center sphere hidden
        ball.isEnabled = false

        // Always update or create the plane as a child of the anchor
        updatePlaneWithBall(anchor: anchor)
        
        // Update all lines to stretch to the moving ball
        updateLines(to: ballPosition)
        updateDynamicLine()

        // Ensure Front_Bus follows the center guide (shared anchor) and faces camera
        if frontBusEntity == nil, let tex = frontBusTexture {
            // Create once as a child of the shared anchor so it moves/rotates with the center guide
            let mesh = MeshResource.generatePlane(width: 0.1, height: 0.1)
            var unlit = UnlitMaterial()
            unlit.baseColor = .texture(tex)
            unlit.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: 1.0))
            let entity = ModelEntity(mesh: mesh, materials: [unlit])
            // Offset slightly along local Z to avoid z-fighting with the center plane
            entity.position = SIMD3<Float>(0, 0, 0.005)
            if let anchor = sharedAnchor {
                anchor.addChild(entity)
                frontBusEntity = entity
            }
        }
        if let bus = frontBusEntity {
            // Face camera each frame from the bus' world position
            let busPos = bus.position(relativeTo: nil)
            bus.look(at: arView.cameraTransform.translation, from: busPos, relativeTo: nil)
        }
    }
    
    private func createLine(from start: SIMD3<Float>, to end: SIMD3<Float>, attachTo anchor: AnchorEntity) {
        let direction = end - start
        let distance = length(direction)
        let midPoint = (start + end) / 2

        // Cylinder aligned along Y, we’ll rotate it to match direction
        let lineMesh = MeshResource.generateBox(size: [0.004, distance, 0.004])
        let material = SimpleMaterial(color: .blue, isMetallic: false)
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [material])

        // Position at midpoint
        lineEntity.position = midPoint

        // Rotate to face correct direction
        lineEntity.look(at: end, from: midPoint, relativeTo: nil)

        anchor.addChild(lineEntity)
    }
    
    private func updateLines(to movingBallPosition: SIMD3<Float>) {
        for link in clones {
            let start = link.clone.position(relativeTo: nil)
            let end = movingBallPosition

            let direction = end - start
            let distance = length(direction)
            let midPoint = (start + end) / 2

            // Update line scale & position
            link.line.scale = SIMD3<Float>(1, 1, distance / 0.002) // z-stretch based on distance
            link.line.position = midPoint
            link.line.look(at: end, from: midPoint, relativeTo: nil)
        }
    }
    
    private struct CloneLink {
        var clone: ModelEntity
        var line: ModelEntity
    }
    private var clones: [CloneLink] = []

    private func updatePlaneWithBall(anchor: AnchorEntity) {
        if planeEntity == nil {
            let planeMesh = MeshResource.generatePlane(width: 0.1, depth: 0.1, cornerRadius: 0)
            // Apply guide texture using an unlit material; enable transparent blending so PNG alpha is respected
            if let tex = guideTexture ?? (try? TextureResource.load(named: "Guide")) {
                var unlit = UnlitMaterial()
                unlit.baseColor = .texture(tex)
                unlit.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: 1.0))
                let plane = ModelEntity(mesh: planeMesh, materials: [unlit])
                planeEntity = plane
            } else {
                let plane = ModelEntity(mesh: planeMesh, materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
                planeEntity = plane
            }
            if let plane = planeEntity {
                anchor.addChild(plane)
            }
        }
        guard let plane = planeEntity else { return }
        plane.position = .zero // Always at anchor origin
        plane.orientation = simd_quatf() // No local rotation, handled by anchor
        plane.isEnabled = true
        // Ensure material stays assigned if the model component resets
        if let tex = guideTexture ?? (try? TextureResource.load(named: "Guide")), var unlit = plane.model?.materials.first as? UnlitMaterial {
            unlit.baseColor = .texture(tex)
            unlit.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: 1.0))
            plane.model?.materials[0] = unlit
        }
    }
}


