//
//  UsersAPI.swift
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//

import Foundation

// Payload for https://fakestoreapi.com/users
struct FSUser: Decodable {
    struct Name: Decodable { let firstname: String; let lastname: String }
    struct Geo: Decodable { let lat: String; let long: String }
    struct Address: Decodable { let city: String; let street: String; let number: Int; let zipcode: String; let geolocation: Geo }

    let id: Int
    let email: String
    let username: String
    let name: Name
    let address: Address
    let phone: String
}

enum FakeStoreUsersAPI {
    struct GetAll: Endpoint {
        typealias Response = [FSUser]
        let path = "/users"
        let method: HTTPMethod = .GET
    }
}
