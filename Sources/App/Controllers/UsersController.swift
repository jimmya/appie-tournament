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
                return Response(redirect: "/users").flash(.error, "Please fill in all fields")
        }
        guard passwordConfirm == password else {
            return Response(redirect: "/users").flash(.error, "Passwords do not match")
        }
        guard let team = try Team.find(teamId) else {
            return Response(redirect: "/users").flash(.error, "Team not found")
        }

        let credentials = UsernamePassword(username: username, password: password)
        var user: User?
        do {
            user = try User.register(credentials: credentials) as? User
        } catch {
            return Response(redirect: "/users").flash(.error, "Password is not secure enough")
        }
        guard var unwrappedUser = user else {
            return Response(redirect: "/users").flash(.error, "Something went wrong, please try again")
        }
        let existingUserCount = try User.query().or({ (query) in
            try query.filter("username", username)
            try query.filter("email", email)
        }).count()
        guard existingUserCount == 0 else {
            return Response(redirect: "/users").flash(.error, "A user with these credentials allready exists")
        }
        do {
            unwrappedUser.email = try email.validated()
            try unwrappedUser.save()
            let email = unwrappedUser.email?.value ?? ""
            var pivot = Pivot<Team, User>(team, unwrappedUser)
            try pivot.save()
            return Response(redirect: "/users/requestconfirmemail?email=\(email)")
        } catch {
            return Response(redirect: "/users").flash(.error, "Invalid emailadress")
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
                return Response(redirect: "/users/login").flash(.error, "Please fill in all fields")
        }
        let credentials = UsernamePassword(username: email, password: password)
        do {
            guard let user = try User.authenticate(credentials: credentials) as? User else {
                throw Abort.serverError
            }
            guard user.verified else {
                return Response(redirect: "/users/requestconfirmemail").flash(.error, "This account has not yet been activated. Please check your email for a confirmation mail. Or request a new confirmation email by entering your emailadress below.")
            }
            let response = Response(redirect: "/teams")
            let cookie = try user.generateCookie()
            response.cookies.insert(cookie)
            return response
        } catch {
            return Response(redirect: "/users/login").flash(.error, "Invalid login credentials")
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

    func getRequestResetPassword(request: Request) throws -> ResponseRepresentable {
        if request.accept.prefers("html") {
            return try renderer.make("requestresetpassword", for: request)
        }
        throw Abort.badRequest
    }

    func requestResetPassword(request: Request) throws -> ResponseRepresentable {
        guard let email = request.data["email"]?.string else {
            return Response(redirect: "/users/requestresetpassword").flash(.error, "Please fill in all fields")
        }
        guard let user = try User.query().filter("email", email).first(),
            let userId = user.id else {
                return Response(redirect: "/users/requestresetpassword").flash(.error, "A user with this emailadress doesn't exist. Please try again")
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
            return Response(redirect: "/users/requestresetpassword").flash(.error, "Something went wrong please try again")
        }
        return Response(redirect: "/users/login").flash(.success, "An email with instructions how to reset your password has been sent")
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
                return Response(redirect: "/users/resetpassword").flash(.error, "Please fill in all fields")
        }
        let redirectUrl = "/users/resetpassword?email=\(email)&token=\(tokenString)"
        guard password == passwordConfirm else {
            return Response(redirect: redirectUrl).flash(.error, "Passwords don't match")
        }
        do {
            try Password.validate(input: password)
        } catch {
              return Response(redirect: redirectUrl).flash(.error, "Password is not secure enough")
        }
        guard var user = try User.query().filter("email", email).first(),
            let userId = user.id else {
                return Response(redirect: redirectUrl).flash(.error, "A user with this emailadress doesn't exist. Please try again")
        }
        let queryToken = try UserSession.query().filter("uuid", tokenString).filter("user_id", userId).first()
        guard let token = queryToken,
            let expires = token.expires else {
                return Response(redirect: redirectUrl).flash(.error, "The request to reset your password has been expired. Please try again")
        }
        guard Date().timeIntervalSince1970 < expires else {
            return Response(redirect: redirectUrl).flash(.error, "The request to reset your password has been expired. Please try again")
        }
        user.password = try BCrypt.digest(password: password)
        try user.save()
        try token.delete()
        return Response(redirect: "/users/login").flash(.success, "You password has been changed")
    }

    func logout(request: Request) throws -> ResponseRepresentable {
        let response = Response(redirect: "/teams")
        let cookie = Cookie(name: "login", value: "", expires: Date())
        response.cookies.insert(cookie)
        return response
    }

    func confirmEmail(request: Request) throws -> ResponseRepresentable {
        guard let token = request.query?["token"] else {
            return Response(redirect: "/users/requestconfirmemail").flash(.error, "This verification token has expired, enter your emailadress below to request a new confirmation email.")
        }
        guard let userSession = try UserSession.query().filter("uuid", token).first() else {
            return Response(redirect: "/users/requestconfirmemail").flash(.error, "This verification token has expired, enter your emailadress below to request a new confirmation email.")
        }
        if userSession.expires ?? 0 < Date().timeIntervalSince1970 {
            return Response(redirect: "/users/requestconfirmemail").flash(.error, "This verification token has expired, enter your emailadress below to request a new confirmation email.")
        }
        guard let userId = userSession.userId,
            let user = try User.find(userId) else {
            return Response(redirect: "/users/login").flash(.error, "Something went wrong. Please try again")
        }
        var editableUser = user
        editableUser.verified = true
        try editableUser.save()
        try userSession.delete()
        return Response(redirect: "/users/login").flash(.success, "Your account has been verified")
    }

    func requestConfirmEmail(request: Request) throws -> ResponseRepresentable {
        guard let email = request.query?["email"] else {
            try request.flash.add(.info, "Enter your email below to request a new confirmation email")
            return try renderer.make("requestemailconfirmation", for: request)
        }
        guard let user = try User.query().filter("email", email).first(),
            let userId = user.id else {
            return Response(redirect: "/users/login").flash(.error, "Something went wrong. Please try again")
        }
        guard !user.verified else {
            return Response(redirect: "/users/login").flash(.warning, "This account has allready been activated")
        }
        var userSession = UserSession(userId: userId)
        try userSession.save()
        guard let token = userSession.uuid else {
            throw Abort.serverError
        }

        let config = Droplet().config
        let host = config["app", "host"]?.string ?? "http://localhost:8090"
        let subject = "Confirm account"
        let message = "To confirm your account visit the link below.<br /><br /><a href=\"\(host)/users/confirmemail?token=\(token)\">Confirm your account here.</a>"
        let emailResponse = try user.sendEmail(subject: subject, message: message)
        guard emailResponse.status == .ok else {
            logger.error("Sending password reset email failed: \(emailResponse.body.bytes?.string ?? "n/a")")
            return Response(redirect: "/users/requestresetpassword").flash(.error, "Something went wrong please try again")
        }
        return Response(redirect: "/users/login").flash(.success, "An email with instructions how to activate your account has been sent")
    }
}
