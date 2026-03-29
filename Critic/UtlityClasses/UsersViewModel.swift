//
//  UsersViewModel.swift
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//

import Foundation
import Combine
import SwiftUI
import CoreLocation

final class UsersViewModel: ObservableObject {
    @Published private(set) var userLocations: [UserLocation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let repo: UsersRepositoryType
    private var bag = Set<AnyCancellable>()
    private let symbols = ["person.fill","person.circle.fill","person.crop.circle","person.2.fill"]

    init(repo: UsersRepositoryType) { self.repo = repo }

    func load() {
        isLoading = true
        repo.fetchUsers()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] comp in
                self?.isLoading = false
                if case .failure(let e) = comp { self?.error = e.localizedDescription }
            } receiveValue: { [weak self] users in
                guard let self = self else { return }
                self.userLocations = users.enumerated().map { idx, u in
                    let lat = Double(u.address.geolocation.lat) ?? 0
                    let lon = Double(u.address.geolocation.long) ?? 0
                    return UserLocation(
                        id: "U\(u.id)",
                        latitude: lat,
                        longitude: lon,
                        profileImageName: self.symbols[idx % self.symbols.count], // ⬅️ explicit self
                        displayName: "\(u.name.firstname.capitalized) \(u.name.lastname.capitalized)"
                    )
                }
            }
            .store(in: &bag)
    }
}
