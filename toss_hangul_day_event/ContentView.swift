import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @StateObject private var ocrModel = OCRModel()
    
    var body: some View {
        ZStack {
            CameraView(session: ocrModel.session) // 카메라 뷰
            TextOverlay(text: ocrModel.recognizedText) // 인식된 텍스트 오버레이
        }
        .onAppear {
            ocrModel.startSession()
        }
    }
}

class OCRModel: NSObject, ObservableObject {
    @Published var recognizedText = ""
    let session = AVCaptureSession()
    private let visionQueue = DispatchQueue(label: "visionQueue")
    
    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        
        session.beginConfiguration()
        session.addInput(videoDeviceInput)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        session.addOutput(videoOutput)
        session.commitConfiguration()
    }
    
    func startSession() {
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    private func recognizeText(in image: CGImage) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            // 한글만 필터링
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string.filter { $0.isHangul }
            }
            
            DispatchQueue.main.async {
                self?.recognizedText = recognizedStrings.joined(separator: "\n")
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko"] // 한글 언어 설정
        
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        try? requestHandler.perform([request])
    }
}

extension OCRModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        recognizeText(in: cgImage)
    }
}

struct CameraView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) { }
}

struct TextOverlay: View {
    let text: String
    
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.largeTitle)
                .padding()
                .background(Color.black.opacity(0.5))
                .foregroundColor(.white)
        }
    }
}

extension Character {
    /// 한글 문자 여부를 확인하는 함수
    var isHangul: Bool {
        return ("\u{AC00}" <= self && self <= "\u{D7A3}")
    }
}
