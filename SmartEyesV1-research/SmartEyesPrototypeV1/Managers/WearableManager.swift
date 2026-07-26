import Foundation
import Combine
import UIKit
import MWDATCore
import MWDATCamera

@MainActor
public class WearableManager: ObservableObject {
    public static let shared = WearableManager()
    
    // Published states for SwiftUI integration
    @Published public var isRegistered: Bool = false
    @Published public var registrationState: String = "Unregistered"
    @Published public var connectedDevices: [String] = []
    @Published public var isStreaming: Bool = false
    @Published var streamStateDescription: String = "Stopped"
    @Published public var currentFrame: UIImage? = nil
    @Published public var errorMessage: String? = nil
    @Published public var isConnecting: Bool = false
    
    // Simulation / Mock mode properties
    @Published public var isMockMode: Bool = false
    private var mockTimer: Timer?
    private var mockFrameIndex = 0
    private let mockImages = ["inspection_gauge", "exit_door", "pipe_valves", "clean_pipe"]
    
    // SDK Reference
    private var wearables: any WearablesInterface {
        return Wearables.shared
    }
    
    private var activeSession: DeviceSession?
    private var activeStream: MWDATCamera.Stream?
    private var cancellables = Set<AnyCancellable>()
    private var frameListenerToken: (any AnyListenerToken)?
    private var stateListenerToken: (any AnyListenerToken)?
    private var errorListenerToken: (any AnyListenerToken)?
    private var photoListenerToken: (any AnyListenerToken)?
    @Published public var lastCapturedPhoto: UIImage? = nil
    private var rawDiscoveredDevices: [String] = []
    private var sessionStateTask: Task<Void, Never>?
    
    private init() {
        #if targetEnvironment(simulator)
        self.isMockMode = true
        self.registrationState = "Mock Mode Active"
        self.isRegistered = true
        self.connectedDevices = ["Meta Glasses (Simulated)"]
        #else
        configureWearables()
        setupListeners()
        #endif
    }
    
    // MARK: - SDK Lifecycle
    
    private func configureWearables() {
        do {
            try Wearables.configure()
            self.errorMessage = nil
        } catch {
            self.errorMessage = "SDK Configuration Error: \(error.localizedDescription)"
            print("Failed to configure Wearables SDK: \(error)")
        }
    }
    
    private func setupListeners() {
        // Observe Registration State Changes
        Task {
            for await state in wearables.registrationStateStream() {
                self.isRegistered = (state == .registered)
                self.registrationState = "\(state)"
                print("Registration state updated: \(state)")
            }
        }
        
        // Observe Device Stream
        Task {
            for await devices in wearables.devicesStream() {
                await MainActor.run {
                    self.rawDiscoveredDevices = devices
                    self.connectedDevices = devices.map { "Glasses (ID: \($0.prefix(6)))" }
                    print("Devices updated: \(devices.count) discovered. Raw IDs: \(devices)")
                }
            }
        }
    }
    
    // MARK: - Discovery Helpers
    
    private func waitForDiscoveredDevice(timeout: TimeInterval = 10.0) async -> String? {
        print("Checking discovered devices...")
        if let first = rawDiscoveredDevices.first {
            print("Device already discovered: \(first)")
            return first
        }
        
        print("No device discovered yet. Waiting up to \(timeout) seconds for device to connect/be discovered...")
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // Sleep 0.5s
            } catch {
                return nil
            }
            
