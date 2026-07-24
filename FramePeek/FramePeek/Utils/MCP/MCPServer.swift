import Foundation

// MARK: - JSON value

public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

// MARK: - JSON-RPC envelopes

private struct RPCRequest: Decodable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

private struct RPCResponse: Encodable {
    let jsonrpc = "2.0"
    let id: JSONValue
    var result: JSONValue?
    var error: RPCError?
}

private struct RPCError: Encodable {
    let code: Int
    let message: String
}

// MARK: - MCP server

/// Handles MCP (Model Context Protocol) messages: newline-delimited
/// JSON-RPC 2.0 with the initialize/tools handshake. Transport-agnostic;
/// the CLI pumps stdin/stdout through `handle`.
public struct MCPServer: Sendable {
    public static let serverName = "framepeek"
    public static let serverVersion = "1.0.0"
    static let fallbackProtocolVersion = "2025-06-18"

    public init() {}

    public struct HTTPReply: Sendable {
        public let status: Int
        public let body: String?
    }

    /// Streamable-HTTP mapping: requests get 200 + JSON, notifications 202.
    public func handleHTTP(_ body: String) async -> HTTPReply {
        guard let response = await handle(body) else {
            return HTTPReply(status: 202, body: nil)
        }
        return HTTPReply(status: 200, body: response)
    }

    /// Returns the JSON response line, or nil for notifications.
    public func handle(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let request = try? JSONDecoder().decode(RPCRequest.self, from: Data(trimmed.utf8)) else {
            return encode(RPCResponse(id: .null, error: RPCError(code: -32700, message: "Parse error")))
        }

        let isNotification = request.id == nil
        let response = await dispatch(request)
        guard !isNotification else { return nil }
        return encode(response)
    }

    private func dispatch(_ request: RPCRequest) async -> RPCResponse {
        let id = request.id ?? .null
        switch request.method {
        case "initialize":
            let clientVersion = request.params?.objectValue?["protocolVersion"]?.stringValue
            return RPCResponse(id: id, result: .object([
                "protocolVersion": .string(clientVersion ?? Self.fallbackProtocolVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string(Self.serverName),
                    "version": .string(Self.serverVersion),
                ]),
            ]))
        case "ping":
            return RPCResponse(id: id, result: .object([:]))
        case "tools/list":
            return RPCResponse(id: id, result: .object(["tools": .array(MCPTools.definitions)]))
        case "tools/call":
            guard let params = request.params?.objectValue,
                  let name = params["name"]?.stringValue else {
                return RPCResponse(id: id, error: RPCError(code: -32602, message: "Missing tool name"))
            }
            let arguments = params["arguments"] ?? .object([:])
            let result = await MCPTools.call(name: name, arguments: arguments)
            switch result {
            case .success(let json):
                return RPCResponse(id: id, result: .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(json)])]),
                    "isError": .bool(false),
                ]))
            case .failure(let error):
                if case MCPToolError.unknownTool = error {
                    return RPCResponse(id: id, error: RPCError(code: -32602, message: "Unknown tool: \(name)"))
                }
                return RPCResponse(id: id, result: .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(error.localizedDescription)])]),
                    "isError": .bool(true),
                ]))
            }
        default:
            return RPCResponse(id: id, error: RPCError(code: -32601, message: "Method not found: \(request.method)"))
        }
    }

    private func encode(_ response: RPCResponse) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(response),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return text
    }
}
