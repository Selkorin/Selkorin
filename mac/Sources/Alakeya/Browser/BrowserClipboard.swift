import AppKit

@MainActor
enum BrowserClipboard {
    static func copy(_ image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let wroteImage = pasteboard.writeObjects([image])

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            return wroteImage
        }
        let wrotePNG = pasteboard.setData(png, forType: .png)
        return wroteImage || wrotePNG
    }
}
