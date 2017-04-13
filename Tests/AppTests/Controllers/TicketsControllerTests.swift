import Vapor
import Fluent
import HTTP
import XCTest

@testable import App

class TicketsControllerTests: XCTestCase {
    
    let ticketsController = TicketsController()
    
    static var allTests : [(String, (TicketsControllerTests) -> () throws -> Void)] {
        return [
            ("testGetTicket", testGetTicket),
            ("testGetAllTickets", testGetAllTickets),
            ("testGetUserTickets", testGetUserTickets),
            ("testCreateTicketUnauthorized", testCreateTicketUnauthorized),
            ("testCreateTicket", testCreateTicket),
            ("testCreateTicketBadRequest", testCreateTicketBadRequest),
            ("testDeleteTicket", testDeleteTicket),
            ("testDeleteTicketUnauthorized", testDeleteTicketUnauthorized),
            ("testDeleteTicketOtherUser", testDeleteTicketOtherUser),
            ("testUpdateTicket", testUpdateTicket),
            ("testUpdateTicketUnauthorized", testUpdateTicketUnauthorized),
            ("testUpdateTicketOtherUser", testUpdateTicketOtherUser),
        ]
    }
    
    override func setUp() {
        super.setUp()
        
        let driver = MemoryDriver()
        Database.default = Database(driver)
    }
    
    func testGetTicket() throws {
        var ticket = Ticket(id: Node(.int(1)), title: "TestTitle", userId: Node(.int(1)), exists: false)
        try ticket.save()
        let request = try Request(method: .get, uri: "")
        let retrievedTicket = try ticketsController.show(request: request, ticket: ticket) as! Ticket
        XCTAssertNotNil(retrievedTicket)
        XCTAssertEqual(retrievedTicket.title, "TestTitle")
        XCTAssertEqual(retrievedTicket.id, ticket.id)
        XCTAssertEqual(retrievedTicket.userId, ticket.userId)
    }
    
    func testGetAllTickets() throws {
        var ticket = Ticket(id: Node(.int(1)), title: "TestTitle", userId: Node(.int(1)), exists: false)
        try ticket.save()
        let request = try Request(method: .get, uri: "")
        let tickets = try ticketsController.index(request: request) as! JSON
        XCTAssertEqual(tickets.node.array?.count, 1)
    }
    
    func testGetUserTickets() throws {
        var ticket = Ticket(id: Node(.int(1)), title: "TestTitle", userId: Node(.int(1)), exists: false)
        try ticket.save()
        var ticket2 = Ticket(id: Node(.int(2)), title: "TestTitle", userId: Node(.int(2)), exists: false)
        try ticket2.save()
        let accessToken = try createMockUserIfNeeded().generateAccessToken()
        let request = try Request(method: .get, uri: "", headers: ["Authorization": accessToken])
        let tickets = try ticketsController.index(request: request) as! JSON
        XCTAssertEqual(tickets.node.array?.count, 1)
    }
    
    func testCreateTicketUnauthorized() throws {
        let request = try mockCreateTicketRequest(accessToken: nil, userId: 1)
        XCTAssertThrowsError(try ticketsController.create(request: request))
    }
    
    func testCreateTicket() throws {
        let title = "Title"
        let user = try createMockUserIfNeeded()
        let accessToken = try user.generateAccessToken()
        let request = try mockCreateTicketRequest(accessToken: accessToken, title: title, userId: 1)
        let ticket = try ticketsController.create(request: request) as! Ticket
        XCTAssertNotNil(ticket)
        XCTAssertEqual(ticket.title, title)
        XCTAssertEqual(ticket.userId, user.id)
    }
    
    func testCreateTicketBadRequest() throws {
        let accessToken = try createMockUserIfNeeded().generateAccessToken()
        let request = try Request(method: .post, uri: "", headers: ["Authorization": accessToken])
        XCTAssertThrowsError(try ticketsController.create(request: request))
    }
    
