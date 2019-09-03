//
//  ViewController.swift
//  BlueAR-BodyDetection
//
//  Created by Hakan Karakaya on 3.09.2019.
//  Copyright © 2019 Hakan Karakaya. All rights reserved.
//

import UIKit
import RealityKit
import ARKit
import Combine
import Firebase
import McPicker

class ViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var loadCaptureButton: RoundedButton!
    @IBOutlet weak var captureButton: RoundedButton!
    @IBOutlet weak var animationsButton: UIButton!
    
    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [-1.0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    
    // A tracked raycast which is used to place the character accurately
    // in the scene wherever the user taps.
    var placementRaycast: ARTrackedRaycast?
    var tapPlacementAnchor: AnchorEntity?
    
    var isCapture: Bool = false
    var isCapturePlay: Bool = false
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.session.delegate = self
        
        // If the iOS device doesn't support body tracking, raise a developer error for
        // this unhandled case.
        guard ARBodyTrackingConfiguration.isSupported else {
            print("This feature is not supported your device!")
            return
        }
        
        // Run a body tracking configration.
        let configuration = ARBodyTrackingConfiguration()
        
        arView.session.run(configuration)
        arView.scene.addAnchor(characterAnchor)
        
        loadCaptureButton.isEnabled = false
        animationsButton.isHidden = true
        
        // Asynchronously load the 3D character.
        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "character/robot").sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Error: Unable to load model: \(error.localizedDescription)")
                }
                cancellable?.cancel()
        }, receiveValue: { (character: Entity) in
            if let character = character as? BodyTrackedEntity {
                // Scale the character to human size
                character.scale = [1.0, 1.0, 1.0]
                self.character = character
                cancellable?.cancel()
            } else {
                print("Error: Unable to load model as BodyTrackedEntity")
            }
        })
        
        getAnimationDataFromFirebaseDB()
    }
    
    // MARK: - ARSessionDelegateMethods
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // if the character does not play the captured data, it continues to move with the human
        if !isCapturePlay {
            for anchor in anchors {
                guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
                
                // Update the position of the character anchor's position.
                let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
                
                if isCapture {
                    capturedAnchorDataArray.append(bodyAnchor)
                }
                
                characterAnchor.position = bodyPosition + characterOffset
                // Also copy over the rotation of the body anchor, because the skeleton's pose
                // in the world is relative to the body anchor's rotation.
                characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
                
                if let character = character, character.parent == nil {
                    // Attach the character to its anchor as soon as
                    // 1. the body anchor was detected and
                    // 2. the character was loaded.
                    characterAnchor.addChild(character)
                }
            }
        }
    }
    
    // MARK: - Button actions
    
    @IBAction func captureButtonTapped(_ sender: Any) {
        if isCapture {
            captureButton.setTitle("Start Capturing", for: .normal)
            saveCapturedData()
        }else {
            loadCaptureButton.isEnabled = false
            captureButton.setTitle("Stop Capturing", for: .normal)
            capturedAnchorDataArray.removeAll()
        }
        
        isCapture = !isCapture
    }
    
    @IBAction func loadCaptureButtonTapped(_ button: UIButton) {
        loadCapturedData()
    }
    
    @IBAction func animationsButtonTapped(_ sender: Any) {
        // Show animations list picker
        let mcPicker = McPicker(data: [self.downloadedAnimations.keys.compactMap { $0 }])
        
        let customLabel = UILabel()
        customLabel.textAlignment = .center
        customLabel.textColor = .black
        mcPicker.label = customLabel // Set custom label
        
        mcPicker.show { (selections: [Int : String]) in
            if let id = selections[0] {
                self.loadCapturedDataFromURL(id: id, url: self.downloadedAnimations[id] ?? "")
            }
        }
    }
    
    // MARK: - Saving and Loading captured data
    
    lazy var mapSaveURL: URL = {
        do {
            return try FileManager.default
                .url(for: .documentDirectory,
                     in: .userDomainMask,
                     appropriateFor: nil,
                     create: true)
                .appendingPathComponent("map.arexperience")
        } catch {
            fatalError("Can't get file save URL: \(error.localizedDescription)")
        }
    }()
    
    // Called opportunistically to verify that map data can be loaded from filesystem.
    var mapDataFromFile: Data? {
        return try? Data(contentsOf: mapSaveURL)
    }
    
    var capturedAnchorDataArray: [ARBodyAnchor] = []
    
    func saveCapturedData() {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: capturedAnchorDataArray, requiringSecureCoding: true)
            try data.write(to: self.mapSaveURL, options: [.noFileProtection])
            DispatchQueue.main.async {
                self.loadCaptureButton.isEnabled = true
                // Share captured data
                self.shareCapturedDataFile()
            }
        } catch {
            print("Can't save map: \(error.localizedDescription)")
        }
    }
    
    func loadCapturedDataFromURL(id:String, url: String) {
        
        DownloadManager.sharedInstance.getAnimationDataFromURL(id: id, modelURL: url) { (downloadedData) in
            guard let data = downloadedData else {return}
            
            do {
                let screenCentre : CGPoint = CGPoint(x: self.arView.bounds.midX, y: self.arView.bounds.midY)
                
                let arHitTestResults : [ARHitTestResult] = self.arView.hitTest(screenCentre, types: [.featurePoint])
                
                if let closestResult = arHitTestResults.first {
                    // Get Coordinates of HitTest
                    let transform : matrix_float4x4 = closestResult.worldTransform
                    
                    // Set up some properties
                    self.character?.position = simd_make_float3(transform.columns.3)
                }
                
                let map = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! [ARBodyAnchor]
                self.frame = 0
                self.capturedAnchorDataArray = map
                self.playCapturedAnimation()
            } catch {
                print("Can't unarchive ARBodyAnchor from file data: \(error)")
            }
        }
    }
    
    func loadCapturedData(){
        guard let data = mapDataFromFile
            else { print("Map data should already be verified to exist before Load button is enabled."); return; }
        do {
            self.capturedAnchorDataArray = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! [ARBodyAnchor]
            self.frame = 0
            self.playCapturedAnimation()
        } catch {
            print("Can't unarchive ARBodyAnchor from file data: \(error)")
        }
    }
    
    //MARK: -Share capture data file
    
    func shareCapturedDataFile(){
        var filesToShare = [Any]()
        // Add the path of the file to the Array
        filesToShare.append(self.mapSaveURL)
        // Make the activityViewContoller which shows the share-view
        let activityViewController = UIActivityViewController(activityItems: filesToShare, applicationActivities: nil)
        // Show the share-view
        self.present(activityViewController, animated: true, completion: nil)
    }
    
    // MARK: - Play captured data
    
    // Captured da playing frame
    var frame: Int = 0
    // play frames at time intervals
    var capturePlayTimer: Timer?
    
    func playCapturedAnimation() {
        isCapturePlay = true
        capturePlayTimer?.invalidate()
        capturePlayTimer = Timer.scheduledTimer(timeInterval: 0.30, target: self, selector: #selector(playFrame), userInfo: nil, repeats: true)
    }
    
    @objc func playFrame() {
        if self.frame < self.capturedAnchorDataArray.count {
            self.playCapturedFrame(capturedData: self.capturedAnchorDataArray[self.frame])
            self.frame+=1
        }
        else{
            isCapturePlay = false
            capturePlayTimer!.invalidate()
        }
    }
    
    func playCapturedFrame(capturedData anchor: ARBodyAnchor){
        //        for anchor in capturedData {
        // Update the position of the character anchor's position.
        let bodyPosition = simd_make_float3(anchor.transform.columns.3)
        
        characterAnchor.position = bodyPosition + characterOffset
        // Also copy over the rotation of the body anchor, because the skeleton's pose
        // in the world is relative to the body anchor's rotation.
        characterAnchor.orientation = Transform(matrix: anchor.transform).rotation
        
        if let character = character, character.parent == nil {
            // Attach the character to its anchor as soon as
            // 1. the body anchor was detected and
            // 2. the character was loaded.
            characterAnchor.addChild(character)
        }
    }
    
    // MARK: - Get animation data from Firebase DB
    
    var downloadedAnimations: [String:String] = [:]
    
    func getAnimationDataFromFirebaseDB(){
        Database.database().reference().child("CharacterAnimations").observe(.value, with: { (snapshot) in
            if snapshot.exists() {
                
                guard let objects = snapshot.value as? [String : AnyObject] else {return}
                self.animationsButton.isHidden = false
                
                for object in objects {
                    guard let values = object.value as? [String : String] else {return}
                    
                    guard let id = values["id"] else {return}
                    guard let url = values["animationURL"] else {return}
                    
                    self.downloadedAnimations.updateValue(url, forKey: id)
                }
            }else {
                
            }
        })
    }
}
