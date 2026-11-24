import XCTest
@testable import Search

/// GitHub live folders (GitHubPulls.swift): which addresses are GitHub's
/// pull request lists and what search each is, and how the search's answer
/// reads as lines. No network, no gh.
final class GitHubPullsTests: XCTestCase {
    private func query(_ text: String) -> GitHubPulls.Query? {
        GitHubPulls.query(URL(string: text)!)
    }

    func testPullsAndItsTabsAreGitHubsOwnSearches() {
        XCTAssertEqual(query("https://github.com/pulls"),
                       .init(q: "is:open is:pr author:@me archived:false", title: "Your pull requests"))
        XCTAssertEqual(query("https://github.com/pulls/review-requested")?.q,
                       "is:open is:pr review-requested:@me archived:false")
        XCTAssertEqual(query("https://www.github.com/pulls/assigned")?.q, "is:open is:pr assignee:@me archived:false")
        XCTAssertEqual(query("https://github.com/pulls/mentioned")?.title, "Mentioning you")
        XCTAssertNil(query("https://github.com/pulls/nonsense"))
    }

    func testAQueryOnThePageIsTakenAsItIs() {
        let q = query("https://github.com/pulls?q=is%3Aopen+is%3Apr+author%3A%40me+org%3AExample")
        XCTAssertEqual(q?.q, "is:open is:pr author:@me org:Example")
        XCTAssertEqual(q?.title, "Your pull requests")
        // Pull requests said outright when the query doesn't.
        XCTAssertEqual(query("https://github.com/pulls?q=org%3AExample")?.q, "org:Example is:pr")
    }

    func testARepositorysPullsAreSearchedInIt() {
        XCTAssertEqual(query("https://github.com/owner/repo/pulls"),
                       .init(q: "is:pr is:open repo:owner/repo", title: "repo pull requests", repo: "owner/repo"))
        XCTAssertEqual(query("https://github.com/owner/repo/pulls?q=is%3Apr+is%3Aopen+label%3Abug")?.q,
                       "is:pr is:open label:bug repo:owner/repo")
    }

    func testASearchForPullRequestsIsOneAndAnythingElseIsAFeed() {
        XCTAssertEqual(query("https://github.com/search?q=author%3Ame&type=pullrequests")?.q, "author:me is:pr")
        XCTAssertNil(query("https://github.com/search?q=author%3Ame&type=repositories"))
        XCTAssertNil(query("https://github.com/owner/repo/releases.atom"))
        XCTAssertNil(query("https://github.com/owner/repo"))
        XCTAssertNil(query("https://gitlab.com/pulls"))
    }

    func testTheAPIAddressKeepsAPlusAPlus() throws {
        let q = try XCTUnwrap(query("https://github.com/pulls?q=is%3Apr+label%3Ac%2B%2B"))
        let api = try XCTUnwrap(GitHubPulls.api(q)).absoluteString
        XCTAssertTrue(api.hasPrefix("https://api.github.com/search/issues?q=is:pr%20label:c%2B%2B&per_page=50"), api)
        XCTAssertTrue(api.hasSuffix("&sort=updated&order=desc"), api)
    }

    private let answer = Data("""
    {"total_count": 3, "items": [
      {"number": 741, "title": "fix(ui): say  when\\n a file is missing", "html_url": "https://github.com/acme/web/pull/741",
       "repository_url": "https://api.github.com/repos/acme/web"},
      {"number": 12, "title": "Tom &amp; Jerry", "html_url": "https://github.com/acme/api/pull/12",
       "repository_url": "https://api.github.com/repos/acme/api"},
      {"number": 741, "title": "again", "html_url": "https://github.com/acme/web/pull/741",
       "repository_url": "https://api.github.com/repos/acme/web"},
      {"number": 1, "title": "elsewhere", "html_url": "https://evil.example/pull/1"}
    ]}
    """.utf8)

    func testLinesNameTheRepositoryUnlessTheFolderIsOnes() throws {
        let many = try XCTUnwrap(GitHubPulls.items(answer, repo: nil))
        XCTAssertEqual(many.map(\.title), ["web#741 · fix(ui): say when a file is missing", "api#12 · Tom & Jerry"])
        XCTAssertEqual(many.map(\.link.absoluteString),
                       ["https://github.com/acme/web/pull/741", "https://github.com/acme/api/pull/12"])
        let one = try XCTUnwrap(GitHubPulls.items(answer, repo: "acme/web"))
        XCTAssertEqual(one.first?.title, "#741 · fix(ui): say when a file is missing")
        XCTAssertNil(GitHubPulls.items(Data("<html>".utf8), repo: nil))
    }

    func testAPullRequestsLineWearsItsMark() {
        XCTAssertEqual(FeedItem(id: UUID(), title: "", link: URL(string: "https://github.com/a/b/pull/3")!).symbol,
                       "arrow.triangle.pull")
        XCTAssertEqual(FeedItem(id: UUID(), title: "", link: URL(string: "https://blog.example/3")!).symbol, "doc.text")
    }
}
