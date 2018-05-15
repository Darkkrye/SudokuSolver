//
//  ViewController.swift
//  Sudoku Solver
//
//  Created by Pierre on 14/05/2018.
//  Copyright © 2018 boudonpierre. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
    
    private var textDetectionRequest: VNDetectTextRectanglesRequest?
    private let session = AVCaptureSession()
    private var preview: Preview {
        return view as! Preview
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        if isAuthorized() {
            configureTextDetection()
            configureCamera()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    private func configureTextDetection() {
        textDetectionRequest = VNDetectTextRectanglesRequest(completionHandler: handleDetection)
        textDetectionRequest!.reportCharacterBoxes = true
    }

    private func configureCamera() {
        preview.session = session
        let cameraDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        var cameraDevice: AVCaptureDevice?
        for device in cameraDevices.devices {
            if device.position == .back {
                cameraDevice = device
                break
            }
        }
        
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: cameraDevice!)
            if session.canAddInput(captureDeviceInput) {
                session.addInput(captureDeviceInput)
            }
        } catch {
            print("Error occured \(error)")
            return
        }
        
        session.sessionPreset = .high
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "Buffer Queue", qos: .userInteractive, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil))
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
        preview.videoPreviewLayer.videoGravity = .resize
        session.startRunning()
    }
    
    private func handleDetection(request: VNRequest, error: Error?) {
        guard let detectionResults = request.results else {
            print("No detection results")
            return
        }
        let textResults = detectionResults.map() {
            return $0 as? VNTextObservation
        }
        if textResults.isEmpty {
            return
        }
        
        DispatchQueue.main.async {
            self.view.layer.sublayers?.removeSubrange(1...)
            let viewWidth = self.view.frame.size.width
            let viewHeight = self.view.frame.size.height
            
            for textResult in textResults {
                guard let rects = textResult?.characterBoxes else {
                    return
                }
                
                var xMin = CGFloat.greatestFiniteMagnitude
                var xMax: CGFloat = 0
                var yMin = CGFloat.greatestFiniteMagnitude
                var yMax: CGFloat = 0
                
                for rect in rects {
                    xMin = min(xMin, rect.bottomLeft.x)
                    xMax = max(xMax, rect.bottomRight.x)
                    yMin = min(yMin, rect.bottomRight.y)
                    yMax = max(yMax, rect.topRight.y)
                }
                
                let x = xMin * viewWidth
                let y = (1 - yMax) * viewHeight
                let width = (xMax - xMin) * viewWidth
                let height = (yMax - yMin) * viewHeight
                
                let layer = CALayer()
                layer.frame = CGRect(x: x, y: y, width: width, height: height)
                layer.borderWidth = 2
                layer.borderColor = UIColor.red.cgColor
                self.view.layer.addSublayer(layer)
            }
        }
    }
    
    private func isAuthorized() -> Bool {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorizationStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { (granted) in
                if granted {
                    DispatchQueue.main.async {
                        self.configureCamera()
                        self.configureTextDetection()
                    }
                }
            }
            return true
            
        case .authorized:
            return true
        default:
            return false
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        var imageRequestOptions = [VNImageOption: Any]()
        if let cameraData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            imageRequestOptions[.cameraIntrinsics] = cameraData
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: 6)!, options: imageRequestOptions)
        do {
            try imageRequestHandler.perform([textDetectionRequest!])
        } catch {
            print("Error occured => \(error)")
        }
    }
}
