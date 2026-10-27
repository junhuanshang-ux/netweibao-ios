import Combine
import Foundation

@MainActor
final class ReportViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: ReportProgress?
    @Published private(set) var results: [ReportTestResult] = []
    @Published private(set) var snapshot: ReportSnapshot?
    @Published private(set) var pdfURL: URL?
    @Published private(set) var pdfData: Data?
    @Published var errorMessage: String?
    @Published var showExporter = false

    private var task: Task<Void, Never>?

    var progressValue: Double {
        progress?.value ?? 0
    }

    var progressText: String {
        guard let progress else { return "准备检测" }
        return "\(progress.message)（\(progress.completed)/\(progress.total)）"
    }

    var pdfFilename: String {
        ReportPDFRenderer.filename(for: snapshot?.generatedAt ?? Date())
            .replacingOccurrences(of: ".pdf", with: "")
    }

    var exportDocument: ReportPDFDocument? {
        pdfData.map { ReportPDFDocument(data: $0) }
    }

    func start() {
        guard !isRunning else { return }

        isRunning = true
        errorMessage = nil
        results = []
        snapshot = nil
        pdfURL = nil
        pdfData = nil
        progress = ReportProgress(
            kind: .ping,
            completed: 0,
            total: ReportTestKind.allCases.count,
            message: "准备检测"
        )

        task = Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await ReportRunner.run { [weak self] update in
                    self?.progress = update
                }
                try Task.checkCancellation()

                self.snapshot = snapshot
                self.results = snapshot.results
                self.makePDF(snapshot)
            } catch is CancellationError {
                // User stopped the run.
            } catch {
                self.errorMessage = error.localizedDescription
            }

            self.isRunning = false
            self.progress = nil
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        progress = nil
    }

    func regeneratePDF() {
        guard let snapshot else { return }
        makePDF(snapshot)
    }

    private func makePDF(_ snapshot: ReportSnapshot) {
        do {
            let data = ReportPDFRenderer.render(snapshot)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(ReportPDFRenderer.filename(for: snapshot.generatedAt))
            try data.write(to: url, options: .atomic)
            self.pdfData = data
            self.pdfURL = url
        } catch {
            self.errorMessage = "PDF 生成失败：\(error.localizedDescription)"
        }
    }
}
