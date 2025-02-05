import SwiftUI
import SceneKit
import ModelIO

struct VoxelizedSceneView: UIViewRepresentable {
    @Binding var rotationAngle: Double
    @Binding var scale: Double
    @Binding var brightness: Double
    @Binding var hue: Double
    
    let gridSize: Int = 8
    let gridSpacing: Float = 0.5
    
    // Cache the original model data
    private class ModelData {
        var vertices: [SCNVector3] = []
        var bounds: (min: SCNVector3, max: SCNVector3) = (SCNVector3Zero, SCNVector3Zero)
    }
    
    // Store model data using UIKit's associated objects pattern
    private static var modelDataKey = "modelData"
    
    private func getOrCreateModelData(for sceneView: SCNView) -> ModelData {
        if let modelData = objc_getAssociatedObject(sceneView, &Self.modelDataKey) as? ModelData {
            return modelData
        }
        let modelData = ModelData()
        objc_setAssociatedObject(sceneView, &Self.modelDataKey, modelData, .OBJC_ASSOCIATION_RETAIN)
        return modelData
    }
    
    // Snap rotation to 90-degree increments
    private func snapRotation(_ angle: Double) -> Float {
        let snapAngle = Double.pi / 2 // 90 degrees
        let snappedAngle = round(angle / snapAngle) * snapAngle
        return Float(snappedAngle)
    }
    
    // Snap scale to ensure voxels align with grid
    private func snapScale(_ scale: Double) -> Float {
        // Limit maximum scale to ensure model stays within grid
        let maxScale = 1.0 // Maximum scale is 1.0 (full grid size)
        let minScale = 0.125 // Minimum scale is 1/8 of grid size
        let snapIncrement = 0.125 // Scale in 1/8th increments
        
        // Clamp and snap the scale value
        let clampedScale = min(max(scale, minScale), maxScale)
        let snappedScale = round(clampedScale / snapIncrement) * snapIncrement
        
        return Float(snappedScale)
    }
    
    // Snap position to grid intersections
    private func snapToGrid(_ position: SCNVector3) -> SCNVector3 {
        let snapX = round(position.x / gridSpacing) * gridSpacing
        let snapY = round(position.y / gridSpacing) * gridSpacing
        let snapZ = round(position.z / gridSpacing) * gridSpacing
        return SCNVector3(snapX, snapY, snapZ)
    }
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = SCNScene()
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = .clear
        
        // Add static grid
        let gridNode = createGridCube()
        sceneView.scene?.rootNode.addChildNode(gridNode)
        
        // Create container node for the voxelized model
        let containerNode = SCNNode()
        containerNode.name = "modelContainer"
        sceneView.scene?.rootNode.addChildNode(containerNode)
        
        if let modelURL = Bundle.main.url(forResource: "sample", withExtension: "stl") {
            if let scene = try? SCNScene(url: modelURL, options: nil),
               let modelNode = scene.rootNode.childNodes.first {
                
                guard let geometry = modelNode.geometry else { return sceneView }
                let vertices = extractVertices(from: geometry)
                let bounds = calculateBounds(vertices: vertices)
                
                // Store original model data
                let modelData = getOrCreateModelData(for: sceneView)
                modelData.vertices = vertices
                modelData.bounds = bounds
                
                // Initial voxelization
                updateVoxelization(for: sceneView, scale: Float(scale))
            }
        }
        
