import XCTest
@testable import GHOrchestratorCore

final class RepositoryNotificationEventEvaluatorTests: XCTestCase {
    private let evaluator = RepositoryNotificationEventEvaluator()
    private let repository = ObservedRepository(owner: "openai", name: "codex")

    func testFirstBaselineEmitsNoEvents() {
        let current = [
            section(reviewStatus: .approved)
        ]

        let evaluation = evaluator.evaluate(
            previousBaseline: nil,
            currentSections: current,
            settings: settings()
        )

        XCTAssertTrue(evaluation.events.isEmpty)
        XCTAssertNotNil(evaluation.baseline.state(for: "openai/codex#1"))
    }

    func testNewlyObservedPullRequestEmitsCreatedEventAfterBaseline() {
        let baseline = RepositoryNotificationBaseline(sections: [
            section(number: 1)
        ])

        let evaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(number: 1),
                section(number: 2, title: "Add PR created notifications", authorLogin: "new-author")
            ],
            settings: settings(enabledTriggers: [.pullRequestCreated])
        )

        XCTAssertEqual(evaluation.events.map(\.trigger), [.pullRequestCreated])
        XCTAssertEqual(evaluation.events[0].pullRequestNumber, 2)
        XCTAssertEqual(evaluation.events[0].pullRequestTitle, "Add PR created notifications")
        XCTAssertEqual(evaluation.events[0].authorLogin, "new-author")
        XCTAssertEqual(evaluation.events[0].targetURL.absoluteString, "https://github.com/openai/codex/pull/2")
    }

    func testNewlyObservedPullRequestDoesNotEmitCreatedEventWhenTriggerDisabled() {
        let baseline = RepositoryNotificationBaseline(sections: [
            section(number: 1)
        ])

        let evaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(number: 1),
                section(number: 2)
            ],
            settings: settings(enabledTriggers: [.approval])
        )

        XCTAssertTrue(evaluation.events.isEmpty)
    }

    func testApprovalAndChangesRequestedTransitionsEmitOnce() {
        let baseline = RepositoryNotificationBaseline(sections: [
            section(reviewStatus: .reviewRequired)
        ])

        let approvedEvaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [section(reviewStatus: .approved)],
            settings: settings()
        )

        XCTAssertEqual(approvedEvaluation.events.map(\.trigger), [.approval])

        let unchangedApprovedEvaluation = evaluator.evaluate(
            previousBaseline: approvedEvaluation.baseline,
            currentSections: [section(reviewStatus: .approved)],
            settings: settings()
        )

        XCTAssertTrue(unchangedApprovedEvaluation.events.isEmpty)

        let changesRequestedEvaluation = evaluator.evaluate(
            previousBaseline: approvedEvaluation.baseline,
            currentSections: [section(reviewStatus: .changesRequested)],
            settings: settings()
        )

        XCTAssertEqual(changesRequestedEvaluation.events.map(\.trigger), [.changesRequested])
    }

    func testNewUnresolvedReviewCommentEmitsOnce() {
        let baseline = RepositoryNotificationBaseline(sections: [
            section(comments: [
                comment(id: 1)
            ])
        ])

        let firstEvaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(comments: [
                    comment(id: 1),
                    comment(id: 2, authorLogin: "reviewer")
                ])
            ],
            settings: settings()
        )

        XCTAssertEqual(firstEvaluation.events.map(\.trigger), [.newUnresolvedReviewComment])
        XCTAssertEqual(firstEvaluation.events[0].commentAuthorLogin, "reviewer")
        XCTAssertEqual(firstEvaluation.events[0].targetURL.absoluteString, "https://github.com/openai/codex/pull/1#discussion-2")

        let secondEvaluation = evaluator.evaluate(
            previousBaseline: firstEvaluation.baseline,
            currentSections: [
                section(comments: [
                    comment(id: 1),
                    comment(id: 2)
                ])
            ],
            settings: settings()
        )

        XCTAssertTrue(secondEvaluation.events.isEmpty)
    }

    func testNewlyObservedPullRequestsOnlyEmitCreatedEventForExistingMatchingStates() {
        let baseline = RepositoryNotificationBaseline(sections: [
            RepositorySection(repository: repository, pullRequests: [])
        ])

        let evaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(
                    reviewStatus: .approved,
                    comments: [
                        comment(id: 3)
                    ],
                    workflowRuns: [
                        workflowRun(
                            id: 30,
                            name: "CI",
                            status: "completed",
                            conclusion: "success",
                            jobs: [
                                workflowJob(id: 300, name: "Build", status: "completed", conclusion: "success")
                            ]
                        )
                    ]
                )
            ],
            settings: settings()
        )

        XCTAssertEqual(evaluation.events.map(\.trigger), [.pullRequestCreated])
    }

    func testCompletedWorkflowRunHonorsNameFilters() {
        let baseline = RepositoryNotificationBaseline(sections: [
            section(workflowRuns: [
                workflowRun(id: 10, name: "CI", status: "in_progress")
            ])
        ])

        let matchingEvaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(workflowRuns: [
                    workflowRun(id: 10, name: "CI", status: "completed", conclusion: "success")
                ])
            ],
            settings: settings(workflowNameFilters: ["ci"])
        )

        XCTAssertEqual(matchingEvaluation.events.map(\.trigger), [.workflowRunCompleted])
        XCTAssertEqual(matchingEvaluation.events[0].workflowName, "CI")
        XCTAssertEqual(matchingEvaluation.events[0].workflowConclusion, "success")

        let suppressedEvaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(workflowRuns: [
                    workflowRun(id: 10, name: "CI", status: "completed", conclusion: "success")
                ])
            ],
            settings: settings(workflowNameFilters: ["Release"])
        )

        XCTAssertTrue(suppressedEvaluation.events.isEmpty)
    }

    func testCompletedWorkflowJobHonorsJobNameFilters() {
        let baseline = RepositoryNotificationBaseline(sections: [
            section(workflowRuns: [
                workflowRun(
                    id: 10,
                    name: "CI",
                    status: "in_progress",
                    jobs: [
                        workflowJob(id: 101, name: "Build", status: "in_progress"),
                        workflowJob(id: 102, name: "Test", status: "in_progress")
                    ]
                )
            ])
        ])

        let evaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(workflowRuns: [
                    workflowRun(
                        id: 10,
                        name: "CI",
                        status: "in_progress",
                        jobs: [
                            workflowJob(id: 101, name: "Build", status: "completed", conclusion: "success"),
                            workflowJob(id: 102, name: "Test", status: "completed", conclusion: "failure")
                        ]
                    )
                ])
            ],
            settings: settings(
                enabledTriggers: [.workflowJobCompleted],
                workflowJobNameFiltersByWorkflowName: [
                    "CI": ["Test"]
                ]
            )
        )

        XCTAssertEqual(evaluation.events.map(\.workflowJobName), ["Test"])
        XCTAssertEqual(evaluation.events.map(\.workflowJobConclusion), ["failure"])
    }

    func testCompletedWorkflowJobHonorsNameFiltersAndEmitsOnce() {
        let baseline = RepositoryNotificationBaseline(sections: [
            section(workflowRuns: [
                workflowRun(
                    id: 10,
                    name: "CI",
                    status: "in_progress",
                    jobs: [
                        workflowJob(id: 101, name: "Build", status: "in_progress"),
                        workflowJob(id: 102, name: "Test", status: "queued")
                    ]
                )
            ])
        ])

        let matchingEvaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(workflowRuns: [
                    workflowRun(
                        id: 10,
                        name: "CI",
                        status: "in_progress",
                        jobs: [
                            workflowJob(id: 101, name: "Build", status: "completed", conclusion: "success"),
                            workflowJob(id: 102, name: "Test", status: "in_progress")
                        ]
                    )
                ])
            ],
            settings: settings(
                enabledTriggers: [.workflowJobCompleted],
                workflowNameFilters: ["ci"]
            )
        )

        XCTAssertEqual(matchingEvaluation.events.map(\.trigger), [.workflowJobCompleted])
        XCTAssertEqual(matchingEvaluation.events[0].workflowName, "CI")
        XCTAssertEqual(matchingEvaluation.events[0].workflowJobID, 101)
        XCTAssertEqual(matchingEvaluation.events[0].workflowJobName, "Build")
        XCTAssertEqual(matchingEvaluation.events[0].workflowJobConclusion, "success")
        XCTAssertEqual(
            matchingEvaluation.events[0].targetURL.absoluteString,
            "https://github.com/openai/codex/actions/runs/10/job/101"
        )

        let unchangedEvaluation = evaluator.evaluate(
            previousBaseline: matchingEvaluation.baseline,
            currentSections: [
                section(workflowRuns: [
                    workflowRun(
                        id: 10,
                        name: "CI",
                        status: "in_progress",
                        jobs: [
                            workflowJob(id: 101, name: "Build", status: "completed", conclusion: "success")
                        ]
                    )
                ])
            ],
            settings: settings(enabledTriggers: [.workflowJobCompleted])
        )

        XCTAssertTrue(unchangedEvaluation.events.isEmpty)

        let suppressedEvaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [
                section(workflowRuns: [
                    workflowRun(
                        id: 10,
                        name: "CI",
                        status: "in_progress",
                        jobs: [
                            workflowJob(id: 101, name: "Build", status: "completed", conclusion: "success")
                        ]
                    )
                ])
            ],
            settings: settings(
                enabledTriggers: [.workflowJobCompleted],
                workflowNameFilters: ["Release"]
            )
        )

        XCTAssertTrue(suppressedEvaluation.events.isEmpty)
    }

    func testDisabledRepositoryAndDisabledTriggerSuppressEvents() {
        let baseline = RepositoryNotificationBaseline(sections: [
            section(reviewStatus: .reviewRequired)
        ])

        let disabledRepositoryEvaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [section(reviewStatus: .approved)],
            settings: settings(enabled: false)
        )

        XCTAssertTrue(disabledRepositoryEvaluation.events.isEmpty)

        let disabledTriggerEvaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: [section(reviewStatus: .approved)],
            settings: settings(enabledTriggers: [.changesRequested])
        )

        XCTAssertTrue(disabledTriggerEvaluation.events.isEmpty)
    }

    private func settings(
        enabled: Bool = true,
        enabledTriggers: Set<RepositoryNotificationTrigger> = RepositoryNotificationSettings.defaultEnabledTriggers,
        workflowNameFilters: [String] = [],
        workflowJobNameFiltersByWorkflowName: [String: [String]] = [:]
    ) -> AppSettings {
        AppSettings(
            observedRepositories: [repository],
            repositoryNotificationSettings: [
                RepositoryNotificationSettings(
                    repository: repository,
                    enabled: enabled,
                    enabledTriggers: enabledTriggers,
                    workflowNameFilters: workflowNameFilters,
                    workflowJobNameFiltersByWorkflowName: workflowJobNameFiltersByWorkflowName
                )
            ]
        )
    }

    private func section(
        number: Int = 1,
        title: String = "Add notifications",
        authorLogin: String = "octocat",
        reviewStatus: ReviewStatus = .none,
        comments: [UnresolvedReviewCommentItem] = [],
        workflowRuns: [WorkflowRunItem] = []
    ) -> RepositorySection {
        RepositorySection(
            repository: repository,
            pullRequests: [
                PullRequestItem(
                    repository: repository,
                    number: number,
                    title: title,
                    url: URL(string: "https://github.com/openai/codex/pull/\(number)")!,
                    authorLogin: authorLogin,
                    isDraft: false,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    reviewStatus: reviewStatus,
                    unresolvedReviewThreadCount: comments.count,
                    unresolvedReviewComments: comments,
                    checkRollupState: workflowRuns.isEmpty ? .none : .passing,
                    workflowRuns: workflowRuns
                )
            ]
        )
    }

    private func comment(
        id: Int,
        authorLogin: String = "reviewer"
    ) -> UnresolvedReviewCommentItem {
        UnresolvedReviewCommentItem(
            url: URL(string: "https://github.com/openai/codex/pull/1#discussion-\(id)")!,
            authorLogin: authorLogin,
            bodyText: "Please update this.",
            filePath: "Sources/File.swift"
        )
    }

    private func workflowRun(
        id: Int,
        name: String,
        status: String,
        conclusion: String? = nil,
        jobs: [ActionJobItem] = []
    ) -> WorkflowRunItem {
        WorkflowRunItem(
            id: id,
            name: name,
            status: status,
            conclusion: conclusion,
            detailsURL: URL(string: "https://github.com/openai/codex/actions/runs/\(id)")!,
            jobs: jobs
        )
    }

    private func workflowJob(
        id: Int,
        name: String,
        status: String,
        conclusion: String? = nil
    ) -> ActionJobItem {
        ActionJobItem(
            id: id,
            name: name,
            status: status,
            conclusion: conclusion,
            detailsURL: URL(string: "https://github.com/openai/codex/actions/runs/10/job/\(id)")!
        )
    }
}
