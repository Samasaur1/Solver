import Foundation

public enum LexicalToken: Equatable {
    case number(value: String)
    case identifier(name: String)

    case leftParen, rightParen

    case equals

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
                    throw SolverError.ParseError.numberEndingInDot(lexeme: String(str))
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
                throw SolverError.ParseError.loneDot
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
        case "=": tokens.append(.equals); next()
        default:
            throw SolverError.ParseError.illegalCharacter(char: c)
        }
    }
    return tokens
}

func parse(tokens: [LexicalToken]) throws -> (ResolvedExpression, String?) {
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
    var variableName: String? = nil
    func __parse() throws -> ResolvedExpression {
        let tree = try term()
        if let token = peek() {
            if token == .equals {
                _ = next()
                let right = try term()
                if peek() != nil {
                    throw SolverError.ParseError.tokensRemainingAfterParsing(remaining: Array(tokens[idx...]))
                }
                return .equation(left: tree, right: right)
            }
            throw SolverError.ParseError.tokensRemainingAfterParsing(remaining: Array(tokens[idx...]))
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
            throw SolverError.ParseError.incompleteExpression
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
                throw SolverError.ParseError.unmatchedOpeningParenthesis
            }
            return expr
        case .identifier(let name):
            if let v = variableName {
                if v == name {
                    return .variable
                } else {
                    throw SolverError.ParseError.tooManyVariables(newVariable: name)
                }
            }
            variableName = name
            return .variable
        default:
            throw SolverError.ParseError.unknownToken(token: tokens[idx-1])
        }
//        fatalError("Unreachable code!")
    }

    return (try __parse(), variableName)
}
public func parse(_ input: String) throws -> (ResolvedExpression, String?) {
    return try parse(tokens: tokenize(input))
}

enum Expression {

}

