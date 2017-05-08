import Vapor
import HTTP
import Auth
import Turnstile
import BCrypt
import Foundation
import JWT
import Cookies
import Fluent

final class UsersController: ResourceRepresentable {

    let renderer: Vapor.ViewRenderer
    let logger: LogProtocol

    init(renderer: Vapor.ViewRenderer, logger: LogProtocol) {
        self.renderer = renderer
        self.logger = logger
    }

    func index(request: Request) throws -> ResponseRepresentable {
        do {
            _ = try request.user()
            return Response(redirect: "/teams")
        } catch {
            if request.accept.prefers("html") {
                let teams = try Team.query().sort("id", .ascending).all().makeNode()
                return try renderer.make("register", ["teams": teams], for: request)
            }
            throw Abort.badRequest
        }
    }

    func create(request: Request) throws -> ResponseRepresentable {
        guard let username = request.data["username"]?.string,
            let password = request.data["password"]?.string,
            let passwordConfirm = request.data["passwordConfirm"]?.string,
            let email = request.data["email"]?.string,
            let teamId = try request.data["team"]?.int?.makeNode() else {
                return try request.respondWithMessage(message: "Please fill in all the fields", redirect: "/users", status: .badRequest, flashType: .error)
        }
        guard passwordConfirm == password else {
            return try request.respondWithMessage(message: "Passwords do not match", redirect: "/users", status: .badRequest, flashType: .error)
        }
        guard let team = try Team.find(teamId) else {
            return try request.respondWithMessage(message: "Team not found", redirect: "/users", status: .badRequest, flashType: .error)
        }

        let credentials = UsernamePassword(username: username, password: password)
        var user: User?
        do {
            user = try User.register(credentials: credentials) as? User
        } catch {
            return try request.respondWithMessage(message: "Password is not secure enough", redirect: "/users", status: .badRequest, flashType: .error)
        }
        guard var unwrappedUser = user else {
            return try request.respondWithMessage(message: "Something went wrong, please try again", redirect: "/users", status: .internalServerError, flashType: .error)
        }
        let existingUserCount = try User.query().or({ (query) in
            try query.filter("username", username)
            try query.filter("email", email)
        }).count()
        guard existingUserCount == 0 else {
            return try request.respondWithMessage(message: "A user with these credentials allready exists", redirect: "/users", status: .badRequest, flashType: .error)
        }
        do {
            unwrappedUser.email = try email.validated()
            try unwrappedUser.save()
            let email = unwrappedUser.email?.value ?? ""
            var pivot = Pivot<Team, User>(team, unwrappedUser)
            try pivot.save()
            return Response(redirect: "/users/requestconfirmemail?email=\(email)")
        } catch {
            return try request.respondWithMessage(message: "Invalid emailadress", redirect: "/users", status: .badRequest, flashType: .error)
        }
    }

    func makeResource() -> Resource<User> {
        return Resource(
            index: index,
            store: create
        )
    }
}

extension UsersController {

    func login(request: Request) throws -> ResponseRepresentable {
        guard let email = request.data["email"]?.string,
            let password = request.data["password"]?.string else {
                return try request.respondWithMessage(message: "Please fill in all fields.", redirect: "/users/login", status: .badRequest, flashType: .error)
        }
        let credentials = UsernamePassword(username: email, password: password)
        do {
            guard let user = try User.authenticate(credentials: credentials) as? User else {
                return try request.respondWithMessage(message: "Something went wrong, please try again.", redirect: "/users/login", status: .internalServerError, flashType: .error)
            }
            guard user.verified else {
                return try request.respondWithMessage(message: "This account has not yet been activated. Please check your email for a confirmation mail. Or request a new confirmation email.", redirect: "/users/requestconfirmemail", status: .badRequest, flashType: .error)
            }
            if request.accept.prefers("html") {
                let response = Response(redirect: "/teams")
                let cookie = try user.generateCookie()
                response.cookies.insert(cookie)
                return response
            }
            return try returnToken(request: request, user: user)
        } catch {
            return try request.respondWithMessage(message: "Invalid login credentials.", redirect: "/users/login", status: .badRequest, flashType: .error)
        }
    }

    func getLogin(request: Request) throws -> ResponseRepresentable {
        if request.accept.prefers("html") {
            return try renderer.make("login", for: request)
        }
        throw Abort.badRequest
    }
}

extension UsersController {
    
    func refreshToken(request: Request) throws -> ResponseRepresentable {
        guard let refreshUserId = request.data["user_id"]?.int,
            let refreshToken = request.data["refresh_token"]?.string else {
                throw Abort.badRequest
        }
        let refreshCredentials = RefreshCredentials(string: refreshToken, userId: refreshUserId)
        guard let user = try User.authenticate(credentials: refreshCredentials) as? User else {
            throw Abort.badRequest
        }
        return try returnToken(request: request, user: user)
    }
}

