import SwiftUI
import UIKit

private struct OverlineKeyboardDismissToolbarModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isEnabled {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()

                        Button(action: dismissKeyboard) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("키보드 닫기")
                    }
                }
            }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    func overlineKeyboardDismissToolbar(isEnabled: Bool = true) -> some View {
        modifier(OverlineKeyboardDismissToolbarModifier(isEnabled: isEnabled))
    }
}
