import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}
require(AssistantSigningPolicy.matches("Ab12", portalSerials: ["ab12"], hasPrivateKey: true), "Mixed-case certificate serial must match")
require(!AssistantSigningPolicy.matches("ab12", portalSerials: ["ab12"], hasPrivateKey: false), "Public certificate alone cannot sign")
require(!AssistantSigningPolicy.matches("wrong", portalSerials: ["ab12"], hasPrivateKey: true), "Wrong account or revoked certificate must be refused")
require(!AssistantSigningPolicy.matches("", portalSerials: [""], hasPrivateKey: true), "Empty serial is invalid")
require(AssistantSigningPolicy.canCreateCertificate(portalSerials: [], hasImportedCertificate: false), "New account can create its first certificate")
require(!AssistantSigningPolicy.canCreateCertificate(portalSerials: ["ab12"], hasImportedCertificate: false), "Missing private key must not create replacement certificate")
require(!AssistantSigningPolicy.canCreateCertificate(portalSerials: [], hasImportedCertificate: true), "Imported certificate missing from portal must not trigger replacement")
print("Certificate account, private-key and creation-policy tests passed")
