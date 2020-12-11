import SolverKit

let expression = ResolvedExpression.binaryOperation(left: .unaryOperator(operator: .negation, value: .number(value: 2)), operator: .multiplication, right: .unaryOperator(operator: .factorial, value: .number(value: 3.1)))


dump(expression)
do {
    print(try expression.resolve())
} catch let SolverKit.Error.nonIntegerFactorial(val) {
    print("Attempted to take the factorial of a non-integer value (\(val))")
}
do {
    dump(try parse("-2*3.1!"))
} catch let SolverKit.Error.illegalCharacter(char) {
    print("Attempted to parse illegal character (\(char))")
}
import ArgumentParser

struct Solver: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "solver",
        abstract: "Solve mathematical equations",
        discussion: "This command can either compute long equations (given in pseudo-LaTeX) or try to solve for a specific variable, if there is only one given and it is not too complex",
        version: "0.1.0",
        shouldDisplay: true,
        subcommands:[],
        defaultSubcommand: nil,
        helpNames: .shortAndLong)
}
