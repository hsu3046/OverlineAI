import Foundation

// UIKit-free line fixture for the production assembler extracted by run.sh.
struct CameraRecognizedTextLine {
    let id: String
    let text: String
    let boundingBox: CGRect
    let readingIndex: Int
    let isVertical: Bool
}
