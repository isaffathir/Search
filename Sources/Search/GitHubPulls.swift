import Foundation

// A live folder of GitHub pull requests, as Arc's GitHub live folder: what
// github.com/pulls (and its Assigned, Mentioned and Review requests tabs),
// a repository's Pull requests page, or a search for pull requests lists.
// GitHub has no feed for these, so New Live Folder… on such an address asks
// GitHub's search API with the page's own query instead, and the folder
// holds what is open now: a pull request merged or closed leaves it.
//
// Signed in as the account GitHub's own command line tool, gh, has active,
// when it is installed and signed in: the token is asked of `gh auth token`
// at each fetch, sent to api.github.com only, and kept nowhere. Without gh
// only public repositories read, and a query with @me reads nothing.
//
// Fetched every five minutes, open work changing faster than a blog.

enum GitHubPulls {
    /// A list of open work wants all of it, not a blog's latest twelve.
    static let most = 50
    static let every: TimeInterval = 5 * 60

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
            "": ("is:open is:pr author:@me archived:false", "Your pull requests"),
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

    /// GitHub's search API wants pull requests or issues said outright.
    private static func pulls(_ q: String) -> String {
        let words = q.lowercased().split(separator: " ")
        let said = ["is:pr", "is:pull-request", "type:pr", "is:issue", "type:issue"]
        return words.contains(where: { said.contains(String($0)) }) ? q : q + " is:pr"
    }

    static func isPullRequest(_ link: URL) -> Bool {
        let parts = link.path().split(separator: "/")
        return link.host()?.lowercased() == "github.com" && parts.count >= 4 && parts[2] == "pull"
    }

    /// The API's address for a query: the most recently changed first,
    /// unless the query sorts itself.
    static func api(_ query: Query) -> URL? {
        var parts = URLComponents(string: "https://api.github.com/search/issues")
        var items = [URLQueryItem(name: "q", value: query.q), URLQueryItem(name: "per_page", value: String(most))]
        if !query.q.lowercased().contains("sort:") {
            items += [URLQueryItem(name: "sort", value: "updated"), URLQueryItem(name: "order", value: "desc")]
        }
        parts?.queryItems = items
        // A + in the query is a plus, not a space.
        let encoded = parts?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        parts?.percentEncodedQuery = encoded
        return parts?.url
    }

    /// What the search answered, as the folder's lines: a repository's own
    /// list says `#12 · Title`; any other names the repository first, since
    /// the same title often stands in many (`api#12 · Title`).
    static func items(_ data: Data, repo: String?) -> [FeedItem]? {
        struct Answer: Decodable {
            struct Item: Decodable {
                let number: Int
                let title: String
                let html_url: URL
                let repository_url: URL?
            }
            let items: [Item]
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        var seen = Set<URL>()
        return answer.items.compactMap { item -> FeedItem? in
            guard item.html_url.scheme == "https", item.html_url.host()?.lowercased() == "github.com",
                  seen.insert(item.html_url).inserted else { return nil }
            let title = Feed.clean(item.title, html: false)
            let name = repo == nil ? item.repository_url?.lastPathComponent ?? "" : ""
            return FeedItem(id: UUID(), title: String((name + "#\(item.number) · " + title).prefix(300)),
                            link: item.html_url)
        }
        .prefix(most).map { $0 }
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
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        return URLSession(configuration: config)
    }()

    static func load(_ url: URL, _ query: Query) async -> Result<Feed.Read, Feed.Problem> {
        guard let api = api(query) else { return .failure(.notAFeed) }
        let token = await token()
        var request = URLRequest(url: api)
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { return .failure(.network) }
        guard data.count <= Feed.maxBytes else { return .failure(.tooBig) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            guard let items = items(data, repo: query.repo) else { return .failure(.notAFeed) }
            return .success(Feed.Read(title: query.title, feed: url, items: items))
        case 401:
            return .failure(.gitHub("GitHub turned down the sign-in gh gave. Run `gh auth login` in Terminal, then Refresh."))
        case 403, 429:
            return .failure(.gitHub("GitHub asked Search to wait a little before asking again. Try Refresh in a minute."))
        case 422:
            return .failure(.gitHub(token == nil
                ? "GitHub needs a sign-in to read @me or private repositories. Install gh (brew install gh) and run `gh auth login`."
                : "GitHub couldn’t read that search. Check the q= part of the address on github.com first."))
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
    /// GitHub's mark for a pull request on one's line; a page's on a post's.
    var symbol: String { GitHubPulls.isPullRequest(link) ? "arrow.triangle.pull" : "doc.text" }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
