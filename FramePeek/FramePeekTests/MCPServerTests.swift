import Testing
import Foundation
@testable import FramePeekCore

/// Drives the MCP JSON-RPC dispatcher in-process; the CLI's `mcp`
/// subcommand is a thin stdin/stdout pump around the same handler.
struct MCPServerTests {

    private let server = MCPServer()

    private var fixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-h264.mp4")
            .path
    }

    private func send(_ json: String) async throws -> [String: Any]? {
        guard let response = await server.handle(json) else { return nil }
        let object = try JSONSerialization.jsonObject(with: Data(response.utf8))
        return object as? [String: Any]
    }

    private func callTool(_ name: String, arguments: String) async throws -> (text: String, isError: Bool) {
        let request = #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
        let response = try #require(try await send(request))
        let result = try #require(response["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        return (text, result["isError"] as? Bool ?? false)
    }

    @Test func initialize_returnsHandshake() async throws {
        let response = try #require(try await send(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#
        ))
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        let serverInfo = try #require(result["serverInfo"] as? [String: Any])
        #expect(serverInfo["name"] as? String == "framepeek")
        let capabilities = try #require(result["capabilities"] as? [String: Any])
        #expect(capabilities["tools"] != nil)
    }

    @Test func notifications_produceNoResponse() async throws {
        #expect(await server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(await server.handle("") == nil)
    }

    @Test func unknownMethod_and_parseError_returnRPCErrors() async throws {
        let unknown = try #require(try await send(#"{"jsonrpc":"2.0","id":2,"method":"bogus/method"}"#))
        #expect(((unknown["error"] as? [String: Any])?["code"] as? Int) == -32601)

        let garbage = try #require(try await send("this is not json"))
        #expect(((garbage["error"] as? [String: Any])?["code"] as? Int) == -32700)
    }

    @Test func toolsList_declaresToolsWithSchemas() async throws {
        let response = try #require(try await send(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#))
        let result = try #require(response["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names == ["analyze_media", "media_summary", "inspect_container", "inspect_hls_ladder"])

        for tool in tools {
            let schema = try #require(tool["inputSchema"] as? [String: Any])
            #expect(schema["type"] as? String == "object")
            #expect((schema["required"] as? [String])?.count == 1)
            #expect((tool["description"] as? String)?.isEmpty == false)
        }
    }

    @Test func inspectHLSLadder_returnsVariantsAndFindings() async throws {
        let masterPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hls/master.m3u8")
            .path
        let (text, isError) = try await callTool("inspect_hls_ladder", arguments: #"{"url":"\#(masterPath)"}"#)
        #expect(!isError)
        let result = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let variants = try #require(result["variants"] as? [[String: Any]])
        #expect(variants.count == 2)
        #expect(variants.allSatisfy { ($0["measuredAverageBitrate"] as? Double ?? 0) > 0 })
        #expect(result["isVOD"] as? Bool == true)
        #expect(result["findings"] is [Any])
        #expect(!text.contains("keyframeTimes"))
    }

    @Test func mediaSummary_returnsCompactMetadata() async throws {
        let (text, isError) = try await callTool("media_summary", arguments: #"{"path":"\#(fixturePath)"}"#)
        #expect(!isError)
        let summary = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(summary["resolution"] as? String == "320x180")
        let duration = try #require(summary["durationSeconds"] as? Double)
        #expect(abs(duration - 5.0) < 0.1)
        let audio = try #require(summary["audioTracks"] as? [[String: Any]])
        #expect(audio.count == 1)
    }

    @Test func analyzeMedia_withBitrate_returnsSamples() async throws {
        let (text, isError) = try await callTool(
            "analyze_media",
            arguments: #"{"path":"\#(fixturePath)","include":["metadata","bitrate"],"max_samples":100}"#
        )
        #expect(!isError)
        let result = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(result["metadata"] != nil)
        let bitrate = try #require(result["bitrate"] as? [String: Any])
        let samples = try #require(bitrate["samples"] as? [[String: Any]])
        #expect(!samples.isEmpty)
        #expect(samples.count <= 100)

        let (compact, _) = try await callTool(
            "analyze_media",
            arguments: #"{"path":"\#(fixturePath)","include":["bitrate"]}"#
        )
        let compactResult = try #require(try JSONSerialization.jsonObject(with: Data(compact.utf8)) as? [String: Any])
        let compactBitrate = try #require(compactResult["bitrate"] as? [String: Any])
        let compactSamples = try #require(compactBitrate["samples"] as? [[String: Any]])
        #expect(compactSamples.count <= 200)
    }

    @Test func analyzeMedia_unknownKind_isToolError() async throws {
        let (text, isError) = try await callTool(
            "analyze_media",
            arguments: #"{"path":"\#(fixturePath)","include":["bogus"]}"#
        )
        #expect(isError)
        #expect(text.contains("bogus"))
    }

    @Test func inspectContainer_returnsAtomTree() async throws {
        let (text, isError) = try await callTool("inspect_container", arguments: #"{"path":"\#(fixturePath)"}"#)
        #expect(!isError)
        let result = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let atoms = try #require(result["atoms"] as? [[String: Any]])
        let fourCCs = Set(atoms.compactMap { $0["fourCC"] as? String })
        #expect(fourCCs.contains("moov"))
        #expect(fourCCs.contains("ftyp"))
    }

    @Test func nonexistentPath_isToolErrorNotTransportFailure() async throws {
        let (text, isError) = try await callTool("media_summary", arguments: #"{"path":"/nonexistent/file.mp4"}"#)
        #expect(isError)
        #expect(text.contains("File not found"))
    }

    @Test func httpMapping_requestsGet200_notifications202() async throws {
        let request = await server.handleHTTP(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        #expect(request.status == 200)
        #expect(request.body?.contains(#""id":1"#) == true)

        let prettyPrinted = await server.handleHTTP("{\n  \"jsonrpc\": \"2.0\",\n  \"id\": 2,\n  \"method\": \"ping\"\n}\n")
        #expect(prettyPrinted.status == 200)

        let notification = await server.handleHTTP(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(notification.status == 202)
        #expect(notification.body == nil)
    }

    @Test func unknownTool_isRPCError() async throws {
        let response = try #require(try await send(
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"bogus_tool","arguments":{}}}"#
        ))
        #expect(((response["error"] as? [String: Any])?["code"] as? Int) == -32602)
    }
}
