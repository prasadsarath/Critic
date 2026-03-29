//
//  UsersRepository.swift
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//

import Foundation
import Combine

protocol UsersRepositoryType {
    func fetchUsers() -> AnyPublisher<[FSUser], APIError>
}

final class UsersRepository: UsersRepositoryType {
    private let client: NetworkClient
    init(client: NetworkClient) { self.client = client }
    func fetchUsers() -> AnyPublisher<[FSUser], APIError> {
        client.execute(FakeStoreUsersAPI.GetAll())
    }
}
