//
//  ReviewViewUI.swift
//  Critic
//
//  Received / Posted feed with joined user name + profile_url avatar
//

import SwiftUI

// MARK: - Date helpers
private let iso8601Z: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let iso8601Basic: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func parseDate(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    if let d = iso8601Z.date(from: s) ?? iso8601Basic.date(from: s) { return d }
    let df = DateFormatter()
    df.locale = .init(identifier: "en_US_POSIX")
    df.timeZone = .init(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df.date(from: s)
}

private func relative(_ date: Date) -> String {
    let r = RelativeDateTimeFormatter()
    r.unitsStyle = .short
    return r.localizedString(for: date, relativeTo: Date())
}

// MARK: - Small UI helpers

struct FlatTabBar2: View {
    @Binding var selectedTab: Int
    let tabs: [String]

    private func iconName(for idx: Int) -> String {
        idx == 0 ? "tray.and.arrow.down.fill" : "paperplane.fill"
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(tabs.indices, id: \.self) { idx in
                let isSelected = selectedTab == idx

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = idx
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: idx))
                            .font(.system(size: 14, weight: .semibold))
                        Text(tabs[idx])
                            .font(isSelected ? .critic(.button) : .critic(.bodyStrong))
                    }
                    .foregroundColor(isSelected ? .white : CriticPalette.onSurfaceMuted)
                    .padding(.horizontal, 22)
                    .frame(height: 42)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                isSelected
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [
                                                CriticPalette.primary,
                                                CriticPalette.primaryDark
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    : AnyShapeStyle(CriticPalette.surface)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(
                                        isSelected ? CriticPalette.primary.opacity(0.16) : CriticPalette.outline,
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(CriticPalette.background)
    }
}

// MARK: - Row context
private enum RowContext: Equatable {
    case received
    case posted(isFutureScheduled: Bool, scheduledText: String?, secondaryText: String?)
}

private struct ScheduleDisplay {
    let isFuture: Bool
    let scheduledText: String
    let secondaryText: String?
}

private func absoluteTimestampString(for date: Date) -> String {
    DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
}

private func scheduleDisplay(for item: PostItem) -> ScheduleDisplay? {
    guard item.isscheduled == true, let scheduledDate = parseDate(item.ScheduledTime) else { return nil }

    let isFuture = scheduledDate > Date()
    let scheduledText = "Scheduled: \(absoluteTimestampString(for: scheduledDate))"

    let secondaryText: String?
    if let createdDate = parseDate(item.createdAt) {
        if isFuture {
            secondaryText = "Queued: \(absoluteTimestampString(for: createdDate))"
        } else if createdDate.timeIntervalSince(scheduledDate) >= -60 {
            secondaryText = "Delivered: \(absoluteTimestampString(for: createdDate))"
        } else {
            secondaryText = nil
        }
    } else {
        secondaryText = nil
    }

    return .init(isFuture: isFuture, scheduledText: scheduledText, secondaryText: secondaryText)
}

private struct FeedParty {
    let userId: String?
    let name: String?
    let profileUrl: String?
}

private func normalizedUserId(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty else { return nil }
    return trimmed.lowercased()
}

private func normalizedIdentityToken(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty else { return nil }
    return trimmed.lowercased()
}

private func emailLocalPart(_ value: String?) -> String? {
    guard let token = normalizedIdentityToken(value) else { return nil }
    return token.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
}

private func currentUserAliases() -> Set<String> {
    var aliases = Set<String>()

    let rawValues = [
        UserDefaults.standard.string(forKey: "userId"),
        UserDefaults.standard.string(forKey: "userName"),
        UserDefaults.standard.string(forKey: "userEmail")
    ]

    rawValues.compactMap(normalizedIdentityToken).forEach { value in
        aliases.insert(value)
        if let local = emailLocalPart(value) {
            aliases.insert(local)
        }
    }

    return aliases
}

private func partyMatchesCurrentUser(_ party: FeedParty) -> Bool {
    let aliases = currentUserAliases()
    guard !aliases.isEmpty else { return false }

    let candidates = [
        normalizedIdentityToken(party.userId),
        normalizedIdentityToken(party.name),
        emailLocalPart(party.userId),
        emailLocalPart(party.name)
    ].compactMap { $0 }

    return candidates.contains(where: { aliases.contains($0) })
}

private func makeParty(user: UserLite?, fallbackId: String?) -> FeedParty {
    FeedParty(
        userId: user?.userId ?? fallbackId,
        name: user?.name,
        profileUrl: user?.profileUrl
    )
}

private func preferredParty(for item: PostItem, context: RowContext) -> FeedParty {
    let sender = makeParty(user: item.sender, fallbackId: item.senderId)
    let receiver = makeParty(user: item.receiver, fallbackId: item.receiverId)
    let senderMatchesSelf = partyMatchesCurrentUser(sender)
    let receiverMatchesSelf = partyMatchesCurrentUser(receiver)

    if senderMatchesSelf && !receiverMatchesSelf {
        return receiver
    }
    if receiverMatchesSelf && !senderMatchesSelf {
        return sender
    }

    switch context {
    case .received:
        return sender
    case .posted:
        return receiver
    }
}

// MARK: - Helpers to extract name & avatar (NO ViewBuilder)
private func displayName(for item: PostItem, context: RowContext) -> String {
    if case .received = context {
        return "Anonymous"
    }
    let party = preferredParty(for: item, context: context)
    if let n = party.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
        return n
    }
    let resolved = DisplayNameResolver.resolve(displayName: nil, userId: party.userId)
    return resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User" : resolved
}

