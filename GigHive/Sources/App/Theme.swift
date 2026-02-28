import SwiftUI

enum GHTheme {
    static let bg = Color(red: 0x0b/255, green: 0x10/255, blue: 0x20/255)
    static let card = Color(red: 0x12/255, green: 0x1a/255, blue: 0x33/255)
    static let cardBorder = Color(red: 0x1d/255, green: 0x2a/255, blue: 0x55/255)
    static let text = Color(red: 0xe9/255, green: 0xee/255, blue: 0xf7/255)
    static let muted = Color(red: 0xa8/255, green: 0xb3/255, blue: 0xcf/255)
    static let accent = Color(red: 0xEB/255, green: 0xB0/255, blue: 0x00/255)
    static let caret = Color.green
}

// MARK: - Compatibility helpers
extension View {
    @ViewBuilder
    func ghForeground(_ color: Color) -> some View {
        if #available(iOS 15.0, *) {
            self.foregroundStyle(color)
        } else {
            self.foregroundColor(color)
        }
    }

    @ViewBuilder
    func ghBackgroundMaterial(fallback: Color = GHTheme.card.opacity(0.2)) -> some View {
        if #available(iOS 15.0, *) {
            self.background(.ultraThinMaterial)
        } else {
            self.background(fallback)
        }
    }

    @ViewBuilder
    func ghTint(_ color: Color) -> some View {
        if #available(iOS 15.0, *) {
            self.tint(color)
        } else {
            self.accentColor(color)
        }
    }

    @ViewBuilder
    func ghFullScreenBackground(_ color: Color) -> some View {
        if #available(iOS 15.0, *) {
            self.background(color.ignoresSafeArea())
        } else {
            self.background(color).edgesIgnoringSafeArea(.all)
        }
    }

    // Text input capitalization helpers
    @ViewBuilder
    func ghNoAutocapitalization() -> some View {
        if #available(iOS 15.0, *) {
            self.textInputAutocapitalization(.never)
        } else {
            self.autocapitalization(.none)
        }
    }

    @ViewBuilder
    func ghWordsAutocap() -> some View {
        if #available(iOS 15.0, *) {
            self.textInputAutocapitalization(.words)
        } else {
            self.autocapitalization(.words)
        }
    }
}

// Custom TextField wrapper that disables input accessory to prevent Auto Layout warnings
struct NoAccessoryTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var textContentType: UITextContentType? = nil
    var font: UIFont = .systemFont(ofSize: 13)
    var textColor: UIColor = UIColor(red: 0xe9/255, green: 0xee/255, blue: 0xf7/255, alpha: 1.0)
    var tintColor: UIColor = .green
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType
        if let tct = textContentType {
            textField.textContentType = tct
        }
        textField.font = font
        textField.textColor = textColor
        textField.tintColor = tintColor
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        
        // Disable input accessory view to prevent Auto Layout warnings
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Preserve normal iOS cursor/selection behavior while the user is editing.
        // If SwiftUI pushes text updates into an active UITextField, UIKit often resets the selection.
        guard !uiView.isFirstResponder else { return }
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NoAccessoryTextField
        var isUpdatingFromUserInput = false
        
        init(_ parent: NoAccessoryTextField) {
            self.parent = parent
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            // Removed redundant update - textField(_:shouldChangeCharactersIn:) handles updates
            // This was causing cursor to jump to end when backspacing
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if let text = textField.text,
               let textRange = Range(range, in: text) {
                let updatedText = text.replacingCharacters(in: textRange, with: string)
                isUpdatingFromUserInput = true
                parent.text = updatedText
                isUpdatingFromUserInput = false
            }
            return true
        }
    }
}

// Custom SecureField wrapper that disables input accessory to prevent Auto Layout warnings
struct NoAccessorySecureField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var textContentType: UITextContentType? = .password
    var font: UIFont = .systemFont(ofSize: 13)
    var textColor: UIColor = UIColor(red: 0xe9/255, green: 0xee/255, blue: 0xf7/255, alpha: 1.0)
    var tintColor: UIColor = .green
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType
        if let tct = textContentType {
            textField.textContentType = tct
        }
        textField.font = font
        textField.textColor = textColor
        textField.tintColor = tintColor
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.isSecureTextEntry = true
        
        // Disable input accessory view to prevent Auto Layout warnings
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NoAccessorySecureField
        
        init(_ parent: NoAccessorySecureField) {
            self.parent = parent
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if let text = textField.text,
               let textRange = Range(range, in: text) {
                let updatedText = text.replacingCharacters(in: textRange, with: string)
                parent.text = updatedText
            }
            return true
        }
    }
}

struct GHCard<Content: View>: View {
    let content: () -> Content
    let pad: CGFloat
    init(pad: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.pad = pad
        self.content = content
    }
    var body: some View {
        content()
            .padding(pad)
            .background(GHTheme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.cardBorder, lineWidth: 1))
            .cornerRadius(16)
    }
}

struct GHLabel: View {
    let text: String
    var body: some View { Text(text).font(.caption2).ghForeground(GHTheme.muted) }
}

struct GHButtonStyle: ButtonStyle {
    var color: Color = GHTheme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .ghForeground(GHTheme.text)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color, lineWidth: 1.5)
                    .background(configuration.isPressed ? GHTheme.card.opacity(0.6) : GHTheme.card.opacity(0.3))
            )
            .cornerRadius(10)
    }
}
