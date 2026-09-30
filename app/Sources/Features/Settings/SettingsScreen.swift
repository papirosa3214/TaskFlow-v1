import SwiftUI

/// `/settings` — spec/SCREENS-2.md §6. Дерево настроек: профиль, тема/
/// биометрия/иконка, ИИ, общие разделы-переходы, сервер, выход.
///
/// Шапка — `SettingsHeaderChrome` (своя композиция, не `TFScreenHeader`):
/// см. комментарий в файле компонента — веб держит здесь `variant="large"`
/// (по умолчанию) СО стрелкой «назад» (правило добавлено в
/// `ScreenHeader.tsx` 27.08.2026), а нативный `TFScreenHeader.large` стрелку
/// не рисует вовсе — гэп, не мой файл чинить.
struct SettingsScreen: View {
    @State private var appIconSheetOpen = false
    @State private var appIcon: AppIconOption = .current
    @Environment(SessionStore.self) private var session
    @State private var viewModel = SettingsViewModel()
    @State private var profileOverride: ApiUser?
    @State private var isEditProfilePresented = false
    @AppStorage("settings.user.expanded") private var userSettingsExpanded = true
    @AppStorage("settings.ai.expanded") private var aiExpanded = true
    @AppStorage(SecretaryVoice.storageKey) private var secretaryVoice = SecretaryVoice.default.rawValue
    @AppStorage("settings.general.expanded") private var generalExpanded = true
    @AppStorage("settings.server.expanded") private var serverExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.xl) {
                    accountSection
                    userSettingsSection
                    aiSection
                    generalSection
                    serverSection
                    signOutSection
                }
                .padding(.vertical, TFSpacing.lg)
            }
        }
        // Своя шапка уже несёт заголовок и кнопку «назад» — системный навбар
        // поверх неё давал ВТОРУЮ стрелку и лишнюю полосу.
        // Нативная сворачивающаяся шапка по официальным гайдам SwiftUI.
        .tfNativeHeader("Настройки")
        .background(Color.tfBackground)
        .environment(viewModel)
        .tfBottomSheet(isPresented: $isEditProfilePresented) {
            if let user = displayedUser {
                EditProfileSheet(
                    user: user,
                    avatarURLOverride: profileOverride?.avatarUrl,
                    settings: viewModel,
                    onSaved: { updated in profileOverride = updated },
                    onAvatarChanged: { newURL in patchAvatarURL(newURL, baseUser: user) }
                )
            }
        }
        .tfBottomSheet(isPresented: $appIconSheetOpen) {
            AppIconPickerSheet(selection: $appIcon) { appIconSheetOpen = false }
        }
    }

    private var displayedUser: ApiUser? { profileOverride ?? session.currentUser }

    @ViewBuilder
    private var accountSection: some View {
        Group {
            if let user = displayedUser {
                ProfileAccountRow(
                    user: user,
                    avatarURLOverride: profileOverride?.avatarUrl,
                    onEdit: { isEditProfilePresented = true },
                    onAvatarChanged: { newURL in patchAvatarURL(newURL, baseUser: user) }
                )
            } else {
                TFListRow(icon: "person", iconStyle: .plain, title: "Аккаунт")
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Общий патч локального вида после смены/удаления фото — переиспользуют
    /// и строка профиля (тап по аватарке), и шторка «Изменить» (кнопка
    /// «Убрать фото», просьба владельца 03.09.2026 — см. `EditProfileSheet`).
    /// `SessionStore.currentUser` не обновляем (нет публичного сеттера),
    /// только локальный вид (`profileOverride`).
    private func patchAvatarURL(_ newURL: String?, baseUser: ApiUser) {
        let patched = displayedUser ?? baseUser
        profileOverride = ApiUser(
            id: patched.id, name: patched.name, email: patched.email,
            role: patched.role, type: patched.type, avatarColor: patched.avatarColor,
            initials: patched.initials, status: patched.status, createdAt: patched.createdAt,
            isSystemBot: patched.isSystemBot, createdBy: patched.createdBy,
            avatarUrl: newURL?.isEmpty == false ? newURL : nil,
            avatarUrlWorking: patched.avatarUrlWorking, avatarUrlBlocked: patched.avatarUrlBlocked,
            lastSeenAt: patched.lastSeenAt, activity: patched.activity, online: patched.online,
            lastAction: patched.lastAction, lastActionTitle: patched.lastActionTitle, limits: patched.limits
        )
    }

    @ViewBuilder
    private var userSettingsSection: some View {
        section(title: "Пользовательские настройки", isExpanded: $userSettingsExpanded) {
            toggleRow(icon: "moon", title: "Тема", isOn: $viewModel.isDarkTheme)
            if viewModel.isBiometryAvailable {
                TFDivider(inset: rowDividerInset)
                toggleRow(icon: viewModel.biometryKind == .faceID ? "faceid" : "touchid", title: viewModel.biometryLabel, isOn: $viewModel.isBiometryEnabled)
            }
            TFDivider(inset: rowDividerInset)
            Button {
                appIconSheetOpen = true
            } label: {
                TFListRow(icon: "photo", iconStyle: .plain, title: "Иконка",
                          trailing: AnyView(editAction), titleStyle: .action,
                          verticalPadding: TFSpacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.app-icon")
            TFDivider(inset: rowDividerInset)
            toggleRow(icon: "keyboard", title: "Своя клавиатура", isOn: $viewModel.isCustomKeyboardEnabled)
        }
    }

    @ViewBuilder
    /// LOCK-179: ИИ разделён на СЕРВЕРНЫЙ (провайдеры и модели Pi) и
    /// ЛОКАЛЬНЫЙ («На устройстве»). Раньше единственная строка вела в
    /// `VoiceModelsScreen` — локальные модели; теперь это разные пункты.
    private var aiSection: some View {
        section(title: "Искусственный интеллект", isExpanded: $aiExpanded) {
            navRow(icon: "cpu", title: "Агенты (модели и провайдеры)", route: .runtimeProviders)
            TFDivider(inset: rowDividerInset)
            navRow(icon: "iphone", title: "Приложение (телефон и сервер)", route: .voiceModels)
            TFDivider(inset: rowDividerInset)
            NavigationLink(value: AppRoute.secretaryVoicePicker) {
                TFListRow(icon: "waveform", iconStyle: .plain, title: "Голос Секретаря",
                          trailing: AnyView(secretaryVoiceValue), titleStyle: .action,
                          verticalPadding: TFSpacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.secretary-voice")
        }
    }

    /// Текущий голос + шеврон: выбор и прослушивание — на отдельном экране.
    private var secretaryVoiceValue: some View {
        HStack(spacing: TFSpacing.sm) {
            Text(secretaryVoice).tfText(.body).foregroundStyle(Color.tfSub)
            chevron
        }
    }

    @ViewBuilder
    private var generalSection: some View {
        section(title: "Общие", isExpanded: $generalExpanded) {
            navRow(icon: "bookmark", title: "Шаблоны задач", route: .templates)
            TFDivider(inset: rowDividerInset)
            navRow(icon: "tag", title: "Метки", route: .labels)
            TFDivider(inset: rowDividerInset)
            navRow(icon: "person.3.fill", title: "Команда", route: .agents)
            TFDivider(inset: rowDividerInset)
            navRow(icon: "link", title: "Интеграции (Google, Apple)", route: .integrations)
        }
    }

    @ViewBuilder
    /// LOCK-180/181: к серверным строкам добавлены «Pi Runtime» (статус
    /// рантайма) и «Service Accounts» (переехавшая из «Команды» механика
    /// ApiUser/токена).
    private var serverSection: some View {
        section(title: "Сервер", isExpanded: $serverExpanded) {
            if session.currentUser?.role == .owner {
                SystemControlSection()
                TFDivider(inset: rowDividerInset)
            }
            ServerStatusSection()
            TFDivider(inset: rowDividerInset)
            RuntimeStatusRow()
            TFDivider(inset: rowDividerInset)
            navRow(icon: "person.badge.key", title: "Сервер MCP", route: .serviceAccounts)
        }
    }

    @ViewBuilder
    private var signOutSection: some View {
        Button(role: .destructive) {
            session.logout()
        } label: {
            HStack {
                Text("Выйти")
                    .tfText(.body)
                    .foregroundStyle(Color.tfRed)
                Spacer()
            }
            .padding(.horizontal, TFSpacing.lg)
            .frame(minHeight: TFField.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    // MARK: - Общие строители строк

    private func section<Content: View>(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button { isExpanded.wrappedValue.toggle() } label: {
                Text(title)
                    .tfText(.body)
                    .foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded.wrappedValue ? "Развернут" : "Свернут")
            if isExpanded.wrappedValue {
                TFCard(padding: 0) { VStack(spacing: 0) { content() } }
                    .padding(.horizontal, TFSpacing.screenHorizontal)
            }
        }
    }

    private func navRow(icon: String, title: String, route: AppRoute) -> some View {
        NavigationLink(value: route) {
            TFListRow(icon: icon, iconStyle: .plain, title: title, trailing: AnyView(chevron), titleStyle: .action, verticalPadding: TFSpacing.xs)
        }
        .buttonStyle(.plain)
    }

    /// Шеврон рисуется вручную через `trailing`, а не через `action` у
    /// `TFListRow`: тап-зону и переход уже даёт обёртывающий `NavigationLink`,
    /// вложенный `Button` внутри него задвоил бы жест (см. INTEGRATION.md —
    /// переходы только `NavigationLink(value:)`).
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13))
            .foregroundStyle(Color.tfDim)
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        TFListRow(
            icon: icon, iconStyle: .plain, title: title,
            trailing: AnyView(TFToggle(isOn: isOn)),
            titleStyle: .action,
            verticalPadding: TFSpacing.xs
        )
    }

    private var editAction: some View {
        Text("Изменить")
            .tfText(.meta)
            .foregroundStyle(Color.tfText)
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, TFSpacing.xs)
            .background(Color.tfCard2)
            .overlay(RoundedRectangle(cornerRadius: TFRadius.md).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 40 + TFSpacing.md }
}