private func avatarURL(for item: PostItem, context: RowContext) -> String? {
    preferredParty(for: item, context: context).profileUrl
}

private func avatarSeed(for item: PostItem, context: RowContext) -> String? {
    let party = preferredParty(for: item, context: context)
    return party.userId ?? party.name
}

private func counterpartUserId(for item: PostItem, context: RowContext) -> String? {
    preferredParty(for: item, context: context).userId
}

// MARK: - Post Row
private struct PostCardRow: View {
    let title: String
    let message: String
    let created: String?
    let avatarURLString: String?
    let avatarSeed: String?
    let context: RowContext

    let onAvatarTapped: () -> Void
    let onAbortTapped: () -> Void
    let onDeleteTapped: () -> Void
    let onReportTapped: () -> Void
    let onBlockTapped: () -> Void

    private var showsAvatar: Bool {
        if case .received = context {
            return false
        }
        return true
    }

    // ✅ avatar uses profile_url string
    @ViewBuilder
    private func avatarView(urlString: String?, seed: String?) -> some View {
        AvatarView(
            urlString: urlString,
            seed: seed,
            fallbackSystemName: "person.circle.fill",
            size: 36,
            tintColor: .accentColor
        )
        .onTapGesture { onAvatarTapped() }
    }

    @ViewBuilder
    private func overflowMenu() -> some View {
        Menu {
            switch context {
            case .posted(let isFuture, _, _):
                if isFuture {
                    Button { onAbortTapped() } label: {
                        Label("Abort (cancel schedule)", systemImage: "xmark.circle")
                    }
                }
                Button(role: .destructive) { onDeleteTapped() } label: {
                    Label("Delete", systemImage: "trash")
                }
            case .received:
                Button { onReportTapped() } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }
                Button(role: .destructive) { onBlockTapped() } label: {
                    Label("Block user", systemImage: "hand.raised.fill")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CriticPalette.onSurfaceMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if showsAvatar {
                    avatarView(urlString: avatarURLString, seed: avatarSeed)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.critic(.listTitle))
                        .foregroundColor(CriticPalette.onSurface)

                    Text(message)
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurface)
                        .fixedSize(horizontal: false, vertical: true)

                    switch context {
                    case .posted(let isFutureScheduled, let scheduledText, let secondaryText):
                        if let scheduledText {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "clock.fill").font(.caption2)
                                Text(scheduledText)
                                    .font(.critic(.caption))
                            }
                            .foregroundColor(isFutureScheduled ? .orange : CriticPalette.onSurfaceMuted)

                            if let secondaryText {
                                Text(secondaryText)
                                    .font(.critic(.caption))
                                    .foregroundColor(CriticPalette.onSurfaceMuted)
                            }
                        } else if let created {
                            Text(created)
                                .font(.critic(.caption))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                        }
                    case .received:
                        if let created {
                            Text(created)
                                .font(.critic(.caption))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                        }
                    }
                }

                Spacer(minLength: 4)

                overflowMenu()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CriticPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CriticPalette.outline, lineWidth: 1)
                )
        )
    }
}

