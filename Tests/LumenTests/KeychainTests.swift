import Foundation
import Testing
@testable import LumenProviders

private func security(_ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    try? p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// Секреты идут через /usr/bin/security (см. Keychain.swift): что записал Lumen, видно в настоящей Связке, и наоборот —
/// в том числе с кавычками, переносами и русским
@Test func keychainRoundTripThroughSecurityTool() throws {
    let service = "com.roman.lumen.tests.\(UUID().uuidString)"
    let k = Keychain(service: service)
    defer { for a in ["a", "b", "c"] { _ = security(["delete-generic-password", "-s", service, "-a", a]) } }

    let value = "{\"token\":\"x y\\\"z\",\"n\":1}\nвторая строка ✓"
    try k.save(value, for: "a")
    #expect(k.has("a"))
    // записано по-настоящему, а не только в кэш: то же самое лежит в самой Связке (hex от UTF-8)
    let hexOf = { (s: String) in Data(s.utf8).map { String(format: "%02X", $0) }.joined() }
    #expect(security(["find-generic-password", "-s", service, "-a", "a", "-w"]).out == Data(value.utf8).map { String(format: "%02x", $0) }.joined() + "\n")
    // обновление поверх существующей записи
    try k.save("новый", for: "a")
    #expect(security(["find-generic-password", "-s", service, "-a", "a", "-w"]).out == Data("новый".utf8).map { String(format: "%02x", $0) }.joined() + "\n")
    _ = hexOf

    // запись, созданная не Lumen (как старые секреты), читается без кэша
    #expect(security(["add-generic-password", "-s", service, "-a", "c", "-w", "из связки"]).status == 0)
    #expect(Keychain(service: service).read("c") == "из связки")

    // удаление убирает и из Связки
    k.delete("a")
    #expect(security(["find-generic-password", "-s", service, "-a", "a", "-w"]).status != 0)
    #expect(Keychain(service: service).read("b") == nil)
}

@Test func securityToolOutputIsParsedBothWays() {
    #expect(Keychain.parsePassword("keychain: \"x\"\npassword: \"ab\"c d\"\n") == "ab\"c d")
    #expect(Keychain.parsePassword("password: \"deadbeef00\"\n") == "deadbeef00")
    #expect(Keychain.parsePassword("password: 0xD0BDD0BED0B2D18BD0B9 \n") == "новый")
    #expect(Keychain.parsePassword("password: 0x6C310A6C32  \"l1\\012l2\"\n") == "l1\nl2")
    #expect(Keychain.parsePassword("password: <NULL>\n") == "")
    #expect(Keychain.parsePassword("нет записи") == nil)
}
