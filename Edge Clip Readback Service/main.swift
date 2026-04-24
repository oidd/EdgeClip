import Foundation

let delegate = ClipboardReadbackService()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