// MARK: - External Profile View
private struct ExternalProfileView: View {
    let userId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                CriticDetailHeader(title: "Profile") {
                    dismiss()
                }

                VStack(spacing: 14) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 108, height: 108)
                        .foregroundColor(CriticPalette.primary)
                        .background(Circle().fill(CriticPalette.surfaceVariant))
                        .clipShape(Circle())

                    Text(userId.isEmpty ? "User" : userId)
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(24)
                .criticCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
    }
}

// MARK: - Main View
struct ReviewFeedView: View {
    let showNavigationTitle: Bool
    let showsTabBar: Bool
    private let tabSelection: Binding<Int>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = ReviewFeedViewModel()
    @State private var selectedTab: Int // 0=Received, 1=Posted
    @State private var isVisible = false

    private let refreshTicker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    // Delete / Abort
    @State private var showDelete = false
    @State private var showAbort = false
    @State private var pendingItem: PostItem?

    // Report sheet
    @State private var showReportSheet = false
    @State private var pendingReportItem: PostItem?
    @State private var reasons: [(id: String, text: String)] = []
    @State private var reasonsLoading = false
    @State private var selectedReasonId: String?
    @State private var otherText: String = ""
    @State private var sendInProgress = false
    @State private var reportError: String?

    // External profile navigation (local)
    @State private var pushExternalProfile = false
    @State private var externalUserId: String = ""

    // Block user alert state
    @State private var showBlock = false
    @State private var pendingBlockUserId: String?

    private var activeTab: Binding<Int> {
        tabSelection ?? $selectedTab
    }

    private var activeTabValue: Int {
        activeTab.wrappedValue
    }

    private var embeddedTopSpacing: CGFloat {
        0
    }

    private var currentList: [PostItem] {
        activeTabValue == 0 ? vm.receivedPosts : vm.myPosts
    }

    private var emptyCountLabel: String {
        activeTabValue == 0 ? "0 critics received" : "0 critics posted"
    }

    init(initialTab: Int = 0, tabSelection: Binding<Int>? = nil, showNavigationTitle: Bool = true, showsTabBar: Bool = true) {
        self.showNavigationTitle = showNavigationTitle
        self.showsTabBar = showsTabBar
        self.tabSelection = tabSelection
        _selectedTab = State(initialValue: tabSelection?.wrappedValue ?? initialTab)
    }

