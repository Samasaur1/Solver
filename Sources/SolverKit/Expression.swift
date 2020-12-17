import Foundation

//MARK: - Tokenization and Parsing

public enum LexicalToken: Equatable {
    case number(value: String)
    case identifier(name: String)

    case leftParen, rightParen
    case leftBrace, rightBrace, comma
    case verticalBar

    case equals

    //binary operators
    case plus, times, slash, caret, percent

    //joint binary-unary operators
    case minus

    //unary operators
    case exclamationPoint
    case plusMinus
}

//MARK: Tokenization
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
        case "|": tokens.append(.verticalBar); next()
        case "±": tokens.append(.plusMinus); next()
        case "{": tokens.append(.leftBrace); next()
        case "}": tokens.append(.rightBrace); next()
        case ",": tokens.append(.comma); next()
        default:
            throw SolverError.ParseError.illegalCharacter(char: c)
        }
    }
    return tokens
}

//MARK: Parsing
func parse(tokens: [LexicalToken]) throws -> (Expression, String?) {
    var idx = 0
    func peek() -> LexicalToken? {
        if idx < tokens.count {
            return tokens[idx]
        }
        return nil
    }
    func next(error: SolverError.ParseError? = nil) throws -> LexicalToken {
        idx += 1
        guard idx <= tokens.count else {
            throw SolverError.ParseError.expectedMoreTokens(error: error)
        }
        return tokens[idx - 1]
    }
    var variableName: String? = nil
    func __parse() throws -> Expression {
        let tree = try expression()
        if let token = peek() {
            if token == .equals {
                _ = try next()
                let right = try expression()
                if peek() != nil {
                    throw SolverError.ParseError.tokensRemainingAfterParsing(remaining: Array(tokens[idx...]))
                }
                return .equation(left: tree, right: right)
            }
            throw SolverError.ParseError.tokensRemainingAfterParsing(remaining: Array(tokens[idx...]))
        }
        return tree
    }
    func expression() throws -> Expression {
        return try term()
    }
    func term() throws -> Expression {
        var expr = try factor()
        while [.plus, .minus, .plusMinus].contains(peek()) {
            switch try next() {
            case .plus:
                expr = .binaryOperation(left: expr, operator: .addition, right: try factor())
            case .minus:
                expr = .binaryOperation(left: expr, operator: .subtraction, right: try factor())
            case .plusMinus:
                let nxt = try factor()
                expr = .multiplePossibilities(possiblities: [.binaryOperation(left: expr, operator: .addition, right: nxt), .binaryOperation(left: expr, operator: .subtraction, right: nxt)])
            default:
                throw SolverError.InternalError.unreachable(reason: "Cannot match non-(plus/minus) inside block only entered upon matching those operators")
            }
        }
        return expr
    }
    func factor() throws -> Expression {
        var expr = try unaryNegation()
        while [.times, .slash, .percent].contains(peek()) {
            switch try next() {
            case .times:
                expr = .binaryOperation(left: expr, operator: .multiplication, right: try unaryNegation())
            case .slash:
                expr = .binaryOperation(left: expr, operator: .division, right: try unaryNegation())
            case .percent:
                expr = .binaryOperation(left: expr, operator: .modulus, right: try unaryNegation())
            default:
                throw SolverError.InternalError.unreachable(reason: "Cannot match non-(times/divided by/modulo) inside block only entered upon matching those operators")
            }
        }
        return expr
    }
    func unaryNegation() throws -> Expression {
        if .minus == peek() {
            _ = try next()
            return .unaryOperator(operator: .negation, value: try unaryNegation())
        } else if .plusMinus == peek() {
            _ = try next()
            let nxt = try unaryNegation()
            return .multiplePossibilities(possiblities: [nxt, .unaryOperator(operator: .negation, value: nxt)])
        }
        return try exponentiation()
    }
    func exponentiation() throws -> Expression {
        let base = try factorial()
        if .caret == peek() {
            _ = try next()
            let exp = try exponentiation() //right-associative
            return .binaryOperation(left: base, operator: .exponentiation, right: exp)
        }
        return base
    }
    func factorial() throws -> Expression {
        let lit = try literal() //NOTE: this does not handle more than one factorial in a row
        if .exclamationPoint == peek() {
            _ = try next()
            return .unaryOperator(operator: .factorial, value: lit)
        }
        return lit
    }
    func literal() throws -> Expression {
        guard let token = peek() else {
            throw SolverError.ParseError.incompleteExpression
        }
        _ = try next()
        switch token {
        case .number(let value):
            guard let val = Double(value) else {
                throw SolverError.InternalError.unreachable(reason: "Cannot parse .number token into Double (\(value))")
            }
            return .number(value: val)
        case .leftParen:
            let expr = try expression()
            guard try next(error: .unmatchedOpeningParenthesis) == .rightParen else {
                throw SolverError.ParseError.unmatchedOpeningParenthesis
            }
            return expr
        case .verticalBar:
            let expr = try expression()
            guard try next(error: .unmatchedAbsoluteValue) == .verticalBar else {
                throw SolverError.ParseError.unmatchedAbsoluteValue
            }
            return .unaryOperator(operator: .absoluteValue, value: expr)
        case .leftBrace:
            var exprs = [try expression()]
            while .comma == peek() {
                _ = try next()
                exprs.append(try expression())
            }
            guard try next(error: .unmatchedOpeningBrace) == .rightBrace else {
                throw SolverError.ParseError.unmatchedOpeningBrace
            }
            return .multiplePossibilities(possiblities: exprs)
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
            throw SolverError.ParseError.illegalToken(token: tokens[idx-1])
        }
    }

    return (try __parse(), variableName)
}
public func parse(_ input: String) throws -> (Expression, String?) {
    return try parse(tokens: tokenize(input))
}

