import HTTP
import Routing
import Vapor
import Auth
import Fluent
import Flash
import Foundation
import VaporAPNS

public struct Configuration {
    
    public let viewRenderer: Vapor.ViewRenderer
    public let localization: Vapor.Localization
    public let logger: LogProtocol
    
    public init(viewRenderer: Vapor.ViewRenderer,
                localization: Vapor.Localization,
                logger: LogProtocol) {
        self.viewRenderer = viewRenderer
        self.localization = localization
        self.logger = logger
        
//        let notificationsAppId = "com.jimmy.Appie-Tournament"
//        let apnsKeyIdentifier = "YWTTXH2V72"
//        let apnsTeamIdentifier = "GNY93HF8FU"
        
        do {
            var options = try Options(topic: "com.jimmy.Appie-Tournament", teamId: "GNY93HF8FU", keyId: "YWTTXH2V72", keyPath: "\(Droplet().resourcesDir)/Certificates/APNS.p8")
            options.disableCurlCheck = true
            let vaporAPNS = try VaporAPNS(options: options)
        } catch let e {
            print(e)
        }
    }
}

public func configureRoutes<T : Routing.RouteBuilder>(router: T, configuration: Configuration) where T.Value == HTTP.Responder {
    let renderer = configuration.viewRenderer
    let logger = configuration.logger
    
    router.get { (request) -> ResponseRepresentable in
        return Response(redirect: "/teams")
    }
    
    let matchesController = MatchesController(renderer: renderer)
    router.resource("matches", matchesController)
    router.group("matches") { (matches) in
        matches.group(RedirectMiddleware(), closure: { (matchesRedirectRouter) in
            matchesRedirectRouter.get("add", handler: matchesController.getAdd)
            matchesRedirectRouter.post("add", handler: matchesController.add)
            matchesRedirectRouter.get("pending", handler: matchesController.getPending)
            matchesRedirectRouter.post(Match.self, "approve", handler: matchesController.approve)
            matchesRedirectRouter.post(Match.self, "delete", handler: matchesController.delete)
        })
    }
    
    let teamsAdminController = TeamsAdminController(renderer: renderer)
    router.group(RedirectMiddleware(adminOnly: true), closure: { (teamsRedirectRouter) in
        teamsRedirectRouter.resource("admin/teams", teamsAdminController)
        teamsRedirectRouter.group("admin/teams") { (teams) in
            teams.get("add", handler: teamsAdminController.getCreate)
            teams.post("add", handler: teamsAdminController.create)
            teams.get(Team.self, "members", handler: teamsAdminController.getAddMember)
            teams.post(Team.self, "members", handler: teamsAdminController.addMember)
        }
    })
    
    let teamsController = TeamsController(renderer: renderer)
    router.resource("teams", teamsController)
    router.group("teams") { (teams) in
        teams.get("all", handler: teamsController.getAll)
    }
    
    let usersController = UsersController(renderer: renderer, logger: logger)
    router.resource("users", usersController)
    router.group("users") { (users) in
        users.post("login", handler: usersController.login)
        users.get("login", handler: usersController.getLogin)
        users.post("refresh", handler: usersController.refreshToken)
        users.get("logout", handler: usersController.logout)
        users.get("resetpassword", handler: usersController.getResetPassword)
        users.post("resetpassword", handler: usersController.resetPassword)
        users.get("requestresetpassword", handler: usersController.getRequestResetPassword)
        users.post("requestresetpassword", handler: usersController.requestResetPassword)
        users.get("confirmemail", handler: usersController.confirmEmail)
        users.get("requestconfirmemail", handler: usersController.requestConfirmEmail)
        users.post("pushtoken", handler: usersController.registerPushToken)
        users.delete("pushtoken", handler: usersController.deletePushToken)
    }
}

public func configurePreparations(preparations: inout [Preparation.Type]) {
    preparations.append(Match.self)
    preparations.append(Team.self)
    preparations.append(User.self)
    preparations.append(Pivot<User, Team>.self)
    preparations.append(UserSession.self)
    preparations.append(RefreshToken.self)
    preparations.append(PushToken.self)
}

public func configureMiddleware(middleware: inout [Middleware]) {
    middleware.append(FlashMiddleware())
    middleware.append(AuthMiddleware(user: User.self))
    middleware.append(AuthenticatedMiddleware())
}

extension Request {
    
    func respondWithMessage(message: String, redirect: String, status: Status, flashType: Flash.Helper.FlashType) throws -> ResponseRepresentable {
        if accept.prefers("html") {
            return Response(redirect: redirect).flash(flashType, message)
        }
        if flashType == .success || flashType == .info {
            return message
        }
        throw Abort.custom(status: status, message: message)
    }
}
