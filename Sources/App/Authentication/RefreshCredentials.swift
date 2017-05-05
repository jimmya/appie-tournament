import Turnstile

public class RefreshCredentials: Credentials {
    
    public let string: String
    public let userId: Int
    
    public init(string: String, userId: Int) {
        self.string = string
        self.userId = userId
    }
}
