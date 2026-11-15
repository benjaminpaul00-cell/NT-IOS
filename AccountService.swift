import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import Observation
import Security
import SwiftUI

struct DominoFriend: Identifiable, Equatable {
    let id: String
    let displayName: String
    let friendCode: String
    let avatarIndex: Int
}

struct TableInvitation: Identifiable, Equatable {
    let id: String
    let roomCode: String
    let senderName: String
}

struct FriendRequest: Identifiable, Equatable {
    let id: String
    let senderID: String
    let senderName: String
    let senderAvatarIndex: Int
}

@MainActor
@Observable
final class AccountService {
    private(set) var displayName = "Player"
    private(set) var friendCode = ""
    private(set) var friends: [DominoFriend] = []
    private(set) var friendRequests: [FriendRequest] = []
    private(set) var invitations: [TableInvitation] = []
    private(set) var isAuthenticatedProfile = false
    private(set) var errorMessage: String?

    private let database = Firestore.firestore()
    private var currentNonce: String?
    private var invitationsListener: ListenerRegistration?
    private var friendRequestsListener: ListenerRegistration?

    func refresh(avatarIndex: Int) async {
        guard let user = Auth.auth().currentUser else { return }
        await saveProfile(user: user, avatarIndex: avatarIndex)
        await loadFriends()
        observeFriendRequests()
        observeInvitations()
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try Self.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeAppleSignIn(
        _ result: Result<ASAuthorization, Error>,
        avatarIndex: Int
    ) async {
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw AccountError.message("The Apple response is incomplete.")
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: token,
                rawNonce: nonce,
                fullName: credential.fullName
            )

            let authResult: AuthDataResult
            if Auth.auth().currentUser?.isAnonymous == true,
               let currentUser = Auth.auth().currentUser {
                authResult = try await currentUser.link(with: firebaseCredential)
            } else {
                authResult = try await Auth.auth().signIn(with: firebaseCredential)
            }

            await saveProfile(user: authResult.user, avatarIndex: avatarIndex)
            await loadFriends()
            observeFriendRequests()
            observeInvitations()
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    func signInWithGoogle(avatarIndex: Int) async {
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw AccountError.message("The Google client ID is missing.")
            }
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let viewController = windowScene.keyWindow?.rootViewController else {
                throw AccountError.message("Unable to open Google Sign-In.")
            }

            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController
            )
            guard let idToken = result.user.idToken?.tokenString else {
                throw AccountError.message("Google did not return an identity token.")
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let authResult: AuthDataResult
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                do {
                    authResult = try await currentUser.link(with: credential)
                } catch {
                    authResult = try await Auth.auth().signIn(with: credential)
                }
            } else {
                authResult = try await Auth.auth().signIn(with: credential)
            }

            await saveProfile(user: authResult.user, avatarIndex: avatarIndex)
            await loadFriends()
            observeFriendRequests()
            observeInvitations()
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    func updateProfile(name: String, avatarIndex: Int) async {
        guard let user = Auth.auth().currentUser else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanName.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            errorMessage = "Username must contain 3–20 letters, numbers, or underscores."
            return
        }
        do {
            let usernameKey = cleanName.lowercased()
            let profileReference = database.collection("profiles").document(user.uid)
            let usernameReference = database.collection("usernames").document(usernameKey)

            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let profileSnapshot = try transaction.getDocument(profileReference)
                    let usernameSnapshot = try transaction.getDocument(usernameReference)
                    if let owner = usernameSnapshot.data()?["uid"] as? String,
                       owner != user.uid {
                        throw AccountError.message("This username is already taken.")
                    }

                    let oldUsernameKey = profileSnapshot.data()?["usernameKey"] as? String
                    if let oldUsernameKey, oldUsernameKey != usernameKey {
                        transaction.deleteDocument(
                            self.database.collection("usernames").document(oldUsernameKey)
                        )
                    }

                    if !usernameSnapshot.exists {
                        transaction.setData(["uid": user.uid], forDocument: usernameReference)
                    }
                    var profileData: [String: Any] = [
                        "username": cleanName,
                        "usernameKey": usernameKey,
                        "avatarId": Self.avatarID(avatarIndex),
                        "catalogVersion": 1,
                        "updatedAt": FieldValue.serverTimestamp()
                    ]
                    if !profileSnapshot.exists {
                        profileData["createdAt"] = FieldValue.serverTimestamp()
                    }
                    transaction.setData(profileData, forDocument: profileReference, merge: true)
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }

            let profileChange = user.createProfileChangeRequest()
            profileChange.displayName = cleanName
            try await profileChange.commitChanges()

            try await database.collection("users").document(user.uid).setData([
                "displayName": cleanName,
                "avatarIndex": avatarIndex,
                "friendCode": friendCode,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            displayName = cleanName
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    func addFriend(username: String) async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUsername.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            errorMessage = "Username must contain 3–20 letters, numbers, or underscores."
            return false
        }
        let usernameKey = cleanUsername.lowercased()

        do {
            let usernameSnapshot = try await database.collection("usernames").document(usernameKey).getDocument()
            guard let friendID = usernameSnapshot.data()?["uid"] as? String else {
                throw AccountError.message("No player has that username.")
            }
            guard friendID != user.uid else {
                throw AccountError.message("You cannot add yourself.")
            }
            if friends.contains(where: { $0.id == friendID }) {
                throw AccountError.message("You are already friends.")
            }
            if let incomingRequest = friendRequests.first(where: { $0.senderID == friendID }) {
                await acceptFriendRequest(incomingRequest)
                errorMessage = "Friend added."
                return true
            }
            let ownProfile = try await database.collection("profiles").document(user.uid).getDocument()
            guard let ownData = ownProfile.data(),
                  let ownName = ownData["username"] as? String,
                  let ownAvatar = ownData["avatarId"] as? String else {
                throw AccountError.message("Save your username before adding friends.")
            }
            try await database.collection("friendRequests")
                .document("\(user.uid)_\(friendID)")
                .setData([
                    "fromUid": user.uid,
                    "toUid": friendID,
                    "fromName": ownName,
                    "fromAvatar": ownAvatar,
                    "status": "pending",
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            errorMessage = "Friend request sent."
            return true
        } catch {
            errorMessage = firebaseMessage(error)
            return false
        }
    }

    func acceptFriendRequest(_ request: FriendRequest) async {
        guard let user = Auth.auth().currentUser else { return }
        do {
            let ownProfile = try await database.collection("profiles").document(user.uid).getDocument()
            guard let ownData = ownProfile.data(),
                  let ownName = ownData["username"] as? String,
                  let ownAvatar = ownData["avatarId"] as? String else {
                throw AccountError.message("Save your username before accepting friends.")
            }

            let batch = database.batch()
            let requestReference = database.collection("friendRequests").document(request.id)
            batch.updateData([
                "status": "accepted",
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: requestReference)
            batch.setData([
                "uid": request.senderID,
                "username": request.senderName,
                "avatarId": Self.avatarID(request.senderAvatarIndex),
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: database.collection("friends").document(user.uid)
                .collection("items").document(request.senderID))
            batch.setData([
                "uid": user.uid,
                "username": ownName,
                "avatarId": ownAvatar,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: database.collection("friends").document(request.senderID)
                .collection("items").document(user.uid))
            try await batch.commit()
            await loadFriends()
            await loadFriends()
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    func declineFriendRequest(_ request: FriendRequest) async {
        do {
            try await database.collection("friendRequests").document(request.id).delete()
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    func invite(friend: DominoFriend, to roomCode: String) async {
        guard let user = Auth.auth().currentUser, !roomCode.isEmpty else { return }
        do {
            try await database.collection("invites")
                .document(friend.id)
                .collection("items")
                .document(roomCode)
                .setData([
                    "fromUid": user.uid,
                    "fromName": displayName,
                    "roomId": roomCode,
                    "createdAt": FieldValue.serverTimestamp(),
                    "expiresAt": Timestamp(date: Date().addingTimeInterval(10 * 60))
                ])
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    func dismissInvitation(_ invitation: TableInvitation) async {
        guard let user = Auth.auth().currentUser else { return }
        try? await database.collection("invites")
            .document(user.uid)
            .collection("items")
            .document(invitation.id)
            .delete()
    }

    func clearError() {
        errorMessage = nil
    }

    private func saveProfile(user: User, avatarIndex: Int) async {
        let reference = database.collection("users").document(user.uid)
        do {
            let snapshot = try await reference.getDocument()
            let existing = snapshot.data()
            let profileSnapshot = try await database.collection("profiles").document(user.uid).getDocument()
            let modernProfile = profileSnapshot.data()
            let generatedCode = existing?["friendCode"] as? String ?? Self.makeFriendCode()
            let storedName = modernProfile?["username"] as? String
                ?? existing?["displayName"] as? String
            let resolvedName = storedName == "\u{4A}\u{6F}\u{75}\u{65}\u{75}\u{72}"
                ? "Player"
                : storedName
                    ?? user.displayName
                    ?? user.email?.components(separatedBy: "@").first
                    ?? "Player"

            friendCode = generatedCode
            displayName = resolvedName
            isAuthenticatedProfile = !user.isAnonymous

            try await reference.setData([
                "displayName": resolvedName,
                "friendCode": generatedCode,
                "avatarIndex": avatarIndex,
                "providerIDs": user.providerData.map(\.providerID),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    private func loadFriends() async {
        guard let user = Auth.auth().currentUser else { return }
        do {
            let snapshot = try await database.collection("friends").document(user.uid)
                .collection("items").getDocuments()
            let friendIDs = snapshot.documents.map(\.documentID)
            var loadedFriends: [DominoFriend] = []
            for friendID in friendIDs {
                let friendSnapshot = try await database.collection("profiles").document(friendID).getDocument()
                guard let data = friendSnapshot.data() else { continue }
                loadedFriends.append(
                    DominoFriend(
                        id: friendID,
                        displayName: data["username"] as? String ?? "Player",
                        friendCode: data["usernameKey"] as? String ?? "",
                        avatarIndex: Self.avatarIndex(data["avatarId"] as? String)
                    )
                )
            }
            friends = loadedFriends.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    private func observeFriendRequests() {
        guard let user = Auth.auth().currentUser else { return }
        friendRequestsListener?.remove()
        friendRequestsListener = database.collection("friendRequests")
            .whereField("toUid", isEqualTo: user.uid)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = self.firebaseMessage(error)
                        return
                    }
                    self.friendRequests = snapshot?.documents.compactMap { document in
                        let data = document.data()
                        guard data["status"] as? String == "pending" else { return nil }
                        guard let senderID = data["fromUid"] as? String,
                              let senderName = data["fromName"] as? String else {
                            return nil
                        }
                        return FriendRequest(
                            id: document.documentID,
                            senderID: senderID,
                            senderName: senderName,
                            senderAvatarIndex: Self.avatarIndex(data["fromAvatar"] as? String)
                        )
                    } ?? []
                }
            }
    }

    private func observeInvitations() {
        guard let user = Auth.auth().currentUser else { return }
        invitationsListener?.remove()
        invitationsListener = database.collection("invites")
            .document(user.uid)
            .collection("items")
            .limit(to: 30)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.invitations = snapshot?.documents.map { document in
                        let data = document.data()
                        return TableInvitation(
                            id: document.documentID,
                            roomCode: data["roomId"] as? String ?? document.documentID,
                            senderName: data["fromName"] as? String ?? "A friend"
                        )
                    } ?? []
                }
            }
    }

    private func firebaseMessage(_ error: Error) -> String {
        if let accountError = error as? AccountError {
            return accountError.description
        }
        return error.localizedDescription
    }

    private static func makeFriendCode() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }

    private static func avatarID(_ index: Int) -> String {
        String(format: "classic_%02d", max(0, index) + 1)
    }

    private static func avatarIndex(_ id: String?) -> Int {
        guard let id, let number = Int(id.split(separator: "_").last ?? "1") else { return 0 }
        return max(0, number - 1)
    }

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonce(length: Int = 32) throws -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else {
                throw AccountError.message("Unable to secure Apple Sign-In.")
            }

            for byte in bytes where remaining > 0 {
                guard byte < characters.count else { continue }
                result.append(characters[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }
}

private enum AccountError: LocalizedError {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): text
        }
    }

    var errorDescription: String? { description }
}

struct AccountAuthenticationView: View {
    let model: AppModel

    private var account: AccountService {
        model.account
    }

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                account.prepareAppleRequest(request)
            } onCompletion: { result in
                Task {
                    await account.completeAppleSignIn(
                        result,
                        avatarIndex: model.selectedAvatarIndex
                    )
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(.capsule)

            Button {
                Task {
                    await account.signInWithGoogle(avatarIndex: model.selectedAvatarIndex)
                }
            } label: {
                Label("Continue with Google", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 360)
    }
}