    private func refreshFeed(showSpinner: Bool? = nil) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        Task {
            await vm.load(showSpinner: showSpinner ?? !vm.hasLoadedOnce)
        }
    }

    private func markVisibleReceivedPostsAsRead() {
        guard isVisible, activeTabValue == 0 else { return }
        let userId = UserDefaults.standard.string(forKey: "userId")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !userId.isEmpty else { return }
        let postIds = vm.receivedPosts.map(\.postId)
        guard !postIds.isEmpty else { return }
        ReceivedPostsReadStore.markSeen(postIds: postIds, for: userId)
    }

    private func syncReceivedVisibilityState() {
        ReceivedPostsVisibilityState.isViewingReceivedTab = isVisible && activeTabValue == 0
    }

    // MARK: - small row builder
    @ViewBuilder
    private func rowView(for item: PostItem, in context: RowContext) -> some View {
        let name = displayName(for: item, context: context)
        let avatar = avatarURL(for: item, context: context)
        let seed = avatarSeed(for: item, context: context)

        let createdString: String? = {
            if let s = item.createdAt, let d = parseDate(s) {
                return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .short)
            }
            return nil
        }()

        let schedule = scheduleDisplay(for: item)

        PostCardRow(
            title: (context == .received ? "From: \(name)" : "To: \(name)"),
            message: item.postcontent,
            created: createdString,
            avatarURLString: avatar,             // <— pass profile_url here
            avatarSeed: seed,
            context: {
                switch context {
                case .received:
                    return .received
                case .posted:
                    return .posted(
                        isFutureScheduled: schedule?.isFuture ?? false,
                        scheduledText: schedule?.scheduledText,
                        secondaryText: schedule?.secondaryText
                    )
                }
            }(),
            onAvatarTapped: {
                let tappedId = counterpartUserId(for: item, context: context) ?? ""
                if !tappedId.isEmpty {
                    externalUserId = tappedId
                    pushExternalProfile = true
                }
            },
            onAbortTapped: {
                pendingItem = item
                showAbort = true
            },
            onDeleteTapped: {
                pendingItem = item
                showDelete = true
            },
            onReportTapped: {
                pendingReportItem = item
                Task { await openReportSheet(for: item) }
            },
            onBlockTapped: {
                if let counterpartId = counterpartUserId(for: item, context: context) {
                    pendingBlockUserId = counterpartId
                    showBlock = true
                }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if showNavigationTitle {
                    CriticDetailHeader(title: activeTabValue == 0 ? "Received" : "Posted") {
                        dismiss()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }

                if showsTabBar {
                    FlatTabBar2(selectedTab: activeTab, tabs: ["Received", "Posted"])
                }

                Group {
                    if vm.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading…")
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(CriticPalette.background)

                    } else if let err = vm.errorText {
                        VStack(spacing: 10) {
                            Text("Couldn’t load messages")
                                .font(.critic(.pageTitle))
                                .foregroundColor(CriticPalette.onSurface)
                            Text(err)
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                                .multilineTextAlignment(.center)
                            Button("Retry") { Task { await vm.load() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(CriticPalette.background)

                    } else {
                        let list: [PostItem] = currentList
                        if list.isEmpty {
                            VStack(spacing: 10) {
                                Text(emptyCountLabel)
                                    .font(.critic(.pageTitle))
                                    .foregroundColor(CriticPalette.onSurface)
                                Text("New reviews will appear here.")
                                    .font(.critic(.body))
                                    .foregroundColor(CriticPalette.onSurfaceMuted)
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(CriticPalette.background)
                        } else {
                            ScrollView {
                                VStack(spacing: 14) {
                                    ForEach(list) { item in
                                        if activeTabValue == 0 {
                                            rowView(for: item, in: .received)
                                        } else {
                                            let schedule = scheduleDisplay(for: item)
                                            rowView(
                                                for: item,
                                                in: .posted(
                                                    isFutureScheduled: schedule?.isFuture ?? false,
                                                    scheduledText: schedule?.scheduledText,
                                                    secondaryText: schedule?.secondaryText
                                                )
                                            )
                                        }
                                    }
                                    Spacer(minLength: 8)
                                }
                                .frame(maxWidth: .infinity, alignment: .top)
                                .padding(.top, 12)
                                .padding(.horizontal, 16)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(CriticPalette.background)
                        }
                    }
                }
                .padding(.top, embeddedTopSpacing)
            }
            .navigationBarBackButtonHidden(true)
            .navigationBarHidden(true)
            .onAppear {
                isVisible = true
                if UserDefaults.standard.string(forKey: "inboxStartTab") == "posted" {
                    activeTab.wrappedValue = 1
                    UserDefaults.standard.removeObject(forKey: "inboxStartTab")
                }
                syncReceivedVisibilityState()
                refreshFeed()
                markVisibleReceivedPostsAsRead()
            }
            .onDisappear {
                isVisible = false
                syncReceivedVisibilityState()
            }
            .onChange(of: activeTabValue) { newValue in
                syncReceivedVisibilityState()
                if newValue == 1, let first = vm.myPosts.first {
                    withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                } else if newValue == 0 {
                    markVisibleReceivedPostsAsRead()
                }
            }
            .onChange(of: vm.receivedPosts) { _ in
                markVisibleReceivedPostsAsRead()
            }
            .onChange(of: scenePhase) { phase in
                guard isVisible, phase == .active else { return }
                markVisibleReceivedPostsAsRead()
                refreshFeed(showSpinner: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .jumpToPosted)) { _ in
                activeTab.wrappedValue = 1
                refreshFeed(showSpinner: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviewFeedNeedsRefresh)) { _ in
                refreshFeed(showSpinner: false)
            }
            .onReceive(refreshTicker) { _ in
                guard isVisible, scenePhase == .active else { return }
                refreshFeed(showSpinner: false)
            }
            .background(
                NavigationLink(
                    destination: ExternalProfileView(userId: externalUserId),
                    isActive: $pushExternalProfile
                ) { EmptyView() }
                .opacity(0)
            )
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)

        // Alerts
        .alert("Delete this post?", isPresented: $showDelete, presenting: pendingItem) { item in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { _ = await vm.delete(postId: item.postId) }
            }
        } message: { _ in
            Text("This action can’t be undone.")
        }

        .alert("Abort this scheduled post?", isPresented: $showAbort, presenting: pendingItem) { item in
            Button("Cancel", role: .cancel) {}
            Button("Abort", role: .destructive) {
                Task { _ = await vm.abort(postId: item.postId) }
            }
        } message: { item in
            let when = parseDate(item.ScheduledTime).map { relative($0) } ?? "future"
            Text("It’s scheduled for \(when). Aborting will cancel the schedule.")
        }

        .alert("Block this user?", isPresented: $showBlock) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                let target = pendingBlockUserId
                pendingBlockUserId = nil
                if let uid = target {
                    Task { _ = await vm.blockUser(targetUserId: uid, reason: "user-initiated") }
                }
            }
        } message: {
            Text("They will no longer be able to interact with you. You can unblock them later.")
        }

        .sheet(isPresented: $showReportSheet, onDismiss: resetReportSheet) {
            ReportSheetView(
                reasons: reasons,
                reasonsLoading: reasonsLoading,
                reportError: reportError,
                pendingItem: pendingReportItem,
                selectedReasonId: $selectedReasonId,
                otherText: $otherText,
                sendInProgress: $sendInProgress,
                onSelectReason: { id, text in Task { await handleReasonTap(reasonId: id, reasonText: text) } },
                onSendOther: { Task { await sendOtherReason() } },
                onDismiss: { showReportSheet = false }
            )
        }
    }

    // MARK: - Report Sheet View (nested)
    struct ReportSheetView: View {
        let reasons: [(id: String, text: String)]
        let reasonsLoading: Bool
        let reportError: String?
        let pendingItem: PostItem?

        @Binding var selectedReasonId: String?
        @Binding var otherText: String
        @Binding var sendInProgress: Bool

        let onSelectReason: (_ reasonId: String, _ reasonText: String) -> Void
        let onSendOther: () -> Void
        let onDismiss: () -> Void

        var body: some View {
            NavigationView {
                VStack(spacing: 12) {
                    CriticDetailHeader(title: "Report") {
                        onDismiss()
                    }

                    if reasonsLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading reasons…")
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    } else if let err = reportError {
                        VStack(spacing: 12) {
                            Text("Report Status")
                                .font(.critic(.pageTitle))
                                .foregroundColor(CriticPalette.onSurface)
                            Text(err)
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.onSurface)
                                .multilineTextAlignment(.center)
                                .padding()
                            Button("Close") { onDismiss() }
                                .buttonStyle(.bordered)
                        }
                        .padding()

                    } else {
                        VStack(spacing: 8) {
                            Text("Report Post")
                                .font(.critic(.pageTitle))
                                .foregroundColor(CriticPalette.onSurface)
                                .padding(.top, 8)

                            if let item = pendingItem {
                                Text(item.postcontent)
                                    .font(.critic(.body))
                                    .foregroundColor(CriticPalette.onSurface)
                                    .lineLimit(3)
                                    .padding(.horizontal)
                            }

                            Divider().padding(.vertical, 8)

                            ScrollView {
                                VStack(spacing: 10) {
                                    ForEach(reasons, id: \.id) { r in
                                        Button {
                                            onSelectReason(r.id, r.text)
                                        } label: {
                                            HStack {
                                                Text(r.text.capitalized)
                                                    .font(.critic(.bodyStrong))
                                                    .foregroundColor(CriticPalette.onSurface)
                                                Spacer()
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(CriticPalette.surfaceVariant)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if selectedReasonId == "other" {
                                VStack(spacing: 8) {
                                    if #available(iOS 16.0, *) {
                                        TextField("Explain the issue…", text: $otherText, axis: .vertical)
                                            .lineLimit(3...6)
                                            .font(.critic(.body))
                                            .padding(10)
                                            .background(CriticPalette.surface)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                                    } else {
                                        TextField("Explain the issue…", text: $otherText)
                                            .font(.critic(.body))
                                            .padding(10)
                                            .background(CriticPalette.surface)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                                    }

                                    Button {
                                        onSendOther()
                                    } label: {
                                        if sendInProgress {
                                            ProgressView().frame(maxWidth: .infinity)
                                        } else {
                                            Text("Send").frame(maxWidth: .infinity)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendInProgress)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(16)
                .background(CriticPalette.background.ignoresSafeArea())
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(true)
            }
        }
    }

    // MARK: - Report helpers
    private func openReportSheet(for item: PostItem) async {
        pendingReportItem = item
        reasons = []
        reportError = nil
        selectedReasonId = nil
        otherText = ""
        reasonsLoading = true
        showReportSheet = true

        let (already, message) = await vm.checkAlreadyReported(postId: item.postId)
        reasonsLoading = false
        if already {
            reportError = message ?? "You’ve already reported this post. Your report is under review."
            reasons = []
            return
        }

        let fetched = await vm.fetchReportReasons()
        if fetched.isEmpty {
            reasons = [("1","spam"),("2","harassment"),("3","other")]
        } else {
            var mapped = fetched.map { ($0.id, $0.text.lowercased()) }
            if !mapped.contains(where: { $0.1 == "other" }) {
                mapped.append(("other","other"))
            }
            reasons = mapped.map { (id: $0.0, text: $0.1) }
        }
    }

    private func resetReportSheet() {
        pendingReportItem = nil
        reasons = []
        selectedReasonId = nil
        otherText = ""
        sendInProgress = false
        reportError = nil
    }

    private func handleReasonTap(reasonId: String, reasonText: String) async {
        if reasonId.lowercased() == "other" || reasonText.lowercased() == "other" {
            selectedReasonId = "other"
            return
        }

        selectedReasonId = reasonId
        sendInProgress = true
        defer { sendInProgress = false }

        guard let item = pendingReportItem else {
            reportError = "No post selected"
            return
        }

        let ok = await vm.report(postId: item.postId, reason: reasonText)
        if ok {
            showReportSheet = false
            Task { await vm.load() }
        } else {
            reportError = "Failed to send report. Try again."
        }
    }

    private func sendOtherReason() async {
        guard let item = pendingReportItem else { return }
        let text = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { reportError = "Please explain the issue."; return }
        sendInProgress = true
        defer { sendInProgress = false }

        let ok = await vm.report(postId: item.postId, reason: "other - \(text)")
        if ok {
            showReportSheet = false
            Task { await vm.load() }
        } else {
            reportError = "Failed to send report. Try again."
        }
    }
}

// MARK: - Preview
struct ReviewFeedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { ReviewFeedView() }
    }
}
