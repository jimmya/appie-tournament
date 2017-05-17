import Vapor
import Fluent
import Foundation

// MARK: Model
struct Team: Model {
    
    var id: Node?
    var name: String?
    var score: Double
    var position: Int = 0
    var matches: [Match]?
    
    // used by fluent internally
    var exists: Bool = false
}

// MARK: NodeConvertible
extension Team: NodeConvertible {
    
    init(node: Node, in context: Context) throws {
        id = node["id"]
        name = node["name"]?.string
        score = node["score"]?.double ?? 0
    }
    
    func makeNode(context: Context) throws -> Node {
        var teamNode = try Node(node: [
                "id": id,
                "name": name,
            ])
        let members = try self.members().all()
        let memberNames = members.flatMap { (user) -> String? in
            return user.username
        }.joined(separator: ", ")
        switch context {
        case is DatabaseContext:
            teamNode["score"] = score.makeNode()
        default:
            teamNode["score"] = try Int(score).makeNode()
            teamNode["members"] = try members.makeNode()
            teamNode["position"] = try position.makeNode()
            teamNode["memberNames"] = memberNames.makeNode()
            if let matches = matches {
                teamNode["matches"] = try matches.makeNode()
            }
        }
        return teamNode
    }
}

// MARK: Database Preparations
extension Team: Preparation {
    
    static func prepare(_ database: Database) throws {
        try database.create(entity) { teams in
            teams.id()
            teams.string("name", optional: false)
            teams.double("score", optional: false)
        }
    }
    
    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Merge
extension Team {
    
    mutating func merge(updates: Team) {
        id = updates.id ?? id
        name = updates.name ?? name
        score = updates.score
    }
}

// MARK: Score
extension Team {
    
    mutating func updateScore(result: MatchResult, otherTeamScore: Double) throws {
        switch result {
        case .Loss:
            break
        case .Victory:
            score += 50 + (max(0.0, otherTeamScore - score) / 2)
        case .Draw:
            score += 25 + (max(0.0, otherTeamScore - score) / 3)
        }
    }
}

extension Team {
    
    func members() throws -> Siblings<User> {
        return try siblings()
    }
}
