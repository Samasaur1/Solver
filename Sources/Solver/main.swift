import SolverKit
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

    @Argument(help: .init("The equation to evaluate. If not given, reads from standard input.", discussion: "This can either be an expression (no variables, no equals sign), in which case it will be evaluated, or an equation (one variable, one equals sign), in which case the command will attempt to solve for the variable.")) var equation: String?

    func run() throws {
        if let eq = equation {
            handle(equation: eq)
        } else {
            while let eq = readLine() {
                handle(equation: eq)
            }
        }
    }

    private func handle(equation: String) {
        do {
            let tree = try SolverKit.parse(equation)
            let result = try tree.resolve()
            print(result)
        } catch {
            print("Error:".red, error, to: &STDERR)
        }
    }
}

Solver.main()
