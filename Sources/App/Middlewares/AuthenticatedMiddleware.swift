import Vapor
import HTTP

class AuthenticatedMiddleware: Middleware {
    
    public func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        do {
            let user = try request.user()
            do {
                _ = try user.team()
                request.storage["hasteam"] = true.makeNode()
            } catch {
                
            }
            request.storage["admin"] = user.admin.makeNode()
            request.storage["authenticated"] = true.makeNode()
        } catch {
            
        }
        let response = try next.respond(to: request)
        return response
    }
}
