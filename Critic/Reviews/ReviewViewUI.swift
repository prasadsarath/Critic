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

private struct FlatTabBar2: View {
    @Binding var selectedTab: Int
    let tabs: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tabs.indices, id: \.self) { idx in
                let isSelected = selectedTab == idx

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = idx
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            CriticPalette.primary,
                                            CriticPalette.primaryDark
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: CriticPalette.primary.opacity(0.18), radius: 10, x: 0, y: 5)
                        }

                        Text(tabs[idx])
                            .font(isSelected ? .critic(.button) : .critic(.bodyStrong))
                            .foregroundColor(isSelected ? .white : CriticPalette.onSurfaceMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                    }
                    .frame(height: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CriticPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CriticPalette.outline, lineWidth: 1)
                )
                .shadow(color: Color(hex: 0x151A2D, alpha: 0.04), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(CriticPalette.background)
    }
}

// MARK: - Row context
private enum RowContext: Equatable {
    case received
    case posted(isFutureScheduled: Bool, scheduledLabel: String?)
}

private struct ScheduleState {
    let label: String
    let tint: Color
}

private func scheduleState(for item: PostItem) -> ScheduleState? {
    guard item.isscheduled == true, let d = parseDate(item.ScheduledTime) else { return nil }
    let text = "Scheduled • \(relative(d))"
    let tint: Color = (d > Date()) ? .orange : .gray
    return .init(label: text, tint: tint)
}

// MARK: - Helpers to extract name & avatar (NO ViewBuilder)
private func displayName(for item: PostItem, context: RowContext) -> String {
    switch context {
    case .received:
        if let n = item.sender?.name, !n.isEmpty { return n }
        let id = item.sender?.userId ?? item.senderId
        return DisplayNameResolver.resolve(displayName: nil, userId: id)
    case .posted:
        if let n = item.receiver?.name, !n.isEmpty { return n }
        let id = item.receiver?.userId ?? item.receiverId
        return DisplayNameResolver.resolve(displayName: nil, userId: id)
    }
}

private func avatarURL(for item: PostItem, context: RowContext) -> String? {
    switch context {
    case .received:
        return item.sender?.profileUrl    // <— this is your profile_url
    case .posted:
        return item.receiver?.profileUrl
    }
}

private func avatarSeed(for item: PostItem, context: RowContext) -> String? {
    switch context {
    case .received:
        return item.sender?.userId ?? item.senderId ?? item.sender?.name
    case .posted:
        return item.receiver?.userId ?? item.receiverId ?? item.receiver?.name
    }
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
            case .posted(let isFuture, _):
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
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {

                avatarView(urlString: avatarURLString, seed: avatarSeed)      // <— profile_url is used here

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    switch context {
                    case .posted(_, let schedLabel):
                        if let schedLabel {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.fill").font(.caption2)
                                Text(schedLabel).font(.caption)
                            }
                            .foregroundColor(.orange)
                        } else if let created {
                            Text(created)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .received:
                        if let created {
                            Text(created)
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - External Profile View
private struct ExternalProfileView: View {
    let userId: String

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "person.circle.fill")
                        .resizable().scaledToFit()
                        .frame(width: 108, height: 108)
                        .foregroundColor(.accentColor)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                        .clipShape(Circle())

                    Text(userId.isEmpty ? "User" : userId)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color(.systemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Main View
struct ReviewFeedView: View {
    let showNavigationTitle: Bool
    @StateObject private var vm = ReviewFeedViewModel()
    @State private var selectedTab: Int // 0=Received, 1=Posted

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

    private var currentList: [PostItem] {
        selectedTab == 0 ? vm.receivedPosts : vm.myPosts
    }

    init(initialTab: Int = 0, showNavigationTitle: Bool = true) {
        self.showNavigationTitle = showNavigationTitle
        _selectedTab = State(initialValue: initialTab)
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

        let sched = scheduleState(for: item)
        let isFuture = (parseDate(item.ScheduledTime) ?? .distantPast) > Date()

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
                    return .posted(isFutureScheduled: isFuture, scheduledLabel: sched?.label)
                }
            }(),
            onAvatarTapped: {
                let tappedId: String
                switch context {
                case .received:
                    tappedId = item.sender?.userId ?? item.senderId ?? ""
                case .posted:
                    tappedId = item.receiver?.userId ?? item.receiverId ?? ""
                }
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
                if let sender = item.sender?.userId ?? item.senderId {
                    pendingBlockUserId = sender
                    showBlock = true
                }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {

                FlatTabBar2(selectedTab: $selectedTab, tabs: ["Received", "Posted"])

                Group {
                    if vm.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading…").foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))

                    } else if let err = vm.errorText {
                        VStack(spacing: 10) {
                            Text("Couldn’t load messages").font(.headline)
                            Text(err).font(.caption).foregroundColor(.secondary)
                            Button("Retry") { Task { await vm.load() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))

                    } else {
                        let list: [PostItem] = currentList
                        ScrollView {
                            VStack(spacing: 14) {
                                ForEach(list) { item in
                                    if selectedTab == 0 {
                                        rowView(for: item, in: .received)
                                    } else {
                                        let sched = scheduleState(for: item)
                                        rowView(for: item, in: .posted(isFutureScheduled: (sched != nil), scheduledLabel: sched?.label))
                                    }
                                }
                                Spacer(minLength: 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.top, 12)
                            .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color(.systemGroupedBackground))
                    }
                }
            }
            .navigationTitle(showNavigationTitle ? (selectedTab == 0 ? "Received" : "Posted") : "")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if UserDefaults.standard.string(forKey: "inboxStartTab") == "posted" {
                    selectedTab = 1
                    UserDefaults.standard.removeObject(forKey: "inboxStartTab")
                }
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
                   !vm.isLoading,
                   !vm.hasLoadedOnce {
                    Task { await vm.load() }
                }
            }
            .onChange(of: selectedTab) { newValue in
                if newValue == 1, let first = vm.myPosts.first {
                    withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jumpToPosted)) { _ in
                selectedTab = 1
            }
            .background(
                NavigationLink(
                    destination: ExternalProfileView(userId: externalUserId),
                    isActive: $pushExternalProfile
                ) { EmptyView() }
                .opacity(0)
            )
        }

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
                    if reasonsLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading reasons…").foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    } else if let err = reportError {
                        VStack(spacing: 12) {
                            Text("Report Status").font(.headline)
                            Text(err)
                                .font(.body)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .padding()
                            Button("Close") { onDismiss() }
                                .buttonStyle(.bordered)
                        }
                        .padding()

                    } else {
                        VStack(spacing: 8) {
                            Text("Report Post").font(.headline).padding(.top, 8)

                            if let item = pendingItem {
                                Text(item.postcontent)
                                    .font(.body)
                                    .foregroundColor(.primary)
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
                                                Text(r.text.capitalized).foregroundColor(.primary)
                                                Spacer()
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color(.secondarySystemBackground))
                                            )
                                        }
                                    }

                                    if selectedReasonId == "other" {
                                        VStack(spacing: 8) {
                                            if #available(iOS 16.0, *) {
                                                TextField("Explain the issue…", text: $otherText, axis: .vertical)
                                                    .lineLimit(3...6)
                                                    .padding(10)
                                                    .background(Color(.systemBackground))
                                                    .cornerRadius(8)
                                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                                            } else {
                                                TextField("Explain the issue…", text: $otherText)
                                                    .padding(10)
                                                    .background(Color(.systemBackground))
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
                        .padding()
                    }
                }
                .navigationBarTitle("Report", displayMode: .inline)
                .navigationBarItems(leading: Button("Close") { onDismiss() })
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
