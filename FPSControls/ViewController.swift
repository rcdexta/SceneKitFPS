import UIKit
import AVKit
import AVFoundation
import SceneKit

struct CollisionCategory {
    static let None: Int = 0b00000000
    static let All: Int = 0b11111111
    static let Map: Int = 0b00000001
    static let Hero: Int = 0b00000010
    static let Monster: Int = 0b00000100
    static let Bullet: Int = 0b00001000
}

class ViewController: UIViewController, UIGestureRecognizerDelegate, SCNSceneRendererDelegate, SCNPhysicsContactDelegate, AVAudioPlayerDelegate {
    
    //MARK: config
    let autofireTapTimeThreshold = 0.2
    let maxRoundsPerSecond = 30
    let bulletRadius = 0.05
    let bulletImpulse = 15
    let maxBullets = 100
    
    @IBOutlet var sceneView: GameView!
    @IBOutlet var overlayView: UIView!
    
    var lookGesture: UIPanGestureRecognizer!
    var walkGesture: UIPanGestureRecognizer!
    var fireGesture: FireGestureRecognizer!
    var heroNode: SCNNode!
    var camNode: SCNNode!
    var elevation: Float = 0
    var mapNode: SCNNode!
    var map: Map!
    
    var tapCount = 0
    var lastTappedFire: NSTimeInterval = 0
    var lastFired: NSTimeInterval = 0
    var bullets = [SCNNode]()
    
    var bgmPlayer : AVAudioPlayer! = nil
    
    let coinSoundAction = SCNAction.playAudioSource(SCNAudioSource(named: "coin.wav")!, waitForCompletion: false)
    
    func collada2SCNNode(filepath:String) -> SCNNode {
        let node = SCNNode()
        let scene = SCNScene(named: filepath)
        let nodeArray = scene!.rootNode.childNodes
        
        for childNode in nodeArray {
            node.addChildNode(childNode as SCNNode)
        }
        
        return node
    }
    
    func applyDoorTexture(plane:SCNGeometry){
        plane.firstMaterial?.diffuse.contents = UIImage(named: "exit")
    }

    
    func applyWallTexture(plane:SCNGeometry){
        plane.firstMaterial?.diffuse.contents = UIImage(named: "brick")
        plane.firstMaterial?.diffuse.wrapS = SCNWrapMode.Repeat
        plane.firstMaterial?.diffuse.wrapT = SCNWrapMode.Repeat
        plane.firstMaterial?.doubleSided = true
        plane.firstMaterial?.diffuse.mipFilter = SCNFilterMode.Linear
    }
    
    func createFloor() -> SCNNode {
        let floorNode = SCNNode()

        floorNode.geometry = SCNPlane(width: CGFloat(map.width), height: CGFloat(map.height))
        floorNode.geometry?.firstMaterial?.diffuse.contents = "grass"
        floorNode.geometry?.firstMaterial?.locksAmbientWithDiffuse = true
        floorNode.geometry?.firstMaterial?.diffuse.wrapS = SCNWrapMode.Repeat
        floorNode.geometry?.firstMaterial?.diffuse.wrapT = SCNWrapMode.Repeat
        floorNode.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeScale(20, 20, 1)
        
        floorNode.rotation = SCNVector4(x: 1, y: 0, z: 0, w: Float(-M_PI_2))
        floorNode.position = SCNVector3(x: Float(map.width)/2, y: 0, z: Float(map.height)/2)

        return floorNode
    }
    
    func playBGM(){
        let path = NSBundle.mainBundle().pathForResource("bgm", ofType:"mp3")
        let fileURL = NSURL(fileURLWithPath: path!)
        do {
            bgmPlayer = try AVAudioPlayer(contentsOfURL: fileURL)
        } catch let error1 as NSError {
            print(error1)
        }
        bgmPlayer.numberOfLoops = 0
        bgmPlayer.prepareToPlay()
        bgmPlayer.delegate = self
        bgmPlayer.play()
    }
    
