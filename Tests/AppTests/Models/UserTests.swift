import Vapor
import HTTP
import Fluent
import XCTest
import JWT

@testable import App

class UserTests: XCTestCase {
    
    static var allTests : [(String, (UserTests) -> () throws -> Void)] {
        return [
            ("testRequest", testRequest),
            ("testGenerateToken", testGenerateToken),
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
    
    func testRequest() throws {
        let user = try User.query().first()!
        let accessToken = try user.generateAccessToken()
        
        let request = try Request(method: .get, uri: "", headers: ["Authorization": accessToken])
        let requestUser = try request.user()
        XCTAssertNotNil(requestUser)
        XCTAssertEqual(user.id, requestUser.id)
    }
    
    func testGenerateToken() throws {
        let user = try User.query().first()!
        let accessToken = try user.generateAccessToken()
        
        let jwtKey = Droplet().config["app", "signing_secret"]?.string ?? ""
        let jwt = try JWT(token: accessToken)
        try jwt.verifySignature(using: HS256(key: jwtKey.bytes))
        let claims: [Claim] = [
            ExpirationTimeClaim(Date(), leeway: 120),
            UserIDClaim(userID: user.id!.int!)
        ]
        let valid = jwt.verifyClaims(claims)
        XCTAssertTrue(valid)
    }
    
    func testGenerateRefreshToken() throws {
        let user = try User.query().first()!
        let refreshToken = try user.generateRefreshToken()
        
        let jwtKey = Droplet().config["app", "signing_secret"]?.string ?? ""
        let jwt = try JWT(token: refreshToken)
        try jwt.verifySignature(using: HS256(key: jwtKey.bytes))
        
        let uuid = jwt.payload[JWTIDClaim.name]
        let fetchedRefreshToken = try RefreshToken.query().filter("uuid", uuid!).filter("user_id", user.id!).first()
        XCTAssertNotNil(fetchedRefreshToken)
    }
    
    func testRefreshToken() throws {
        let user = try User.query().first()!
        let refreshToken = try user.generateRefreshToken()
        let credentials = RefreshCredentials(string: refreshToken, userId: user.id!.int!)
        let authenticatedUser = try User.authenticate(credentials: credentials)
        XCTAssertEqual(user.id, authenticatedUser.id)
    }
}
