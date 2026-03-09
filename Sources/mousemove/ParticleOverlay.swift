import AppKit
import MetalKit
import QuartzCore

@MainActor
protocol MovementVisualizer: Sendable {
    func moveTo(_ point: CGPoint) async
    func explodeSupernova() async
}

@MainActor
final class ParticleOverlay: NSObject, MTKViewDelegate, MovementVisualizer {
    static let shared = ParticleOverlay()
    private var window: NSWindow!
    private var mtkView: MTKView!
    
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    
    private var currentPoint: CGPoint = CGPoint(x: -10000, y: -10000)
    private var velocity: CGPoint = .zero
    private var lastTime: CFTimeInterval = 0
    private var startTime: CFTimeInterval = 0
    
    private var isExploding: Bool = false
    private var explosionStartTime: CFTimeInterval? = nil
    
    private let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float2 mousePos;
        float2 velocity;
        float time;
        float explosionProgress;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    float hash(float2 p) {
        return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453123);
    }

    float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float a = hash(i);
        float b = hash(i + float2(1.0, 0.0));
        float c = hash(i + float2(0.0, 1.0));
        float d = hash(i + float2(1.0, 1.0));
        float2 u = f*f*(3.0-2.0*f);
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    float fbm(float2 p) {
        float f = 0.0;
        f += 0.5000 * noise(p); p = p * 2.02;
        f += 0.2500 * noise(p); p = p * 2.03;
        f += 0.1250 * noise(p); p = p * 2.01;
        f += 0.0625 * noise(p);
        return f;
    }

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(0)]]) {
        VertexOut out;
        float2 offsets[6] = {
            float2(-1, -1), float2( 1, -1), float2(-1,  1),
            float2( 1, -1), float2( 1,  1), float2(-1,  1)
        };
        float2 offset = offsets[vertexID];
        
        float size = 1200.0; // quad half-size in pixels 
        float2 quadPos = uniforms.mousePos + offset * size;
        float2 ndc = (quadPos / uniforms.resolution) * 2.0 - 1.0;
        
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = offset; 
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(0)]]) {
        float speed = min(length(uniforms.velocity), 100.0);
        float2 dir = speed > 0.1 ? normalize(uniforms.velocity) : float2(0, 1);
        
        float2 localUv = in.uv * 7.5; 
        
        float expProg = uniforms.explosionProgress;
        
        // Physics of supernova: Implosion collapse (0.0 -> 0.15), shockwave (0.15 -> 0.4), lingering light traces (0.4 -> 1.0)
        float implosion = smoothstep(0.0, 0.15, expProg) * (1.0 - smoothstep(0.15, 0.2, expProg));
        float explosion = smoothstep(0.15, 1.0, expProg);
        
        // Scale fireball: collapse into a singularity then violently expand outward 500%
        float scale = 1.0 - implosion * 0.95 + explosion * 5.0;
        
        // Swirling distortion logic before and during burst
        float swirlDist = length(localUv);
        float angle = atan2(localUv.y, localUv.x);
        
        // Add extreme vortex spiraling mostly during the implosion/early explosion
        float swirl = sin(swirlDist * 10.0 - uniforms.time * 20.0) * (implosion * 3.0 + explosion * 0.5);
        angle += swirl;
        
        // Rotate local coordinates based on the vortex
        float2 rotatedUv = float2(cos(angle), sin(angle)) * swirlDist;
        localUv = rotatedUv / scale;
        
        float dotDir = dot(localUv, dir);
        float2 perpUv = localUv - dir * dotDir;
        
        float tailLength = speed * 0.2 * (1.0 - expProg); // shrink tail while exploding
        if (dotDir < 0.0 && speed > 0.1) {
            dotDir = dotDir / (1.0 + tailLength);
        }
        
        localUv = dir * dotDir + perpUv;
        
        // Recalculate distance AFTER tail scale
        float dist = length(localUv);
        
        float2 flowDir = speed > 0.1 ? dir : float2(0, 1);
        
        float2 radialDir = dist > 0.01 ? (localUv / dist) : float2(0, 1);
        float2 nUv = localUv * 3.5 - flowDir * uniforms.time * 6.0;
        
        // Physical blast wave pushing noise radially outward (Shatter force)
        nUv -= radialDir * explosion * 15.0;
        
        // Base Fractal Noise
        float n1 = fbm(nUv);
        float n2 = fbm(nUv * 2.0 + float2(uniforms.time * 2.0));
        float noiseVal = (n1 + n2 * 0.5) / 1.5;
        
        // Eject random huge jagged chunks into space during the explosion
        float chunkNoise = fbm(nUv * 1.5 + radialDir * 5.0 + float2(uniforms.time * 5.0));
        noiseVal += explosion * chunkNoise * 2.5; 
        
        float baseRadius = 0.35;
        
        // The jaggedness of the edge increases drastically
        float d = dist + (0.5 - noiseVal) * (0.5 + explosion * 3.0);
        
        float mask = smoothstep(baseRadius + 0.3, baseRadius - 0.1, d);
        float core = smoothstep(baseRadius - 0.1, baseRadius - 0.4, d);
        
        // Generate outward light rays directly from the core when exploding
        float rayNoise = fbm(radialDir * 4.0 + float2(dist * 0.5, -uniforms.time * 10.0));
        float lightRays = smoothstep(0.4, 0.7, rayNoise) * explosion * (1.0 - smoothstep(0.2, 0.8, expProg));
        lightRays *= smoothstep(0.0, 0.5, dist); // Start rays slightly outside the dense core
        
        // Absolute preserved rich blue colors (no white wash-out)
        float3 darkBlue = float3(0.01, 0.15, 0.8);
        float3 mainBlue = float3(0.05, 0.6, 1.0);
        float3 coreWhite = float3(0.85, 0.95, 1.0);
        float3 cyanRay = float3(0.3, 0.9, 1.0);
        
        float3 color = mix(darkBlue, mainBlue, smoothstep(baseRadius + 0.1, baseRadius - 0.1, d));
        // Fade the white hot-core out so the explosion burns out as pure plasma blue
        color = mix(color, coreWhite, core * (1.0 - explosion * 0.8));
        
        // Add Light Rays Bursting
        color += cyanRay * lightRays * 2.0;
        
        // Implosion flash precisely at the tiny dense center
        color += float3(0.7, 0.9, 1.0) * implosion * smoothstep(0.1, 0.0, dist);
        
        // Add a giant blinding additive flash right at the "bang" point (0.15 to 0.3)
        float bangFlash = smoothstep(0.1, 0.15, expProg) * (1.0 - smoothstep(0.15, 0.3, expProg));
        color += float3(0.8, 0.9, 1.0) * bangFlash * smoothstep(1.5, 0.0, dist);
        
        float alpha = mask * smoothstep(0.9, 0.2, dist);
        alpha += lightRays * 0.5; // Ensure rays have alpha
        
        // Keep the star visible until the tail end of the shockwave
        alpha *= (1.0 - smoothstep(0.3, 1.0, explosion));
        
        // Fix hard edges of the quad: force alpha to 0 at the farthest limits of our UV space
        float edgeFade = smoothstep(1.0, 0.7, length(in.uv));
        alpha *= edgeFade;
        
        return float4(color * alpha, alpha);
    }
    """
    
    class TransparentMTKView: MTKView {
        override var isOpaque: Bool { false }
    }
    
    func install() {
        guard let mtlDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }
        self.device = mtlDevice
        self.commandQueue = device.makeCommandQueue()
        
        let screenRect = NSScreen.screens.map { $0.frame }.reduce(NSRect.zero) { $0.union($1) }
        
        window = NSWindow(
            contentRect: screenRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        
        mtkView = TransparentMTKView(frame: screenRect, device: device)
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        mtkView.layer?.isOpaque = false
        mtkView.layer?.backgroundColor = NSColor.clear.cgColor
        
        mtkView.delegate = self
        // High refresh rate syncing natively
        mtkView.preferredFramesPerSecond = 120
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertexFunction = library.makeFunction(name: "vertex_main"),
                  let fragmentFunction = library.makeFunction(name: "fragment_main") else {
                fatalError("Failed to find shader functions")
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Error compiling Metal shader: \(error)")
        }
        
        window.contentView = mtkView
        window.makeKeyAndOrderFront(nil)
        
        startTime = CACurrentMediaTime()
        lastTime = startTime
    }
    
    func moveTo(_ point: CGPoint) {
        let mainHeight = NSScreen.main?.frame.height ?? 1080
        let screenRect = window.frame
        let nsY = mainHeight - point.y
        let nsX = point.x
        
        let localPoint = CGPoint(x: nsX - screenRect.minX, y: nsY - screenRect.minY)
        
        let now = CACurrentMediaTime()
        let dt = max(0.001, now - lastTime)
        
        isExploding = false
        explosionStartTime = nil
        
        if currentPoint.x > -5000 { // Ignore the initial off-screen start
            let dx = localPoint.x - currentPoint.x
            let dy = localPoint.y - currentPoint.y
            let frameDt = dt * 60.0
            
            // Smoothly integrate velocity to prevent jitter spikes
            let targetVelocity = CGPoint(x: dx / frameDt, y: dy / frameDt)
            velocity.x = velocity.x * 0.5 + targetVelocity.x * 0.5
            velocity.y = velocity.y * 0.5 + targetVelocity.y * 0.5
        }
        
        currentPoint = localPoint
        lastTime = now
    }
    
    func explodeSupernova() {
        if !isExploding && currentPoint.x > -5000 {
            isExploding = true
            explosionStartTime = CACurrentMediaTime()
        }
    }
    
    func hideInstantaneously() {
        if !isExploding {
            currentPoint.x = -10000
            velocity = .zero
        }
    }
    
    // MARK: - MTKViewDelegate
    
    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    nonisolated func draw(in view: MTKView) {
        DispatchQueue.main.async {
            self.render(in: view)
        }
    }
    
    private func render(in view: MTKView) {
        // Natural velocity decay
        velocity.x *= 0.85
        velocity.y *= 0.85
        
        var explosionProgress: Float = 0.0
        if isExploding, let expStart = explosionStartTime {
            let elapsed = CACurrentMediaTime() - expStart
            // 1.0 seconds long explosion
            explosionProgress = Float(min(1.0, elapsed / 1.0))
            
            if explosionProgress >= 1.0 {
                // Done exploding, hide it completely
                currentPoint.x = -10000
                isExploding = false
                explosionStartTime = nil
                velocity = .zero
            }
        }
        
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Removing the hide fireball logic entirely. Let it stay visible always until exploded or initialized
        if currentPoint.x < -4000 && !isExploding {
            // Uninitialized, just clear màn
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        let scale = Float(view.window?.backingScaleFactor ?? 1.0)
        var uniformsBuffer: [Float] = [
            Float(view.drawableSize.width), Float(view.drawableSize.height),
            Float(currentPoint.x) * scale, Float(currentPoint.y) * scale,
            Float(velocity.x) * scale, Float(velocity.y) * scale,
            Float(CACurrentMediaTime() - startTime), explosionProgress
        ]
        
        encoder.setVertexBytes(&uniformsBuffer, length: MemoryLayout<Float>.stride * 8, index: 0)
        encoder.setFragmentBytes(&uniformsBuffer, length: MemoryLayout<Float>.stride * 8, index: 0)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
