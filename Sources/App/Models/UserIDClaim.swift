import Vapor
import JWT

struct UserIDClaim: Claim {
    
    static let name = "user_id"
    
    var node: Node {
        return .number(.int(userID))
    }
    
    let userID: Int
    
    init(userID: Int) {
        self.userID = userID
    }
    
    func verify(_ node: Node) -> Bool {
        guard let otherID = node.int else {
            return false
        }
        return otherID == userID
    }
}
