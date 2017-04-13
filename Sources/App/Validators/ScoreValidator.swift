import Vapor

class Score: ValidationSuite {
    
    static func validate(input value: Int) throws {
        if value < 0 || value > 10 {
            throw error(with: value)
        }
    }
}
