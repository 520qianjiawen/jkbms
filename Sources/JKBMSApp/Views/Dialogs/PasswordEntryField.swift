import SwiftUI

/// Keeps the existing field location while giving its hit area a visible boundary.
struct PasswordEntryField: View {
    let title: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @State private var showsPassword = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if showsPassword { TextField(title, text: $text) }
                else { SecureField(title, text: $text) }
            }
            .textContentType(.password)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .onSubmit(onSubmit)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif

            Button {
                showsPassword.toggle()
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .foregroundColor(JKTheme.primaryBlue)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsPassword ? "隐藏密码" : "显示密码")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(JKTheme.primaryBlue.opacity(0.75), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }
}
