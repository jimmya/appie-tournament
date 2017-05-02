import Vapor
import Fluent
import Foundation

enum MatchResult: Int {
    case Loss = 0
    case Victory
    case Draw
}

// MARK: Model
struct Match: Model {

    var id: Node?
    var teamOneId: Node?
    var teamTwoId: Node?
    var teamOneScore: Int
    var teamTwoScore: Int
    var timestamp: TimeInterval?
    var approved: Bool
    var canApprove: Bool = false
    
    var teamOneScoreChange: Int = 0
    var teamTwoScoreChange: Int = 0

    var dateString: String {
        guard let timestamp = timestamp else {
            return ""
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "nl")
        dateFormatter.dateFormat = "dd-MM-yyyy HH:mm"
        let date = Date(timeIntervalSince1970: timestamp + 7200)
        return dateFormatter.string(from: date)
    }

    var teamOneResult: MatchResult {
        if teamOneScore > teamTwoScore {
            return .Victory
        } else if teamOneScore == teamTwoScore {
            return .Draw
        }
        return .Loss
    }
    var teamTwoResult: MatchResult {
        if teamTwoScore > teamOneScore {
            return .Victory
        } else if teamOneScore == teamTwoScore {
            return .Draw
        }
        return .Loss
    }

    // used by fluent internally
    var exists: Bool = false
}

// MARK: NodeConvertible
extension Match: NodeConvertible {

    init(teamOneId: Node, teamTwoId: Node, teamOneScore: Int, teamTwoScore: Int) {
        self.teamOneId = teamOneId
        self.teamTwoId = teamTwoId
        self.teamOneScore = teamOneScore
        self.teamTwoScore = teamTwoScore
        self.approved = false
    }

    init(node: Node, in context: Context) throws {
        id = node["id"]
        teamOneId = node["team_one_id"]
        teamTwoId = node["team_two_id"]
        teamOneScore = node["team_one_score"]?.int ?? 0
        teamTwoScore = node["team_two_score"]?.int ?? 0
        timestamp = node["timestamp"]?.double
        approved = node["approved"]?.bool ?? false
    }

    func makeNode(context: Context) throws -> Node {
        var matchNode = try Node(node: [
            "id": id,
            "team_one_score": teamOneScore,
            "team_two_score": teamTwoScore,
            "approved": approved
            ])
        switch context {
        case is DatabaseContext:
            matchNode["team_one_id"] = teamOneId
            matchNode["team_two_id"] = teamTwoId
            matchNode["timestamp"] = (timestamp ?? Date().timeIntervalSince1970).makeNode()
        default:
            guard let teamOneName = try Team.find(teamOneId!)?.name,
                let teamTwoName = try Team.find(teamTwoId!)?.name else {
                throw Abort.serverError
            }
            matchNode["team_one_name"] = teamOneName.makeNode()
            matchNode["team_two_name"] = teamTwoName.makeNode()
            matchNode["date"] = dateString.makeNode()
            matchNode["can_approve"] = canApprove.makeNode()
            if teamOneScoreChange > 0 {
                matchNode["team_one_score_change"] = try teamOneScoreChange.makeNode()
            }
            if teamTwoScoreChange > 0 {
                matchNode["team_two_score_change"] = try teamTwoScoreChange.makeNode()
            }
        }
        return matchNode
    }
}

// MARK: Database Preparations
extension Match: Preparation {

    public static var entity: String {
        return "matches"
    }

    static func prepare(_ database: Database) throws {
        try database.create(entity) { matches in
            matches.id()
            matches.int("team_one_id", optional: false)
            matches.int("team_two_id", optional: false)
            matches.int("team_one_score", optional: false)
            matches.int("team_two_score", optional: false)
            matches.double("timestamp", optional: false)
            matches.bool("approved")
        }
    }

    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Merge
extension Match {

    mutating func merge(updates: Match) {
        id = updates.id ?? id
        teamOneId = updates.teamOneId ?? teamOneId
        teamTwoId = updates.teamTwoId ?? teamTwoId
        teamOneScore = updates.teamOneScore
        teamTwoScore = updates.teamTwoScore
        timestamp = updates.timestamp ?? timestamp
        approved = updates.approved
    }
}
