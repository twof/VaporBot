import Vapor

public func githubRoutes(router: GithubCommandRouter) throws {
    let permissionChecked = router.grouped(PermissionCheckMiddleware(target: .write))
    let tagged = permissionChecked.grouped("@vapor-bot")
    
    tagged.register(command: "test performance") { (req) -> Future<HTTPStatus> in
        return try req.content.decode(GithubWebhook.self).flatMap { webhook -> Future<(GithubComment, GithubRepository, GithubIssue, GithubShortFormPullRequest)> in
            guard let comment = webhook.comment, comment.user.login != "vapor-bot" else {
                return req.future(error: Abort(.ok))
            }
            let repo = webhook.repository
            let issue = webhook.issue
            
            let github = try req.make(GithubService.self)
            
            guard let pullRequest = webhook.issue.pullRequest else {
                return github.postComment(
                    repo: repo.fullName,
                    issue: issue.number,
                    body: "Unknown command",
                    on: req
                ).flatMap { _ in req.future(error: Abort(.ok)) }
            }
            
            return req.future((comment, repo, issue, pullRequest))
        }.flatMap { (comment, repo, issue, pullRequest) in
            let github = try req.make(GithubService.self)
            let circle = try req.make(CircleCIService.self)
            
            return try req.client().get(pullRequest.url).flatMap { response -> Future<String> in
                let pullRequestHead = try response.content.syncDecode(GithubPullRequest.self).head
                let branchName = pullRequestHead.name
                
                return circle.start(job: "linux-performance", repo: repo.fullName, branch: branchName, on: req)
            }.flatMap { _ -> Future<CreateCommentResponse> in
                return github.postComment(
                    repo: repo.fullName,
                    issue: issue.number,
                    body: "Starting performance test",
                    on: req
                )
            }.transform(to: .ok)
        }
    }
    
    tagged.register() { req -> Future<HTTPStatus> in
        return try req.content.decode(GithubWebhook.self).flatMap { webhook in
            guard let comment = webhook.comment, comment.user.login != "vapor-bot" else {
                return req.future(.ok)
            }
            
            let repo = webhook.repository
            let issue = webhook.issue
            
            let github = try req.make(GithubService.self)
            
            return github.postComment(
                repo: repo.fullName,
                issue: issue.number,
                body: "Sorry? Didn't catch that.",
                on: req
            ).transform(to: .ok)
        }
    }
}