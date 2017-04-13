import Vapor
import HTTP
import Fluent

final class TeamsAdminController: ResourceRepresentable {
    
    let renderer: Vapor.ViewRenderer
    
    init(renderer: Vapor.ViewRenderer) {
        self.renderer = renderer
    }
    
    func index(request: Request) throws -> ResponseRepresentable {
        let teams = try Team.query().sort("score", .descending).all()
        var sortedTeams: [Team] = []
        for (index, team) in teams.enumerated() {
            var mutableTeam = team
            mutableTeam.position = index + 1
            sortedTeams.append(mutableTeam)
        }
        if request.accept.prefers("html") {
            return try renderer.make("adminteams", ["teams": sortedTeams.makeNode()], for: request)
        }
        return try sortedTeams.makeNode().converted(to: JSON.self).makeResponse()
    }
    
    func show(request: Request, team: Team) throws -> ResponseRepresentable {
        if request.accept.prefers("html") {
            guard let teamId = team.id else {
                return Response(redirect: "/admin/teams").flash(.error, "Something went wrong please try again")
            }
            let matches = try Match.query().or({ (query) in
                try query.filter("team_one_id", teamId)
                try query.filter("team_two_id", teamId)
            }).sort("timestamp", .descending).all().makeNode()
            return try renderer.make("adminteam", ["team": team, "matches": matches], for: request)
        }
        return team
    }
    
    func makeResource() -> Resource<Team> {
        return Resource(
            index: index,
            show: show
        )
    }
}

extension TeamsAdminController {
    
    func getAddMember(request: Request, team: Team) throws -> ResponseRepresentable {
        let users = try User.query().all().array
        var filteredUsers: [User] = []
        for user in users {
            do {
                _ = try user.team()
            } catch {
                filteredUsers.append(user)
            }
        }
        return try renderer.make("addteammember", ["users": filteredUsers.makeNode()], for: request)
    }
    
    func addMember(request: Request, team: Team) throws -> ResponseRepresentable {
        guard let memberId = try request.data["member"]?.int?.makeNode() else {
            return Response(redirect: "/admin/teams").flash(.error, "Something went wrong please try again")
        }
        guard let member = try User.find(memberId) else {
            return Response(redirect: "/admin/teams").flash(.error, "Something went wrong please try again")
        }
        guard try Pivot<Team, User>.query().filter("user_id", memberId).count() == 0 else {
            return Response(redirect: "/admin/teams").flash(.error, "Something went wrong please try again")
        }
        
        var pivot = Pivot<Team, User>(team, member)
        try pivot.save()
        return Response(redirect: "/admin/teams").flash(.success, "The user has been added to the team")
    }
}
    
extension TeamsAdminController {
        
    func getCreate(request: Request) throws -> ResponseRepresentable {
        if request.accept.prefers("html") {
            return try renderer.make("createteam", for: request)
        }
        throw Abort.badRequest
    }
    
    func create(request: Request) throws -> ResponseRepresentable {
        guard let name = request.data["name"]?.string else {
            return Response(redirect: "/admin/teams/add").flash(.error, "Please fill in all fields")
        }
        var team = Team(id: nil, name: name, score: 0, position: 0, exists: false)
        try team.save()
        return Response(redirect: "/admin/teams").flash(.success, "Team has been added")
    }
}
