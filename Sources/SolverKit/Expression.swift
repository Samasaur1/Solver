import Foundation

public enum LexicalToken: Equatable {
    case number(value: String)
    case identifier(name: String)

    case leftParen, rightParen

    //binary operators
    case plus, times, slash, caret, percent

    //joint binary-unary operators
    case minus

    //unary operators
    case exclamationPoint
}

func tokenize(_ input: String) throws -> [LexicalToken] {
    var idx = input.startIndex
    func next() {
        idx = input.index(after: idx)
    }
    var c: Character {
        input[idx]
    }
    var tokens = [LexicalToken]()
    while idx < input.endIndex {
        switch c {
        case _ where c.isWhitespace: next()
        case "+": tokens.append(.plus); next()
        case "*": tokens.append(.times); next()
        case "/": tokens.append(.slash); next()
        case "^": tokens.append(.caret); next()
        case "%": tokens.append(.percent); next()
        case "-": tokens.append(.minus); next()
        case "!": tokens.append(.exclamationPoint); next()
        case "0"..."9":
            var str = [c]
            next()
            while idx < input.endIndex && ("0"..."9").contains(c) {
                str.append(c)
                next()
            }
            if idx < input.endIndex && c == "." {
                str.append(c)
                next()
                if idx >= input.endIndex || !("0"..."9").contains(c) {
                    throw Error.numberEndingInDot(lexeme: String(str))
                }
                while idx < input.endIndex && ("0"..."9").contains(c) {
                    str.append(c)
                    next()
                }
            }
            tokens.append(.number(value: String(str)))
        case ".":
            var str: [Character] = ["0", "."]
            next()
            if idx >= input.endIndex || !("0"..."9").contains(c) {
                throw Error.loneDot
            }
            while idx < input.endIndex && ("0"..."9").contains(c) {
                str.append(c)
                next()
            }
            tokens.append(.number(value: String(str)))
        case _ where c.isLetter:
            var str = [c]
            next()
            while idx < input.endIndex && (("0"..."9").contains(c) || ("a"..."z").contains(c) || ("A"..."Z").contains(c)) {
                str.append(c)
                next()
            }
            tokens.append(.identifier(name: String(str)))
        case "(": tokens.append(.leftParen); next()
        case ")": tokens.append(.rightParen); next()
        default:
            throw Error.illegalCharacter(char: c)
        }
    }
    return tokens
}

