//
//  CriticTests.swift
//  CriticTests
//
//  Created by chinni Rayapudi on 7/14/25.
//

import Testing
@testable import Critic

struct CriticTests {
    @Test
    func displayNameResolverRejectsOpaqueIdentifiers() {
        let opaqueId = "44280468-0001-7090-852b-3c98914d6f40"

        #expect(DisplayNameResolver.resolve(displayName: opaqueId, userId: opaqueId) == "User")
        #expect(DisplayNameResolver.homeHeaderName(storedName: opaqueId, userId: opaqueId, email: nil) == "User")
    }

    @Test
    func homeHeaderFallsBackToEmailWhenNameIsInvalid() {
        #expect(
            DisplayNameResolver.homeHeaderName(
                storedName: "guest",
                userId: "44280468-0001-7090-852b-3c98914d6f40",
                email: "person@example.com"
            ) == "person@example.com"
        )
    }

    @Test
    func releaseLinksUseProductionDomains() {
        #expect(AppExternalLinks.inviteLanding.host() == "veranosoft.com")
        #expect(AppExternalLinks.terms.scheme == "https")
        #expect(AppExternalLinks.privacy.scheme == "https")
        #expect(AppExternalLinks.faq.scheme == "https")
    }

}
