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
    
    func getAll(request: Request) throws -> ResponseRepresentable {
        return try Team.query().all().makeNode().converted(to: JSON.self).makeResponse()
    }
    
    func makeResource() -> Resource<Team> {
        return Resource(
            index: index
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
