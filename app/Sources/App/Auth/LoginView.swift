import SwiftUI

/// Экран входа — `POST /api/auth/login` с email/паролем владельца
/// (spec/API.md §2.1: беспарольный LAN-вход «для нативного клиента НЕ
/// ПОДХОДИТ», сервер пускает только запросы, «похожие на браузер»).
///
/// Учётные данные нигде не зашиты и не выдуманы — их вводит владелец при
/// первом запуске; сессия дальше живёт 30 дней в Keychain (`KeychainService`).
struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges — не `.background(...)`
        // на внутреннем контейнере, до угла клавиатуры он не достаёт.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            loginForm
        }
    }

    private var loginForm: some View {
        VStack(spacing: TFSpacing.xl) {
            Spacer()

            VStack(spacing: TFSpacing.xs) {
                Text("TaskFlow")
                    .tfText(.titleLarge)
                    .foregroundStyle(Color.tfText)
                Text("Войдите под своей учётной записью")
                    .tfText(.body)
                    .foregroundStyle(Color.tfSub)
            }

            VStack(spacing: TFSpacing.md) {
                // Логин, а не почта: сервер с 01.09.2026 принимает и имя
                // учётки, и короткое имя из почты (просьба Максима — «можно
                // не имейл, а просто логин»). Почта тоже подходит, поэтому
                // подпись говорит про оба варианта.
                TFTextField("Логин или почта", text: $email, icon: "person")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                // `DesignSystem` пока не даёт secure-вариант `TFTextField` —
                // а пароль открытым текстом на экране входа это не «мелкая
                // деталь на потом», заводить его здесь, своими силами, теми
                // же токенами (не трогая сам `DesignSystem`).
                SecurePasswordField(placeholder: "Пароль", text: $password)
            }

            TFErrorBanner(session.errorMessage, variant: .block)

            TFButton(
                isSubmitting ? "Входим…" : "Войти",
                variant: .primary,
                isEnabled: !isSubmitting && !email.isEmpty && !password.isEmpty
            ) {
                Task {
                    isSubmitting = true
                    await session.login(email: email, password: password)
                    isSubmitting = false
                }
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, TFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Локальная замена `TFTextField` только для пароля — тот же вид (иконка,
/// отступы, карточка, радиус — все токены `DesignSystem`), но `SecureField`
/// вместо `TextField`. Живёт в `App/`, а не в `DesignSystem/`: пока это
/// единственное место, где нужен secure-ввод, заводить компонент в чужой,
/// сейчас read-only для меня, папке — не мой вызов.
private struct SecurePasswordField: View {
    let placeholder: String
    @Binding var text: String

    /// 14.09.2026, Dynamic Type: как и в `TFTextField` — рост вместо обрезки.
    @ScaledMetric(relativeTo: .callout) private var minHeight: CGFloat = TFField.height
    @ScaledMetric(relativeTo: .callout) private var iconSize: CGFloat = TFIconSize.sm

    var body: some View {
        HStack(spacing: TFField.iconTextGap) {
            Image(systemName: "lock")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.tfDim)
            SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.tfDim))
                .tfText(.input)
                .foregroundStyle(Color.tfText)
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: minHeight)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
    }
}
