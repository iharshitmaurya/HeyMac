import Testing
import Foundation
@testable import FaceUnlockCore

@Test func allMessagesRoundTripThroughEncodeDecode() {
    let messages: [WireMessage] = [.verify, .verifyLock, .ok, .fail]
    for message in messages {
        let decoded = WireMessage.decode(message.encoded())
        #expect(decoded == message)
    }
}

@Test func garbageBytesDecodeToNil() {
    let garbage = Data([0xFF, 0x00, 0x01, 0x02])
    #expect(WireMessage.decode(garbage) == nil)
}

@Test func emptyDataDecodesToNil() {
    #expect(WireMessage.decode(Data()) == nil)
}

@Test func decodeIgnoresSurroundingWhitespace() {
    let data = Data(" VERIFY \n".utf8)
    #expect(WireMessage.decode(data) == .verify)
}
