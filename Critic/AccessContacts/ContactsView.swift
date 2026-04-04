import SwiftUI

struct ContactsView: View {
    @ObservedObject var vm: ContactsViewModel
    var onWrite: (_ userId: String, _ displayName: String?) -> Void

    @State private var showShare = false
    @State private var shareText = "Hey! I’m using Critic to share quick reviews. Join me!"

    var body: some View {
        VStack(spacing: 0) {
            if vm.permissionStatus == .notDetermined {
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(CriticPalette.primary)

                    Text("Find friends already on Critic")
                        .font(.critic(.pageTitle))
                        .foregroundColor(CriticPalette.onSurface)

                    Text("Allow contacts only when you want to see which friends are already using the app and who you can invite.")
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button {
                        Task { await vm.requestAccessAndLoad() }
                    } label: {
                        Label("Allow Contacts", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CriticFilledButtonStyle())
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.loading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Checking your contacts…").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = vm.errorMessage {
                VStack(spacing: 12) {
                   // Text("Contacts").font(.headline)
                    Text(msg).multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "gearshape.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)

                        Button {
                            Task { await vm.requestAccessAndLoad() }
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(header: Text("On Critic (\(vm.registered.count))")) {
                        if vm.registered.isEmpty {
                            Text("None of your contacts are on Critic (yet).").foregroundColor(.secondary)
                        } else {
                            ForEach(vm.registered) { user in
                                HStack {
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading) {
                                        Text(user.name ?? "Friend").font(.body)
                                        if !user.phoneE164.isEmpty {
                                            Text(user.phoneE164).font(.caption).foregroundColor(.secondary)
                                        }
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

                    Section(header: Text("Invite to Critic (\(vm.invitable.count))")) {
                        if vm.invitable.isEmpty {
                            Text("No one to invite.").foregroundColor(.secondary)
                        } else {
                            ForEach(vm.invitable) { c in
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading) {
                                        Text(c.displayName).font(.body)
                                        Text(c.phones.first ?? "")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        shareText = "Hey \(c.displayName), join me on Critic! Download & ping me when you’re in."
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
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: 24)
                }
                .background(CriticPalette.background)
                .refreshable { await vm.refresh() }
            }
        }
        .task { await vm.bootstrap() }
        .sheet(isPresented: $showShare) { ShareSheet2(items: [shareText]) }
       // .navigationTitle("Contacts")
    }
}