//MARK: - Expressions
public indirect enum Expression: Equatable {
    case number(value: Double)
    case binaryOperation(left: Expression, operator: BinaryOperator, right: Expression)
    case unaryOperator(operator: UnaryOperator, value: Expression)
    case variable
    case equation(left: Expression, right: Expression)
    case multiplePossibilities(possiblities: [Expression])
}

extension Expression { //Output
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
        case .multiplePossibilities(possiblities: let list):
            switch list.count {
            case 0: return "{}"
            case 1: return list[0].toString()
            default: return "{ \(list.map { $0.toString() }.joined(separator: ", ")) }"
            }
        }
    }
}

extension Expression { //Evaluation
    public func resolve() throws -> [Double] {
        switch self {
        case let .number(value):
            return [value]
        case let .binaryOperation(left, op, right):
            return try op.perform(on: left, and: right)
        case let .unaryOperator(op, value):
            return try op.perform(on: value)
        case .variable:
            throw SolverError.ResolveError.resolvingVariable
        case .equation:
            throw SolverError.ResolveError.resolvingEquation
        case .multiplePossibilities(possiblities: let list):
            return try list.flatMap { try $0.resolve() }
        }
    }
}

extension Expression { //Utils (?)
    func contains(_ subexpr: Expression) -> Bool {
        if self == subexpr { return true }
        switch self {
        case .number: return false
        case let .binaryOperation(left, _, right):
            return left.contains(subexpr) || right.contains(subexpr)
        case let .unaryOperator(_, value):
            return value.contains(subexpr)
        case .variable: return self == subexpr
        case let .equation(left, right):
            return left.contains(subexpr) || right.contains(subexpr)
        case .multiplePossibilities(possiblities: let list):
            return list.contains { $0.contains(subexpr) }
        }
    }
    func simplify() -> Expression {
        switch self {
        case .number: return self
        case .variable: return self
        case let .unaryOperator(op, value):
            let v = value.simplify()
            switch op {
            case .absoluteValue:
                if case let .number(val) = v {
                    return .number(value: abs(val))
                }
            case .factorial:
                if case let .number(val) = v {
                    if let f = try? val.factorial() {
                        return .number(value: f)
                    }
                }
            case .negation:
                switch v {
                case .number(value: let val): return .number(value: -val)
                case .unaryOperator(operator: let op2, value: let value2) where op2 == .negation:
                    return value2.simplify()
                default: break
                }
                if case let .number(val) = v {
                    return .number(value: -val)
                }
            }
            return .unaryOperator(operator: op, value: v)
        case let .binaryOperation(left, operator: op, right):
            let l = left.simplify()
            let r = right.simplify()
            switch op {
            case .addition:
                if case let (.number(val1), .number(val2)) = (l, r) {
                    return .number(value: val1 + val2)
                }
                if let (lc, ld) = l.nonVariableCoefficientAndDegree, let (rc, rd) = r.nonVariableCoefficientAndDegree {
                    if (ld == rd) {
                        return Expression.binaryOperation(left: .binaryOperation(left: lc, operator: .addition, right: rc), operator: .multiplication, right: .binaryOperation(left: .variable, operator: .exponentiation, right: ld)).simplify()
                    }
                }
            case .subtraction:
                if case let (.number(val1), .number(val2)) = (l, r) {
                    return .number(value: val1 - val2)
                }
                if let (lc, ld) = l.nonVariableCoefficientAndDegree, let (rc, rd) = r.nonVariableCoefficientAndDegree {
                    if (ld == rd) {
                        return Expression.binaryOperation(left: .binaryOperation(left: lc, operator: .subtraction, right: rc), operator: .multiplication, right: .binaryOperation(left: .variable, operator: .exponentiation, right: ld)).simplify()
                    }
                }
            case .multiplication:
                if case let (.number(val1), .number(val2)) = (l, r) {
                    return .number(value: val1 * val2)
                }
                if let (lc, ld) = l.nonVariableCoefficientAndDegree, let (rc, rd) = r.nonVariableCoefficientAndDegree {
                    return Expression.binaryOperation(left: .binaryOperation(left: lc, operator: .multiplication, right: rc), operator: .multiplication, right: .binaryOperation(left: .variable, operator: .exponentiation, right: .binaryOperation(left: ld, operator: .addition, right: rd))).simplify()
                }
                func oneSideNum(_ num: Double, other: Expression) -> Expression? {
                    switch num {
                    case 0: return .number(value: 0)
                    case 1: return other
                    case -1: return Expression.unaryOperator(operator: .negation, value: other).simplify()
                    default:
                        switch other {
                        case .binaryOperation(let left, operator: let op, let right):
                            switch op {
                            case .addition, .subtraction:
                                return Expression.binaryOperation(left: .binaryOperation(left: .number(value: num), operator: .multiplication, right: left), operator: op, right: .binaryOperation(left: .number(value: num), operator: .multiplication, right: right)).simplify()
                            case .multiplication:
                                if left == .variable {
                                    return Expression.binaryOperation(left: .binaryOperation(left: .number(value: num), operator: .multiplication, right: right), operator: .multiplication, right: .variable).simplify()
                                } else {
                                    return Expression.binaryOperation(left: .binaryOperation(left: .number(value: num), operator: .multiplication, right: left), operator: .multiplication, right: .variable).simplify()
                                }
                            default: return nil
                            }
                        default: return nil
                        }
                    }
                }
                if case let .number(num) = l {
                    if let res = oneSideNum(num, other: r) { return res }
                }
                if case let .number(num) = r {
                    if let res = oneSideNum(num, other: l) { return res }
                }
            case .division:
                if case let (.number(val1), .number(val2)) = (l, r) {
                    return .number(value: val1 / val2)
                }
                if let (lc, ld) = l.nonVariableCoefficientAndDegree, let (rc, rd) = r.nonVariableCoefficientAndDegree {
                    return Expression.binaryOperation(left: .binaryOperation(left: lc, operator: .division, right: rc), operator: .multiplication, right: .binaryOperation(left: .variable, operator: .exponentiation, right: .binaryOperation(left: ld, operator: .subtraction, right: rd))).simplify()
                }
                func oneSideNum(_ num: Double, other: Expression) -> Expression? {
                    switch num {
                    case 0: return .number(value: 0)
                    case 1: return other
                    case -1: return Expression.unaryOperator(operator: .negation, value: other).simplify()
                    default:
                        switch other {
                        case .binaryOperation(let left, operator: let op, let right):
                            switch op {
                            case .addition, .subtraction:
                                return Expression.binaryOperation(left: .binaryOperation(left: .number(value: num), operator: .multiplication, right: left), operator: op, right: .binaryOperation(left: .number(value: num), operator: .multiplication, right: right)).simplify()
                            case .multiplication:
                                if left == .variable {
                                    return Expression.binaryOperation(left: .binaryOperation(left: .number(value: num), operator: .multiplication, right: right), operator: .multiplication, right: .variable).simplify()
                                } else {
                                    return Expression.binaryOperation(left: .binaryOperation(left: .number(value: num), operator: .multiplication, right: left), operator: .multiplication, right: .variable).simplify()
                                }
                            default: return nil
                            }
                        default: return nil
                        }
                    }
                }
                if case let .number(num) = l {
                    //num/something
                    switch num {
                    case 0: return .number(value: 0)
                    default:
                        switch r {
                        case .binaryOperation(let left, operator: let op, let right):
                            //num/(left op right)
                            switch op {
//                            case .addition, .subtraction:
//                                return Expression.binaryOperation(left: .binaryOperation(left: l, operator: .division, right: left), operator: op, right: .binaryOperation(left: l, operator: .division, right: right)).simplify()
                            case .multiplication:
                                if left == .variable {
                                    //l/(x*right) -> (l/right)/x
                                    return Expression.binaryOperation(left: .binaryOperation(left: l, operator: .division, right: right), operator: .division, right: .variable).simplify()
                                } else {
                                    //l/(left*x) -> (l/left)/x
                                    return Expression.binaryOperation(left: .binaryOperation(left: l, operator: .division, right: left), operator: .division, right: .variable).simplify()
                                }
                            default: break
                            }
                        default: break
                        }
                    }
                }
                if case let .number(num) = r {
                    //something/num
                    switch num {
//                    case 0: return .binaryOperation(left: .number(value: 0), operator: .division, right: .number(value: 0))
                    case 1: return l
                    case -1: return Expression.unaryOperator(operator: .negation, value: l).simplify()
                    default:
                        switch l {
                        case .binaryOperation(let left, operator: let op, let right):
                            //(left op right)/num
                            switch op {
                            case .addition, .subtraction:
                                //(left op right)/num -> left/num op right/num
                                return Expression.binaryOperation(left: .binaryOperation(left: left, operator: .division, right: r), operator: op, right: .binaryOperation(left: right, operator: .division, right: r)).simplify()
                            case .multiplication:
                                if left == .variable {
                                    //(x*right)/r -> x*(right/r)
                                    return Expression.binaryOperation(left: .variable, operator: .multiplication, right: .binaryOperation(left: right, operator: .division, right: r)).simplify()
                                } else {
                                    //(left*x)/r -> x*(left/r)
                                    return Expression.binaryOperation(left: .variable, operator: .multiplication, right: .binaryOperation(left: left, operator: .division, right: r)).simplify()
                                }
                            default: break
                            }
                        default: break
                        }
                    }
                }
            case .exponentiation:
                if case let (.number(base), .number(exp)) = (l, r) {
                    return .number(value: pow(base, exp))
                }
                if case let .number(exp) = r {
                    switch exp {
                    case 0: return .number(value: 1)
                    case 1: return l
                    default: break
                    }
                }
            case .modulus:
                if case let (.number(val1), .number(val2)) = (l, r) {
                    return .number(value: val1.truncatingRemainder(dividingBy: val2))
                }
            }
            return .binaryOperation(left: l, operator: op, right: r)
        case .equation(left: let left, right: let right):
            let l = left.simplify()
            let r = right.simplify()
            //TODO (?)
            return .equation(left: l, right: r)
        case .multiplePossibilities(possiblities: let list):
            switch list.count {
            case 0: return .multiplePossibilities(possiblities: [])
            case 1: return list[0].simplify()
            default: return .multiplePossibilities(possiblities: list.map { $0.simplify() })
            }
        }
    }
}

