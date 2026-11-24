import XCTest
@testable import Search

/// GitHub live folders (GitHubPulls.swift): which addresses are GitHub's
/// pull request lists and what search each is, and how the search's answer
/// reads as lines, marked with its review. No network, no gh.
final class GitHubPullsTests: XCTestCase {
    private func query(_ text: String) -> GitHubPulls.Query? {
        GitHubPulls.query(URL(string: text)!)
    }

    func testPullsAndItsTabsAreGitHubsOwnSearches() {
        XCTAssertEqual(query("https://github.com/pulls"),
                       .init(q: "is:open is:pr author:@me archived:false", title: "Your open pull requests"))
        XCTAssertEqual(query("https://github.com/pulls/review-requested")?.q,
                       "is:open is:pr review-requested:@me archived:false")
        XCTAssertEqual(query("https://www.github.com/pulls/assigned")?.q, "is:open is:pr assignee:@me archived:false")
        XCTAssertEqual(query("https://github.com/pulls/mentioned")?.title, "Mentioning you")
        XCTAssertNil(query("https://github.com/pulls/nonsense"))
    }

    func testAQueryOnThePageIsTakenAsItIs() {
        let q = query("https://github.com/pulls?q=is%3Aopen+is%3Apr+author%3A%40me+org%3AExample")
        XCTAssertEqual(q?.q, "is:open is:pr author:@me org:Example")
        XCTAssertEqual(q?.title, "Your open pull requests")
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

    func testOpenOnesAndThoseMergedSinceAreSearched() throws {
        let since = Date(timeIntervalSince1970: 1_795_000_000)  // 2026-11-18T11:06:40Z
        let mine = try XCTUnwrap(query("https://github.com/pulls"))
        let both = GitHubPulls.searches(mine, since: since)
        XCTAssertEqual(both.open, "is:open is:pr author:@me archived:false sort:updated-desc")
        XCTAssertEqual(both.merged, "is:merged is:pr author:@me archived:false merged:>=2026-11-18T11:06:40Z sort:updated-desc")
        // Open only, said when the query doesn't; its own sort kept.
        let repo = try XCTUnwrap(query("https://github.com/o/r/pulls?q=is%3Apr+label%3Abug+sort%3Acreated-asc"))
        XCTAssertEqual(GitHubPulls.searches(repo, since: since).open, "is:pr label:bug sort:created-asc repo:o/r is:open")
        // One that asks for merged or closed ones gets just those.
        let done = try XCTUnwrap(query("https://github.com/pulls?q=is%3Apr+is%3Amerged+author%3A%40me"))
        XCTAssertEqual(GitHubPulls.searches(done, since: since).open, "is:pr is:merged author:@me sort:updated-desc")
        XCTAssertNil(GitHubPulls.searches(done, since: since).merged)
    }

    func testTheReviewIsGitHubsDecisionElseTheLatestReviews() {
        typealias S = GitHubPulls.State
        XCTAssertEqual(S.of(merged: true, decision: "CHANGES_REQUESTED", reviews: []), .merged)
        XCTAssertEqual(S.of(merged: false, decision: "APPROVED", reviews: []), .approved)
        XCTAssertEqual(S.of(merged: false, decision: "CHANGES_REQUESTED", reviews: ["APPROVED"]), .changes)
        // One approval of two wanted is still waiting.
        XCTAssertEqual(S.of(merged: false, decision: "REVIEW_REQUIRED", reviews: ["APPROVED"]), .open)
        XCTAssertEqual(S.of(merged: false, decision: nil, reviews: ["APPROVED", "CHANGES_REQUESTED"]), .changes)
        XCTAssertEqual(S.of(merged: false, decision: nil, reviews: ["COMMENTED", "APPROVED"]), .approved)
        XCTAssertEqual(S.of(merged: false, decision: nil, reviews: ["COMMENTED"]), .open)
    }

    private let answer = Data("""
    {"data": {
      "open": {"nodes": [
        {"number": 741, "title": "fix(ui): say  when\\n a file is missing", "url": "https://github.com/acme/web/pull/741",
         "mergedAt": null, "reviewDecision": "APPROVED", "repository": {"name": "web"},
         "comments": {"totalCount": 2}, "reviewThreads": {"totalCount": 1}, "latestReviews": {"nodes": [{"state": "APPROVED"}]}},
        {},
        {"number": 1, "title": "elsewhere", "url": "https://evil.example/pull/1", "repository": {"name": "x"}},
        {"number": 12, "title": "Tom &amp; Jerry", "url": "https://github.com/acme/api/pull/12",
         "mergedAt": null, "reviewDecision": null, "repository": {"name": "api"},
         "comments": {"totalCount": 0}, "reviewThreads": {"totalCount": 0}, "latestReviews": {"nodes": []}}
      ]},
      "merged": {"nodes": [
        {"number": 741, "title": "again", "url": "https://github.com/acme/web/pull/741", "mergedAt": "2026-11-24T01:00:00Z"},
        {"number": 9, "title": "Done", "url": "https://github.com/acme/web/pull/9", "mergedAt": "2026-11-24T01:00:00Z",
         "repository": {"name": "web"}}
      ]}
    }}
    """.utf8)

    func testLinesAreTheOpenOnesThenTheMergedMarkedWithTheirReview() throws {
        let many = try XCTUnwrap(GitHubPulls.items(answer, repo: nil).items)
        XCTAssertEqual(many.map(\.title), ["fix(ui): say when a file is missing", "Tom & Jerry", "Done"])
        XCTAssertEqual(many.map(\.state), ["approved", "open", "merged"])
        XCTAssertEqual(many.map(\.comments), [3, 0, 0])
        XCTAssertEqual(many.map(\.link.absoluteString), ["https://github.com/acme/web/pull/741",
                                                         "https://github.com/acme/api/pull/12",
                                                         "https://github.com/acme/web/pull/9"])
        XCTAssertEqual(many[0].pullSaid, "Approved · 3 comments")
        XCTAssertEqual(many[0].pullPlace, "acme/web#741")
        XCTAssertEqual(many[1].pullSaid, "Open")
    }

    func testATitleManyShareNamesItsRepositoryUnlessTheFolderIsOnes() throws {
        let same = Data("""
        {"data": {"open": {"nodes": [
          {"number": 8, "title": "fix(security): one fix", "url": "https://github.com/acme/api/pull/8", "repository": {"name": "api"}},
          {"number": 3, "title": "fix(security): one fix", "url": "https://github.com/acme/web/pull/3", "repository": {"name": "web"}},
          {"number": 4, "title": "Only once", "url": "https://github.com/acme/web/pull/4", "repository": {"name": "web"}}
        ]}}}
        """.utf8)
        XCTAssertEqual(try XCTUnwrap(GitHubPulls.items(same, repo: nil).items).map(\.title),
                       ["api · fix(security): one fix", "web · fix(security): one fix", "Only once"])
        XCTAssertEqual(try XCTUnwrap(GitHubPulls.items(same, repo: "acme/web").items).map(\.title),
                       ["fix(security): one fix", "fix(security): one fix", "Only once"])
    }

    func testGitHubsComplaintIsKeptAndAPageReadsAsNothing() {
        let said = GitHubPulls.items(Data(#"{"errors": [{"message": "Bad qualifier"}]}"#.utf8), repo: nil)
        XCTAssertNil(said.items)
        XCTAssertEqual(said.complaint, "Bad qualifier")
        XCTAssertNil(GitHubPulls.items(Data("<html>".utf8), repo: nil).items)
    }

    func testAPullRequestsStateIsKeptAndAPostIsWrittenAsBefore() throws {
        let pull = FeedItem(id: UUID(), title: "t", link: URL(string: "https://github.com/a/b/pull/3")!,
                            state: "changes", comments: 4)
        XCTAssertEqual(try JSONDecoder().decode(FeedItem.self, from: JSONEncoder().encode(pull)), pull)
        let post = FeedItem(id: UUID(), title: "t", link: URL(string: "https://blog.example/3")!)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(post)) as? [String: Any])
        XCTAssertEqual(Set(written.keys), ["id", "title", "link"])
        XCTAssertNil(post.pull)
    }

    func testAPullRequestsLineWearsItsMark() {
        XCTAssertEqual(FeedItem(id: UUID(), title: "", link: URL(string: "https://github.com/a/b/pull/3")!).symbol,
                       "arrow.triangle.pull")
        XCTAssertEqual(FeedItem(id: UUID(), title: "", link: URL(string: "https://github.com/a/b/pull/3")!,
                                state: "merged").symbol, "arrow.triangle.merge")
        XCTAssertEqual(FeedItem(id: UUID(), title: "", link: URL(string: "https://blog.example/3")!).symbol, "doc.text")
    }
}
