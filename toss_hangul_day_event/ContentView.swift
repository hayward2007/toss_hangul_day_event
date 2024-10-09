import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @StateObject private var ocrModel = OCRModel()
    
    var body: some View {
        ZStack {
            CameraView(session: ocrModel.session) // 카메라 뷰
            TextOverlay(texts: ocrModel.recognizedTexts, mainTexts: ocrModel.mainTexts) // 인식된 텍스트 오버레이 및 좌표
        }
        .onAppear {
            ocrModel.startSession()
        }
    }
}

class OCRModel: NSObject, ObservableObject {
    @Published var recognizedTexts: [(text: String, boundingBox: CGRect)] = []
    @Published var mainTexts: [String] = []
    let session = AVCaptureSession()
    private let visionQueue = DispatchQueue(label: "visionQueue")
    
    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        // 'AVCaptureDevice.default'는 Optional 반환이므로 'guard let'으로 안전하게 언래핑합니다.
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("카메라를 찾을 수 없습니다.")
            return
        }
        
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("카메라 입력을 가져올 수 없습니다.")
            return
        }
        
        session.beginConfiguration()
        session.addInput(videoDeviceInput)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        session.addOutput(videoOutput)
        session.commitConfiguration()
        
        // 카메라 자동 초점 모드 설정
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.focusMode = .continuousAutoFocus // 자동 초점 맞추기
            videoDevice.unlockForConfiguration()
        } catch {
            print("카메라 설정 오류: \(error)")
        }
    }

    
    func startSession() {
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    private func recognizeText(in image: CGImage) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let recognizedStrings = observations.compactMap { observation -> (String, CGRect)? in
                guard let text = observation.topCandidates(1).first?.string.filter({ $0.isHangul }) else { return nil }
                let boundingBox = observation.boundingBox
                return (text, boundingBox) // 텍스트와 위치 반환
            }
            
            DispatchQueue.main.async {
                var result: [(text: String, boundingBox: CGRect)] = []
                var wordFrequency: [String: Int] = [:]
                for recognizedString in recognizedStrings {
                    if(recognizedString.0.count == 2) {
                        result.append(recognizedString)
                    }
                }
                
                for givenWord in result {
                    if(wordFrequency[givenWord.text] != nil) {
                        wordFrequency[givenWord.text]! += 1
                    } else {
                        wordFrequency.updateValue(0, forKey: givenWord.text)
                    }
                }
                
                for index in wordFrequency {
                    if(index.value > 2) {
                        self?.mainTexts.append(index.key)
                    }
                }
                
                self!.recognizedTexts = result
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
        
        context.coordinator.previewLayer = previewLayer // 미리보기 레이어 저장
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds // 뷰 크기가 변경되면 레이어 크기도 업데이트
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: CameraView
        var previewLayer: AVCaptureVideoPreviewLayer?
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
    }
}

struct TextOverlay: View {
    let texts: [(text: String, boundingBox: CGRect)]
    let mainTexts: [String]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(texts.enumerated()), id: \.offset) { index, item in
                let (text, boundingBox) = item
                if(mainTexts.contains(text)) {
                    Text(text)
                        .font(.title)
                        .foregroundColor(.green)
                        .position(self.position(for: boundingBox, in: geometry.size))
                        .background(Color.clear)
                } else {
                    Text(text)
                        .font(.title)
                        .foregroundColor(.red)
                        .position(self.position(for: boundingBox, in: geometry.size))
                        .background(Color.clear)
                }
            }
        }
    }
    
    private func position(for boundingBox: CGRect, in size: CGSize) -> CGPoint {
        return CGPoint(x: size.width * (boundingBox.origin.y), y: size.height * (boundingBox.origin.x))
//        return CGPoint(x: size.height * boundingBox.origin.y, y: size.width * boundingBox.origin.x)
//        return CGPoint(x: boundingBox.origin.x, y: boundingBox.origin.y)
    }
}

extension Character {
    var isHangul: Bool {
        return ("\u{AC00}" <= self && self <= "\u{D7A3}")
    }
}