func parse(tokens: [LexicalToken]) throws -> ResolvedExpression {
//    print("Entering \(#function)")
//    print("Token count: \(tokens.count)")
    var idx = 0
    func peek() -> LexicalToken? {
        if idx < tokens.count {
            return tokens[idx]
        }
        return nil
    }
    func next() -> LexicalToken {
        idx += 1
        return tokens[idx - 1]
    }
    func __parse() throws -> ResolvedExpression {
        let tree = try term()
        if let c = peek() {
            fatalError("Tokens remaining after parsing (char: \(c), idx: \(idx), out of: \(tokens.count))")
        }
        return tree
    }
    func term() throws -> ResolvedExpression {
        var expr = try factor()
        while [.plus, .minus].contains(peek()) {
            switch next() {
            case .plus:
                expr = .binaryOperation(left: expr, operator: .addition, right: try factor())
            case .minus:
                expr = .binaryOperation(left: expr, operator: .subtraction, right: try factor())
            default:
                fatalError("Unreachable code!")
            }
        }
        return expr
    }
    func factor() throws -> ResolvedExpression {
        var expr = try unaryNegation()
        while [.times, .slash, .percent].contains(peek()) {
            switch next() {
            case .times:
                expr = .binaryOperation(left: expr, operator: .multiplication, right: try unaryNegation())
            case .slash:
                expr = .binaryOperation(left: expr, operator: .division, right: try unaryNegation())
            case .percent:
                expr = .binaryOperation(left: expr, operator: .modulus, right: try unaryNegation())
            default:
                fatalError("Unreachable code!")
            }
        }
        return expr
    }
    func unaryNegation() throws -> ResolvedExpression {
        if .minus == peek() {
            _ = next()
            return .unaryOperator(operator: .negation, value: try unaryNegation())
        }
        return try exponentiation()
//        var expr = try exponentiation()
//        while [.minus].contains(peek()) {
//            switch next() {
//            case .minus:
//                expr = .unaryOperator(operator: .negation, value: try exponentiation())
//            default:
//                fatalError("Unreachable code!")
//            }
//        }
//        return expr
    }
    func exponentiation() throws -> ResolvedExpression {
        let base = try factorial()
        if .caret == peek() {
            _ = next()
            let exp = try exponentiation() //right-associative
            return .binaryOperation(left: base, operator: .exponentiation, right: exp)
        }
        return base
    }
    func factorial() throws -> ResolvedExpression {
        let lit = try literal() //NOTE: this does not handle more than one factorial in a row
        if .exclamationPoint == peek() {
            _ = next()
            return .unaryOperator(operator: .factorial, value: lit)
        }
        return lit
    }
    func literal() throws -> ResolvedExpression {
        guard let token = peek() else {
            throw Error.incompleteExpression
        }
        _ = next()
        switch token {
        case .number(let value):
            guard let val = Double(value) else {
                fatalError("Cannot parse .number token into Double (\(value))")
            }
            return .number(value: val)
        case .leftParen:
            let expr = try term()
            guard next() == .rightParen else {
                throw Error.unmatchedOpeningParenthesis
            }
            return expr
        case .identifier(let name):
            fatalError("Variable are not yet implemented (\(name))")
        default:
            throw Error.unknownToken(token: tokens[idx-1])
        }
//        fatalError("Unreachable code!")
    }

    return try __parse()
}
public func parse(_ input: String) throws -> ResolvedExpression {
    return try parse(tokens: tokenize(input))
}

enum Expression {

}

public indirect enum ResolvedExpression {
    case number(value: Double)
    case binaryOperation(left: ResolvedExpression, operator: BinaryOperator, right: ResolvedExpression)
    case unaryOperator(operator: UnaryOperator, value: ResolvedExpression)

    public func resolve() throws -> Double {
        switch self {
        case let .number(value):
            return value
        case let .binaryOperation(left, op, right):
            return try op.perform(on: left, and: right)
        case let .unaryOperator(op, value):
            return try op.perform(on: value)
        }
    }
}

public enum BinaryOperator {
    case addition
    case subtraction
    case multiplication
    case division
    case exponentiation
    case modulus

    func perform(on left: ResolvedExpression, and right: ResolvedExpression) throws -> Double {
        let l = try left.resolve()
        let r = try right.resolve()
        switch self {
        case .addition: return l + r
        case .subtraction: return l - r
        case .multiplication: return l * r
        case .division: return l / r
        case .exponentiation: return pow(l, r)
        case .modulus: return l.truncatingRemainder(dividingBy: r)
        }
    }

    var precedence: Int {
        switch self {
        case .addition: return 2
        case .subtraction: return 2
        case .multiplication: return 2
        case .division: return 2
        case .exponentiation: return 2
        case .modulus: return 2
        }
    }
}

public enum UnaryOperator {
    case factorial
    case negation

    func perform(on value: ResolvedExpression) throws -> Double {
        let val = try value.resolve()
        switch self {
        case .factorial:
            if val == round(val) { //integer
                return Double(Array(1...Int(val)).reduce(1, *))
            } else {
                throw Error.nonIntegerFactorial(val: val)
            }
        case .negation:
            return -val
        }
    }
}

public enum Error: Swift.Error {
    case nonIntegerFactorial(val: Double)
    case illegalCharacter(char: Character)
    case numberEndingInDot(lexeme: String)
    case loneDot
    case unmatchedOpeningParenthesis
    case unknownToken(token: LexicalToken)
    case incompleteExpression
}
