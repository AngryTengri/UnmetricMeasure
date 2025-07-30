//
//  CollisionViewController.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/02/01.
//

import RealityKit
import ARKit
import Combine
import SceneKit

class CollisionViewController: UIViewController, ARSessionDelegate {
    
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
            let ball = ModelEntity(mesh: .generateSphere(radius: 0.02),
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
    
    
    
    @objc
    func handleTap(_ sender: UITapGestureRecognizer) {
        // Toggle automatic raycast on/off with tap
        if raycastTimer?.isValid == true {
            // Stop automatic raycast
            raycastTimer?.invalidate()
            raycastTimer = nil
            print("Stopped automatic raycast")
            
            // Hide the reusable ball
            reusableBall?.isEnabled = false
        } else {
            // Start automatic raycast
            startAutomaticRaycast()
            
            // Show the reusable ball
            reusableBall?.isEnabled = true
        }
    }
    
    private func performAutomaticRaycast() {
        guard let ball = reusableBall else { return }
        
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let ray = arView.ray(through: center) else { return }
        
        let dir = simd_normalize(ray.direction)
        let hits = arView.scene.raycast(
            origin: ray.origin,
            direction: dir,
            length: 10.0,
            query: .nearest
        )
        
        if let hit = hits.first {
            ball.setPosition(hit.position, relativeTo: nil) // world space
            ball.isEnabled = true
            return
        }
        
        // Fallback: 2 m straight ahead if the mesh isn't ready yet
        ball.setPosition(ray.origin + dir * 2.0, relativeTo: nil)
        ball.isEnabled = true
    }
}
