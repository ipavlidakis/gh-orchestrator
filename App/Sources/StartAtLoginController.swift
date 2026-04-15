import ServiceManagement

enum StartAtLoginRegistrationStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

protocol StartAtLoginControlling {
    @MainActor
    var registrationStatus: StartAtLoginRegistrationStatus { get }

    @MainActor
    func setStartAtLoginEnabled(_ isEnabled: Bool) throws

    @MainActor
    func openSystemSettingsLoginItems()
}

struct StartAtLoginController: StartAtLoginControlling {
    var registrationStatus: StartAtLoginRegistrationStatus {
        Self.registrationStatus(from: SMAppService.mainApp.status)
    }

    func setStartAtLoginEnabled(_ isEnabled: Bool) throws {
        let service = SMAppService.mainApp

        if isEnabled {
            switch service.status {
            case .enabled, .requiresApproval:
                return
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } else {
            switch service.status {
            case .notRegistered, .notFound:
                return
            case .enabled, .requiresApproval:
                try service.unregister()
            @unknown default:
                try service.unregister()
            }
        }
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func registrationStatus(from status: SMAppService.Status) -> StartAtLoginRegistrationStatus {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }
}
