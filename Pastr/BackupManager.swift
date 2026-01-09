import CommonCrypto
import CryptoKit
import Foundation

final class BackupManager {
    private let persistence = HistoryPersistence()

    func export(items: [ClipboardItem], to url: URL, format: ExportFormat) throws {
        switch format {
        case .json:
            let data = try persistence.encodeItems(items)
            try data.write(to: url, options: .atomic)
        case .csv:
            let csv = csvString(from: items)
            try csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func createBackup(items: [ClipboardItem], to url: URL, password: String?) throws {
        let data = try persistence.encodeItems(items)
        if let password, !password.isEmpty {
            let encrypted = try encryptBackup(data: data, password: password)
            try encrypted.write(to: url, options: .atomic)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func restoreBackup(from url: URL, password: String?) throws -> [ClipboardItem] {
        let data = try Data(contentsOf: url)
        if isEncryptedBackup(data) {
            guard let password, !password.isEmpty else {
                throw BackupError.passwordRequired
            }
            let decrypted = try decryptBackup(data: data, password: password)
            return try persistence.decodeItems(from: decrypted)
        }
        return try persistence.decodeItems(from: data)
    }

    func isEncryptedBackup(_ data: Data) -> Bool {
        data.starts(with: BackupCrypto.magic)
    }

    private func csvString(from items: [ClipboardItem]) -> String {
        var lines: [String] = []
        lines.append("createdAt,type,textContent,urlString,fileURLs,sourceAppName,isPinned,pinnedTitle")
        for item in items {
            let createdAt = ISO8601DateFormatter().string(from: item.createdAt)
            let fileURLs = item.fileURLs.map { $0.path }.joined(separator: "|")
            let columns = [
                createdAt,
                item.type.rawValue,
                item.textContent ?? "",
                item.urlString ?? "",
                fileURLs,
                item.sourceAppName ?? "",
                item.isPinned ? "true" : "false",
                item.pinnedTitle ?? ""
            ]
            lines.append(columns.map { csvEscape($0) }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n")
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if needsQuotes {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }

    private func encryptBackup(data: Data, password: String) throws -> Data {
        try BackupCrypto.encrypt(data: data, password: password)
    }

    private func decryptBackup(data: Data, password: String) throws -> Data {
        try BackupCrypto.decrypt(data: data, password: password)
    }
}

enum ExportFormat {
    case json
    case csv
}

enum BackupError: LocalizedError {
    case passwordRequired
    case invalidPassword
    case corruptedBackup

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "Password required to decrypt this backup."
        case .invalidPassword:
            return "Incorrect password for this backup."
        case .corruptedBackup:
            return "This backup file is corrupted or unreadable."
        }
    }
}

private enum BackupCrypto {
    static let magic = Data("PSTRBK1".utf8)
    private static let saltLength = 16
    private static let keyLength = 32
    private static let pbkdfRounds: UInt32 = 120_000

    static func encrypt(data: Data, password: String) throws -> Data {
        let salt = randomData(count: saltLength)
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw BackupError.corruptedBackup
        }
        var output = Data()
        output.append(magic)
        output.append(salt)
        output.append(combined)
        return output
    }

    static func decrypt(data: Data, password: String) throws -> Data {
        guard data.count > magic.count + saltLength else {
            throw BackupError.corruptedBackup
        }
        let saltRange = magic.count..<(magic.count + saltLength)
        let salt = data.subdata(in: saltRange)
        let sealedData = data.subdata(in: (magic.count + saltLength)..<data.count)
        let key = deriveKey(password: password, salt: salt)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw BackupError.invalidPassword
        }
    }

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        var derivedKey = Data(count: keyLength)
        let passwordData = Data(password.utf8)
        let result = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    pbkdfRounds,
                    derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyLength
                )
            }
        }
        if result != kCCSuccess {
            return SymmetricKey(data: SHA256.hash(data: passwordData + salt))
        }
        return SymmetricKey(data: derivedKey)
    }

    private static func randomData(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        return data
    }
}
