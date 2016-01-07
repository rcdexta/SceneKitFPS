import Foundation

enum EntityType {
    case Hero
    case Monster
    case Gem
}

class Entity {
    
    var type: EntityType
    var x, y: Float
    
    init(type: EntityType, x: Float, y: Float) {
        
        self.type = type
        self.x = x
        self.y = y
    }
}
