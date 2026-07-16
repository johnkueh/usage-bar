import Foundation

func bytes(_ string: String) -> Data {
    Data(string.utf8)
}

func bigEndian(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3, !arguments.count.isMultiple(of: 2) else {
    FileHandle.standardError.write(Data("usage: make-icns.swift output.icns TYPE image.png [...]\n".utf8))
    exit(2)
}

let output = arguments[0]
var body = Data()
var index = 1
while index < arguments.count {
    let type = arguments[index]
    let path = arguments[index + 1]
    guard type.utf8.count == 4, let image = FileManager.default.contents(atPath: path) else {
        FileHandle.standardError.write(Data("invalid icon entry: \(type) \(path)\n".utf8))
        exit(2)
    }
    body.append(bytes(type))
    body.append(bigEndian(UInt32(image.count + 8)))
    body.append(image)
    index += 2
}

var icon = bytes("icns")
icon.append(bigEndian(UInt32(body.count + 8)))
icon.append(body)
try icon.write(to: URL(fileURLWithPath: output), options: .atomic)
