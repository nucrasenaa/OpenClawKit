import Foundation
#if canImport(Security)
import Security
#endif

public enum OpenClawSecurity {
    public static func normalizeFingerprint(_ value: String) -> String {
        let stripped = value.replacingOccurrences(
            of: #"(?i)^sha-?256\s*:?\s*"#,
            with: "",
            options: .regularExpression
        )
        return stripped.lowercased().filter(\.isHexDigit)
    }

    #if canImport(Security)
    public static func tlsLeafCertificateSHA256(trust: SecTrust) -> String? {
        guard
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
            let cert = chain.first
        else {
            return nil
        }

        let data = SecCertificateCopyData(cert) as Data
        return OpenClawCrypto.sha256Hex(data)
    }
    #endif
}

