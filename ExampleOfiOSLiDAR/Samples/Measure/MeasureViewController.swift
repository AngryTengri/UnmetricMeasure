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
            arView.environment.sceneUnderstanding.options.insert(.physics)
            arView.renderOptions = [.disablePersonOcclusion, .disableDepthOfField, .disableMotionBlur]
            arView.automaticallyConfigureSession = false
        }
        func buildConfigure() -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()
            
            configuration.sceneReconstruction = .meshWithClassification
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
            let ball = ModelEntity(mesh: .generateSphere(radius: 0.01),
                                   materials: [SimpleMaterial(color: .white, isMetallic: false)])
            
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
    // Removed guidePlane and guidePlaneAnchor

    @objc
    func handleTap(_ sender: UITapGestureRecognizer) {
        guard let ball = reusableBall else { return }
        let worldPos = ball.position(relativeTo: nil)

        // Place new clone
        let clone = ModelEntity(mesh: .generateSphere(radius: 0.01),
                                materials: [SimpleMaterial(color: .red, isMetallic: false)])
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
    }

    private func addStaticLine(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        let direction = end - start
        let distance = length(direction)
        let midPoint = (start + end) / 2

        // Line entity
        let lineMesh = MeshResource.generateBox(size: [0.004, distance, 0.004]) // Y-axis is length
        let line = ModelEntity(mesh: lineMesh, materials: [SimpleMaterial(color: .blue, isMetallic: false)])
        line.position = .zero

        // Anchor for line and text
        let lineAnchor = AnchorEntity(world: midPoint)

        // Rotate line Y-axis → direction
        let up = SIMD3<Float>(0, 1, 0)
        let dir = normalize(direction)
        if abs(dot(up, dir)) < 0.999 {
            let axis = normalize(cross(up, dir))
            let angle = acos(max(min(dot(up, dir), 1.0), -1.0))
            line.orientation = simd_quatf(angle: angle, axis: axis)
        }

        // Add line
        lineAnchor.addChild(line)

        // Text: create at midpoint and lift slightly upward (world offset)
        let text = String(format: "%.2f m", distance)
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.0001,
            font: .systemFont(ofSize: 0.02),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let textEntity = ModelEntity(mesh: textMesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])

        // Position text above line (lift upward relative to world)
        let worldOffset = SIMD3<Float>(0, 0.02, 0) // raise 2cm above midpoint
        textEntity.position = worldOffset

        // Match line rotation instead of billboarding
        textEntity.orientation = line.orientation

        // Add text to same anchor
        lineAnchor.addChild(textEntity)
        arView.scene.addAnchor(lineAnchor)
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
            let lineMesh = MeshResource.generateBox(size: [0.004, 0.004, 0.002]) // base length along Z = 0.002
            let line = ModelEntity(mesh: lineMesh, materials: [SimpleMaterial(color: .green, isMetallic: false)])
            line.position = .zero
            anchor.addChild(line)
            arView.scene.addAnchor(anchor)
            dynamicLineAnchor = anchor
            dynamicLine = line
        }

        guard let anchor = dynamicLineAnchor, let line = dynamicLine else { return }

        // Keep anchor at identity so local == world for the line
        anchor.transform = Transform()

        // Position and orient the line in world space, then RealityKit composes with identity anchor
        line.position = midPoint
        line.look(at: end, from: midPoint, relativeTo: nil)

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
        guard let ray = arView.ray(through: center) else { return }
        
        let dir = simd_normalize(ray.direction)
        let hits = arView.scene.raycast(origin: ray.origin, direction: dir, length: 10.0, query: .nearest)

        var ballPosition = ray.origin + dir * 2.0
        var ballRotation = simd_quatf()
        if let hit = hits.first {
            ballPosition = hit.position
            // Compute rotation from hit normal using quaternion-from-to (no acos)
            let up = SIMD3<Float>(0, 1, 0)
            let n = simd_normalize(hit.normal)
            ballRotation = simd_quatf(from: up, to: n)
        }

        // Move the anchor, so both ball and plane move together
        anchor.transform = Transform(
            scale: SIMD3<Float>(repeating: 1),
            rotation: ballRotation,
            translation: ballPosition
        )
        ball.position = .zero
        ball.orientation = simd_quatf() // No local rotation, handled by anchor
        ball.isEnabled = true

        // Always update or create the plane as a child of the anchor
        updatePlaneWithBall(anchor: anchor)
        
        // Update all lines to stretch to the moving ball
        updateLines(to: ballPosition)
        updateDynamicLine()
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
            let planeMesh = MeshResource.generatePlane(width: 0.1, depth: 0.1)
            let plane = ModelEntity(mesh: planeMesh, materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
            planeEntity = plane
            anchor.addChild(plane)
        }
        guard let plane = planeEntity else { return }
        plane.position = .zero // Always at anchor origin
        plane.orientation = simd_quatf() // No local rotation, handled by anchor
        plane.isEnabled = true
    }
}