public indirect enum ResolvedExpression: Equatable {
    case number(value: Double)
    case binaryOperation(left: ResolvedExpression, operator: BinaryOperator, right: ResolvedExpression)
    case unaryOperator(operator: UnaryOperator, value: ResolvedExpression)
    case variable
    case equation(left: ResolvedExpression, right: ResolvedExpression)

    public func toString() -> String {
        switch self {
        case let .number(value): return String(value)
        case let .binaryOperation(left, op, right):
            let leftOutput: String
            switch left {
            case .number, .variable, .unaryOperator:
                leftOutput = left.toString()
            default:
                leftOutput = "(\(left.toString()))"
            }
            let rightOutput: String
            switch right {
            case .number, .variable, .unaryOperator:
                rightOutput = right.toString()
            default:
                rightOutput = "(\(right.toString()))"
            }
            return "\(leftOutput) \(op.symbol) \(rightOutput)"
        case let .unaryOperator(op, value): return op.symbol(on: value)
        case .variable: return "x"
        case let .equation(left, right): return "\(left.toString()) = \(right.toString())"
        }
    }

    public func resolve() throws -> Double {
        switch self {
        case let .number(value):
            return value
        case let .binaryOperation(left, op, right):
            return try op.perform(on: left, and: right)
        case let .unaryOperator(op, value):
            return try op.perform(on: value)
        case .variable:
            throw SolverError.ResolveError.resolvingVariable
        case .equation:
            throw SolverError.ResolveError.resolvingEquation
        }
    }

    func contains(_ subexpr: ResolvedExpression) -> Bool {
        if self == subexpr { return true }
        switch self {
        case .number: return self == subexpr
        case let .binaryOperation(left, _, right):
            return left.contains(subexpr) || right.contains(subexpr)
        case let .unaryOperator(_, value):
            return value.contains(subexpr)
        case .variable: return self == subexpr
        case let .equation(left, right):
            return left.contains(subexpr) || right.contains(subexpr)
        }
    }

    public func solve() throws -> ResolvedExpression {
        guard case let .equation(left, right) = self else {
            throw SolverError.SolveError.solvingExpression
        }
        let lv = left.contains(.variable)
        let rv = right.contains(.variable)
        guard lv || rv else {
            let l = try left.resolve()
            let r = try right.resolve()
            throw SolverError.SolveError.solvingEquationWithoutVariable(equal: l == r)
        }
        if lv {
            if rv {
                //variable on both sides

            } else {
                //variable on left but not right
                return try ResolvedExpression.solve(variableSide: left, nonVariableSide: right)
            }
        } else {
            //variable on right but not left
            return try ResolvedExpression.solve(variableSide: right, nonVariableSide: left)
        }
        return self
    }

    fileprivate static func solve(variableSide: ResolvedExpression, nonVariableSide: ResolvedExpression) throws -> ResolvedExpression {
        switch variableSide {
        case .number, .equation: break //impossible
        case .variable: return nonVariableSide
        case let .unaryOperator(op, value):
            switch op {
            case .factorial: throw SolverError.SolveError.variableInFactorial
            case .negation:
                let newLeft = value
                let newRight = ResolvedExpression.unaryOperator(operator: .negation, value: nonVariableSide)
                let newEquation = ResolvedExpression.equation(left: newLeft, right: newRight)
                return try newEquation.solve()
            }
        case let .binaryOperation(left, op, right):
            switch op {
            case .addition:
                let lv = left.contains(.variable)
                let rv = right.contains(.variable)
                guard lv || rv else {
                    throw SolverError.InternalError.variableHasMagicallyDisappeared
                }
                if lv {
                    if rv {
                        //both
                        fatalError()//TODO: auto-generated method stub
                    } else {
                        //l only
                        let newLeft = left
                        let newRight = ResolvedExpression.binaryOperation(left: nonVariableSide, operator: .subtraction, right: right)
                        let newEquation = ResolvedExpression.equation(left: newLeft, right: newRight)
                        return try newEquation.solve()
                    }
                } else {
                    //r only
                    let newLeft = right
                    let newRight = ResolvedExpression.binaryOperation(left: nonVariableSide, operator: .subtraction, right: left)
                    let newEquation = ResolvedExpression.equation(left: newLeft, right: newRight)
                    return try newEquation.solve()
                }
            case .subtraction:break
            case .multiplication:
                return try solveBinaryOperation(left: left, right: right) { (varSide, nonVarSide) in
                    let newLeft = varSide
                    let newRight = ResolvedExpression.binaryOperation(left: nonVariableSide, operator: .division, right: nonVarSide)
                    let newEquation = ResolvedExpression.equation(left: newLeft, right: newRight)
                    return try newEquation.solve()
                } twoVars: { (first, second) in
                    fatalError()
                }
            case .division:break
            case .exponentiation:break
            case .modulus:break
            }
        }
        return nonVariableSide
    }

    fileprivate static func solveBinaryOperation(left: ResolvedExpression, right: ResolvedExpression, oneVar: (_ varSide: ResolvedExpression, _ nonVarSide: ResolvedExpression) throws -> ResolvedExpression, twoVars: (ResolvedExpression, ResolvedExpression) throws -> ResolvedExpression) throws -> ResolvedExpression {
        let lv = left.contains(.variable)
        let rv = right.contains(.variable)
        guard lv || rv else {
            throw SolverError.InternalError.variableHasMagicallyDisappeared
        }
        if lv && rv {
            return try twoVars(left, right)
        }
        if lv {
            return try oneVar(left, right)
        }
        return try oneVar(right, left)
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

    var symbol: String {
        switch self {
        case .addition: return "+"
        case .subtraction: return "-"
        case .multiplication: return "*"
        case .division: return "/"
        case .exponentiation: return "^"
        case .modulus: return "%"
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
                throw SolverError.ResolveError.nonIntegerFactorial(val: val)
            }
        case .negation:
            return -val
        }
    }

    func symbol(on expr: ResolvedExpression) -> String {
        let exprOutput: String
        switch expr {
        case .number, .variable, .unaryOperator:
            exprOutput = expr.toString()
        default:
            exprOutput = "(\(expr.toString()))"
        }
        switch self {
        case .factorial:
            return "\(exprOutput)!"
        case .negation:
            return "-\(exprOutput)"
        }
    }
}

public enum SolverError: Swift.Error {
    public enum ResolveError: Swift.Error {
        case resolvingVariable
        case nonIntegerFactorial(val: Double)
        case resolvingEquation
    }
    public enum ParseError: Swift.Error {
        case illegalCharacter(char: Character)
        case numberEndingInDot(lexeme: String)
        case loneDot
        case unmatchedOpeningParenthesis
        case unknownToken(token: LexicalToken)
        case incompleteExpression
        case tokensRemainingAfterParsing(remaining: [LexicalToken])
        case tooManyVariables(newVariable: String)
    }
    public enum SolveError: Swift.Error {
        case solvingExpression
        case solvingEquationWithoutVariable(equal: Bool)
        case variableInFactorial
    }
    fileprivate enum InternalError: Swift.Error {
        case variableHasMagicallyDisappeared
    }
}
