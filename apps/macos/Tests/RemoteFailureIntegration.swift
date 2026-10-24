import Foundation
@main struct RemoteFailureIntegration {
 static func main() async throws {
  func check(_ value: Bool, _ label: String) throws {
   guard value else { throw NSError(domain: label, code: 1) }; print("PASS: " + label)
  }
  let cases: [(String, GitRemoteFailure.Kind)] = [
   ("fatal: could not read Username: terminal prompts disabled", .authentication),
   ("remote: HTTP Basic: Access denied", .authentication),
   ("Permission denied (publickey).", .authentication),
   ("remote: Permission to org/repo denied to user. 403", .permission),
   ("protected branch hook declined", .permission),
   ("Could not resolve host: github.com", .network),
   ("SSL certificate problem", .network),
   ("Host key verification failed", .network),
   ("Repository not found", .repository),
   ("[rejected] main -> main (fetch first)", .rejected),
   ("unknown server error", .other)
  ]
  for (raw, expected) in cases { try check(GitRemoteFailure.classify(raw) == expected, raw) }
  func failure(_ urls: [String]) -> GitRemoteFailure { GitRemoteFailure(root: "/tmp", arguments: ["push"], destinations: urls, kind: .authentication) }
  try check(failure(["https://github.com/org/repo.git"]).canLogin, "GitHub HTTPS offers browser login")
  for urls in [["git@github.com:org/repo.git"], ["https://gitlab.com/org/repo"], ["https://github.com.evil.invalid/repo"], ["https://github.com/a", "https://example.invalid/b"], []] {
   try check(!failure(urls).canLogin, "No wrong-host or wrong-protocol browser login")
  }
  for address in ["https://gitlab.com/org/repo", "https://git.company.invalid/group/repo", "https://git.company.invalid:8443/group/repo", "https://192.0.2.1/repo"] {
   try check(failure([address]).canPasswordLogin, "HTTPS password prompt for " + address)
  }
  for urls in [["http://git.company.invalid/a"], ["https://user:secret@git.company.invalid/a"], ["https://git.company.invalid/a", "https://git.company.invalid:8443/b"], ["https://git.company.invalid:0/a"]] {
   try check(!failure(urls).canAuthenticate, "No unsafe or mixed-server credential prompt")
  }
  try check(failure(["https://github.com.evil.invalid/repo"]).loginServer == "github.com.evil.invalid", "lookalike host displays its own identity, never GitHub OAuth")
  let network = GitRemoteFailure(root: "/tmp", arguments: ["push"], destinations: ["https://gitlab.com/a"], kind: .network)
  try check(!network.canPasswordLogin, "network and certificate errors do not request a password")
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-remote-test-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  _ = try await Git.run(root.path, ["init", "-b", "main"])
  _ = try await Git.run(root.path, ["remote", "add", "origin", root.appendingPathComponent("missing.git").path])
  do { _ = try await Git.run(root.path, ["fetch", "origin"]); throw NSError(domain: "Expected failure", code: 1) }
  catch let f as GitRemoteFailure {
   try check(f.arguments == ["fetch", "origin"] && f.root == root.path, "Retry captures only failed remote command")
   if f.kind != .repository { print("Unexpected local remote failure kind: \(f.kind)"); fflush(stdout) }
   try check(f.kind == .repository && !f.message.contains("fatal:"), "Remote errors produce a concise repository message")
  }
  _ = try await Git.run(root.path, ["config", "url.https://git.company.invalid:8443/.insteadOf", "https://gitlab.com/"])
  let resolved = try await Git.destinations(root.path, ["clone", "--", "https://gitlab.com/team/repo.git", root.appendingPathComponent("clone").path])
  try check(resolved == ["https://git.company.invalid:8443/team/repo.git"], "clone authentication respects actual URL rewrite destination")
  do { _ = try await Git.run(root.path, ["rev-parse", "--verify", "HEAD"]); throw NSError(domain: "Expected local failure", code: 1) }
  catch is GitFailure { print("PASS: local errors do not trigger remote login") }
 }
}
