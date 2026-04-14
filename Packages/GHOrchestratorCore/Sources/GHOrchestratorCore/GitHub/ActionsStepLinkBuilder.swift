import Foundation

public enum ActionsStepLinkBuilder {
    public static func stepURL(jobURL: URL?, stepNumber: Int) -> URL? {
        guard let jobURL else {
            return nil
        }

        guard stepNumber > 0 else {
            return jobURL
        }

        return URL(string: "\(jobURL.absoluteString)#step:\(stepNumber):1")
    }
}
