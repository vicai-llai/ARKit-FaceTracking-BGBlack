//
//  ViewController.swift
//  FaceTracking-BGBlack
//
//  Created by Toshihiro Goto on 2017/12/11.
//  Copyright © 2017年 Toshihiro Goto. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

struct FaceMesh: Codable {
    let timestamp: Double
    let faceMeshFrame: [String: Double]
}

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    // Face Tracking の起点となるノードとジオメトリを格納するノード
    private var faceNode = SCNNode()
    private var virtualFaceNode = SCNNode()
    
    // シリアルキューの設定
    private let serialQueue = DispatchQueue(label: "com.test.FaceTracking.serialSceneKitQueue")
    
    // Json data
    var faceMeshList = [FaceMesh]()
    var prevTimestamp = NSDate().timeIntervalSince1970;
    var fileCount = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Face Tracking が使えなければ、これ以下の命令を実行を実行しない
        guard ARFaceTrackingConfiguration.isSupported else { return }
        
        // Face Tracking アプリの場合、画面を触らない状況が続くため画面ロックを止める
        UIApplication.shared.isIdleTimerDisabled = true
        
        // ARSCNView と ARSession のデリゲート、周囲の光の設定
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        
        // ワイヤーフレーム表示
        sceneView.debugOptions = .showWireframe
        
        // シーンの背景を黒へ変更
        sceneView.scene.background.contents = UIColor.black
        
        
        // virtualFaceNode に ARSCNFaceGeometry を設定する
        let device = sceneView.device!
        let maskGeometry = ARSCNFaceGeometry(device: device)!
        
        // ジオメトリの色を黒にする
        maskGeometry.firstMaterial?.diffuse.contents = UIColor.black
        maskGeometry.firstMaterial?.lightingModel = .physicallyBased
        
        virtualFaceNode.geometry = maskGeometry
        
        // トラッキングの初期化を実行
        resetTracking()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prefersHomeIndicatorAutoHidden() -> Bool {
        return true
    }
    
    // この ViewController が表示された場合にトラッキングの初期化する
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        resetTracking()
    }
    
    // この ViewController が非表示になった場合にセッションを止める
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sceneView.session.pause()
    }
    
    // Face Tracking の設定を行い
    // オプションにトラッキングのリセットとアンカーを全て削除してセッション開始
    func resetTracking() {
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // Face Tracking の起点となるノードの初期設定
    private func setupFaceNodeContent() {
        // faceNode 以下のチルドノードを消す
        for child in faceNode.childNodes {
            child.removeFromParentNode()
        }
        
        // マスクのジオメトリの入った virtualFaceNode をノードに追加する
        faceNode.addChildNode(virtualFaceNode)
    }
    
    // MARK: - ARSCNViewDelegate
    /// ARNodeTracking 開始
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        faceNode = node
        serialQueue.async {
            self.setupFaceNodeContent()
        }
    }
    
    /// ARNodeTracking 更新。ARSCNFaceGeometry の内容を変更する
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        let geometry = virtualFaceNode.geometry as! ARSCNFaceGeometry
        var curBlendShapeDict = [String: Double]()
        for (blendShapeLocation, number) in faceAnchor.blendShapes {
            curBlendShapeDict[blendShapeLocation.rawValue] = number.doubleValue
        }
        let timestamp = NSDate().timeIntervalSince1970
        // 25 frame per second
        if (timestamp - prevTimestamp > 0.04) {
            prevTimestamp = timestamp
            let faceMesh = FaceMesh(timestamp: timestamp, faceMeshFrame: curBlendShapeDict)
            faceMeshList.append(faceMesh)
        }
        geometry.update(from: faceAnchor.geometry)
    }
    
    // MARK: - ARSessionDelegate
    /// エラーと中断処理
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        let concurrentQueue = DispatchQueue(label: "fileWrite", attributes: .concurrent)
        concurrentQueue.async {
            self.saveFacemashesToDisk(faceMeshes: self.faceMeshList);
        }
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            // 中断復帰後トラッキングを再開させる
            self.resetTracking()
        }
    }
    
    // Helper method to get a URL to the user's documents directory
    // see https://developer.apple.com/icloud/documentation/data-storage/index.html
    func getDocumentsURL() -> URL {
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return url
        } else {
            fatalError("Could not retrieve documents directory")
        }
    }
    
    func saveFacemashesToDisk(faceMeshes: [FaceMesh]) {
        // 1. Create a URL for documents-directory/posts.json
        let url = getDocumentsURL().appendingPathComponent("facemeshes\(fileCount).json")
        // 2. Endcode our [Post] data to JSON Data
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(faceMeshes)
            // 3. Write this data to the url specified in step 1
            print(data)
            try data.write(to: url, options: [])
            fileCount += 1
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    func getFaceMashesFromDisk() -> [Dictionary<String, Double>] {
        // 1. Create a url for documents-directory/posts.json
        let url = getDocumentsURL().appendingPathComponent("facemeshes.json")
        let decoder = JSONDecoder()
        do {
            // 2. Retrieve the data on the file in this path (if there is any)
            let data = try Data(contentsOf: url, options: [])
            // 3. Decode an array of Posts from this Data
            let facemashes = try decoder.decode([Dictionary<String, Double>].self, from: data)
            return facemashes
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