extension UsersController {

    func getRequestResetPassword(request: Request) throws -> ResponseRepresentable {
        if request.accept.prefers("html") {
            return try renderer.make("requestresetpassword", for: request)
        }
        throw Abort.badRequest
    }

    func requestResetPassword(request: Request) throws -> ResponseRepresentable {
        guard let email = request.data["email"]?.string else {
            return try request.respondWithMessage(message: "Please fill in all fields.", redirect: "/users/requestresetpassword", status: .badRequest, flashType: .error)
        }
        guard let user = try User.query().filter("email", email).first(),
            let userId = user.id else {
                return try request.respondWithMessage(message: "A user with this emailadress doesn't exist.", redirect: "/users/requestresetpassword", status: .notFound, flashType: .error)
        }
        var userSession = UserSession(userId: userId)
        try userSession.save()
        guard let token = userSession.uuid else {
            throw Abort.serverError
        }
        let config = Droplet().config
        let host = config["app", "host"]?.string ?? "http://localhost:8090"
        let subject = "Password reset"
        let message = "A request has been made to reset your password. To change your password visit the link below. If you want to keep your current password just ignore this email.<br /><br /><a href=\"\(host)/users/resetpassword?email=\(email)&token=\(token)\">Reset your password here.</a>"
        let emailResponse = try user.sendEmail(subject: subject, message: message)
        guard emailResponse.status == .ok else {
            logger.error("Sending password reset email failed: \(emailResponse.body.bytes?.string ?? "n/a")")
            return try request.respondWithMessage(message: "Something went wrong please try again.", redirect: "/users/requestresetpassword", status: .internalServerError, flashType: .error)
        }
        return try request.respondWithMessage(message: "An email with instructions how to reset your password has been sent.", redirect: "/users/login", status: .ok, flashType: .success)
    }
}

extension UsersController {

    func getResetPassword(request: Request) throws -> ResponseRepresentable {
        guard request.accept.prefers("html") else {
            throw Abort.badRequest
        }
        request.storage["email"] = request.query?["email"]
        request.storage["token"] = request.query?["token"]
        return try renderer.make("resetpassword", for: request)
    }

    func resetPassword(request: Request) throws -> ResponseRepresentable {
        guard let email = request.data["email"]?.string,
            let tokenString = request.data["token"]?.string,
            let password = request.data["password"]?.string,
            let passwordConfirm = request.data["passwordConfirm"]?.string else {
                return try request.respondWithMessage(message: "Please fill in all fields.", redirect: "/users/resetpassword", status: .badRequest, flashType: .error)
        }
        let redirectUrl = "/users/resetpassword?email=\(email)&token=\(tokenString)"
        guard password == passwordConfirm else {
            return try request.respondWithMessage(message: "Passwords don't match.", redirect: redirectUrl, status: .badRequest, flashType: .error)
        }
        do {
            try Password.validate(input: password)
        } catch {
            return try request.respondWithMessage(message: "Passwords is not secure enough.", redirect: redirectUrl, status: .badRequest, flashType: .error)
        }
        guard var user = try User.query().filter("email", email).first(),
            let userId = user.id else {
                return try request.respondWithMessage(message: "A user with this emailadress doesn't exist.", redirect: redirectUrl, status: .badRequest, flashType: .error)
        }
        let queryToken = try UserSession.query().filter("uuid", tokenString).filter("user_id", userId).first()
        guard let token = queryToken,
            let expires = token.expires else {
                return try request.respondWithMessage(message: "The request to reset your password has been expired.", redirect: redirectUrl, status: .badRequest, flashType: .error)
        }
        guard Date().timeIntervalSince1970 < expires else {
            return try request.respondWithMessage(message: "The request to reset your password has been expired.", redirect: redirectUrl, status: .badRequest, flashType: .error)
        }
        user.password = try BCrypt.digest(password: password)
        try user.save()
        try token.delete()
        return try request.respondWithMessage(message: "Your password has been changed.", redirect: "/users/login", status: .ok, flashType: .success)
    }

    func logout(request: Request) throws -> ResponseRepresentable {
        let response = Response(redirect: "/teams")
        let cookie = Cookie(name: "login", value: "", expires: Date())
        response.cookies.insert(cookie)
        return response
    }

