import CoreImage
import Testing
@testable import SkinKitCore

/// A skin's filter list is untrusted input: CoreImage raises an Objective-C exception for a
/// key a filter does not have, which took the app down mid-frame.
@Suite struct ScreenFilterUndefinedKeyTests {
    private let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))

    @Test func unknownParameterKeyIsSkipped() throws {
        let brightness: Float = 0.25
        let info = DeltaSkin.FilterInfo(name: "CIColorControls",
                                        parameters: ["inputNoSuchKey": .number(1), "inputBrightness": .number(brightness)])
        let filter = try #require(DeltaSkinScreenFilter(filterInfo: info))
        #expect((filter.filter.value(forKey: kCIInputBrightnessKey) as? NSNumber)?.floatValue == brightness)
        #expect(filter.apply(to: image, in: image.extent) != nil)
    }

    @Test func generatorWithoutInputImageFiltersNothing() throws {
        let info = DeltaSkin.FilterInfo(name: "CIConstantColorGenerator", parameters: [:])
        let filter = try #require(DeltaSkinScreenFilter(filterInfo: info))
        #expect(filter.apply(to: image, in: image.extent) == nil)
    }
}
