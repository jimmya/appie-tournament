import Foundation
import Vapor
import HTTP
import Fluent

final class TeamsController: ResourceRepresentable {
    
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
            return try renderer.make("teams", ["teams": sortedTeams.makeNode()], for: request)
        }
        return try sortedTeams.makeNode().converted(to: JSON.self).makeResponse()
    }
    
    func show(request: Request, team: Team) throws -> ResponseRepresentable {
        if request.accept.prefers("html") {
            guard let teamId = team.id else {
                return Response(redirect: "/teams").flash(.error, "Something went wrong please try again")
            }
            let matches = try Match.query().or({ (query) in
                try query.filter("team_one_id", teamId)
                try query.filter("team_two_id", teamId)
            }).filter("approved", true.makeNode()).sort("timestamp", .descending).all().makeNode()
            return try renderer.make("team", ["team": team, "matches": matches], for: request)
        }
        return team
    }
    
    func getAll(request: Request) throws -> ResponseRepresentable {
        return try Team.query().all().makeNode().converted(to: JSON.self).makeResponse()
    }
    
    func makeResource() -> Resource<Team> {
        return Resource(
            index: index,
            show: show
        )
    }
}

extension Request {
    
    func team() throws -> Team {
        guard let json = json else {
            throw Abort.badRequest
        }
        return try Team(node: json)
    }
}
