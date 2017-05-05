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
        case let refreshCredentials as RefreshCredentials:
            let userId = refreshCredentials.userId
            let refreshToken = refreshCredentials.string
            let jwtKey = Droplet().config["app", "signing_secret"]?.string ?? ""
            let jwt = try JWT(token: refreshToken)
            try jwt.verifySignature(using: HS256(key: jwtKey.bytes))
            guard let uuid = jwt.payload[JWTIDClaim.name] else {
                throw Abort.badRequest
            }
            let refreshTokenObject = try RefreshToken.query().filter("uuid", uuid).filter("user_id", Node(.int(userId))).first()
            guard let objectUUID = refreshTokenObject?.uuid else {
                throw Abort.badRequest
            }
            let valid = jwt.verifyClaims([ExpirationTimeClaim(Date(), leeway: 120),
                                          JWTIDClaim(objectUUID)])
            guard valid else {
                throw Abort.badRequest
            }
            
            let refreshTokenQuery = try RefreshToken.query().filter("user_id", userId).filter("token", refreshToken)
            guard try refreshTokenQuery.count() != 0 else {
                throw Abort.badRequest
            }
            try refreshTokenQuery.delete()
            let user = try User.find(Node(.int(userId)))
            if let user = user {
                return user
            }
            throw Abort.badRequest
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
        let tokenValidDuration = Droplet().config["app", "cookie_valid_duration"]?.double ?? 0
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

extension User {
    
    func generateAccessToken() throws -> String {
        guard let userId = id?.int else {
            throw Abort.serverError
        }
        let tokenValidDuration = Droplet().config["app", "token_valid_duration"]?.double ?? 0
        let claims: [Claim] = [
            ExpirationTimeClaim(Date() + tokenValidDuration),
            UserIDClaim(userID: userId)
        ]
        let jwtKey = Droplet().config["app", "signing_secret"]?.string ?? ""
        let jwt = try JWT(payload: Node(claims),
                          signer: HS256(key: jwtKey.bytes))
        return try jwt.createToken()
    }
    
    func generateRefreshToken() throws -> String {
        guard let userId = id?.int else {
            throw Abort.serverError
        }
        let refreshUUID = UUID().uuidString
        let refreshTokenValidDuration = Droplet().config["app", "refresh_token_valid_duration"]?.double ?? 0
        let refreshClaims: [Claim] = [
            ExpirationTimeClaim(Date() + refreshTokenValidDuration),
            JWTIDClaim(refreshUUID)
        ]
        let jwtKey = Droplet().config["app", "signing_secret"]?.string ?? ""
        let refreshJWT = try JWT(payload: Node(refreshClaims),
                                 signer: HS256(key: jwtKey.bytes))
        let refreshJWTString = try refreshJWT.createToken()
        var newRefreshToken = RefreshToken(token: refreshJWTString, uuid: refreshUUID, userId: Node(.int(userId)))
        try newRefreshToken.save()
        return refreshJWTString
    }
}
