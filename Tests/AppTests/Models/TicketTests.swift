import Vapor
import Fluent
import XCTest

@testable import App

class TicketTests: XCTestCase {
    
    static var allTests : [(String, (TicketTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
    
    override func setUp() {
        super.setUp()
        
        do {
            let driver = MemoryDriver()
            Database.default = Database(driver)
        
            var testUser = User(username: try "jimmy".validated(), password: "wachtwoord")
            testUser.email = try "arts.jimmy@gmail.com".validated()
            try testUser.save()
        } catch {
            
        }
    }
    
    func testExample() throws {
        do {
            let userCount = try User.query().all().count
            XCTAssertTrue(userCount == 1)
        } catch {
            
        }
        XCTAssertTrue(true)
    }
    
}
