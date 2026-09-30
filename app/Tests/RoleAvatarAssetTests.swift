import UIKit
import XCTest
@testable import TaskFlow

final class RoleAvatarAssetTests: XCTestCase {
    func testKnownAgentAccountsResolveToBundledPortraits() {
        let expected = [
            "role_architect": "RoleAvatarArchitect",
            "role_builder": "RoleAvatarBuilder",
            "role_qa": "RoleAvatarQA",
            "role_researcher": "RoleAvatarResearcher",
            "role_analyst": "RoleAvatarAnalyst",
            "role_critic_verifier": "RoleAvatarCriticVerifier",
            "role_designer": "RoleAvatarDesigner",
            "u-secretary": "RoleAvatarSecretary"
        ]
        for (userID, asset) in expected {
            XCTAssertEqual(RoleAvatarAsset.imageName(forUserID: userID), asset)
            guard let image = UIImage(named: asset) else {
                return XCTFail("Missing bundled portrait: \(asset)")
            }
            XCTAssertLessThan(alpha(in: image, x: 0, y: 0), 10, "Opaque corner: \(asset)")
        }
    }

    func testHumanAndUnknownAccountsKeepTheirExistingAvatarFallback() {
        XCTAssertNil(RoleAvatarAsset.imageName(forUserID: nil))
        XCTAssertNil(RoleAvatarAsset.imageName(forUserID: "owner-1"))
        XCTAssertNil(RoleAvatarAsset.imageName(forUserID: "role_reviewer"))
        XCTAssertNil(RoleAvatarAsset.imageName(forUserID: "role_architect_extra"))
    }

    private func alpha(in image: UIImage, x: Int, y: Int) -> UInt8 {
        guard let cgImage = image.cgImage,
              let pixel = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
        else { return .max }
        var rgba = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &rgba,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .max }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return rgba[3]
    }
}