//MARK: Expression: Solving
extension Expression { //Solving
    //TODO: refactor solving:
    //  1. simplify (bottom-up) (both sides of equation)
    //  2. you should be left with only addition/subtraction. inspect the tree AS A WHOLE, combining like terms. (both sides of equation)
    //  3. now … it's complicated? you should have `ax^b + cx^d - fx^g ... = hx^k - mx^n + px^q ... — how to solve? idk?
    //  3b. look at the derivation of the quadratic formula? the problem is that sometimes you could have `x=5` (or `x-5=0`) and that gets solved very differently than `x^2+2^x+4=0`
    //  3c. more problems appear when you realize that one of your terms could have an x that is actually `|x|`, or `|x|^n`, or even `x^n*|x|^m`. weird.
    //  3d. Perhaps look at synthetic division with the zero product property
    public func solve(printSteps: Bool) throws -> Expression {
        if printSteps { print(self.toString()) }
        let simplified = self.simplify()
        if printSteps { print(simplified.toString()) }
        guard case let .equation(left, right) = simplified else {
            throw SolverError.SolveError.solvingExpression
        }

        func flattenAdditionTree(_ tree: Expression) -> [Expression] {
            switch tree {
            case .variable: return [tree]
            case .number: return [tree]
            case .binaryOperation(left: let l, operator: let op, right: let r):
                switch op {
                case .addition:
                    return flattenAdditionTree(l) + flattenAdditionTree(r)
                case .subtraction:
                    return flattenAdditionTree(l) + flattenAdditionTree(r).map { Expression.unaryOperator(operator: .negation, value: $0) }
                default: return [tree]
                }
            case .unaryOperator(operator: let op, value: let v):
                switch op {
                case .negation:
                    return [tree]//maybe?
                default: return [tree]
                }
            default: return [tree]
            }
        }
        func reconstituteAdditionTree(_ list: [Expression]) -> Expression {
            switch list.count {
            case 0: return .number(value: 0)
            case 1: return list[0]
            case 2: return .binaryOperation(left: list[0], operator: .addition, right: list[1])
            default:
                let last = list.last!
                let remaining = Array(list.dropLast())
                return .binaryOperation(left: reconstituteAdditionTree(remaining), operator: .addition, right: last)
            }
        }
        func sorter(first: Expression, second: Expression) -> Bool {
            if let firstCAD = first.nonVariableCoefficientAndDegree, let secondCAD = second.nonVariableCoefficientAndDegree {
                if case let (.number(fd), .number(sd)) = (firstCAD.degree, secondCAD.degree) {
                    return fd > sd
                }
            } else {
                if first.nonVariableCoefficientAndDegree != nil {
                    return true
                } else if second.nonVariableCoefficientAndDegree != nil {
                    return false
                }
            }
            return false
        }

        let newEquation = Expression.equation(left: reconstituteAdditionTree(flattenAdditionTree(left).sorted(by: sorter(first:second:))), right: reconstituteAdditionTree(flattenAdditionTree(right).sorted(by: sorter(first:second:))))
        return try newEquation.__solve(printSteps: printSteps)
    }
    func __solve(printSteps: Bool) throws -> Expression {
        if printSteps { print(self.toString()) }
        let simplified = self.simplify()
        if printSteps { print(simplified.toString()) }
        guard case let .equation(left, right) = simplified else {
            throw SolverError.SolveError.solvingExpression
        }

        switch (left, right) {
        case (.number, .number):
            throw SolverError.SolveError.solvingEquationWithoutVariable(equal: left == right)
        case (.equation, .equation):
            throw SolverError.InternalError.unreachable(reason: "This function cannot be called with nested equations")
        case (.variable, .variable):
            throw SolverError.InternalError.notYetSupported(description: "x=x")
        case (.unaryOperator(let op1, let value1), .unaryOperator(let op2, let value2)):
            if op1 == op2 {
                return try Expression.equation(left: value1, right: value2).__solve(printSteps: printSteps)
            }
        case (let .binaryOperation(left1, op1, right1), let .binaryOperation(left2, op2, right2)):
            if (op1 == op2) {
                if (left1 == left2) {
                    return try Expression.equation(left: right1, right: right2).__solve(printSteps: printSteps)
                }
                if (right1 == right2) {
                    return try Expression.equation(left: left1, right: left2).__solve(printSteps: printSteps)
                }
            }
        case (.multiplePossibilities(possiblities: let list), _) where list.count == 1:
            return try Expression.equation(left: list[0], right: right).__solve(printSteps: printSteps)
        case (_, .multiplePossibilities(possiblities: let list)) where list.count == 1:
            return try Expression.equation(left: left, right: list[0]).__solve(printSteps: printSteps)
        default: break
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
                throw SolverError.InternalError.notYetSupported(description: "Solving equations where there is a variable on both sides")
            } else {
                //variable on left but not right
                return try Expression.solve(variableSide: left, nonVariableSide: right, printSteps: printSteps)
            }
        } else {
            //variable on right but not left
            return try Expression.solve(variableSide: right, nonVariableSide: left, printSteps: printSteps)
        }
    }

    fileprivate static func solve(variableSide: Expression, nonVariableSide: Expression, printSteps: Bool) throws -> Expression {
        switch variableSide {
        case .number, .equation:
            throw SolverError.InternalError.unreachable(reason: "This function cannot be called where the variable side of an equation is another equation or has no variable")
        case .variable: return nonVariableSide
        case let .unaryOperator(op, value):
            switch op {
            case .factorial: throw SolverError.SolveError.variableInFactorial
            case .negation:
                let newLeft = value
                let newRight = Expression.unaryOperator(operator: .negation, value: nonVariableSide)
                let newEquation = Expression.equation(left: newLeft, right: newRight)
                return try newEquation.__solve(printSteps: printSteps)
            case .absoluteValue:
                let newLeft = value
                let negativeOppositeSide = Expression.unaryOperator(operator: .negation, value: nonVariableSide)
                let newRight = Expression.multiplePossibilities(possiblities: [nonVariableSide, negativeOppositeSide])
                let newEquation = Expression.equation(left: newLeft, right: newRight)
                return try newEquation.__solve(printSteps: printSteps)
            }
        case let .binaryOperation(left, op, right):
            switch op {
            case .addition:
                return try simpleCommutativeBinaryOperation(left: left, right: right, nonVariableSide: nonVariableSide, invertedOperator: .subtraction, printSteps: printSteps) { (first, second) in
                    if let c1 = first.nonVariableCoefficient, let c2 = second.nonVariableCoefficient {
                        return try Expression.equation(left: .binaryOperation(left: .binaryOperation(left: c1, operator: .addition, right: c2), operator: .multiplication, right: .variable), right: nonVariableSide).__solve(printSteps: printSteps)
                    }
//                    if first == .variable {
//                        switch second {
//                        case .number, .equation: throw SolverError.InternalError.unreachable(reason: "Cannot reach two-var branch when only one side is a var")
//                        case .variable: fatalError("see above")
//                        case let .unaryOperator(op, value):
//                            switch op {
//                            case .negation:
//                                break
//                            }
//                        case let .binaryOperation(left, op, right):
//                            switch op {
//                            case .addition:
//                            case .subtraction:
//                            case .multiplication:
//                                if left == .variable {
//                                    //x + (x*5) = 3 -> (5 + 1)*x=3
//                                    //x+(x*(2*x))=3 -> ((2*x)+1)*x=3
//                                    return try Expression.equation(left: .binaryOperation(left: .binaryOperation(left: right, operator: .addition, right: .number(value: 1)), operator: .multiplication, right: .variable), right: nonVariableSide).solve(printSteps: printSteps)
//                                }
//                            case .division:
//                            case .exponentiation:
//                            case .modulus:
//                            }
//                        }
//                    }
                    throw SolverError.InternalError.notYetSupported(description: "Solving equations where the variable is in both terms")
                }
            case .subtraction:
                let lv = left.contains(.variable)
                let rv = right.contains(.variable)
                guard lv || rv else {
                    throw SolverError.InternalError.variableHasMagicallyDisappeared
                }
                if lv && rv {
                    if let c1 = left.nonVariableCoefficient, let c2 = right.nonVariableCoefficient {
                        return try Expression.equation(left: .binaryOperation(left: .binaryOperation(left: c1, operator: .subtraction, right: c2), operator: .multiplication, right: .variable), right: nonVariableSide).__solve(printSteps: printSteps)
                    }
                    throw SolverError.InternalError.notYetSupported(description: "Solving equations where the variable is in the minuend and the subtrahend")
                }
                if lv {
                    //var on left
                    // e.g. x-5 = 10 -> x = 10+5
                    let newLeft = left
                    let newRight = Expression.binaryOperation(left: nonVariableSide, operator: .addition, right: right)
                    let newEquation = Expression.equation(left: newLeft, right: newRight)
                    return try newEquation.__solve(printSteps: printSteps)
                } else {
                    //var on right
                    // e.g. 1-x = 2 -> 1 = 2+x
                    let newLeft = left
                    let newRight = Expression.binaryOperation(left: nonVariableSide, operator: .addition, right: right)
                    let newEquation = Expression.equation(left: newLeft, right: newRight)
                    return try newEquation.__solve(printSteps: printSteps)
                }
            case .multiplication:
                return try simpleCommutativeBinaryOperation(left: left, right: right, nonVariableSide: nonVariableSide, invertedOperator: .division, printSteps: printSteps) { (first, second) in
                    if let d1 = first.nonVariableDegree, let d2 = second.nonVariableDegree {
                        return try Expression.equation(left: .binaryOperation(left: .variable, operator: .exponentiation, right: .binaryOperation(left: d1, operator: .addition, right: d2)), right: nonVariableSide).__solve(printSteps: printSteps)
                    }
                    //(c1*(x^d1))*(c2*(x^d2)) -> (c1*c2)*(x^(d1+d2))
                    if let (c1, d1) = first.nonVariableCoefficientAndDegree, let (c2, d2) = second.nonVariableCoefficientAndDegree {
                        return try Expression.equation(left: .binaryOperation(left: .binaryOperation(left: c1, operator: .multiplication, right: c2), operator: .multiplication, right: .binaryOperation(left: .variable, operator: .exponentiation, right: .binaryOperation(left: d1, operator: .addition, right: d2))), right: nonVariableSide).__solve(printSteps: printSteps)
                    }
                    throw SolverError.InternalError.notYetSupported(description: "Solving equations where the variable is in both factors")
                }
            case .division:
                let lv = left.contains(.variable)
                let rv = right.contains(.variable)
                guard lv || rv else {
                    throw SolverError.InternalError.variableHasMagicallyDisappeared
                }
                if lv && rv {
                    if let d1 = left.nonVariableDegree, let d2 = right.nonVariableDegree {
                        return try Expression.equation(left: .binaryOperation(left: .variable, operator: .exponentiation, right: .binaryOperation(left: d1, operator: .subtraction, right: d2)), right: nonVariableSide).__solve(printSteps: printSteps)
                    }
                    throw SolverError.InternalError.notYetSupported(description: "Solving equations where the variable is in the dividend and divisor")
                }
                if lv {
                    //var on left
                    // e.g. x/5 = 10 -> x = 10*5
                    let newLeft = left
                    let newRight = Expression.binaryOperation(left: nonVariableSide, operator: .multiplication, right: right)
                    let newEquation = Expression.equation(left: newLeft, right: newRight)
                    return try newEquation.__solve(printSteps: printSteps)
                } else {
                    //var on right
                    // e.g. 1/x = 2 -> 1/2 = x
                    // i could go to 1 = 2*x, but this way I just skip a step
                    let newLeft = Expression.binaryOperation(left: left, operator: .division, right: nonVariableSide)
                    let newRight = right
                    let newEquation = Expression.equation(left: newLeft, right: newRight)
                    if printSteps {
                        //print that skipped step
                        print(left.toString(), "=", Expression.binaryOperation(left: nonVariableSide, operator: .multiplication, right: .variable).toString())
                    }
                    return try newEquation.__solve(printSteps: printSteps)
                }
            case .exponentiation:
                let lv = left.contains(.variable)
                let rv = right.contains(.variable)
                guard lv || rv else {
                    throw SolverError.InternalError.variableHasMagicallyDisappeared
                }
                if lv && rv {
                    throw SolverError.InternalError.notYetSupported(description: "Solving equations where the variable is in the base and the exponent")
                }
                if lv {
                    //var on left (in base)
                    //x^2 = 4 -> x = 4^(1/2)

                    //trying to convert x^2=9 to x=±3
//                    let exp = try! right.resolve()
//                    for e in exp {
//                        if round(e) == e {
//                            Int(e).isMultiple(of: 1) && Int(e) > 1
//                        }
//                    }
                    let newLeft = left
                    let newRight = Expression.binaryOperation(left: nonVariableSide, operator: .exponentiation, right: .binaryOperation(left: .number(value: 1), operator: .division, right: right))
                    let newEquation = Expression.equation(left: newLeft, right: newRight)
                    return try newEquation.__solve(printSteps: printSteps)
                } else {
                    //var on right (in exponent)
                    //2^x = 4 -> x*log(2)=log(4)
                    throw SolverError.InternalError.notYetSupported(description: "Solving equations where the variable is inside an exponent")
                }
            case .modulus:
                throw SolverError.InternalError.notYetSupported(description: "Solving equations where the variable is inside a modulo")
            }
        case .multiplePossibilities(possiblities: let list):
            switch list.count {
            case 0: throw SolverError.InternalError.notYetSupported(description: "{} = something")
            case 1: return try Expression.equation(left: list[0], right: nonVariableSide).__solve(printSteps: printSteps)
            default:
                //{x+1, 2*x}=10
                //x={10-1, 10/2}
                return try Expression.multiplePossibilities(possiblities: list.map { lhs in
                    return try Expression.equation(left: lhs, right: nonVariableSide).__solve(printSteps: printSteps)
                })
            }
//            throw SolverError.InternalError.notYetSupported(description: "variable inside multiple possibilities \(list)")
        }
    }

    fileprivate static func commutativeBinaryOperation(left: Expression, right: Expression, oneVar: (_ varSide: Expression, _ nonVarSide: Expression) throws -> Expression, twoVars: (Expression, Expression) throws -> Expression) throws -> Expression {
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
    fileprivate static func simpleCommutativeBinaryOperation(left: Expression, right: Expression, nonVariableSide: Expression, invertedOperator: BinaryOperator, printSteps: Bool, bothSidesHaveVars twoVars: (Expression, Expression) throws -> Expression) throws -> Expression {
        return try commutativeBinaryOperation(left: left, right: right, oneVar: { (varSide, nonVarSide) in
            let newLeft = varSide
            let newRight = Expression.binaryOperation(left: nonVariableSide, operator: invertedOperator, right: nonVarSide)
            let newEquation = Expression.equation(left: newLeft, right: newRight)
            return try newEquation.__solve(printSteps: printSteps)
        }, twoVars: twoVars)
    }

    //Given 5x, returns 5. Given 5x^1, returns nil
    //Given ax, returns a. Any other form (even without mathematical impact) will return nil
    var nonVariableCoefficient: Expression? {
        switch self {
        case let .binaryOperation(left, op, right):
            switch op {
            case .multiplication:
                let lv = left.contains(.variable)
                let rv = right.contains(.variable)
                guard lv || rv else {
                    return nil
                }
                guard !(lv && rv) else {
                    return nil
                }
                if lv {
                    if left == .variable {
                        return right
                    }
                }
                if rv {
                    if right == .variable {
                        return left
                    }
                }
            default: return nil
            }
        case .variable: return .number(value: 1)
        case .unaryOperator(operator: let op, value: let value):
            if op == .negation {
                if let nvc = value.nonVariableCoefficient {
                    return .unaryOperator(operator: .negation, value: nvc)
                }
            }
        default: return nil
        }
        return nil
    }

    //Given x^2, returns 2. Given 1x^2, returns nil
    var nonVariableDegree: Expression? {
        switch self {
        case let .binaryOperation(left, op, right):
            switch op {
            case .exponentiation:
                let lv = left.contains(.variable)
                let rv = right.contains(.variable)
                guard lv && !rv else {
                    return nil
                }
                if left == .variable {
                    return right
                }
            default: return nil
            }
        case .variable: return .number(value: 1)
        default: return nil
        }
        return nil
    }

    //Given ax^b, returns (a, b) iff x is not in a or b
    var nonVariableCoefficientAndDegree: (coefficient: Expression, degree: Expression)? {
        //If there is no coefficient
        if let nvd = nonVariableDegree {
            return (.number(value: 1), nvd)
        }
        //We expect (a * (x ^ b))
        switch self {
        case let .binaryOperation(left, op, right):
            switch op {
            case .multiplication:
                //TODO: other order?
                let lv = left.contains(.variable)
                let rv = right.contains(.variable)
                guard !(lv && rv) else {
                    return nil
                }
                guard lv || rv else {
                    return nil
                }
                if rv {
                    if case let .binaryOperation(base, op2, exp) = right, op2 == .exponentiation {
                        guard base == .variable else {
                            return nil
                        }
                        guard !exp.contains(.variable) else {
                            return nil
                        }
                        return (left, exp)
                    } else if right == .variable {
                        return (left, .number(value: 1))
                    }
                } else {
                    //variable on left
                    if case let .binaryOperation(base, op2, exp) = left, op2 == .exponentiation {
                        guard base == .variable else {
                            return nil
                        }
                        guard !exp.contains(.variable) else {
                            return nil
                        }
                        return (right, exp)
                    } else if left == .variable {
                        return (right, .number(value: 1))
                    }
                }
            default: return nil
            }
        case .variable: return (.number(value: 1), .number(value: 1))
        case .unaryOperator(operator: let op, value: let value):
            if op == .negation {
                if let nvcad = value.nonVariableCoefficientAndDegree {
                    return (.unaryOperator(operator: .negation, value: nvcad.coefficient), nvcad.degree)
                }
            }
        default: return nil
        }
        return nil
    }
}