            if let first = rawDiscoveredDevices.first {
                print("Device discovered after waiting: \(first)")
                return first
            }
        }
        
        print("Timeout waiting for device. Discovered devices is empty.")
        return nil
    }
    
    private func observeSessionState(session: DeviceSession) {
        sessionStateTask?.cancel()
        sessionStateTask = Task { [weak self] in
            for await state in session.stateStream() {
                guard let self = self else { return }
                print("Session state observer: \(state)")
                if state == .stopped {
                    await MainActor.run {
                        if self.activeSession === session {
                            self.activeSession = nil
                        }
                    }
                    return
                }
            }
        }
    }
    
    // MARK: - Registration Methods
    
    public func registerDevice() {
        if isMockMode {
            self.isRegistered = true
            self.registrationState = "registered (mock)"
            return
        }
        
        Task {
            do {
                try await wearables.startRegistration()
                self.errorMessage = nil
            } catch {
                self.errorMessage = "Registration Error: \(error.localizedDescription)"
                print("Failed to start registration: \(error)")
            }
        }
    }
    
    public func unregisterDevice() {
        if isMockMode {
            self.isRegistered = false
            self.registrationState = "unregistered (mock)"
            self.stopStream()
            return
        }
        
        Task {
            do {
                try await wearables.startUnregistration()
                self.stopStream()
                self.errorMessage = nil
            } catch {
                self.errorMessage = "Unregistration Error: \(error.localizedDescription)"
                print("Failed to start unregistration: \(error)")
            }
        }
    }
    
    public func handleCallbackURL(_ url: URL) async {
        if isMockMode { return }
        
        do {
            _ = try await wearables.handleUrl(url)
            self.errorMessage = nil
            print("Successfully handled URL callback: \(url)")
        } catch {
            self.errorMessage = "Callback Handling Error: \(error.localizedDescription)"
            print("Failed to handle callback URL: \(error)")
        }
    }
    
    // MARK: - Streaming Controls
    
    public func startStream() {
        guard !isStreaming else { return }
        self.isConnecting = true
        self.errorMessage = nil
        
        if isMockMode {
            startMockStreaming()
            return
        }
        
        Task {
            do {
                // Request Camera Permission if needed
                let cameraStatus = try await wearables.requestPermission(.camera)
                guard cameraStatus == .granted else {
                    self.isConnecting = false
                    self.errorMessage = "Camera permission denied by user."
                    return
                }
                
                // Allow Bluetooth L2CAP channel connection to stabilize after deep-link transition
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                let session: DeviceSession
                if let existingSession = self.activeSession, existingSession.state == .started {
                    session = existingSession
                    print("Reusing existing active session in started state.")
                } else {
                    if let staleSession = self.activeSession {
                        print("Stopping stale session before starting new one.")
                        staleSession.stop()
                        self.activeSession = nil
                    }
                    
                    // Wait for a device to be discovered (up to 10 seconds)
                    guard let deviceId = await waitForDiscoveredDevice(timeout: 10.0) else {
                        self.isConnecting = false
                        self.isStreaming = false
                        self.errorMessage = "No eligible Meta Glasses discovered. Make sure they are turned on and nearby."
                        return
                    }
                    
                    // Select device using SpecificDeviceSelector for the discovered device
                    let selector = SpecificDeviceSelector(device: deviceId)
                    print("Creating new device session for device: \(deviceId)")
                    let newSession = try wearables.createSession(deviceSelector: selector)
                    self.activeSession = newSession
                    session = newSession
                    
                    // Start observing session states
                    observeSessionState(session: newSession)
                    
                    // Start Session
                    print("Starting session connection...")
                    try newSession.start()
                    
                    // Wait for session to reach .started state
                    var started = false
                    for await state in newSession.stateStream() {
                        print("Session state connection progress: \(state)")
                        if state == .started {
                            started = true
                            break
                        }
                        if state == .stopped {
                            break
                        }
                    }
                    
                    guard started else {
                        self.isConnecting = false
                        self.isStreaming = false
                        self.errorMessage = "Failed to start device session connection."
                        return
                    }
                }
                
                // Setup stream configuration
                let config = StreamConfiguration(
                    videoCodec: .raw,
                    resolution: .low,    // 360 x 640 - Low resolution reduces bandwidth to the absolute minimum
                    frameRate: 2         // 2 FPS minimizes bandwidth, helping high-res photos transmit without triggering watchdog timeouts
                )
                
                print("Adding stream to started session...")
                guard let stream = try session.addStream(config: config) else {
                    self.isConnecting = false
                    self.isStreaming = false
                    self.errorMessage = "Failed to create camera stream capability."
                    return
                }
                self.activeStream = stream
                
                // Set up event listeners
                setupStreamListeners(stream: stream)
                
                // Start Stream
                print("Starting camera stream...")
                await stream.start()
                
                self.isStreaming = true
                self.isConnecting = false
                print("Meta Glasses streaming started successfully")
            } catch {
                self.isConnecting = false
                self.isStreaming = false
                self.errorMessage = "Session Error: \(error.localizedDescription)"
                print("Failed to start device session: \(error)")
            }
        }
    }
    
    private func setupStreamListeners(stream: MWDATCamera.Stream) {
        // Listen to stream state updates
        self.stateListenerToken = stream.statePublisher.listen { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                self.streamStateDescription = "\(state)"
                if state == .streaming {
                    self.isStreaming = true
                } else if state == .stopped || state == .paused {
                    self.isStreaming = false
                }
            }
        }
        
        // Listen to raw video frame callbacks
        self.frameListenerToken = stream.videoFramePublisher.listen { [weak self] frame in
            guard let self = self else { return }
            let uiImage = frame.makeUIImage()
            Task { @MainActor in
                self.currentFrame = uiImage
            }
        }
        
        // Listen to stream errors
        self.errorListenerToken = stream.errorPublisher.listen { [weak self] error in
            guard let self = self else { return }
            Task { @MainActor in
                self.errorMessage = "Stream Error: \(error.localizedDescription)"
                print("Stream error received: \(error)")
            }
        }
        
        // Listen to high-resolution photo data captures
        self.photoListenerToken = stream.photoDataPublisher.listen { [weak self] photoData in
            guard let self = self else { return }
            print("Received high-resolution photo data from glasses: \(photoData.data.count) bytes")
            if let image = UIImage(data: photoData.data) {
                Task { @MainActor in
                    self.lastCapturedPhoto = image
                    // Save to Photos library for quality inspection
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    print("Saved high-res captured photo to Photo Library. Size: \(image.size)")
                }
            }
        }
    }
    
    public func stopStream() {
        self.isConnecting = false
        
        if isMockMode {
            stopMockStreaming()
            return
        }
        
        // Release listener tokens
        frameListenerToken = nil
        stateListenerToken = nil
        errorListenerToken = nil
        photoListenerToken = nil
        self.lastCapturedPhoto = nil
        
        if let stream = activeStream {
            let streamToStop = stream
            self.activeStream = nil
            Task {
                await streamToStop.stop()
            }
        }
        
        if let session = activeSession {
            print("Stopping active session to disconnect completely...")
            session.stop()
            self.activeSession = nil
        }
        
        self.isStreaming = false
        self.streamStateDescription = "Stopped"
        self.currentFrame = nil
    }
    
    // MARK: - Photo Capture Interface
    
    public func capturePhoto() async -> UIImage? {
        if isMockMode {
            print("Mock mode: capturing current mock frame as photo.")
            return currentFrame
        }
        
        guard let stream = activeStream, isStreaming else {
            print("Cannot capture photo: stream is not active.")
            return nil
        }
        
        print("Triggering high-resolution photo capture on wearables stream...")
        self.lastCapturedPhoto = nil
        
        let success = stream.capturePhoto(format: .jpeg)
        guard success else {
            print("Failed to request photo capture on stream.")
            return nil
        }
        
        // Wait for lastCapturedPhoto to become non-nil (timeout: 6 seconds)
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 6.0 {
            if lastCapturedPhoto != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // Sleep 100ms
        }
        
        if lastCapturedPhoto == nil {
            print("Timeout waiting for high-res photo from glasses.")
        }
        
        let capturedImage = lastCapturedPhoto
        
        // Wait a brief moment to let state publisher update in case of connection drop
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        if !self.isStreaming {
            print("Stream stopped or disconnected during photo capture; auto-resuming stream...")
            self.startStream()
        }
        
        return capturedImage
    }
    
    // MARK: - Simulation/Mock Methods
    
    private func startMockStreaming() {
        self.isConnecting = false
        self.isStreaming = true
        self.streamStateDescription = "Streaming (mock)"
        
        // Timer fires every 0.2s (~5 FPS for simulation)
        mockTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.generateMockFrame()
            }
        }
    }
    
    private func stopMockStreaming() {
        mockTimer?.invalidate()
        mockTimer = nil
        self.isStreaming = false
        self.streamStateDescription = "Stopped"
        self.currentFrame = nil
    }
    
    private func generateMockFrame() {
        // Generates a mock frame with a ticking clock and overlay to verify real-time feel
        let size = CGSize(width: 504, height: 896)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Base dark background
        context.setFillColor(UIColor(red: 0.1, green: 0.11, blue: 0.13, alpha: 1.0).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Dynamic grid lines to simulate inspection view overlay
        context.setStrokeColor(UIColor.green.withAlphaComponent(0.2).cgColor)
        context.setLineWidth(1)
        for x in stride(from: 0, to: size.width, by: 40) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: 0, to: size.height, by: 40) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.strokePath()
        
        // Rotating central crosshair
        let center = CGPoint(x: size.width/2, y: size.height/2)
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(2)
        context.addArc(center: center, radius: 60, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.move(to: CGPoint(x: center.x - 80, y: center.y))
        context.addLine(to: CGPoint(x: center.x + 80, y: center.y))
        context.move(to: CGPoint(x: center.x, y: center.y - 80))
        context.addLine(to: CGPoint(x: center.x, y: center.y + 80))
        context.strokePath()
        
        // Mocking changing text / values (e.g. FPS / status)
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        let dateStr = df.string(from: Date())
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.green
        ]
        
        let statusStr = "DEV SIMULATOR: CONNECTED"
        let valStr = "FPS: 15.0  |  BW: EXCELLENT"
        
        statusStr.draw(at: CGPoint(x: 20, y: 40), withAttributes: textAttributes)
        valStr.draw(at: CGPoint(x: 20, y: 70), withAttributes: textAttributes)
        dateStr.draw(at: CGPoint(x: 20, y: 100), withAttributes: textAttributes)
        
        // Draw simulated object box in the center
        context.setStrokeColor(UIColor.orange.cgColor)
        context.setLineWidth(3)
        let boxRect = CGRect(x: center.x - 100, y: center.y - 100, width: 200, height: 200)
        context.stroke(boxRect)
        
        let objLabel = "INSPECTING..."
        let objAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.orange
        ]
        objLabel.draw(at: CGPoint(x: boxRect.minX, y: boxRect.minY - 25), withAttributes: objAttributes)
        
        if let image = UIGraphicsGetImageFromCurrentImageContext() {
            self.currentFrame = image
        }
    }
    
    // Allows toggling mock mode manually in developer settings
    public func toggleMockMode() {
        stopStream()
        self.isMockMode.toggle()
        if isMockMode {
            self.isRegistered = true
            self.registrationState = "Mock Mode Active"
            self.connectedDevices = ["Meta Glasses (Simulated)"]
        } else {
            self.isRegistered = false
            self.registrationState = "Unregistered"
            self.connectedDevices = []
            configureWearables()
            setupListeners()
        }
    }
}
