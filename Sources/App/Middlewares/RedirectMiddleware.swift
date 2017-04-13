import Vapor
import HTTP

class RedirectMiddleware: Middleware {
    
    let adminOnly: Bool
    
    init(adminOnly: Bool = false) {
        self.adminOnly = adminOnly
    }
    
    public func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        do {
            let user = try request.user()
            if !user.verified {
                return Response(redirect: "/users/login").flash(.error, "You need to login to perform this action")
            }
            if !user.admin && adminOnly {
                return Response(redirect: "/teams").flash(.error, "Insufficient rights")
            }
        } catch {
            return Response(redirect: "/users/login").flash(.error, "You need to login to perform this action")
        }
        return try next.respond(to: request)
    }
}
