import Vapor
import Fluent
import Foundation

// MARK: Model
struct PushToken: Model {
    
    var id: Node?
    var token: String?
    var userId: Node?
    
    // used by fluent internally
    var exists: Bool = false
}

// MARK: NodeConvertible
extension PushToken: NodeConvertible {
    
    init(token: String, userId: Node?) {
        id = nil
        self.token = token
        self.userId = userId
    }
    
    init(node: Node, in context: Context) throws {
        id = node["id"]
        token = node["token"]?.string
        userId = node["user_id"]
    }
    
    func makeNode(context: Context) throws -> Node {
        // model won't always have value to allow proper merges,
        // database defaults to false
        return try Node.init(node:
            [
                "id": id,
                "token": token,
                "user_id": userId
            ]
        )
    }
}

// MARK: Database Preparations
extension PushToken: Preparation {
    
    static func prepare(_ database: Database) throws {
        try database.create(entity) { tokens in
            tokens.id()
            tokens.string("token", optional: false)
            tokens.int("user_id", optional: false)
        }
    }
    
    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Merge
extension PushToken {
    
    mutating func merge(updates: PushToken) {
        id = updates.id ?? id
        token = updates.token ?? token
        userId = updates.userId ?? userId
    }
}
