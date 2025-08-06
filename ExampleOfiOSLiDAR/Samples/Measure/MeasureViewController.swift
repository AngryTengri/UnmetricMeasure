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
    
    // Timer for automatic raycast shooting
    private var raycastTimer: Timer?
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
        startAutomaticRaycast()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        raycastTimer?.invalidate()
        raycastTimer = nil
    }
    
    // MARK: - ARSessionDelegate
    
    private func startAutomaticRaycast() {
        // Start automatic raycast every 0.02 seconds (50 times per second)
        raycastTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            self?.performAutomaticRaycast()
        }
        print("Started automatic raycast shooting (every 0.02 seconds)")
    }
    
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
    private var guidePlane: ModelEntity?
    private var guidePlaneAnchor: AnchorEntity?

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

        // Remove old line and anchor if they exist
        if let anchor = dynamicLineAnchor {
            arView.scene.removeAnchor(anchor)
            dynamicLineAnchor = nil
            dynamicLine = nil
        }

        // Create fresh anchor + line at correct midpoint each frame
        let lineMesh = MeshResource.generateBox(size: [0.004, distance, 0.004]) // Y-axis is the long axis
        let line = ModelEntity(mesh: lineMesh, materials: [SimpleMaterial(color: .green, isMetallic: false)])
        line.position = .zero

        // Rotate Y-axis to match direction
        let up = SIMD3<Float>(0, 1, 0)
        let dir = normalize(direction)
        if abs(dot(up, dir)) < 0.999 {
            let axis = normalize(cross(up, dir))
            let dotValue = max(min(dot(up, dir), 1.0), -1.0)
            let angle = acos(dotValue)
            line.orientation = simd_quatf(angle: angle, axis: axis)
        }

        // Anchor at midpoint and add
        let anchor = AnchorEntity(world: midPoint)
        anchor.addChild(line)
        arView.scene.addAnchor(anchor)

        dynamicLineAnchor = anchor
        dynamicLine = line
    }

    private func spawnPlaneAtBall(position: SIMD3<Float>, normal: SIMD3<Float>) {
        // Remove old plane if it exists
        if let anchor = guidePlaneAnchor {
            arView.scene.removeAnchor(anchor)
        }
        // Create a simple horizontal plane (10cm x 10cm)
        let planeMesh = MeshResource.generatePlane(width: 0.1, depth: 0.1)
        let material = SimpleMaterial(color: .yellow, isMetallic: false)
        let plane = ModelEntity(mesh: planeMesh, materials: [material])
        plane.position = .zero // Centered on anchor

        // Compute rotation: align plane's Y axis with the normal
        let up = SIMD3<Float>(0, 1, 0)
        let axis = simd_normalize(simd_cross(up, normal))
        let angle = acos(simd_dot(up, simd_normalize(normal)))
        let rotation = simd_quatf(angle: angle, axis: axis)

        // Offset the plane so it's tangent to the bottom of the ball
        let ballRadius: Float = 0.01
        let planePosition = position - normal * ballRadius

        // Anchor at the offset position and orientation
        let anchor = AnchorEntity(world: planePosition)
        anchor.orientation = rotation
        anchor.addChild(plane)
        arView.scene.addAnchor(anchor)

        // Store references
        guidePlane = plane
        guidePlaneAnchor = anchor
    }


    private func performAutomaticRaycast() {
        guard let ball = reusableBall else { return }
        
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let ray = arView.ray(through: center) else { return }
        
        let dir = simd_normalize(ray.direction)
        let hits = arView.scene.raycast(origin: ray.origin, direction: dir, length: 10.0, query: .nearest)

        var ballPosition = ray.origin + dir * 2.0
        if let hit = hits.first {
            ballPosition = hit.position
            if let anchor = guidePlaneAnchor {
                let ballRadius: Float = 0.01
                let planePosition = hit.position - hit.normal * ballRadius
                anchor.position = planePosition
                // Update orientation
                let up = SIMD3<Float>(0, 1, 0)
                let axis = simd_normalize(simd_cross(up, hit.normal))
                let angle = acos(simd_dot(up, simd_normalize(hit.normal)))
                anchor.orientation = simd_quatf(angle: angle, axis: axis)
                guidePlane?.isEnabled = true
            } else {
                spawnPlaneAtBall(position: hit.position, normal: hit.normal)
            }
        }

        ball.setPosition(ballPosition, relativeTo: nil)
        ball.isEnabled = true
        
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
}


