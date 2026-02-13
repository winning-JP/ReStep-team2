import SwiftUI
import SceneKit

// =========================
// Avatar Page (SceneKit)
// =========================
struct AvatarView: View {
    var cameraDistanceMultiplier: Float = 2.0
    @AppStorage("restep.profile.height") private var heightCm: Double = 170
    @AppStorage("restep.profile.weight") private var weightKg: Double = 65

    var body: some View {
        SceneKitView(
            modelName: "avatar",
            cameraDistanceMultiplier: cameraDistanceMultiplier,
            heightCm: heightCm,
            weightKg: weightKg
        )
            .ignoresSafeArea()
    }
}

struct AvatarThumbnailView: View {
    var cameraDistanceMultiplier: Float = 1.4

    var body: some View {
        SceneKitView(modelName: "avatar", cameraDistanceMultiplier: cameraDistanceMultiplier)
            .background(Color.clear)
    }
}

struct SceneKitView: UIViewRepresentable {
    let modelName: String
    var cameraDistanceMultiplier: Float = 2.0
    var heightCm: Double = 170
    var weightKg: Double = 65

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.isOpaque = false
        scnView.layer.isOpaque = false
        scnView.layer.backgroundColor = UIColor.clear.cgColor
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = false

        // Create scene
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scnView.scene = scene

        let containerNode = SCNNode()
        containerNode.name = "modelContainer"
        scene.rootNode.addChildNode(containerNode)

        // Load USDZ model
        if let url = Bundle.main.url(forResource: modelName, withExtension: "usdz") {
            do {
                let modelScene = try SCNScene(url: url, options: nil)

                // Get all nodes from the loaded scene
                for child in modelScene.rootNode.childNodes {
                    containerNode.addChildNode(child)
                }

                let scale = Self.scaleVector(heightCm: heightCm, weightKg: weightKg)
                containerNode.scale = scale

                // Auto-fit: calculate bounding box and adjust camera
                let (minVec, maxVec) = containerNode.boundingBox
                let width = maxVec.x - minVec.x
                let height = maxVec.y - minVec.y
                let depth = maxVec.z - minVec.z
                let maxDimension = max(width, max(height, depth))

                // Center the model
                let centerX = (minVec.x + maxVec.x) / 2
                let centerY = (minVec.y + maxVec.y) / 2
                let centerZ = (minVec.z + maxVec.z) / 2

                // Offset model to center it at origin
                containerNode.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)

                // Create camera
                let cameraNode = SCNNode()
                cameraNode.camera = SCNCamera()
                cameraNode.camera?.automaticallyAdjustsZRange = true

                // Position camera to see the whole model. Multiply to allow tuning size in SwiftUI.
                let maxScale = max(scale.x, max(scale.y, scale.z))
                let cameraDistance = maxDimension * maxScale * cameraDistanceMultiplier
                cameraNode.position = SCNVector3(0, 0, Float(cameraDistance))
                cameraNode.look(at: SCNVector3(0, 0, 0))

                scene.rootNode.addChildNode(cameraNode)

                // Store coordinator reference
                context.coordinator.containerNode = containerNode
                context.coordinator.cameraNode = cameraNode
                context.coordinator.baseMaxDimension = maxDimension

                print("✅ モデル読み込み成功: \(width) x \(height) x \(depth)")
            } catch {
                print("❌ モデル読み込み失敗: \(error)")
            }
        } else {
            print("❌ ファイルが見つかりません: \(modelName).usdz")
        }

        // Add pan gesture for horizontal rotation only
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(panGesture)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let containerNode = context.coordinator.containerNode else { return }
        let scale = Self.scaleVector(heightCm: heightCm, weightKg: weightKg)
        containerNode.scale = scale

        if let cameraNode = context.coordinator.cameraNode,
           let baseMaxDimension = context.coordinator.baseMaxDimension {
            let maxScale = max(scale.x, max(scale.y, scale.z))
            let cameraDistance = baseMaxDimension * maxScale * cameraDistanceMultiplier
            cameraNode.position = SCNVector3(0, 0, Float(cameraDistance))
        }
    }

    private static func scaleVector(heightCm: Double, weightKg: Double) -> SCNVector3 {
        let baseHeight: Double = 170
        let baseWeight: Double = 65
        let clampedHeight = max(140, min(200, heightCm))
        let clampedWeight = max(40, min(120, weightKg))

        let heightScale = Float(clampedHeight / baseHeight)
        let weightScale = Float(clampedWeight / baseWeight)

        let y = max(0.85, min(1.15, heightScale))
        let xz = max(0.8, min(1.3, weightScale))
        return SCNVector3(xz, y, xz)
    }

    class Coordinator: NSObject {
        var containerNode: SCNNode?
        var cameraNode: SCNNode?
        var baseMaxDimension: Float?
        var currentAngle: Float = 0

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let node = containerNode else { return }

            let translation = gesture.translation(in: gesture.view)

            // Horizontal rotation only (Y-axis)
            let rotationSpeed: Float = 0.01
            let newAngle = currentAngle + Float(translation.x) * rotationSpeed
            node.eulerAngles.y = newAngle

            if gesture.state == .ended {
                currentAngle = newAngle
            }
        }
    }
}
