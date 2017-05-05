import Vapor
import HTTP
import JWT
import Foundation

extension Request {
    
    func user() throws -> User {
        var tokenString: String? = nil
        if let cookiesTokenString = self.cookies["login"] {
            tokenString = cookiesTokenString
        } else if let headerTokenString = headers["Authorization"] {
            tokenString = headerTokenString
        }
        guard let unwrappedTokenString = tokenString else {
            throw Abort.custom(status: .badRequest, message: "Invalid user type.")
        }
        let jwtKey = Droplet().config["app", "signing_secret"]?.string ?? ""
        let jwt = try JWT(token: unwrappedTokenString)
        try jwt.verifySignature(using: HS256(key: jwtKey.bytes))
        let valid = jwt.verifyClaims([ExpirationTimeClaim(Date(), leeway: 120)])
        guard valid,
            let userId = jwt.payload[UserIDClaim.name]?.int else {
                throw Abort.notFound
        }
        guard let user = try User.find(userId.makeNode()) else {
            throw Abort.notFound
        }
        return user
    }
}
