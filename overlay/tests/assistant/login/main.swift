import Foundation

func require(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
let valid = Data(#"{"client_info":"<client> <system> <AuthKit>","user_agent":"akd/1.0"}"#.utf8)
let client = try AssistantLoginPolicy.decodeClient(valid)
require(client.userAgent == "akd/1.0", "Service client metadata must decode")
for invalid in [Data(#"{"client_info":"bad\r\nInjected: yes","user_agent":"akd"}"#.utf8),
                Data(#"{"client_info":"","user_agent":"akd"}"#.utf8),
                Data(#"{"client_info":"valid"}"#.utf8), Data(repeating: 32, count: 32_769)] {
    do { _ = try AssistantLoginPolicy.decodeClient(invalid); fatalError("Invalid service metadata accepted") }
    catch { }
}
require(AssistantErrorPresentation.describe(domain: "SideSign.ServerError", code: 0, authenticationCode: -80045).contains("-80045"), "Apple code must survive wrapping")
require(AssistantErrorPresentation.describe(domain: "NSURLErrorDomain", code: -1009).contains("网络"), "Network failures must be classified")
let unknown = AssistantErrorPresentation.describe(domain: "secret@example.test/token/device-id", code: 21)
require(!unknown.contains("secret") && !unknown.contains("device-id"), "Arbitrary domains must not leak identifiers")
require(!unknown.contains("配对文件"), "An unknown numeric code must not be diagnosed as invalid pairing")
print("Login metadata validation and safe error classification tests passed")

let legacy = ["certificate": Data([1, 2]), "password": Data([3])]
var local: [String: Data] = ["certificate": Data([9])]
var failWrite = true
enum TestFailure: Error { case write }
func migrate() throws {
    try AssistantCredentialMigration.copyMissing(keys: ["certificate", "password"],
        read: { key, synchronized in synchronized ? legacy[key] : local[key] },
        write: { data, key in
            if failWrite && key == "password" { throw TestFailure.write }
            local[key] = data
        })
}
do { try migrate(); fatalError("Failed storage must prevent migration success") } catch { }
require(local[AssistantCredentialMigration.marker] == nil, "Failed migration must be resumable")
require(local["certificate"] == Data([9]), "Migration must not replace existing local identity")
failWrite = false
try migrate()
require(local["password"] == legacy["password"], "Retry must copy missing credentials")
require(local[AssistantCredentialMigration.marker] != nil, "Success marker must be last")
local["password"] = nil
try migrate()
require(local["password"] == nil, "Logout must not resurrect old synchronized credentials")
require(legacy["certificate"] == Data([1, 2]), "Migration must leave other devices' originals untouched")
print("Credential migration preservation, failure recovery and logout tests passed")
