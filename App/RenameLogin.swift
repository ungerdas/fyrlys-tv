import FyrlysCore
import SwiftUI

/// «Gi nytt navn» på en innlogging («Hjemme», «Sport»), som i Fyrlys for Windows: et felt med navnet; tomt gir
/// «bruker på server» igjen. Høyst 40 tegn.
private struct RenameLoginAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var target: Login?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(L("Gi nytt navn"), isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) {
                TextField(L("Navn"), text: $name)
                    .accessibilityIdentifier("innlogging-navn")
                Button(L("Lagre")) {
                    if let target { model.rename(target, to: name) }
                    target = nil
                }
                .accessibilityIdentifier("lagre-navn")
                Button(L("Avbryt"), role: .cancel) { target = nil }
            } message: {
                Text(L("F.eks. Hjemme eller Sport. Tomt gir «{name}».", ["name": target?.defaultLabel ?? ""]))
            }
            .onChange(of: target?.id) { _, _ in
                name = target?.name ?? ""
            }
    }
}

extension View {
    /// Spør om et nytt navn på [target] når den settes.
    func renameLogin(_ target: Binding<Login?>) -> some View {
        modifier(RenameLoginAlert(target: target))
    }
}
