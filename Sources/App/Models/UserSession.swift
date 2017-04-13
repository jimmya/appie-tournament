import Vapor
import Fluent
import Foundation

// MARK: Model
struct UserSession: Model {
    
    var id: Node?
    var expires: Double?
    var uuid: String?
    var userId: Node?
    
    // used by fluent internally
    var exists: Bool = false
}

// MARK: NodeConvertible
extension UserSession: NodeConvertible {
    
    init(userId: Node) {
        self.id = nil
        self.expires = Date().addingTimeInterval(3600).timeIntervalSince1970
        self.uuid = "r_\(UUID().uuidString)"
        self.userId = userId
    }
    
    init(node: Node, in context: Context) throws {
        id = node["id"]
        expires = node["expires"]?.double
        uuid = node["uuid"]?.string
        userId = node["user_id"]
    }
    
    func makeNode(context: Context) throws -> Node {
        // model won't always have value to allow proper merges,
        // database defaults to false
        return try Node.init(node:
            [
                "id": id,
                "expires": expires,
                "uuid": uuid,
                "user_id": userId
            ]
        )
    }
}

// MARK: Database Preparations
extension UserSession: Preparation {
    
    static func prepare(_ database: Database) throws {
        try database.create(entity) { tokens in
            tokens.id()
            tokens.double("expires", optional: false)
            tokens.string("uuid", optional: false)
            tokens.int("user_id", optional: false)
        }
    }
    
    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Merge
extension UserSession {
    
    mutating func merge(updates: UserSession) {
        id = updates.id ?? id
        expires = updates.expires ?? expires
        uuid = updates.uuid ?? uuid
        userId = updates.userId ?? userId
    }
}
