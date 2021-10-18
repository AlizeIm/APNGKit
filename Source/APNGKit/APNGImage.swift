
import Foundation
import CoreGraphics
import Delegate
import UIKit

public class APNGImage {
    public enum Duration {
        case loadedPartial(TimeInterval)
        case full(TimeInterval)
    }
    
    let decoder: APNGDecoder
    
    public var onFramesInformationPrepared: Delegate<(), Void> { decoder.onFirstPassDone }
    
    public let scale: CGFloat
    public var size: CGSize {
        .init(
            width:  CGFloat(decoder.imageHeader.width)  / scale,
            height: CGFloat(decoder.imageHeader.height) / scale
        )
    }
    
    public var numberOfPlays: Int?
    public var numberOfFrames: Int { decoder.animationControl.numberOfFrames }
    public var duration: Duration {
        // If loading with a streaming way, there is no way to know the duration before the first loading pass finishes.
        // In this case, before the first pass is done, a partial duration of the currently loaded frames will be
        // returned.
        //
        // If you need to know the full duration before the first pass, use `DecodingOptions.fullFirstPass` to
        // initialize the image object.
        let knownDuration = decoder.frames.reduce(0.0) { $0 + ($1?.frameControl.duration ?? 0) }
        return decoder.firstPass ? .loadedPartial(knownDuration) : .full(knownDuration)
    }
    
    weak var owner: APNGImageView?
    
    public convenience init(named name: String) throws {
        try self.init(named: name, in: nil, subdirectory: nil)
    }
    
    public convenience init(named name: String, in bundle: Bundle?, subdirectory subpath: String? = nil) throws {

        let fileName: String
        
        let guessingExtension: [String]
        let splits = name.split(separator: ".")
        if splits.count > 1 {
            guessingExtension = [String(splits.last!)]
            fileName = splits[0 ..< splits.count - 1].joined(separator: ".")
        } else {
            guessingExtension = ["apng", "png"]
            fileName = name
        }
        
        let guessingFromName: [(name: String, scale: CGFloat)]
        
        if fileName.hasSuffix("@2x") {
            guessingFromName = [(fileName, 2)]
        } else if fileName.hasSuffix("@3x") {
            guessingFromName = [(fileName, 3)]
        } else {
            let maxScale = Int(screenScale)
            guessingFromName = (1...maxScale).reversed().map { scale in
                return scale > 1 ? ("\(fileName)@\(scale)x", CGFloat(scale)) : (fileName, CGFloat(1))
            }
        }
        
        let targetBundle = bundle ?? .main
        
        var resource: (URL, CGFloat)? = nil
        
        for nameAndScale in guessingFromName {
            for ext in guessingExtension {
                if let url = targetBundle.url(
                    forResource: nameAndScale.name, withExtension: ext, subdirectory: subpath
                ) {
                    resource = (url, nameAndScale.scale)
                    break
                }
            }
        }
        
        guard let resource = resource else {
            throw APNGKitError.imageError(.resourceNotFound(name: name, bundle: targetBundle))
        }
        
        try self.init(fileURL: resource.0, scale: resource.1)
    }
    
    public convenience init(filePath: String, scale: CGFloat? = nil) throws {
        let fileURL = URL(fileURLWithPath: filePath)
        try self.init(fileURL: fileURL, scale: scale)
    }

    public init(fileURL: URL, scale: CGFloat? = nil) throws {
        if let scale = scale {
            self.scale = scale
        } else {
            var url = fileURL
            url.deletePathExtension()
            if url.lastPathComponent.hasSuffix("@2x") {
                self.scale = 2
            } else if url.lastPathComponent.hasSuffix("@3x") {
                self.scale = 3
            } else {
                self.scale = 1
            }
        }
        
        do {
            decoder = try APNGDecoder(fileURL: fileURL)
            let repeatCount = decoder.animationControl.numberOfPlays
            numberOfPlays = repeatCount == 0 ? nil : repeatCount
        } catch {
            // Special case when the error is lack of acTL. It means this image is not an APNG at all.
            // Then try to load it as a normal image.
            if let apngError = error.apngError, apngError.shouldRevertToNormalImage {
                let data = try Data(contentsOf: fileURL)
                guard let image = UIImage(data: data, scale: self.scale) else {
                    throw error
                }
                throw APNGKitError.imageError(.normalImageDataLoaded(image: image))
            } else {
                throw error
            }
        }
    }

    public init(data: Data, scale: CGFloat = 1.0) throws {
        self.scale = scale
        do {
            self.decoder = try APNGDecoder(data: data)
            let repeatCount = decoder.animationControl.numberOfPlays
            numberOfPlays = repeatCount == 0 ? nil : repeatCount
        } catch {
            // Special case when the error is lack of acTL. It means this image is not an APNG at all.
            // Then try to load it as a normal image.
            if let apngError = error.apngError, apngError.shouldRevertToNormalImage {
                guard let image = UIImage(data: data, scale: self.scale) else {
                    throw error
                }
                throw APNGKitError.imageError(.normalImageDataLoaded(image: image))
            } else {
                throw error
            }
        }
    }
    
    func reset() throws {
        try decoder.reset()
    }
}

extension APNGImage {
    public struct DecodingOptions: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let fullFirstPass      = DecodingOptions(rawValue: 1 << 0)
        public static let loadFrameData      = DecodingOptions(rawValue: 1 << 1)
        public static let cacheDecodedImages = DecodingOptions(rawValue: 1 << 2)
        public static let preloadAllFrames   = DecodingOptions(rawValue: 1 << 3)
    }
}