//MARK: - Operators
public enum BinaryOperator {
    case addition
    case subtraction
    case multiplication
    case division
    case exponentiation
    case modulus

    func perform(on left: Expression, and right: Expression) throws -> [Double] {
        let lef = try left.resolve()
        let rig = try right.resolve()
        var results = [Double]()
        for l in lef {
            for r in rig {
                switch self {
                case .addition: results.append(l + r)
                case .subtraction: results.append(l - r)
                case .multiplication: results.append(l * r)
                case .division: results.append(l / r)
                case .exponentiation: results.append(pow(l, r))
                case .modulus: results.append(l.truncatingRemainder(dividingBy: r))
                }
            }
        }
        return results
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
    case absoluteValue

    func perform(on value: Expression) throws -> [Double] {
        let values = try value.resolve()
        var results = [Double]()
        for val in values {
            switch self {
            case .factorial:
                results.append(try val.factorial())
            case .negation:
                results.append(-val)
            case .absoluteValue:
                results.append(abs(val))
            }
        }
        return results
    }

    func symbol(on expr: Expression) -> String {
        if self == .absoluteValue {
            return "|\(expr.toString())|"
        }
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
        case .absoluteValue: fatalError("Already handled")
        }
    }
}

extension Double {
    var unsafeFactorial: Double {
        Double(Array(1...Int(self)).reduce(1, *))
    }
    func factorial() throws -> Double {
        if self == rounded() { //integer
            return unsafeFactorial
        } else {
            throw SolverError.ResolveError.nonIntegerFactorial(val: self)
        }
    }
}

//MARK: - Errors
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
        case illegalToken(token: LexicalToken)
        case incompleteExpression
        case tokensRemainingAfterParsing(remaining: [LexicalToken])
        case tooManyVariables(newVariable: String)
        case unmatchedAbsoluteValue
        case unmatchedOpeningBrace
        indirect case expectedMoreTokens(error: ParseError?)
    }
    public enum SolveError: Swift.Error {
        case solvingExpression
        case solvingEquationWithoutVariable(equal: Bool)
        case variableInFactorial
    }
    fileprivate enum InternalError: Swift.Error {
        case variableHasMagicallyDisappeared
        case notYetSupported(description: String)
        case unreachable(reason: String)
    }
}
