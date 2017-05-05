import Vapor
import Fluent

// MARK: Model
struct RefreshToken: Model {
    
    var id: Node?
    var token: String?
    var uuid: String?
    var userId: Node?
    
    // used by fluent internally
    var exists: Bool = false
}

// MARK: NodeConvertible
extension RefreshToken: NodeConvertible {
    
    init(token: String, uuid: String, userId: Node) {
        self.id = nil
        self.token = token
        self.uuid = uuid
        self.userId = userId
    }
    
    init(node: Node, in context: Context) throws {
        id = node["id"]
        token = node["token"]?.string
        uuid = node["uuid"]?.string
        userId = node["user_id"]
    }
    
    func makeNode(context: Context) throws -> Node {
        // model won't always have value to allow proper merges,
        // database defaults to false
        return try Node.init(node:
            [
                "id": id,
                "token": token,
                "uuid": uuid,
                "user_id": userId
            ]
        )
    }
}

// MARK: Database Preparations
extension RefreshToken: Preparation {
    
    static func prepare(_ database: Database) throws {
        try database.create(entity) { tokens in
            tokens.id()
            tokens.string("token", optional: false)
            tokens.string("uuid", optional: false)
            tokens.int("user_id", optional: false)
        }
    }
    
    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Merge
extension RefreshToken {
    
    mutating func merge(updates: RefreshToken) {
        id = updates.id ?? id
        token = updates.token ?? token
        uuid = updates.uuid ?? uuid
        userId = updates.userId ?? userId
    }
}
