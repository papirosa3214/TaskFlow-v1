import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

// Голосовой композер повторяет утверждённый VoiceMessageLabScreen.
struct ChatComposer: View {
    @Bindable var viewModel: ChatViewModel
    @State private var isFileImporterPresented = false
    /// Меню «+» (владелец 26.09.2026): фото/файл/камера.
    @State private var isPhotoPickerPresented = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var voice = RoleChatVoiceController()
    @State private var uploadedVoiceID: String?

    private let H: CGFloat = TFChatComposer.elementHeight

    var body: some View {
        VStack(spacing: 0) {
            TFErrorBanner(viewModel.uploadErrorMessage.map { _ in "Не удалось приложить файл" })
                .padding(.horizontal, TFSpacing.lg)
                .padding(.bottom, viewModel.uploadErrorMessage == nil ? 0 : TFSpacing.sm)
            TFErrorBanner(viewModel.sendErrorMessage.map { _ in "Не удалось отправить сообщение" })
                .padding(.horizontal, TFSpacing.lg)
                .padding(.bottom, viewModel.sendErrorMessage == nil ? 0 : TFSpacing.sm)
            TFErrorBanner(voice.errorMessage)
                .padding(.horizontal, TFSpacing.lg)
                .padding(.bottom, voice.errorMessage == nil ? 0 : TFSpacing.sm)

            if !viewModel.pendingAttachments.isEmpty {
                VStack(spacing: 4) {
                    ForEach(viewModel.pendingAttachments) { attachment in
                        pendingChip(attachment)
                    }
                }
                .padding(.horizontal, TFSpacing.lg)
                .padding(.bottom, TFSpacing.sm)
            }

            if viewModel.activeChannel != .owner {
                addresseeSlot
                    .padding(.horizontal, TFSpacing.lg)
            }
            ChatVoiceComposer(
                text: $viewModel.draftText,
                placeholder: placeholder,
                canSendText: viewModel.canSend,
                voice: voice,
                onAttachmentSource: { source in
                    switch source {
                    case .photo: isPhotoPickerPresented = true
                    case .file: isFileImporterPresented = true
                    case .camera: isCameraPresented = true
                    }
                },
                onSendText: { Task { await viewModel.send() } },
                onSendVoice: sendVoice,
                onDiscardVoice: discardVoice
            )
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .pdf, .plainText, .text, .item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            photoPickerItem = nil
            Task { await uploadPickedPhoto(item) }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(
                onCapture: { image in
                    isCameraPresented = false
                    Task { await uploadCameraPhoto(image) }
                },
                onCancel: { isCameraPresented = false }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Адресат

    @ViewBuilder
    private var addresseeSlot: some View {
        if viewModel.activeChannel == .owner {
            // Собеседник один и постоянный — лицо вместо кнопки выбора (не кликабельно).
            ZStack {
                RoundedRectangle(cornerRadius: TFRadius.lg).fill(Color.tfCard2)
                if let counterpart = viewModel.counterpart {
                    TFAvatar(
                        size: .md,
                        initials: counterpart.initials ?? "?",
                        tint: Color(hex: counterpart.avatarColor ?? TFHexDefault.unassigned),
                        userID: counterpart.id
                    )
                }
            }
            .frame(width: H, height: H)
        } else {
            Button {
                viewModel.isAddresseeMenuOpen.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: TFRadius.lg)
                        .fill(addresseeBackground)
                        .overlay {
                            if case .none = viewModel.addressee {
                                RoundedRectangle(cornerRadius: TFRadius.lg)
                                    .strokeBorder(Color.tfRed, style: StrokeStyle(lineWidth: TFBorder.width, dash: [4]))
                            }
                        }
                    Image(systemName: addresseeIsAll ? "person.2.fill" : "cpu")
                        .font(.system(size: 18))
                        .foregroundStyle(addresseeForeground)
                }
                .frame(width: H, height: H)
            }
            .buttonStyle(TFTapScaleStyle())
            .popover(isPresented: $viewModel.isAddresseeMenuOpen) {
                addresseeMenu
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var addresseeIsAll: Bool { viewModel.addressee == .all }

    private var addresseeBackground: Color {
        switch viewModel.addressee {
        case .user: return .tfRed
        case .all: return .tfCard2
        case .none: return .tfCard
        }
    }

    private var addresseeForeground: Color {
        switch viewModel.addressee {
        case .user: return .white
        case .all: return .tfText
        case .none: return .tfRed
        }
    }

    private var addresseeMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuItem(label: "Всем", isSelected: addresseeIsAll) {
                viewModel.addressee = .all
                viewModel.isAddresseeMenuOpen = false
            }
            ForEach(viewModel.others) { participant in
                menuItem(label: participant.name, isSelected: isSelected(participant)) {
                    viewModel.addressee = .user(id: participant.id, name: participant.name)
                    viewModel.isAddresseeMenuOpen = false
                }
            }
        }
        .padding(.vertical, TFSpacing.xs)
        .frame(minWidth: 200)
    }

    private func isSelected(_ participant: ApiChatParticipant) -> Bool {
        if case .user(let id, _) = viewModel.addressee { return id == participant.id }
        return false
    }

    private func menuItem(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: isSelected ? "checkmark" : "cpu")
                    .font(.system(size: TFIconSize.xs))
                    .foregroundStyle(Color.tfRed)
                    .frame(width: 18)
                Text(label).tfText(.row).foregroundStyle(Color.tfText)
                Spacer()
            }
            .padding(.horizontal, TFSpacing.md)
            .frame(height: TFHitTarget.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
    }

    private var placeholder: String {
        switch viewModel.addressee {
        case .user(_, let name) where viewModel.activeChannel != .owner:
            return "\(name)…"
        case .all:
            return "Всем…"
        default:
            if viewModel.activeChannel == .owner, let counterpart = viewModel.counterpart {
                return "\(counterpart.name)…"
            }
            return "Кому? выбери адресата"
        }
    }

    private func sendVoice(_ recording: VoiceMessage) async -> Bool {
        let text: String
        if case .ready(let recognized) = recording.transcript { text = recognized }
        else { text = "" }
        if uploadedVoiceID == nil {
            guard let data = try? Data(contentsOf: recording.audioURL) else {
                voice.fail("Не удалось прочитать запись")
                return false
            }
            let previousCount = viewModel.pendingAttachments.count
            await viewModel.attach(fileName: recording.audioURL.lastPathComponent, data: data, mime: "application/octet-stream")
            guard viewModel.pendingAttachments.count > previousCount else { return false }
            uploadedVoiceID = viewModel.pendingAttachments.last?.id
            viewModel.draftText = [viewModel.draftText, text].filter { !$0.isEmpty }.joined(separator: " ")
        }
        await viewModel.send()
        guard viewModel.sendErrorMessage == nil else { return false }
        uploadedVoiceID = nil
        try? VoiceRecorder.cancelRecordingFile(at: recording.audioURL)
        return true
    }

    private func discardVoice(_ recording: VoiceMessage) {
        if let id = uploadedVoiceID {
            Task { await viewModel.removePendingAttachment(id) }
            uploadedVoiceID = nil
        }
    }

    // MARK: - Вложения

    private func pendingChip(_ attachment: ApiChatAttachment) -> some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: "paperclip")
                .font(.system(size: 13))
                .foregroundStyle(Color.tfSub)
            Text(attachment.fileName)
                .tfText(.meta)
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                Task { await viewModel.removePendingAttachment(attachment.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: TFIconSize.xs))
                    .foregroundStyle(Color.tfDim)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Закрыть")
            .buttonStyle(TFTapScaleStyle())
        }
        .padding(.horizontal, TFSpacing.md)
        .frame(height: TFHitTarget.min)
        .background(Color.tfCard2)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            await viewModel.attach(fileName: url.lastPathComponent, data: data, mime: mime)
        }
    }

    /// Фото из галереи (владелец 26.09.2026) — пережимаем в JPEG, как и снимок камерой.
    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        await viewModel.attach(fileName: "photo.jpg", data: jpeg, mime: "image/jpeg")
    }

    /// Снимок камерой (владелец 26.09.2026).
    private func uploadCameraPhoto(_ image: UIImage) async {
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        await viewModel.attach(fileName: "camera.jpg", data: jpeg, mime: "image/jpeg")
    }
}
