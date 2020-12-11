import SolverKit

//let expression = ResolvedExpression.binaryOperation(left: .unaryOperator(operator: .negation, value: .number(value: 2)), operator: .multiplication, right: .unaryOperator(operator: .factorial, value: .number(value: 3.1)))
//
//
//dump(expression)
//do {
//    print(try expression.resolve())
//} catch let SolverKit.Error.nonIntegerFactorial(val) {
//    print("Attempted to take the factorial of a non-integer value (\(val))")
//}
//do {
//    dump(try parse("-2*3.1!"))
//} catch let SolverKit.Error.illegalCharacter(char) {
//    print("Attempted to parse illegal character (\(char))")
//}
import ArgumentParser
import Rainbow

// From: https://github.com/Samasaur1/DiceKit/blob/d67f52f6d2b483180814644cd1d96edb97e060d1/Sources/DiceKit/Utilities.swift
import Foundation
internal struct FileHandleOutputStream: TextOutputStream {
    private let fileHandle: FileHandle
    let encoding: String.Encoding

    init(_ fileHandle: FileHandle, encoding: String.Encoding = .utf8) {
        self.fileHandle = fileHandle
        self.encoding = encoding
    }

    mutating func write(_ string: String) {
        if let data = string.data(using: encoding) {
            fileHandle.write(data)
        }
    }
}
internal var STDERR = FileHandleOutputStream(.standardError)
internal var STDOUT = FileHandleOutputStream(.standardOutput)
// end from

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

    @Argument var equation: String?

    func run() throws {
        if let eq = equation {
            do {
                let tree = try SolverKit.parse(eq)
                let result = try tree.resolve()
                print(result)
            } catch {
//                print("Error: \(error)")
                print("Error:".red, error, to: &STDERR)
            }
        } else {
            while let eq = readLine() {
                do {
                    let tree = try SolverKit.parse(eq)
                    let result = try tree.resolve()
                    print(result)
                } catch {
//                    print("Error: \(error)", to: &STDERR)
                    print("Error:".red, error, to: &STDERR)
                }
            }
        }
    }
}

Solver.main()
