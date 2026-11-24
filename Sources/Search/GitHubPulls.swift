import SwiftUI

// A live folder of GitHub pull requests, as Arc's GitHub live folder: what
// github.com/pulls (and its Assigned, Mentioned and Review requests tabs),
// a repository's Pull requests page, or a search for pull requests lists.
// GitHub has no feed for these, so New Live Folder… on such an address asks
// GitHub's GraphQL search with the page's own query instead.
//
// The folder holds the pull requests open now, each marked with where its
// review stands (Open, Approved, Changes requested) and how many comments
// it has, and under them those merged in the last day, marked Merged, so a
// merge is seen before it leaves. One closed unmerged just leaves.
//
// Signed in as the account GitHub's own command line tool, gh, has active:
// the token is asked of `gh auth token` at each fetch, sent to
// api.github.com only, and kept nowhere. GitHub's GraphQL reads nothing
// without a sign-in, so without gh the folder says what to do.
//
// Fetched every five minutes, open work changing faster than a blog.

enum GitHubPulls {
    /// A list of open work wants all of it, not a blog's latest twelve.
    static let most = 50
    static let every: TimeInterval = 5 * 60
    /// How long a merged pull request stays, marked Merged.
    static let mergedFor: TimeInterval = 24 * 60 * 60

    /// What a GitHub page lists, as a search: the query, the folder's name,
    /// and the repository when the page is one repository's.
    struct Query: Equatable {
        var q: String
        var title: String
        var repo: String?
    }

