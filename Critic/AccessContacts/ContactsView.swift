import SwiftUI

struct ContactsView: View {
    @ObservedObject var vm: ContactsViewModel
    var onClose: () -> Void
    var onWrite: (_ userId: String, _ displayName: String?) -> Void

    @State private var showShare = false
    @State private var shareText = "Hey! I’m using Kriticapp to share quick reviews. Join me!"

    var body: some View {
        VStack(spacing: 0) {
            if vm.permissionStatus == .notDetermined {
                permissionRequestState
            } else {
                CriticDetailHeader(title: "Contacts") {
                    onClose()
                }

                if vm.loading {
                    loadingState
                } else if let msg = vm.errorMessage, !hasLoadedContacts {
                    errorState(message: msg)
                } else {
                    contactsList
                }
            }
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .task { await vm.bootstrap() }
        .sheet(isPresented: $showShare) { ShareSheet2(items: [shareText]) }
    }

    private var hasLoadedContacts: Bool {
        !vm.registered.isEmpty || !vm.invitable.isEmpty
    }

    private var contactsPermissionNeedsSettings: Bool {
        vm.permissionStatus == .denied || vm.permissionStatus == .restricted
    }

    private var permissionRequestState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            CriticSoftIcon(
                systemName: "person.crop.circle.badge.checkmark",
                color: CriticPalette.primary,
                size: 68,
                iconSize: 30,
                opacity: 0.12
            )

            VStack(spacing: 10) {
                Text("Find people you know")
                    .font(.critic(.pageTitle))
                    .foregroundColor(CriticPalette.onSurface)
                    .multilineTextAlignment(.center)

                Text("Kriticapp will send your contacts' phone numbers to Kriticapp servers to match people already on Kriticapp. We use them only for matching and do not store, share, or show them to other users.")
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 520)

            Button {
                Task { await vm.requestAccessAndLoad() }
            } label: {
                Label("Continue", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CriticFilledButtonStyle())
            .frame(maxWidth: 520)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ProgressView()
            Text("Checking your contacts…")
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            HStack(spacing: 12) {
                if contactsPermissionNeedsSettings {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }

                Button {
                    Task { await vm.requestAccessAndLoad() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }

            Button("Back To Home") {
                onClose()
            }
            .buttonStyle(CriticOutlinedButtonStyle())
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contactsList: some View {
        List {
            Section(header: Text("On Kriticapp (\(vm.registered.count))")) {
                if vm.registered.isEmpty {
                    Text("None of your contacts are on Kriticapp (yet).").foregroundColor(.secondary)
                } else {
                    ForEach(vm.registered) { user in
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(user.name ?? "Friend").font(.body)
                                Text("On Kriticapp")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                onWrite(user.id, user.name)
                            } label: {
                                Text("Write")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.accentColor)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section(header: Text("Invite to Kriticapp (\(vm.invitable.count))")) {
                if vm.invitable.isEmpty {
                    Text("No one to invite.").foregroundColor(.secondary)
                } else {
                    ForEach(vm.invitable) { c in
                        HStack {
                            Image(systemName: "person.badge.plus")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(c.displayName).font(.body)
                                Text("Invite privately")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                shareText = "Hey \(c.displayName), join me on Kriticapp! Download & ping me when you’re in."
                                showShare = true
                            } label: {
                                Text("Invite")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.accentColor)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .modifier(ScrollBGHider())
        .background(CriticPalette.background)
        .refreshable { await vm.refresh() }
    }
}
