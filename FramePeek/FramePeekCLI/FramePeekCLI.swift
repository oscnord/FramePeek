//
//  main.swift
//  FramePeekCLI
//
//  Created by Oscar Nord on 2026-01-24.
//

import ArgumentParser

@main
struct FramePeekCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "framepeek-cli",
        abstract: "Analyze media files from the command line",
        version: "1.0.0",
        subcommands: [AnalyzeCommand.self],
        defaultSubcommand: AnalyzeCommand.self
    )
}