    func doIntroMovie(){
        let panAction1 = SCNAction.moveTo(SCNVector3(x: 10, y: 7 , z: -1), duration: 5.0)
        let axis = SCNVector3(x: -1,y: 0,z: 0)
        let rotateAction1 = SCNAction.rotateByAngle(CGFloat(M_PI/6), aroundAxis: axis, duration: 3.0)
        
        let sequence1 = SCNAction.group([panAction1, rotateAction1])
        
        camNode.runAction(sequence1) { () -> Void in
            let panAction2 = SCNAction.moveTo(SCNVector3(x:0, y: 0, z: 0), duration: 5.0)
            let axis = SCNVector3(x: 1,y: 0,z: 0)
            let rotateAction2 = SCNAction.rotateByAngle(CGFloat(M_PI/6), aroundAxis: axis, duration: 3.0)
            
            let sequence2 = SCNAction.group([panAction2, rotateAction2])
            
            self.camNode.runAction(sequence2) { () -> Void in
                print("show overlay")
                dispatch_async(dispatch_get_main_queue()) {
                    self.overlayView.hidden = false
                }
            }
        }
    }
    
    func playRun1Video(){
        let path = NSBundle.mainBundle().pathForResource("Run1", ofType:"mp4")!
        let player = AVPlayer(URL: NSURL(fileURLWithPath: path))
        
        let playerController = AVPlayerViewController()
        playerController.showsPlaybackControls = false
        playerController.player = player
        self.addChildViewController(playerController)
        self.view.addSubview(playerController.view)
        playerController.view.frame = self.view.frame
        
        player.play()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //generate map
        map = Map(image: UIImage(named:"map.png")!)
        
        //create a new scene
        let scene = SCNScene()
        scene.physicsWorld.gravity = SCNVector3(x: 0, y: -9, z: 0)
        scene.physicsWorld.timeStep = 1.0/360
        scene.physicsWorld.contactDelegate = self
        
        //add entities
        for entity in map.entities {
            switch entity.type {
            case .Hero:
                heroNode = SCNNode()
                heroNode.physicsBody = SCNPhysicsBody(type: .Dynamic, shape: SCNPhysicsShape(geometry: SCNCylinder(radius: 0.2, height: 1), options: nil))
                heroNode.physicsBody?.angularDamping = 0.9999999
                heroNode.physicsBody?.damping = 0.9999999
                heroNode.physicsBody?.rollingFriction = 0
                heroNode.physicsBody?.friction = 0
                heroNode.physicsBody?.restitution = 0
                heroNode.physicsBody?.velocityFactor = SCNVector3(x: 1, y: 0, z: 1)
                heroNode.physicsBody?.categoryBitMask = CollisionCategory.Hero
                heroNode.physicsBody?.collisionBitMask = CollisionCategory.All ^ CollisionCategory.Bullet
                heroNode.physicsBody?.contactTestBitMask = ~0
                heroNode.position = SCNVector3(x: entity.x, y: 0.5, z: entity.y)
                scene.rootNode.addChildNode(heroNode)
            
            case .Gem:
                let gemScene = SCNScene(named: "crystal.dae")
                let gemNode = gemScene!.rootNode.childNodeWithName("crystal", recursively: true)!
                gemNode.position = SCNVector3(x: entity.x, y: 0.1, z: entity.y)
                gemNode.scale = SCNVector3(x: 0.2, y: 0.2, z: 0.2)
                gemNode.physicsBody = SCNPhysicsBody(type: .Static, shape: SCNPhysicsShape(geometry: gemNode.geometry!, options: nil))
                gemNode.physicsBody?.categoryBitMask = CollisionCategory.Monster
                gemNode.physicsBody?.collisionBitMask = CollisionCategory.All
                gemNode.physicsBody?.contactTestBitMask = ~0
                
                let action = SCNAction.rotateByAngle(CGFloat(5), aroundAxis: SCNVector3Make(0,-1,0), duration:10.0)
                let sequence = SCNAction.sequence([action])
                
                let repeatedSequence = SCNAction.repeatActionForever(sequence)
                gemNode.runAction(repeatedSequence)
                
                scene.rootNode.addChildNode(gemNode)
                
            case .Monster:
                let monsterScene = SCNScene(named: "evil-bug-monster.dae")
                let monsterNode = monsterScene!.rootNode.childNodeWithName("bug_obj_1", recursively: true)!
                monsterNode.position = SCNVector3(x: entity.x, y: 0.2, z: entity.y)
                monsterNode.scale = SCNVector3(x: 0.2, y: 0.2, z: 0.2)
                monsterNode.physicsBody = SCNPhysicsBody(type: .Static, shape: SCNPhysicsShape(geometry: monsterNode.geometry!, options: nil))
                monsterNode.physicsBody?.categoryBitMask = CollisionCategory.Monster
                monsterNode.physicsBody?.collisionBitMask = CollisionCategory.All
                monsterNode.physicsBody?.contactTestBitMask = ~0
                
                let action = SCNAction.rotateByAngle(CGFloat(5), aroundAxis: SCNVector3Make(0,-1,0), duration:10.0)
                let sequence = SCNAction.sequence([action])
                
                let repeatedSequence = SCNAction.repeatActionForever(sequence)
                monsterNode.runAction(repeatedSequence)
                
                scene.rootNode.addChildNode(monsterNode)
            }
        }
        
        //add a camera node
        camNode = SCNNode()
//        camNode.position = SCNVector3(x: 0, y: 0 , z: 0)
        camNode.position = SCNVector3(x: Float(map.width)/4+3, y: 0 , z: -Float(map.height)/2-3)
        heroNode.addChildNode(camNode)
        
        //add camera
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = Double(max(map.width, map.height))
        camNode.camera = camera
        
        //create map node
        mapNode = SCNNode()
        
        //add walls
        for tile in map.tiles {
            
            if tile.type == .Wall || tile.type == .Door {
                
                //create walls
                if tile.visibility.contains(.Top) {
                    let wallNode = SCNNode()
                    wallNode.geometry = SCNBox(width: 1, height: 1, length: 0.1, chamferRadius: 0)
                    tile.type == .Wall ? applyWallTexture(wallNode.geometry!) : applyDoorTexture(wallNode.geometry!)
                    wallNode.rotation = SCNVector4(x: 0, y: 1, z: 0, w: Float(M_PI))
                    wallNode.position = SCNVector3(x: Float(tile.x) + 0.5, y: 0.5, z: Float(tile.y))
                    mapNode.addChildNode(wallNode)
                }
                if tile.visibility.contains(.Right) {
                    let wallNode = SCNNode()
                    wallNode.geometry = SCNBox(width: 1.1, height: 1, length: 0.1, chamferRadius: 0)
                    tile.type == .Wall ? applyWallTexture(wallNode.geometry!) : applyDoorTexture(wallNode.geometry!)
                    wallNode.rotation = SCNVector4(x: 0, y: 1, z: 0, w: Float(M_PI_2))
                    wallNode.position = SCNVector3(x: Float(tile.x) + 1, y: 0.5, z: Float(tile.y) + 0.5)
                    mapNode.addChildNode(wallNode)
                }
                if tile.visibility.contains(.Bottom) {
                    let wallNode = SCNNode()
                    wallNode.geometry = SCNBox(width: 1, height: 1, length: 0.1, chamferRadius: 0)
                    tile.type == .Wall ? applyWallTexture(wallNode.geometry!) : applyDoorTexture(wallNode.geometry!)
                    wallNode.rotation = SCNVector4(x: 0, y: 1, z: 0, w: 0)
                    wallNode.position = SCNVector3(x: Float(tile.x) + 0.5, y: 0.5, z: Float(tile.y) + 1)
                    mapNode.addChildNode(wallNode)
                }
                if tile.visibility.contains(.Left) {
                    let wallNode = SCNNode()
                    wallNode.geometry = SCNBox(width: 1.1, height: 1, length: 0.1, chamferRadius: 0)
                    tile.type == .Wall ? applyWallTexture(wallNode.geometry!) : applyDoorTexture(wallNode.geometry!)
                    applyWallTexture(wallNode.geometry!)
                    wallNode.rotation = SCNVector4(x: 0, y: 1, z: 0, w: Float(-M_PI_2))
                    wallNode.position = SCNVector3(x: Float(tile.x), y: 0.5, z: Float(tile.y) + 0.5)
                    mapNode.addChildNode(wallNode)
                }
            }
        }
        
        //add floor
        mapNode.addChildNode(createFloor())
        
        //add ceiling
//        let ceilingNode = SCNNode()
//        ceilingNode.geometry = SCNPlane(width: CGFloat(map.width), height: CGFloat(map.height))
//        ceilingNode.geometry!.firstMaterial?.diffuse.contents = "night"
//        ceilingNode.geometry!.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeScale(10, 10, 1)
//        ceilingNode.geometry!.firstMaterial?.diffuse.wrapS = SCNWrapMode.Repeat
//        ceilingNode.geometry!.firstMaterial?.diffuse.wrapT = SCNWrapMode.Repeat
//        ceilingNode.geometry!.firstMaterial?.diffuse.mipFilter = SCNFilterMode.Linear
//        ceilingNode.rotation = SCNVector4(x: 1, y: 0, z: 0, w: Float(M_PI_2))
//        ceilingNode.position = SCNVector3(x: Float(map.width)/2, y: 1, z: Float(map.height)/2)
//        mapNode.addChildNode(ceilingNode)
        
        //set up map physics
        mapNode.physicsBody = SCNPhysicsBody(type: .Static, shape: SCNPhysicsShape(node: mapNode, options: [SCNPhysicsShapeKeepAsCompoundKey: true]))
        mapNode.physicsBody?.categoryBitMask = CollisionCategory.Map
        mapNode.physicsBody?.collisionBitMask = CollisionCategory.All
        mapNode.physicsBody?.contactTestBitMask = ~0
        scene.rootNode.addChildNode(mapNode)
        
        //set the scene to the view
        sceneView.scene = scene
        sceneView.jitteringEnabled = true
        sceneView.delegate = self
        
        //show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        //configure the view
        sceneView.backgroundColor = UIColor.blackColor()
        
        //look gesture
        lookGesture = UIPanGestureRecognizer(target: self, action: "lookGestureRecognized:")
        lookGesture.delegate = self
        view.addGestureRecognizer(lookGesture)
        
        doIntroMovie()
//        playBGM()
        
//        playRun1Video()
        
//        walk gesture
//        walkGesture = UIPanGestureRecognizer(target: self, action: "walkGestureRecognized:")
//        walkGesture.delegate = self
//        view.addGestureRecognizer(walkGesture)
        
        //fire gesture
        
//        let tapGesture = UITapGestureRecognizer(target: self, action: Selector("handleTap:"))
        
//        fireGesture = FireGestureRecognizer(target: self, action: "walkGestureRecognized:")
//        fireGesture.delegate = self
//        view.addGestureRecognizer(tapGesture)
    }
    
//    func handleTap(gesture: UITapGestureRecognizer)
//    {
//        if gesture.state == UIGestureRecognizerState.Ended || gesture.state == UIGestureRecognizerState.Cancelled {
//            gesture.setTranslation(CGPointZero, inView: self.view)
//        }
//    }
    
