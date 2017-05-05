import Vapor
import HTTP
import Fluent

final class MatchesController: ResourceRepresentable {
    
    let renderer: Vapor.ViewRenderer
    
    init(renderer: Vapor.ViewRenderer) {
        self.renderer = renderer
    }
    
    func index(request: Request) throws -> ResponseRepresentable {
        let matches = try Match.query().filter("approved", true).sort("timestamp", .ascending).all()
        let teams = try Team.all()
        let recalculatedMatches = try matches.map({ (match) -> Match in
            var mutableMatch = match
            mutableMatch.teamOneScoreChange = try pointsChangeForMatch(withId: match.id, forTeamWithId: match.teamOneId, allMatches: matches, teams: teams)
            mutableMatch.teamTwoScoreChange = try pointsChangeForMatch(withId: match.id, forTeamWithId: match.teamTwoId, allMatches: matches, teams: teams)
            return mutableMatch
        })
        if request.accept.prefers("html") {
            return try renderer.make("matches", [
                "matches": recalculatedMatches.reversed().makeNode()
                ], for: request)
        }
        return try recalculatedMatches.makeNode().converted(to: JSON.self)
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
                return try request.respondWithMessage(message: "This match can't be approved", redirect: "/matches/pending", status: .badRequest, flashType: .error)
            }
        }
        
        var mutableMatch = match
        mutableMatch.approved = true
        try mutableMatch.save()
        
        try recalculateMatches()
        
        return try request.respondWithMessage(message: "The match has been approved", redirect: "/matches", status: .ok, flashType: .success)
    }
    
    func delete(request: Request, match: Match) throws -> ResponseRepresentable {
        let user = try request.user()
        if !user.admin {
            let team = try user.team()
            guard (match.teamOneId == team.id || match.teamTwoId == team.id) else {
                return try request.respondWithMessage(message: "This match can't be deleted", redirect: "/matches/pending", status: .badRequest, flashType: .error)
            }
        }
        try match.delete()
        
        return try request.respondWithMessage(message: "The match has been deleted", redirect: "/matches/pending", status: .ok, flashType: .success)
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
        
        if request.accept.prefers("html") {
            return try renderer.make("addmatch", [
                "userteam": team.makeNode(),
                "teams": teams
                ], for: request)
        }
        return try teams.makeNode().converted(to: JSON.self)
    }
    
    func add(request: Request) throws -> ResponseRepresentable {
        let user = try request.user()
        guard let teamOneId = try request.data["team1"]?.int?.makeNode(),
            let teamTwoId = try request.data["team2"]?.int?.makeNode() else {
                return try request.respondWithMessage(message: "Something went wrong", redirect: "/matches", status: .badRequest, flashType: .error)
        }
        
        let teamOneScore = request.data["team1score"]?.int ?? 0
        let teamTwoScore = request.data["team2score"]?.int ?? 0
        do {
            try Score.validate(input: teamOneScore)
            try Score.validate(input: teamTwoScore)
        } catch {
            return try request.respondWithMessage(message: "Invalid scores", redirect: "/matches", status: .badRequest, flashType: .error)
        }
        
        if teamOneId.int == teamTwoId.int {
            return try request.respondWithMessage(message: "Teams can't match", redirect: "/matches", status: .badRequest, flashType: .error)
        }
        
        var match = Match(teamOneId: teamOneId, teamTwoId: teamTwoId, teamOneScore: teamOneScore, teamTwoScore: teamTwoScore)
        try match.save()
        
        let approve = request.data["approve"]?.int ?? 0
        if user.admin && approve == 1 {
            var mutableMatch = match
            mutableMatch.approved = true
            try mutableMatch.save()
            
            try recalculateMatches()
        }
        
        return try request.respondWithMessage(message: "The match has been added", redirect: "/teams", status: .ok, flashType: .success)
    }
}

extension MatchesController {
    
    func calculateTeamScoresUntilMatchWithId(matchId: Node?, includeMatch: Bool = false, teams: [Team], matches: [Match]) throws -> [Team] {
        var recalculatedTeams = teams.map({ (team) -> Team in
            var mutableTeam = team
            mutableTeam.exists = true
            mutableTeam.score = 0
            return mutableTeam
        })
        for currentMatch in matches {
            if currentMatch.id == matchId && !includeMatch {
                break
            }
            guard var teamOne = team(withId: currentMatch.teamOneId, fromArray: recalculatedTeams),
                var teamTwo = team(withId: currentMatch.teamTwoId, fromArray: recalculatedTeams) else {
                    continue
            }
            let teamTwoScore = teamTwo.score
            let teamOneScore = teamOne.score
            try teamOne.updateScore(result: currentMatch.teamOneResult, otherTeamScore: teamTwoScore)
            try teamTwo.updateScore(result: currentMatch.teamTwoResult, otherTeamScore: teamOneScore)
            recalculatedTeams = updateTeam(team: teamOne, inArray: recalculatedTeams)
            recalculatedTeams = updateTeam(team: teamTwo, inArray: recalculatedTeams)
            if currentMatch.id == matchId && includeMatch {
                break
            }
        }
        return recalculatedTeams
    }
    
    func recalculateMatches() throws {
        let matches = try Match.query().filter("approved", true.makeNode()).sort("timestamp", .ascending).all()
        let teams = try Team.all()
        let recalculatedTeams = try calculateTeamScoresUntilMatchWithId(matchId: nil, teams: teams, matches: matches)
        try recalculatedTeams.forEach { (team) in
            var mutableTeam = team
            mutableTeam.exists = true
            try mutableTeam.save()
        }
    }
    
    func pointsChangeForMatch(withId matchId: Node?, forTeamWithId teamId: Node?, allMatches matches: [Match], teams: [Team]) throws -> Int {
        let recalculatedTeamsPreMatch = try calculateTeamScoresUntilMatchWithId(matchId: matchId, teams: teams, matches: matches)
        let recalculatedTeamsPostMatch = try calculateTeamScoresUntilMatchWithId(matchId: matchId, includeMatch: true, teams: teams, matches: matches)
        var teamScoreChange = 0
        for team in recalculatedTeamsPostMatch {
            if team.id == teamId {
                teamScoreChange = Int(team.score)
                break
            }
        }
        for team in recalculatedTeamsPreMatch {
            if team.id == teamId {
                teamScoreChange -= Int(team.score)
                break
            }
        }
        return teamScoreChange
    }
    
    func team(withId teamId: Node?, fromArray teams: [Team]) -> Team? {
        return teams.filter({ (team) -> Bool in
            return team.id == teamId
        }).first
    }
    
    func updateTeam(team: Team, inArray teams: [Team]) -> [Team] {
        return teams.map { (currentTeam) -> Team in
            var mutableCurrentTeam = currentTeam
            if mutableCurrentTeam.id == team.id {
                mutableCurrentTeam.score = team.score
            }
            return mutableCurrentTeam
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
