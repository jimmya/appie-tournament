import Vapor
import HTTP
import Fluent

final class User {
    
    var id: Node?
    var username: String?
    var email: Valid<Email>?
    var password: String
    var verified: Bool
    var admin: Bool
    
    // used by fluent internally
    var exists: Bool = false
    
    init(username: String, password: String) {
        self.id = nil
        self.username = username
        self.email = nil
        self.password = password
        self.verified = false
        self.admin = false
    }
    
    init(node: Node, in context: Context) throws {
        id = try node.extract("id")
        let extractedEmail: String = try node.extract("email")
        username = try node.extract("username")
        email = try extractedEmail.validated()
        password = try node.extract("password")
        verified = try node.extract("verified")
        admin = try node.extract("admin")
    }
}

extension User {
    
    func team() throws -> Team {
        guard let team: Team = try siblings().first() else {
            throw Abort.notFound
        }
        return team
    }
}

extension User {
    
    func pushTokens() throws -> Children<PushToken> {
        return children()
    }
}

extension User: Model {
    
    func makeNode(context: Context) throws -> Node {
        var userNode = try Node(node: [
            "id": id,
            "username": username
            ])
        switch context {
        case is DatabaseContext:
            userNode["password"] = password.makeNode()
            userNode["email"] = email?.value.makeNode()
            userNode["verified"] = verified.makeNode()
            userNode["admin"] = admin.makeNode()
            break
        default:
            do {
                userNode["teamId"] = try team().id
            } catch {
                
            }
            break
        }
        return userNode
    }
}

extension User: Preparation {
    
    static func prepare(_ database: Database) throws {
        try database.create(entity, closure: { (user) in
            user.id()
            user.string("username")
            user.string("email")
            user.string("password")
            user.bool("verified")
            user.bool("admin")
        })
    }
    
    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

extension User {
    
    func sendEmail(subject: String, message: String) throws -> Response {
        guard let email = email?.value.string else {
            throw Abort.serverError
        }
        let config = Droplet().config
        let apiUrl = config["app", "mail_api_url"]?.string ?? ""
        let apiKey = config["app", "mail_api_key"]?.string ?? ""
        let apiString = "api:\(apiKey)"
        let apiKeyEncoded = try apiString.bytes.base64Encoded.string()
        let data = try Body.data( Node([
            "from": "Appie Tournament <postmaster@mg.onnozelheid.nl>".makeNode(),
            "to": email.makeNode(),
            "subject": subject.makeNode(),
            "html": message.makeNode()
            ]).formURLEncoded())
        let response = try Droplet().client.post(apiUrl, headers:
            ["authorization": "Basic \(apiKeyEncoded)",
                "Content-Type": "application/x-www-form-urlencoded"],
                                                 body: data)
        return response
    }
}
