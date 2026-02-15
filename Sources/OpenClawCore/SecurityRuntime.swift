import Foundation

public struct PairingRecord: Sendable, Equatable {
    public let deviceID: String
    public let role: String
    public let token: String
    public let approvedAtMs: Int

    public init(deviceID: String, role: String, token: String, approvedAtMs: Int) {
        self.deviceID = deviceID
        self.role = role
        self.token = token
        self.approvedAtMs = approvedAtMs
    }
}

public actor SecurityRuntime {
    private var pairedDevices: [String: PairingRecord] = [:]
    private var execApprovals: [String: Bool] = [:]

    public init() {}

    public func approveDevice(deviceID: String, role: String, token: String) {
        self.pairedDevices[deviceID] = PairingRecord(
            deviceID: deviceID,
            role: role,
            token: token,
            approvedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
    }

    public func pairedDevice(_ deviceID: String) -> PairingRecord? {
        self.pairedDevices[deviceID]
    }

    public func listPairedDevices() -> [PairingRecord] {
        self.pairedDevices.values.sorted { $0.deviceID < $1.deviceID }
    }

    public func setExecApproval(command: String, approved: Bool) {
        self.execApprovals[command] = approved
    }

    public func isExecApproved(command: String) -> Bool {
        self.execApprovals[command] == true
    }
}

