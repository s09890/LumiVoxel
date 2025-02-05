import SwiftUI

struct ControlButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .frame(width: 60, height: 60)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .clipShape(Circle())
        }
    }
}

struct SliderView: View {
    @Binding var value: Double
    let title: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            Slider(value: $value)
        }
    }
}

struct ContentView: View {
    @State private var brightness: Double = 0.5
    @State private var hue: Double = 0.0
    @State private var rotationAngle: Double = 0
    @State private var scale: Double = 0.5  // Start at middle scale
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                HStack {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.blue)
                        Text("home")
                            .foregroundColor(.blue)
                    }
                    Spacer()
                }
                .padding()
                
                VoxelizedSceneView(rotationAngle: $rotationAngle,
                                 scale: $scale,
                                 brightness: $brightness,
                                 hue: $hue)
                    .frame(height: 300)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding()
                
                // Control buttons
                HStack(spacing: 30) {
                    // Scale down button
                    ControlButton(icon: "arrow.down.right.and.arrow.up.left") {
                        if scale > 0.125 {
                            scale -= 0.125
                        }
                    }
                    
                    // Rotation button
                    ControlButton(icon: "arrow.triangle.2.circlepath") {
                        withAnimation {
                            rotationAngle += .pi / 2
                        }
                    }
                    
                    // Scale up button
                    ControlButton(icon: "arrow.up.left.and.arrow.down.right") {
                        if scale < 1.0 {
                            scale += 0.125
                        }
                    }
                }
                
                VStack(spacing: 15) {
                    SliderView(value: $brightness,
                             title: "Brightness",
                             icon: "sun.max")
                    
                    SliderView(value: $hue,
                             title: "Hue",
                             icon: "paintpalette")
                }
                .padding()
                
                Button("Reset") {
                    brightness = 0.5
                    hue = 0.0
                    rotationAngle = 0
                    scale = 0.5
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
