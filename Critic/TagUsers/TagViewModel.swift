import Foundation
import SwiftUI

@MainActor
public final class TagViewModel: ObservableObject {
    @Published public private(set) var tagged: [TaggedUser] = []
    private let service = TagService()

    public init() {}

    public func refresh(for userId: String) async {
        do {
            print("[TagVM] refresh request userId=\(userId)")
            let list = try await service.list(userId: userId)
            tagged = list
            print("[TagVM] refresh response count=\(tagged.count)")
        } catch {
            print("[TagVM][ERROR] refresh failed: \(error.localizedDescription)")
        }
    }

    public func isTagged(_ targetId: String) -> Bool {
        let v = tagged.contains { $0.taggedUserId == targetId }
        print("[TagVM] isTagged(\(targetId)) -> \(v)")
        return v
    }

    @discardableResult
    public func tag(userId: String, targetId: String) async -> Bool {
        do {
            print("[TagVM] tag request userId=\(userId) targetId=\(targetId)")
            let ok = try await service.act(.tag, userId: userId, taggedUserId: targetId)
            print("[TagVM] tag response ok=\(ok)")
            if ok { await refresh(for: userId) }
            return ok
        } catch {
            print("[TagVM][ERROR] tag failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    public func untag(userId: String, targetId: String) async -> Bool {
        do {
            print("[TagVM] untag request userId=\(userId) targetId=\(targetId)")
            let ok = try await service.act(.untag, userId: userId, taggedUserId: targetId)
            print("[TagVM] untag response ok=\(ok)")
            if ok { await refresh(for: userId) }
            return ok
        } catch {
            print("[TagVM][ERROR] untag failed: \(error.localizedDescription)")
            return false
        }
    }
}