        addLighting(to: sceneView)
        return sceneView
    }
    
    func updateUIView(_ sceneView: SCNView, context: Context) {
        if let containerNode = sceneView.scene?.rootNode.childNode(withName: "modelContainer", recursively: false) {
            // Apply rotation
            containerNode.eulerAngles.y = snapRotation(rotationAngle)
            
            // Update the voxelization with current scale
            updateVoxelization(for: sceneView, scale: Float(scale))
            
            // Update colors after revoxelization
            containerNode.childNodes.forEach { node in
                if let material = node.geometry?.firstMaterial {
                    let color = UIColor(hue: CGFloat(hue),
                                      saturation: 1.0,
                                      brightness: 1.0,
                                      alpha: 1.0)
                    material.diffuse.contents = color
                    material.emission.contents = color.withAlphaComponent(brightness)
                }
            }
        }
    }
    
    private func updateVoxelization(for sceneView: SCNView, scale: Float) {
        guard let containerNode = sceneView.scene?.rootNode.childNode(withName: "modelContainer", recursively: false) else { return }
        
        // Clear existing voxels
        containerNode.childNodes.forEach { $0.removeFromParentNode() }
        
        // Get cached model data
        let modelData = getOrCreateModelData(for: sceneView)
        
        // Calculate effective grid size based on scale
        let effectiveGridSize = Int(round(Float(gridSize) * scale))
        
        // Voxelize with adjusted grid size
        let voxels = voxelize(vertices: modelData.vertices,
                            bounds: modelData.bounds,
                            effectiveGridSize: effectiveGridSize)
        
        // Create new voxel representation
        createVoxelModel(voxels: voxels,
                        in: containerNode,
                        effectiveGridSize: effectiveGridSize)
    }
    
    private func createVoxelModel(voxels: [[[Bool]]], in containerNode: SCNNode, effectiveGridSize: Int) {
        let halfSize = Float(gridSize) * gridSpacing / 2
        let spacing = Float(gridSize) / Float(effectiveGridSize) * gridSpacing
        
        for x in 0..<voxels.count {
            for y in 0..<voxels[x].count {
                for z in 0..<voxels[x][y].count {
                    if voxels[x][y][z] {
                        let sphere = SCNSphere(radius: 0.05)
                        let material = SCNMaterial()
                        let color = UIColor(hue: CGFloat(hue),
                                          saturation: 1.0,
                                          brightness: 1.0,
                                          alpha: 1.0)
                        material.diffuse.contents = color
                        material.emission.contents = color.withAlphaComponent(brightness)
                        sphere.materials = [material]
                        
                        let node = SCNNode(geometry: sphere)
                        let xPos = Float(x) * spacing - halfSize + (spacing / 2)
                        let yPos = Float(y) * spacing - halfSize + (spacing / 2)
                        let zPos = Float(z) * spacing - halfSize + (spacing / 2)
                        node.position = snapToGrid(SCNVector3(xPos, yPos, zPos))
                        containerNode.addChildNode(node)
                    }
                }
            }
        }
    }
    
    private func voxelize(vertices: [SCNVector3],
                         bounds: (min: SCNVector3, max: SCNVector3),
                         effectiveGridSize: Int) -> [[[Bool]]] {
        var voxels = Array(repeating: Array(repeating: Array(repeating: false,
                                                            count: effectiveGridSize),
                                          count: effectiveGridSize),
                          count: effectiveGridSize)
        
        let boundsSize = SCNVector3(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z
        )
        
        vertices.forEach { vertex in
            let normalizedX = (vertex.x - bounds.min.x) / boundsSize.x
            let normalizedY = (vertex.y - bounds.min.y) / boundsSize.y
            let normalizedZ = (vertex.z - bounds.min.z) / boundsSize.z
            
            let x = Int(round(normalizedX * Float(effectiveGridSize - 1)))
            let y = Int(round(normalizedY * Float(effectiveGridSize - 1)))
            let z = Int(round(normalizedZ * Float(effectiveGridSize - 1)))
            
            if x >= 0 && x < effectiveGridSize &&
                y >= 0 && y < effectiveGridSize &&
                z >= 0 && z < effectiveGridSize {
                voxels[x][y][z] = true
            }
        }
        
        return voxels
    }

    private func createGridCube() -> SCNNode {
        let gridNode = SCNNode()
        let lineColor = UIColor.gray.withAlphaComponent(0.5)
        let halfSize = Float(gridSize) * gridSpacing / 2
        
        for i in 0...gridSize {
            let pos = Float(i) * gridSpacing - halfSize
            
            // X lines
            for j in 0...gridSize {
                let yPos = Float(j) * gridSpacing - halfSize
                let line = createLine(
                    from: SCNVector3(pos, yPos, -halfSize),
                    to: SCNVector3(pos, yPos, halfSize),
                    color: lineColor
                )
                gridNode.addChildNode(line)
            }
            
            // Y lines
            for j in 0...gridSize {
                let zPos = Float(j) * gridSpacing - halfSize
                let line = createLine(
                    from: SCNVector3(-halfSize, pos, zPos),
                    to: SCNVector3(halfSize, pos, zPos),
                    color: lineColor
                )
                gridNode.addChildNode(line)
            }
            
            // Z lines
            for j in 0...gridSize {
                let xPos = Float(j) * gridSpacing - halfSize
                let line = createLine(
                    from: SCNVector3(xPos, -halfSize, pos),
                    to: SCNVector3(xPos, halfSize, pos),
                    color: lineColor
                )
                gridNode.addChildNode(line)
            }
        }
        
        return gridNode
    }
    
    private func createLine(from: SCNVector3, to: SCNVector3, color: UIColor) -> SCNNode {
        let line = SCNGeometry.line(from: from, to: to)
        let lineNode = SCNNode(geometry: line)
        lineNode.geometry?.firstMaterial?.diffuse.contents = color
        return lineNode
    }
    
    // Helper methods for vertex extraction and voxelization
    private func extractVertices(from geometry: SCNGeometry) -> [SCNVector3] {
        var vertices: [SCNVector3] = []
        
        if let geometrySource = geometry.sources(for: .vertex).first {
            let stride = geometrySource.dataStride / MemoryLayout<Float>.size
            let count = geometrySource.vectorCount
            let buffer = geometrySource.data
            
            buffer.withUnsafeBytes { rawPtr in
                let ptr = rawPtr.baseAddress!.assumingMemoryBound(to: Float.self)
                for i in 0..<count {
                    let offset = i * stride
                    let x = ptr[offset]
                    let y = ptr[offset + 1]
                    let z = ptr[offset + 2]
                    vertices.append(SCNVector3(x, y, z))
                }
            }
        }
        
        return vertices
    }
    
    private func calculateBounds(vertices: [SCNVector3]) -> (min: SCNVector3, max: SCNVector3) {
        var minX: Float = .infinity
        var minY: Float = .infinity
        var minZ: Float = .infinity
        var maxX: Float = -.infinity
        var maxY: Float = -.infinity
        var maxZ: Float = -.infinity
        
        vertices.forEach { vertex in
            minX = min(minX, vertex.x)
            minY = min(minY, vertex.y)
            minZ = min(minZ, vertex.z)
            maxX = max(maxX, vertex.x)
            maxY = max(maxY, vertex.y)
            maxZ = max(maxZ, vertex.z)
        }
        
        return (SCNVector3(minX, minY, minZ), SCNVector3(maxX, maxY, maxZ))
    }
    
    
    private func addLighting(to sceneView: SCNView) {
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 100
        
        let omniLight = SCNNode()
        omniLight.light = SCNLight()
        omniLight.light?.type = .omni
        omniLight.position = SCNVector3(x: 0, y: 10, z: 10)
        
        sceneView.scene?.rootNode.addChildNode(ambientLight)
        sceneView.scene?.rootNode.addChildNode(omniLight)
    }
}

// Extension for line creation
extension SCNGeometry {
    class func line(from: SCNVector3, to: SCNVector3) -> SCNGeometry {
        let vertices: [SCNVector3] = [from, to]
        let source = SCNGeometrySource(vertices: vertices)
        
        let indices: [Int32] = [0, 1]
        let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: data,
                                       primitiveType: .line,
                                       primitiveCount: 1,
                                       bytesPerIndex: MemoryLayout<Int32>.size)
        
        return SCNGeometry(sources: [source], elements: [element])
    }
}
