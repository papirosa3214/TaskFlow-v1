/// Bundled portraits shared by the team, chats and task surfaces.
/// Only known agent accounts get an illustration; humans keep their own photo/initials.
enum RoleAvatarAsset {
    static func imageName(for role: String?) -> String? {
        switch role {
        case "architect": "RoleAvatarArchitect"
        case "builder": "RoleAvatarBuilder"
        case "qa": "RoleAvatarQA"
        case "researcher": "RoleAvatarResearcher"
        case "analyst": "RoleAvatarAnalyst"
        case "critic_verifier": "RoleAvatarCriticVerifier"
        case "designer": "RoleAvatarDesigner"
        case "secretary": "RoleAvatarSecretary"
        default: nil
        }
    }

    static func imageName(forUserID userID: String?) -> String? {
        guard let userID else { return nil }
        if userID == "u-secretary" { return imageName(for: "secretary") }
        guard userID.hasPrefix("role_") else { return nil }
        return imageName(for: String(userID.dropFirst("role_".count)))
    }
}