    func testDeleteTicket() throws {
        let accessToken = try createMockUserIfNeeded().generateAccessToken()
        var ticket = Ticket(id: Node(.int(9)), title: "TestTitle", userId: Node(.int(1)), exists: false)
        try ticket.save()
        let request = try Request(method: .delete, uri: "tickets/9", headers: ["Authorization": accessToken])
        let _ = try ticketsController.delete(request: request, ticket: ticket)
        let numTickets = try Ticket.query().filter("id", Node(.int(9))).count()
        XCTAssertEqual(0, numTickets)
    }
    
    func testDeleteTicketUnauthorized() throws {
        var ticket = Ticket(id: Node(.int(9)), title: "TestTitle", userId: Node(.int(1)), exists: false)
        try ticket.save()
        let request = try Request(method: .delete, uri: "tickets/9")
        XCTAssertThrowsError(try ticketsController.delete(request: request, ticket: ticket))
    }
    
    func testDeleteTicketOtherUser() throws {
        let accessToken = try createMockUserIfNeeded().generateAccessToken()
        var ticket = Ticket(id: Node(.int(9)), title: "TestTitle", userId: Node(.int(2)), exists: false)
        try ticket.save()
        let request = try Request(method: .delete, uri: "tickets/9", headers: ["Authorization": accessToken])
        XCTAssertThrowsError(try ticketsController.delete(request: request, ticket: ticket))
    }
    
    func testUpdateTicket() throws {
        let accessToken = try createMockUserIfNeeded().generateAccessToken()
        let newTitle = "NewTitle"
        var ticket = Ticket(id: Node(.int(1)), title: "TestTitle", userId: Node(.int(1)), exists: false)
        try ticket.save()
        let request = try Request(method: .patch, uri: "tickets/1", headers: ["Content-Type": "application/json", "Authorization": accessToken], body: Body(JSON(["title": Node(.string(newTitle)), "user_id": 1, "id": 1])))
        let _ = try ticketsController.update(request: request, ticket: ticket) as! Ticket
        let updatedTicket = try Ticket.query().filter("id", Node(.int(1))).first()!
        XCTAssertEqual(updatedTicket.title, newTitle)
        XCTAssertNotEqual(ticket.title, updatedTicket.title)
        XCTAssertEqual(ticket.id, updatedTicket.id)
        XCTAssertEqual(ticket.userId, updatedTicket.userId)
    }
    
    func testUpdateTicketUnauthorized() throws {
        let newTitle = "NewTitle"
        var ticket = Ticket(id: Node(.int(1)), title: "TestTitle", userId: Node(.int(1)), exists: false)
        try ticket.save()
        let request = try Request(method: .patch, uri: "tickets/1", headers: ["Content-Type": "application/json"], body: Body(JSON(["title": Node(.string(newTitle)), "user_id": 1, "id": 1])))
        XCTAssertThrowsError(try ticketsController.update(request: request, ticket: ticket))
    }
    
    func testUpdateTicketOtherUser() throws {
        let accessToken = try createMockUserIfNeeded().generateAccessToken()
        let newTitle = "NewTitle"
        var ticket = Ticket(id: Node(.int(1)), title: "TestTitle", userId: Node(.int(2)), exists: false)
        try ticket.save()
        let request = try Request(method: .patch, uri: "tickets/1", headers: ["Content-Type": "application/json", "Authorization": accessToken], body: Body(JSON(["title": Node(.string(newTitle)), "user_id": 2, "id": 1])))
        XCTAssertThrowsError(try ticketsController.update(request: request, ticket: ticket))
    }
}

private extension TicketsControllerTests {
    
    func mockCreateTicketRequest(accessToken: String?, title: String = "Title", userId: Int) throws -> Request {
        var headers: [HeaderKey: String] = [
            "Content-Type": "application/json"
        ]
        if let accessToken = accessToken {
            headers["Authorization"] = accessToken
        }
        return try Request(method: .post,
                           uri: "",
                           headers: headers,
                           body: try Body(JSON(
                            ["title": Node(.string(title)),
                             "user_id": Node(.int(1))]
                           )))
    }
    
    func createMockUserIfNeeded() throws -> User {
        if let user = try User.find(Node(.int(1))) {
            return user
        }
        var user = User(username: try "jimmy".validated(), password: "wachtwoord")
        user.id = Node(.int(1))
        user.email = try "arts.jimmy@gmail.com".validated()
        try user.save()
        return user
    }
}
