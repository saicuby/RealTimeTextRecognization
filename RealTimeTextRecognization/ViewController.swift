//
//  ViewController.swift
//  RealTimeTextRecognization
//
//  Created by Yusai on 2022/05/28.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {

    private var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "")
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let label: UILabel = {
        let label = UILabel()
        label.text = "analyze number"
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()
    
    private let confidenceLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    private let avCaptureSession = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(self.imageView)
        self.view.addSubview(self.label)
        self.view.addSubview(self.confidenceLabel)
        self.setupCapture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.imageView.frame = CGRect(x: 20,
                                      y: self.view.safeAreaInsets.top,
                                      width: self.view.frame.width - 40,
                                      height: self.view.frame.width - 40)

        self.label.frame = CGRect(x: 20,
                                  y: self.view.safeAreaInsets.top + (self.view.frame.width - 40) + 10,
                                  width: self.view.frame.width - 40,
                                  height: 100)
        
        self.confidenceLabel.frame = CGRect(x: 20,
                                            y: self.view.safeAreaInsets.top + (self.view.frame.width - 40) + 60,
                                            width: self.view.frame.width - 40,
                                            height: 100)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.avCaptureSession.stopRunning()
    }

    private func setupCapture() {
        self.avCaptureSession.sessionPreset = .photo

        let device = AVCaptureDevice.default(for: .video)
        let input = try! AVCaptureDeviceInput(device: device!)
        self.avCaptureSession.addInput(input)

        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: .global())

        self.avCaptureSession.addOutput(videoDataOutput)
        self.avCaptureSession.startRunning()
    }

    private func getTextObservations(pixelBuffer: CVPixelBuffer, completion: @escaping (([VNRecognizedTextObservation])->())) {
        let request = VNRecognizeTextRequest { (request, error) in
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            completion(results)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.20

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    private func getTextRectsImage(sampleBuffer: CMSampleBuffer, textObservations: [VNRecognizedTextObservation]) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        guard let pixelBufferBaseAddres = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) else {
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return nil
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))

        guard let newContext = CGContext(
            data: pixelBufferBaseAddres,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(imageBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else
        {
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return nil
        }

        textObservations.forEach{
            let rect = getUnfoldRect(normalizedRect: $0.boundingBox, targetSize: CGSize(width: width, height: height))
            let text = $0.topCandidates(1).first?.string ?? "" // topCandidates に文字列候補配列が含まれている
            self.drawRect(rect, text: text, context: newContext)
        }

        // pixelBufferにアクセス後にアンロック
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        guard let imageRef = newContext.makeImage() else { return nil }
        let image = UIImage(cgImage: imageRef, scale: 1.0, orientation: UIImage.Orientation.right)

        return image
    }

    private func getUnfoldRect(normalizedRect: CGRect, targetSize: CGSize) -> CGRect {
        return CGRect(
            x: normalizedRect.minX * targetSize.width,
            y: normalizedRect.minY * targetSize.height,
            width: normalizedRect.width * targetSize.width,
            height: normalizedRect.height * targetSize.height
        )
    }

    private func drawRect(_ rect: CGRect, text: String, context: CGContext) {
        context.setLineWidth(4.0)
        context.setStrokeColor(UIColor.green.cgColor)
        context.stroke(rect)
        context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        context.fill(rect)
        DispatchQueue.main.async {
            self.label.text = text
        }
    }
}

extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        self.getTextObservations(pixelBuffer: pixelBuffer) { [weak self] textObservations in
            guard let self = self else { return }
            let image = self.getTextRectsImage(sampleBuffer: sampleBuffer, textObservations: textObservations)
            DispatchQueue.main.async { [weak self] in
                self?.imageView.image = image
                self?.confidenceLabel.text = String(textObservations.first?.confidence ?? 0)
            }
        }
    }
}
