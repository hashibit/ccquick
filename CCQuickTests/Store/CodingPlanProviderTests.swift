import XCTest
@testable import CCQuick

final class CodingPlanProviderTests: XCTestCase {

    func testMatchProviders_byPrefix() {
        // sk-sp- should match 百炼
        let matched = CodingPlanProvider.matchProviders(for: "sk-sp-abc123")
        XCTAssertGreaterThanOrEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.name, "百炼")
    }

    func testMatchProviders_emptyKey_returnsAll() {
        let matched = CodingPlanProvider.matchProviders(for: "")
        XCTAssertEqual(matched.count, CodingPlanProvider.providers.count)
    }

    func testMatchProviders_unknownPrefix_returnsAll() {
        // "sk-" matches multiple providers, should return them all for parallel testing
        let matched = CodingPlanProvider.matchProviders(for: "sk-unknown")
        XCTAssertFalse(matched.isEmpty)
    }

    func testAllProvidersHaveNonEmptyFields() {
        for provider in CodingPlanProvider.providers {
            XCTAssertFalse(provider.name.isEmpty, "\(provider) name empty")
            XCTAssertFalse(provider.baseURL.isEmpty, "\(provider) baseURL empty")
            XCTAssertFalse(provider.haikuModel.isEmpty, "\(provider) haikuModel empty")
            XCTAssertFalse(provider.sonnetModel.isEmpty, "\(provider) sonnetModel empty")
            XCTAssertFalse(provider.opusModel.isEmpty, "\(provider) opusModel empty")
            XCTAssertFalse(provider.keyPrefixes.isEmpty, "\(provider) keyPrefixes empty")
        }
    }

    func testProviderModelFallback() {
        for provider in CodingPlanProvider.providers {
            // model property should equal sonnetModel
            XCTAssertEqual(provider.model, provider.sonnetModel)
        }
    }

    func testAPIType_rawValues() {
        XCTAssertEqual(CodingPlanProvider.APIType.anthropic.rawValue, "anthropic")
        XCTAssertEqual(CodingPlanProvider.APIType.openai.rawValue, "openai")
    }

    func testAuthType_rawValues() {
        XCTAssertEqual(CodingPlanProvider.AuthType.xApiKey.rawValue, "xApiKey")
        XCTAssertEqual(CodingPlanProvider.AuthType.bearer.rawValue, "bearer")
    }

    func testCodingPlanProviderCodable() throws {
        let provider = CodingPlanProvider.providers.first!
        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(CodingPlanProvider.self, from: data)
        XCTAssertEqual(decoded.name, provider.name)
        XCTAssertEqual(decoded.baseURL, provider.baseURL)
        XCTAssertEqual(decoded.keyPrefixes, provider.keyPrefixes)
    }
}
