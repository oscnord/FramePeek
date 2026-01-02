
import SwiftUI

struct KV: View {
    let key: String
    let value: String
    let monospace: Bool

    init(_ key: String, _ value: String, monospace: Bool = false) {
        self.key = key
        self.value = value
        self.monospace = monospace
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .if(monospace) { $0.monospaced() }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct KVMultiline: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    VStack {
        KV("Key", "Value")
        KV("Monospace", "0.123456", monospace: true)
        KVMultiline("Multiline", "This is a longer value that may wrap to multiple lines")
    }
    .padding()
}
