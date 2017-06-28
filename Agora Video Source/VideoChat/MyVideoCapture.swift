//
//  MyVideoCapture.swift
//  Agora Video Source
//
//  Created by GongYuhua on 2017/4/11.
//  Copyright © 2017年 Agora. All rights reserved.
//

import UIKit
import AVFoundation

protocol MyVideoCaptureDelegate {
    func myVideoCapture(_ capture: MyVideoCapture, didOutputSampleBuffer sampleBuffer: CVPixelBuffer, rotation: Int, timeStamp: Int64)
}

enum Camera: Int {
    case front = 1
    case back = 0
    
    static func defaultCamera() -> Camera {
        return .front
    }
    
    func next() -> Camera {
        switch self {
        case .back: return .front
        case .front: return .back
        }
    }
}

class MyVideoCapture: NSObject {
    
    fileprivate var delegate: MyVideoCaptureDelegate?
    private var videoView: MyVideoView
    
    private var currentCamera = Camera.defaultCamera()
    private let captureSession: AVCaptureSession
    private let captureQueue: DispatchQueue
    private var currentOutput: AVCaptureVideoDataOutput? {
        if let outputs = self.captureSession.outputs as? [AVCaptureVideoDataOutput] {
            return outputs.first
        } else {
            return nil
        }
    }
    
    init(delegate: MyVideoCaptureDelegate?, videoView: MyVideoView) {
        self.delegate = delegate
        self.videoView = videoView
        
        captureSession = AVCaptureSession()
        captureSession.usesApplicationAudioSession = false
        
        let captureOutput = AVCaptureVideoDataOutput()
        captureOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        if captureSession.canAddOutput(captureOutput) {
            captureSession.addOutput(captureOutput)
        }
        
        captureQueue = DispatchQueue(label: "MyCaptureQueue")
        
        if let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession) {
            videoView.insertCaptureVideoPreviewLayer(previewLayer: previewLayer)
        }
    }
    
    deinit {
        captureSession.stopRunning()
    }
    
    func startCapture(ofCamera camera: Camera) {
        guard let currentOutput = currentOutput else {
            return
        }
        
        currentCamera = camera
        currentOutput.setSampleBufferDelegate(self, queue: captureQueue)
        
        captureQueue.async { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.changeCaptureDevice(toIndex: camera.rawValue, ofSession: strongSelf.captureSession)
            strongSelf.captureSession.beginConfiguration()
            strongSelf.captureSession.canSetSessionPreset(AVCaptureSessionPreset640x480)
            strongSelf.captureSession.commitConfiguration()
            strongSelf.captureSession.startRunning()
        }
    }
    
    func stopCapture() {
        currentOutput?.setSampleBufferDelegate(nil, queue: nil)
        captureQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    func switchCamera() {
        stopCapture()
        currentCamera = currentCamera.next()
        startCapture(ofCamera: currentCamera)
    }
}

private extension MyVideoCapture {
    func changeCaptureDevice(toIndex index: Int, ofSession captureSession: AVCaptureSession) {
        guard let captureDevice = captureDevice(atIndex: index) else {
            return
        }
        
        let currentInputs = captureSession.inputs as? [AVCaptureDeviceInput]
        let currentInput = currentInputs?.first
        
        if let currentInput = currentInput,
            let currentInputName = currentInput.device.localizedName,
            currentInputName == captureDevice.uniqueID {
            return
        }
        
        guard let newInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            return
        }
        
        captureSession.beginConfiguration()
        if let currentInput = currentInput {
            captureSession.removeInput(currentInput)
        }
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
        }
        captureSession.commitConfiguration()
    }
    
    func captureDevice(atIndex index: Int) -> AVCaptureDevice? {
        guard let devices = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) as? [AVCaptureDevice] else {
            return nil
        }
        
        let count = devices.count
        guard count > 0, index >= 0 else {
            return nil
        }
        
        let device: AVCaptureDevice
        if index >= count {
            device = devices.last!
        } else {
            device = devices[index]
        }
        
        return device
    }
}

extension MyVideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        guard let sampleBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        DispatchQueue.main.async {[weak self] _ in
            guard let weakSelf = self else {
                return
            }
            
            weakSelf.delegate?.myVideoCapture(weakSelf, didOutputSampleBuffer: sampleBuffer, rotation: 90, timeStamp: Int64(CACurrentMediaTime()*1000))
        }
    }
}
