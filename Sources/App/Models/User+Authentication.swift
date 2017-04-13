import Vapor
import Turnstile
import Auth
import JWT
import Foundation
import BCrypt
import Cookies

extension User: Auth.User {
    
    static func authenticate(credentials: Credentials) throws -> Auth.User {
        switch credentials {
        case let id as Identifier:
            guard let user = try User.find(id.id) else {
                throw Abort.custom(status: .badRequest, message: "Invalid login credentials.")
            }
            return user
        case let usernamePassword as UsernamePassword:
            let fetchedUser = try User.query().filter("email", usernamePassword.username).first()
            guard let user = fetchedUser else {
                throw Abort.custom(status: .badRequest, message: "Invalid login credentials.")
            }
            if try BCrypt.verify(password: usernamePassword.password, matchesHash: user.password) {
                return user
            } else {
                throw Abort.custom(status: .badRequest, message: "Invalid login credentials.")
            }
        default:
            let type = type(of: credentials)
            throw Abort.custom(status: .forbidden, message: "Unsupported credential type: \(type).")
        }
    }
    
    static func register(credentials: Credentials) throws -> Auth.User {
        let usernamePassword = credentials as? UsernamePassword
        guard let creds = usernamePassword else {
            let type = type(of: credentials)
            throw Abort.custom(status: .forbidden, message: "Unsupported credential type: \(type).")
        }
        let hashedPassword = try BCrypt.digest(password: try creds.password.validated(by: Password.self).value)
        let user = User(username: creds.username, password: hashedPassword)
        return user
    }
}

extension User {
    
    func generateCookie() throws -> Cookie {
        guard let userId = id?.int else {
            throw Abort.serverError
        }
        let tokenValidDuration = Droplet().config["app", "token_valid_duration"]?.double ?? 0
        let expiration = Date() + tokenValidDuration
        let claims: [Claim] = [
            ExpirationTimeClaim(expiration),
            UserIDClaim(userID: userId)
        ]
        let jwtKey = Droplet().config["app", "signing_secret"]?.string ?? ""
        let jwt = try JWT(payload: Node(claims),
                          signer: HS256(key: jwtKey.bytes))
        let token = try jwt.createToken()
        return Cookie(name: "login", value: token, expires: expiration, httpOnly: true)
    }
}
