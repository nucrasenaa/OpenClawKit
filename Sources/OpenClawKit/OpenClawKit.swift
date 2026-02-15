@_exported import OpenClawAgents
@_exported import OpenClawChannels
@_exported import OpenClawCore
@_exported import OpenClawGateway
@_exported import OpenClawMedia
@_exported import OpenClawMemory
@_exported import OpenClawPlugins
@_exported import OpenClawProtocol

public struct OpenClawSDK: Sendable {
    public static let shared = OpenClawSDK()

    public let buildInfo: OpenClawBuildInfo

    public init(buildInfo: OpenClawBuildInfo = OpenClawBuildInfo(protocolVersion: GATEWAY_PROTOCOL_VERSION)) {
        self.buildInfo = buildInfo
    }
}