    /// The search a GitHub pull requests page shows, or nil for any other
    /// address (a repository's releases.atom stays a feed).
    static func query(_ url: URL) -> Query? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), host == "github.com" || host == "www.github.com"
        else { return nil }
        let parts = url.path().split(separator: "/").map(String.init)
        // A page's address is a form's: a + in it is a space.
        var page = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let spaced = page?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        page?.percentEncodedQuery = spaced
        let items = page?.queryItems ?? []
        let given = items.first { $0.name == "q" }?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty

        // github.com/pulls and its tabs, each as GitHub fills it in.
        let tabs: [String: (q: String, title: String)] = [
            "": ("is:open is:pr author:@me archived:false", "Your open pull requests"),
            "assigned": ("is:open is:pr assignee:@me archived:false", "Assigned to you"),
            "mentioned": ("is:open is:pr mentions:@me archived:false", "Mentioning you"),
            "review-requested": ("is:open is:pr review-requested:@me archived:false", "Review requests"),
        ]
        if parts.first?.lowercased() == "pulls", parts.count <= 2,
           let tab = tabs[parts.count == 2 ? parts[1].lowercased() : ""] {
            return Query(q: pulls(given ?? tab.q), title: tab.title)
        }

        // A repository's Pull requests page: its query, in that repository.
        if parts.count == 3, parts[2].lowercased() == "pulls" {
            let repo = parts[0] + "/" + parts[1]
            var q = pulls(given ?? "is:pr is:open")
            if !q.lowercased().contains("repo:") { q += " repo:" + repo }
            return Query(q: q, title: parts[1] + " pull requests", repo: repo)
        }

        // A search on github.com for pull requests.
        if parts == ["search"], let given,
           items.first(where: { $0.name == "type" })?.value?.lowercased() == "pullrequests" {
            return Query(q: pulls(given), title: "Pull requests")
        }
        return nil
    }

    private static func words(_ q: String) -> [String] {
        q.lowercased().split(separator: " ").map(String.init)
    }

    /// GitHub's search wants pull requests or issues said outright.
    private static func pulls(_ q: String) -> String {
        let said = ["is:pr", "is:pull-request", "type:pr", "is:issue", "type:issue"]
        return words(q).contains(where: said.contains) ? q : q + " is:pr"
    }

    /// The two searches a folder makes: what is open (only that, unless the
    /// query asks for another state), and, when it is the open ones, the
    /// same merged since `since`. Most recently changed first, unless the
    /// query sorts itself.
    static func searches(_ query: Query, since: Date) -> (open: String, merged: String?) {
        let words = words(query.q)
        let sorted = words.contains { $0.hasPrefix("sort:") } ? "" : " sort:updated-desc"
        // A query that asks for closed or merged ones gets just those.
        let other = ["is:closed", "is:merged", "is:unmerged"]
        if !words.contains("is:open"), words.contains(where: { other.contains($0) || $0.hasPrefix("state:") }) {
            return (query.q + sorted, nil)
        }
        let open = words.contains("is:open") ? query.q : query.q + " is:open"
        let day = ISO8601DateFormatter().string(from: since)
        let merged = open.split(separator: " ").map { $0.lowercased() == "is:open" ? "is:merged" : String($0) }
            .joined(separator: " ") + " merged:>=" + day
        return (open + sorted, merged + sorted)
    }

    /// Where a pull request's review stands, as the folder marks it.
    enum State: String {
        case open, approved, changes, merged

        var label: String {
            switch self {
            case .open: "Open"
            case .approved: "Approved"
            case .changes: "Changes"
            case .merged: "Merged"
            }
        }

        /// In the tooltip and for VoiceOver, said whole.
        var said: String {
            switch self {
            case .open: "Open"
            case .approved: "Approved"
            case .changes: "Changes requested"
            case .merged: "Merged"
            }
        }

        var tint: Color {
            switch self {
            case .open: Palette.muted
            case .approved: Color(red: 0.16, green: 0.62, blue: 0.33)
            case .changes: Color(red: 0.86, green: 0.33, blue: 0.24)
            case .merged: Color(red: 0.55, green: 0.36, blue: 0.87)
            }
        }

        /// GitHub's review decision when the repository asks for one, else
        /// the latest review of each reviewer: a change asked for outweighs
        /// an approval.
        static func of(merged: Bool, decision: String?, reviews: [String]) -> State {
            if merged { return .merged }
            switch decision {
            case "APPROVED": return .approved
            case "CHANGES_REQUESTED": return .changes
            case "REVIEW_REQUIRED": return .open
            default:
                if reviews.contains("CHANGES_REQUESTED") { return .changes }
                if reviews.contains("APPROVED") { return .approved }
                return .open
            }
        }
    }

    static func isPullRequest(_ link: URL) -> Bool {
        let parts = link.path().split(separator: "/")
        return link.host()?.lowercased() == "github.com" && parts.count >= 4 && parts[2] == "pull"
    }

    private static let graphQL = """
    query($open: String!, $merged: String!, $both: Boolean!, $n: Int!) {
      open: search(query: $open, type: ISSUE, first: $n) { nodes { ...pull } }
      merged: search(query: $merged, type: ISSUE, first: $n) @include(if: $both) { nodes { ...pull } }
    }
    fragment pull on PullRequest {
      number title url mergedAt reviewDecision
      repository { name }
      comments { totalCount }
      reviewThreads { totalCount }
      latestReviews(first: 20) { nodes { state } }
    }
    """

    /// What GraphQL answered, as the folder's lines, the open ones first.
    /// A line is the pull request's title, all a column's width has room
    /// for; one whose title another line shares too (one fix sent to many
    /// repositories) names its repository first, `api · Title`. Where and
    /// which number are in its tooltip. Nil for an answer that doesn't
    /// read; GitHub's own complaint, when it sent one, in `complaint`.
    static func items(_ data: Data, repo: String?) -> (items: [FeedItem]?, complaint: String?) {
        struct Answer: Decodable {
            struct Found: Decodable { let nodes: [Node?] }
            struct Node: Decodable {
                struct Name: Decodable { let name: String }
                struct Count: Decodable { let totalCount: Int }
                struct Reviews: Decodable { struct Review: Decodable { let state: String }; let nodes: [Review?] }
                let number: Int?
                let title: String?
                let url: URL?
                let mergedAt: String?
                let reviewDecision: String?
                let repository: Name?
                let comments: Count?
                let reviewThreads: Count?
                let latestReviews: Reviews?
            }
            struct Both: Decodable { let open: Found; let merged: Found? }
            struct Complaint: Decodable { let message: String }
            let data: Both?
            let errors: [Complaint]?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return (nil, nil) }
        guard let both = answer.data else { return (nil, answer.errors?.first?.message) }
        var seen = Set<URL>()
        func lines(_ found: Answer.Found?) -> [FeedItem] {
            (found?.nodes ?? []).compactMap { node -> FeedItem? in
                // Issues the query also found are empty here: left out.
                guard let node, let number = node.number, let url = node.url, url.scheme == "https",
                      url.host()?.lowercased() == "github.com", seen.insert(url).inserted else { return nil }
                let title = Feed.clean(node.title ?? "", html: false)
                let state = State.of(merged: node.mergedAt != nil, decision: node.reviewDecision,
                                     reviews: (node.latestReviews?.nodes ?? []).compactMap { $0?.state })
                let comments = (node.comments?.totalCount ?? 0) + (node.reviewThreads?.totalCount ?? 0)
                names[url] = node.repository?.name
                return FeedItem(id: UUID(), title: title.isEmpty ? "#\(number)" : title,
                                link: url, state: state.rawValue, comments: comments)
            }
        }
        var names: [URL: String] = [:]
        var all = Array(lines(both.open).prefix(most)) + Array(lines(both.merged).prefix(most))
        let shared = Dictionary(grouping: all, by: \.title).filter { $0.value.count > 1 }.keys
        for index in all.indices where repo == nil && shared.contains(all[index].title) {
            if let name = names[all[index].link] { all[index].title = name + " · " + all[index].title }
        }
        for index in all.indices { all[index].title = String(all[index].title.prefix(300)) }
        return (all, nil)
    }

    // MARK: - fetching

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    static func load(_ url: URL, _ query: Query) async -> Result<Feed.Read, Feed.Problem> {
        guard let token = await token() else {
            return .failure(.gitHub("GitHub reads pull requests only for a signed-in account. Install gh (brew install gh) and run `gh auth login` in Terminal, then Refresh."))
        }
        let searches = searches(query, since: Date().addingTimeInterval(-mergedFor))
        let variables: [String: Any] = ["open": searches.open, "merged": searches.merged ?? "",
                                        "both": searches.merged != nil, "n": most]
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": graphQL, "variables": variables])
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { return .failure(.network) }
        guard data.count <= Feed.maxBytes else { return .failure(.tooBig) }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300:
            let read = items(data, repo: query.repo)
            if let items = read.items { return .success(Feed.Read(title: query.title, feed: url, items: items)) }
            return .failure(read.complaint.map { .gitHub("GitHub couldn’t read that search: \($0)") } ?? .notAFeed)
        case 401:
            return .failure(.gitHub("GitHub turned down the sign-in gh gave. Run `gh auth login` in Terminal, then Refresh."))
        case 403, 429:
            return .failure(.gitHub("GitHub asked Search to wait a little before asking again. Try Refresh in a minute."))
        default:
            return .failure(.network)
        }
    }

    /// The active account's token from gh, or nil without gh or a sign-in.
    /// A Mac app has no shell's PATH, so gh is looked for where Homebrew
    /// puts it.
    static func token() async -> String? {
        let places = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        guard let gh = places.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return await withCheckedContinuation { done in
            let process = Process()
            let out = Pipe()
            process.executableURL = URL(fileURLWithPath: gh)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { process in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fine = process.terminationStatus == 0 && !token.isEmpty && token.count < 256
                    && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
                done.resume(returning: fine ? token : nil)
            }
            do { try process.run() } catch { done.resume(returning: nil); return }
            // gh that hangs (a keychain asking) is given up on, not waited for.
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

extension FeedItem {
    /// A pull request's review, for one a GitHub folder holds.
    var pull: GitHubPulls.State? { state.flatMap(GitHubPulls.State.init(rawValue:)) }

    /// GitHub's mark for a pull request on one's line, merged or not; a
    /// page's on a post's.
    var symbol: String {
        if pull == .merged { return "arrow.triangle.merge" }
        return GitHubPulls.isPullRequest(link) ? "arrow.triangle.pull" : "doc.text"
    }

    /// Its review and comments, in a line: `Approved · 2 comments`.
    var pullSaid: String? {
        guard let pull else { return nil }
        let count = comments ?? 0
        return count == 0 ? pull.said : pull.said + " · \(count) comment" + (count == 1 ? "" : "s")
    }

    /// Where it is, as GitHub writes it: `acme/web#741`.
    var pullPlace: String? {
        let parts = link.path().split(separator: "/")
        guard pull != nil, parts.count >= 4 else { return nil }
        return "\(parts[0])/\(parts[1])#\(parts[3])"
    }
}

/// A pull request's marks at the end of its line: its comments, when it
/// has some, and where its review stands.
struct PullMarks: View {
    let state: GitHubPulls.State
    let comments: Int

    var body: some View {
        HStack(spacing: 5) {
            if comments > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 9))
                    Text("\(comments)")
                        .font(.system(size: 10).monospacedDigit())
                }
                .foregroundStyle(Palette.muted)
            }
            Text(state.label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(state.tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(state.tint.opacity(0.16)))
                .fixedSize()
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
