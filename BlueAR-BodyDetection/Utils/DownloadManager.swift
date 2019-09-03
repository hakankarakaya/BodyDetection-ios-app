//
//  DownloadManager.swift
//  BlueAR-BodyDetection
//
//  Created by Hakan Karakaya on 3.09.2019.
//  Copyright © 2019 Hakan Karakaya. All rights reserved.
//

import Foundation
import Alamofire
import ZIPFoundation
import SceneKit

class DownloadManager: NSObject {
  let modelsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  
  // Create a singleton instance
  static let sharedInstance: DownloadManager = { return DownloadManager() }()
  
  //MARK: Get model SCNNode
  func getAnimationDataFromURL(id: String, modelURL zipURL: String, completion: @escaping (Data?) -> Void) {
    // Check that assets for that model are not already downloaded
    let fileManager = FileManager.default
    let dirForModel = modelsDirectory.appendingPathComponent(id)
    let dirExists = fileManager.fileExists(atPath: dirForModel.path)
    if dirExists {
      completion(loadAnimationDataFromDisk(id))
    } else {
      downloadAnimationZipFileFromURL(from: zipURL, at: id) {
        if let url = $0 {
          print("Downloaded and unzipped at: \(url.absoluteString)")
          completion(self.loadAnimationDataFromDisk(id))
        } else {
          print("Download Error!")
          completion(nil)
        }
      }
    }
  }
  
  // MARK: If model is exist return model SCNNode
  func loadAnimationDataFromDisk(_ id: String) -> Data? {
    let fileManager = FileManager.default
    let dirForModel = modelsDirectory.appendingPathComponent(id)
    do {
      let files = try fileManager.contentsOfDirectory(atPath: dirForModel.path)
      if let arexperienceFile = files.first(where: { $0.hasSuffix("arexperience") }) {

        return try? Data(contentsOf: dirForModel.appendingPathComponent(arexperienceFile))
       
      } else {
        print("No arexperience file in directory: \(dirForModel.path)")
        return nil
      }
    } catch {
      return nil
    }
  }
  
  // MARK: Download the zip file containing the model and texture
  func downloadAnimationZipFileFromURL(from zipURL: String, at destFileName: String, completion: ((URL?) -> Void)?) {
    print("Downloading \(zipURL)")
    let fullDestName = destFileName + ".zip"
    
    let destination: DownloadRequest.DownloadFileDestination = { _, _ in
      let fileURL = self.modelsDirectory.appendingPathComponent(fullDestName)
      return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
    }
    
    Alamofire.download(zipURL, to: destination).response { response in
      let error = response.error
      if error == nil {
        if let filePath = response.destinationURL?.path {
          let filePathString = NSString(string: filePath)
          let id = NSString(string: filePathString.lastPathComponent).deletingPathExtension
          
          print("File downloaded at: \(filePath)")
          
          let fileManager = FileManager()
          let sourceURL = URL(fileURLWithPath: filePath)
          var destinationURL = self.modelsDirectory
          destinationURL.appendPathComponent(id)
          do {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: sourceURL, to: destinationURL)
            completion?(destinationURL)
          } catch {
            completion?(nil)
            print("Extraction error: \(error)")
          }
        } else {
          completion?(nil)
          print("File path not found")
        }
      } else {
        // Handle error
        completion?(nil)
      }
    }
  }
}



