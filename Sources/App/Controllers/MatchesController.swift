import Vapor
import HTTP
import Fluent

final class MatchesController: ResourceRepresentable {
    
    let renderer: Vapor.ViewRenderer
    
    init(renderer: Vapor.ViewRenderer) {
        self.renderer = renderer
    }
    
    func index(request: Request) throws -> ResponseRepresentable {
        if request.accept.prefers("html") {
            return try renderer.make("matches", [
                "matches": Match.query().filter("approved", true).sort("timestamp", .descending).all().makeNode()
                ], for: request)
        }
        return try Match.all().makeNode().converted(to: JSON.self)
    }
    
    func show(request: Request, match: Match) throws -> ResponseRepresentable {
        return match
    }
    
    func makeResource() -> Resource<Match> {
        return Resource(
            index: index,
            show: show
        )
    }
}

extension MatchesController {
    
    func getPending(request: Request) throws -> ResponseRepresentable {
        let user = try request.user()
        var matches: [Match] = []
        if !user.admin {
            let team = try user.team()
            guard let teamId = team.id else {
                throw Abort.serverError
            }
            matches = try Match.query().or({ (query) in
                try query.filter("team_one_id", teamId)
                try query.filter("team_two_id", teamId)
            }).filter("approved", false.makeNode()).all()
        } else {
            matches = try Match.query().filter("approved", false.makeNode()).all()
        }
        
        let processedMatches = try matches.map { (match) -> Match in
            var mutableMatch = match
            if user.admin {
                mutableMatch.canApprove = true
            } else {
                let team = try user.team()
                if team.id == mutableMatch.teamTwoId {
                    mutableMatch.canApprove = true
                }
            }
            return mutableMatch
        }
        
        if request.accept.prefers("html") {
            return try renderer.make("pending", [
                "matches": processedMatches.makeNode()
                ], for: request)
        }
        return try processedMatches.makeNode().converted(to: JSON.self)
    }
    
    func approve(request: Request, match: Match) throws -> ResponseRepresentable {
        let user = try request.user()
        if !user.admin {
            let team = try user.team()
            guard (match.teamOneId == team.id || match.teamTwoId == team.id) else {
                return Response(redirect: "/matches/pending").flash(.success, "This match can't be approved")
            }
        }
        
        var mutableMatch = match
        mutableMatch.approved = true
        try mutableMatch.save()
        
        try recalculateMatches()
        
        return Response(redirect: "/matches").flash(.success, "The match has been approved")
    }
    
    func delete(request: Request, match: Match) throws -> ResponseRepresentable {
        let user = try request.user()
        if !user.admin {
            let team = try user.team()
            guard (match.teamOneId == team.id || match.teamTwoId == team.id) else {
                return Response(redirect: "/matches/pending").flash(.success, "This match can't be deleted")
            }
        }
        return Response(redirect: "/matches/pending").flash(.error, "Unable to delete match")
    }
}

extension MatchesController {
    
    func getAdd(request: Request) throws -> ResponseRepresentable {
        let user = try request.user()
        let team = try user.team()
        guard let teamId = team.id else {
            throw Abort.serverError
        }
        var teams = try Team.query().sort("id", .ascending).filter("id", .notEquals, teamId).all().makeNode()
        if user.admin {
            teams = try Team.query().sort("id", .ascending).all().makeNode()
        }
        return try renderer.make("addmatch", [
            "userteam": team.makeNode(),
            "teams": teams
            ], for: request)
    }
    
    func add(request: Request) throws -> ResponseRepresentable {
        let user = try request.user()
        guard let teamOneId = try request.data["team1"]?.int?.makeNode(),
            let teamTwoId = try request.data["team2"]?.int?.makeNode() else {
                throw Abort.badRequest
        }
        
        let teamOneScore = request.data["team1score"]?.int ?? 0
        let teamTwoScore = request.data["team2score"]?.int ?? 0
        do {
            try Score.validate(input: teamOneScore)
            try Score.validate(input: teamTwoScore)
        } catch {
            return Response(redirect: "/matches").flash(.error, "Invalid scores")
        }
        
        if teamOneId.int == teamTwoId.int {
            return Response(redirect: "/matches").flash(.error, "Teams can't match")
        }
        
        var match = Match(teamOneId: teamOneId, teamTwoId: teamTwoId, teamOneScore: teamOneScore, teamTwoScore: teamTwoScore)
        try match.save()
        
        let approve = request.data["approve"]?.int ?? 0
        if user.admin && approve == 1 {
            guard let teamOneId = match.teamOneId,
                let teamTwoId = match.teamTwoId else {
                    throw Abort.serverError
            }
            guard var teamOne = try Team.find(teamOneId),
                var teamTwo = try Team.find(teamTwoId) else {
                    throw Abort.notFound
            }
            
            let teamOnePoints = teamOne.score
            let teamTwoPoints = teamTwo.score
            try teamOne.updateScore(result: match.teamOneResult, otherTeamScore: teamTwoPoints)
            try teamTwo.updateScore(result: match.teamTwoResult, otherTeamScore: teamOnePoints)
            
            var mutableMatch = match
            mutableMatch.approved = true
            try mutableMatch.save()
        }
        
        if request.accept.prefers("html") {
            return Response(redirect: "/teams").flash(.success, "The match has been added")
        }
        return match
    }
}

extension MatchesController {
    
    func recalculateMatches() throws {
        let matches = try Match.query().filter("approved", true.makeNode()).sort("timestamp", .ascending).all()
        for team in try Team.all() {
            var mutableTeam = team
            mutableTeam.exists = true
            mutableTeam.score = 0
            try mutableTeam.save()
        }
        for currentMatch in matches {
            guard let currentTeamOneId = currentMatch.teamOneId,
                let currentTeamTwoId = currentMatch.teamTwoId,
                var currentTeamOne = try Team.find(currentTeamOneId),
                var currentTeamTwo = try Team.find(currentTeamTwoId) else {
                    continue
            }
            let teamTwoScore = currentTeamTwo.score
            let teamOneScore = currentTeamOne.score
            try currentTeamOne.updateScore(result: currentMatch.teamOneResult, otherTeamScore: teamTwoScore)
            try currentTeamTwo.updateScore(result: currentMatch.teamTwoResult, otherTeamScore: teamOneScore)
        }
    }
}

extension Request {
    
    func match() throws -> Match {
        guard let json = json else {
            throw Abort.badRequest
        }
        return try Match(node: json)
    }
}
