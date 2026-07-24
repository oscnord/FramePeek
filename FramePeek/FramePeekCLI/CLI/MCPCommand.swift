import Foundation
import ArgumentParser
import FramePeekCore

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run an MCP (Model Context Protocol) server on stdio",
        discussion: """
        Speaks newline-delimited JSON-RPC 2.0 on stdin/stdout for MCP clients \
        (Claude Code, Claude Desktop, etc). Exposes analyze_media, \
        media_summary, and inspect_container tools.

        Claude Code: claude mcp add framepeek -- framepeek-cli mcp
        """
    )

    func run() async throws {
        let server = MCPServer()
        while let line = readLine(strippingNewline: true) {
            if let response = await server.handle(line) {
                print(response)
                fflush(stdout)
            }
        }
    }
}
