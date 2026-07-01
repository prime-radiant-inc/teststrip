public protocol WorkSessionRepository: Sendable {
    func save(_ session: WorkSession) throws
    func session(id: WorkSessionID) throws -> WorkSession
}
