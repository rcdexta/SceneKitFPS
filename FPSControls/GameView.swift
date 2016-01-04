
import SceneKit

class GameView : SCNView {
    
    var touchCount:Int?
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        let touchCount = event!.allTouches()
        self.touchCount = touchCount?.count
    }
    
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        self.touchCount = 0
    }
    
}
