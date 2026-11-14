import XCTest
@testable import RunCoachCore

final class SigningProfileTests: XCTestCase {
    func testReadsExpirationDateInsideSignedEnvelope() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>AppIDName</key><string>Exemple</string>
        <key>ExpirationDate</key><date>2026-11-21T10:00:00Z</date>
        </dict></plist>
        """
        // Octets de signature CMS synthétiques avant et après le plist.
        let data = Data([0x30, 0x82, 0x0F, 0x00, 0x06, 0x09]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x00, 0x01])
        let expected = ISO8601DateFormatter().date(from: "2026-11-21T10:00:00Z")
        XCTAssertEqual(SigningProfile.expirationDate(data), expected)
    }

    func testNoProfileMeansNoDate() {
        XCTAssertNil(SigningProfile.expirationDate(Data("pas un profil".utf8)))
    }
}