    func confirmEmail(request: Request) throws -> ResponseRepresentable {
        guard let token = request.query?["token"] else {
            return try request.respondWithMessage(message: "This verification token has expired, enter your emailadress below to request a new confirmation email.", redirect: "/users/requestconfirmemail", status: .badRequest, flashType: .error)
        }
        guard let userSession = try UserSession.query().filter("uuid", token).first() else {
            return try request.respondWithMessage(message: "This verification token has expired, enter your emailadress below to request a new confirmation email.", redirect: "/users/requestconfirmemail", status: .badRequest, flashType: .error)
        }
        if userSession.expires ?? 0 < Date().timeIntervalSince1970 {
            return try request.respondWithMessage(message: "This verification token has expired, enter your emailadress below to request a new confirmation email.", redirect: "/users/requestconfirmemail", status: .badRequest, flashType: .error)
        }
        guard let userId = userSession.userId,
            let user = try User.find(userId) else {
                return try request.respondWithMessage(message: "Something went wrong. Please try again.", redirect: "/users/login", status: .badRequest, flashType: .error)
        }
        var editableUser = user
        editableUser.verified = true
        try editableUser.save()
        try userSession.delete()
        return try request.respondWithMessage(message: "Your account has been verified.", redirect: "/users/login", status: .ok, flashType: .success)
    }

    func requestConfirmEmail(request: Request) throws -> ResponseRepresentable {
        guard let email = request.query?["email"] else {
            try request.flash.add(.info, "Enter your email below to request a new confirmation email")
            if request.accept.prefers("html") {
                return try renderer.make("requestemailconfirmation", for: request)
            }
            return try request.respondWithMessage(message: "Not supported", redirect: "", status: .notImplemented, flashType: .error)
        }
        guard let user = try User.query().filter("email", email).first(),
            let userId = user.id else {
                return try request.respondWithMessage(message: "Something went wrong. Please try again", redirect: "/users/login", status: .internalServerError, flashType: .error)
        }
        guard !user.verified else {
            return try request.respondWithMessage(message: "This account has allready been activated", redirect: "/users/login", status: .notModified, flashType: .warning)
        }
        var userSession = UserSession(userId: userId)
        try userSession.save()
        guard let token = userSession.uuid else {
            return try request.respondWithMessage(message: "Something went wrong. Please try again", redirect: "/users/login", status: .internalServerError, flashType: .error)
        }

        let config = Droplet().config
        let host = config["app", "host"]?.string ?? "http://localhost:8090"
        let subject = "Confirm account"
        let message = "To confirm your account visit the link below.<br /><br /><a href=\"\(host)/users/confirmemail?token=\(token)\">Confirm your account here.</a>"
        let emailResponse = try user.sendEmail(subject: subject, message: message)
        guard emailResponse.status == .ok else {
            logger.error("Sending password reset email failed: \(emailResponse.body.bytes?.string ?? "n/a")")
            return try request.respondWithMessage(message: "Something went wrong. Please try again", redirect: "/users/login", status: .internalServerError, flashType: .error)
        }
        return try request.respondWithMessage(message: "An email with instructions how to activate your account has been sent.", redirect: "/users/login", status: .ok, flashType: .success)
    }
}

extension UsersController {
    
    func registerPushToken(request: Request) throws -> ResponseRepresentable {
        guard let token = request.data["token"]?.string else {
            return try request.respondWithMessage(message: "Invalid request.", redirect: "", status: .badRequest, flashType: .error)
        }
        let user = try request.user()
        if try user.pushTokens().filter("token", token).count() > 0 {
            return try request.respondWithMessage(message: "Token allready registered.", redirect: "", status: .notModified, flashType: .success)
        }
        var pushToken = PushToken(token: token, userId: user.id)
        try pushToken.save()
        return try request.respondWithMessage(message: "Token has been saved.", redirect: "", status: .ok, flashType: .success)
    }
    
    func deletePushToken(request: Request) throws -> ResponseRepresentable {
        guard let token = request.data["token"]?.string else {
            return try request.respondWithMessage(message: "Invalid request.", redirect: "", status: .badRequest, flashType: .error)
        }
        let user = try request.user()
        guard let pushToken = try user.pushTokens().filter("token", contains: token).first() else {
            return try request.respondWithMessage(message: "Token not found.", redirect: "", status: .notFound, flashType: .error)
        }
        try pushToken.delete()
        return try request.respondWithMessage(message: "Token has been deleted.", redirect: "", status: .ok, flashType: .success)
    }
}

private extension UsersController {
    
    func returnToken(request: Request, user: User) throws -> ResponseRepresentable {
        let accessToken = try user.generateAccessToken()
        let refreshToken = try user.generateRefreshToken()
        let accessTokenValidDuration: Double = Droplet().config["app", "token_valid_duration"]?.double ?? 0
        let expirationDate = Date().addingTimeInterval(accessTokenValidDuration).timeIntervalSince1970
        return try Response(status: Status.ok, json: JSON(Node(
            ["token": .string(accessToken),
             "token_valid_duration": .number(.double(accessTokenValidDuration)),
             "token_expiration_date": .number(.double(expirationDate)),
             "refresh_token": .string(refreshToken),
             "user": user.makeNode()])))
    }
}
