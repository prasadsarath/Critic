//
//  WritePostView.swift
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//
import SwiftUI

@MainActor
struct WriteReviewView: View {
    @StateObject private var vm = WriteReviewViewModel()
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(
                            urlString: vm.targetUserAvatarURL,
                            seed: vm.targetUserSeed,
                            fallbackSystemName: vm.targetUserImageSymbol,
                            size: 54,
                            backgroundColor: CriticPalette.surface,
                            tintColor: CriticPalette.primary
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Posting review to")
                                .font(.critic(.caption))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                            Text(vm.targetUserName)
                                .font(.critic(.pageTitle))
                                .foregroundColor(CriticPalette.onSurface)
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                if let d = vm.targetDistanceText {
                                    CriticPill(icon: "location", label: d.replacingOccurrences(of: ".0", with: ""), iconColor: CriticPalette.primary)
                                }
                                if vm.scheduledAt != nil {
                                    CriticPill(icon: "clock", label: "Scheduled", iconColor: CriticPalette.warning)
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .criticCard()

                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $vm.reviewText)
                            .font(.critic(.body))
                            .frame(minHeight: 240)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: CriticRadius.md, style: .continuous)
                                    .fill(CriticPalette.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CriticRadius.md, style: .continuous)
                                            .stroke(CriticPalette.outline, lineWidth: 1)
                                    )
                            )
                            .onChange(of: vm.reviewText) { _ in vm.handleReviewTextChanged() }

                        if vm.trimmed.isEmpty {
                            Text("Write your review…")
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 22)
                                .allowsHitTesting(false)
                        }
                    }

                    HStack {
                        if vm.trimmedCount > 0 {
                            CriticPill(icon: "square.and.pencil", label: "Draft", iconColor: CriticPalette.warning)
                        }
                        Spacer()
                        CriticPill(icon: "textformat.abc", label: "\(vm.trimmedCount) chars", iconColor: CriticPalette.info)
                    }
                }
                .padding(14)
                .criticCard()

                Button {
                    Task { await vm.runModeration() }
                } label: {
                    Group {
                        if vm.isModerating {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Review your post for content moderation", systemImage: "checkmark.shield")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(CriticFilledButtonStyle())
                .disabled(!vm.canReview)

                HStack(spacing: 10) {
                    Button {
                        Task { await vm.postNow() }
                    } label: {
                        Group {
                            if vm.isPosting {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Post Now", systemImage: "paperplane.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .buttonStyle(CriticFilledButtonStyle(backgroundColor: CriticPalette.success))
                    .disabled(!vm.canPostNow)

                    Button {
                        vm.prepareScheduleSheet()
                    } label: {
                        Label("Schedule", systemImage: "clock.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CriticOutlinedButtonStyle(foregroundColor: CriticPalette.primary))
                    .disabled(!vm.canSchedule)
                }
            }
            .padding(16)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationTitle("Write Review")
        .navigationBarTitleDisplayMode(.inline)
        .criticNavigationBarBackground(CriticPalette.background)
        .onReceive(tick) { _ in
            Task { await vm.handleTick() }
        }
        .alert("Your Critic", isPresented: $vm.showValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.validationMessage)
        }
        .sheet(isPresented: $vm.showPostSheet) {
            ScheduleSheet(
                scheduleDate: $vm.scheduleDate,
                minDate: vm.minSchedule,
                maxDate: vm.maxSchedule,
                onConfirm: {
                    Task { await vm.confirmScheduleSheet() }
                },
                onCancel: { vm.dismissScheduleSheet() }
            )
        }
    }
}

// MARK: - Cross-screen signal to jump to Posted tab
extension Notification.Name {
    static let jumpToPosted = Notification.Name("jumpToPosted")
    static let reviewFeedNeedsRefresh = Notification.Name("reviewFeedNeedsRefresh")
}

// MARK: - Schedule Sheet (bottom sheet)
struct ScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var scheduleDate: Date
    let minDate: Date
    let maxDate: Date

    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Text("Schedule Post")
                    .font(.headline)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick a time within the next 24 hours.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    DatePicker(
                        "",
                        selection: $scheduleDate,
                        in: minDate...maxDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    HStack {
                        Button(role: .cancel) { onCancel() } label: {
                            Text("Cancel").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onConfirm()
                        } label: {
                            Text("Schedule").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 6)
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview
struct WritePostView_Previews: PreviewProvider {
    static var previews: some View {
        WriteReviewView().preferredColorScheme(.light)
        WriteReviewView().preferredColorScheme(.dark)
    }
}