    override func viewDidAppear(animated: Bool) {
        
        UIView.animateWithDuration(0.5) {
            self.overlayView.alpha = 1
        }
    }
    
    @IBAction func hideOverlay() {
        
            UIView.animateWithDuration(0.5) {
                self.overlayView.alpha = 0
            }
        
    }
    
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldReceiveTouch touch: UITouch) -> Bool {
        
//        if gestureRecognizer == lookGesture {
//            return touch.locationInView(view).x > view.frame.size.width / 2
//        } else if gestureRecognizer == walkGesture {
//            return touch.locationInView(view).x < view.frame.size.width / 2
//        }
        return true
    }
    
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        
        return true
    }
    
    func lookGestureRecognized(gesture: UIPanGestureRecognizer) {
        
        //get translation and convert to rotation
        let translation = gesture.translationInView(self.view)
        let hAngle = acos(Float(translation.x) / 200) - Float(M_PI_2)
        let vAngle = acos(Float(translation.y) / 200) - Float(M_PI_2)
        
        //rotate hero
        heroNode.physicsBody?.applyTorque(SCNVector4(x: 0, y: 1, z: 0, w: hAngle), impulse: true)
        
        //tilt camera
        elevation = max(Float(-M_PI_4), min(Float(M_PI_4), elevation + vAngle))
        camNode.rotation = SCNVector4(x: 1, y: 0, z: 0, w: elevation)
        
        sceneView.touchCount = 0
        
        //reset translation
        gesture.setTranslation(CGPointZero, inView: self.view)
    }
    
    func walkGestureRecognized(gesture: UIPanGestureRecognizer) {
        
        if gesture.state == UIGestureRecognizerState.Ended || gesture.state == UIGestureRecognizerState.Cancelled {
            gesture.setTranslation(CGPointZero, inView: self.view)
        }
    }
    
    func fireGestureRecognized(gesture: FireGestureRecognizer) {
        
        //update timestamp
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastTappedFire < autofireTapTimeThreshold {
            tapCount += 1
        } else {
            tapCount = 1
        }
        lastTappedFire = now
    }
    
    func physicsWorld(world: SCNPhysicsWorld, didUpdateContact contact: SCNPhysicsContact) {
//        print("collision")
//        print(contact.nodeA)
//        print(contact.nodeB)
        
        if (contact.nodeA.name == "crystal"){
//            let exp = SCNParticleSystem()
//            exp.loops = false
//            exp.birthRate = 5000
//            exp.emissionDuration = 0.01
//            exp.spreadingAngle = 50
//            exp.particleDiesOnCollision = true
//            exp.particleLifeSpan = 0.5
//            exp.particleLifeSpanVariation = 0.3
//            exp.particleVelocity = 300
//            exp.particleVelocityVariation = 3
//            exp.particleSize = 0.10
//            exp.stretchFactor = 0.15
//            exp.particleColor = UIColor.orangeColor()
//            let systemNode = SCNNode()
//            systemNode.addParticleSystem(exp)
//            systemNode.position = contact.nodeA.position
//            self.sceneView.scene!.rootNode.addChildNode(systemNode)
            contact.nodeB.runAction(coinSoundAction)
            contact.nodeA.removeFromParentNode()
        }
    }
    
    func renderer(aRenderer: SCNSceneRenderer, updateAtTime time: NSTimeInterval) {
        
        struct My {
            var x : Int
            var y: Int
        }
        
        var translation = My(x: 0, y: 0)
        
        //get walk gesture translation
        if (sceneView.touchCount > 0) {
            translation.y -= 20
        }


//        let translation = walkGesture.translationInView(self.view)
//        print(sceneView.touchCount)
//        print(translation)
        
        //create impulse vector for hero
        let angle = heroNode.presentationNode.rotation.w * heroNode.presentationNode.rotation.y
        var impulse = SCNVector3(x: max(-1, min(1, Float(translation.x) / 50)), y: 0, z: max(-1, min(1, Float(-translation.y) / 50)))
        impulse = SCNVector3(
            x: impulse.x * cos(angle) - impulse.z * sin(angle),
            y: 0,
            z: impulse.x * -sin(angle) - impulse.z * cos(angle)
        )
        heroNode.physicsBody?.applyForce(impulse, impulse: true)
        
        //handle firing
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastTappedFire < autofireTapTimeThreshold {
            let fireRate = min(Double(maxRoundsPerSecond), Double(tapCount) / autofireTapTimeThreshold)
            if now - lastFired > 1 / fireRate {
                
                //get hero direction vector
                let angle = heroNode.presentationNode.rotation.w * heroNode.presentationNode.rotation.y
                var direction = SCNVector3(x: -sin(angle), y: 0, z: -cos(angle))
                
                //get elevation
                direction = SCNVector3(x: cos(elevation) * direction.x, y: sin(elevation), z: cos(elevation) * direction.z)
                
                //create or recycle bullet node
                let bulletNode: SCNNode = {
                    if self.bullets.count < self.maxBullets {
                        return SCNNode()
                    } else {
                        return self.bullets.removeAtIndex(0)
                    }
                }()
                bullets.append(bulletNode)
                bulletNode.geometry = SCNBox(width: CGFloat(bulletRadius) * 2, height: CGFloat(bulletRadius) * 2, length: CGFloat(bulletRadius) * 2, chamferRadius: CGFloat(bulletRadius))
                bulletNode.position = SCNVector3(x: heroNode.presentationNode.position.x, y: 0.4, z: heroNode.presentationNode.position.z)
                bulletNode.physicsBody = SCNPhysicsBody(type: .Dynamic, shape: SCNPhysicsShape(geometry: bulletNode.geometry!, options: nil))
                bulletNode.physicsBody?.categoryBitMask = CollisionCategory.Bullet
                bulletNode.physicsBody?.collisionBitMask = CollisionCategory.All ^ CollisionCategory.Hero
                bulletNode.physicsBody?.velocityFactor = SCNVector3(x: 1, y: 0.5, z: 1)
                self.sceneView.scene!.rootNode.addChildNode(bulletNode)
                
                //apply impulse
                let impulse = SCNVector3(x: direction.x * Float(bulletImpulse), y: direction.y * Float(bulletImpulse), z: direction.z * Float(bulletImpulse))
                bulletNode.physicsBody?.applyForce(impulse, impulse: true)
                
                //update timestamp
                lastFired = now
            }
        }
    }
}

