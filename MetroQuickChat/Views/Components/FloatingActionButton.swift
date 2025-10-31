import SwiftUI

struct FloatingActionButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.title2)
                .padding(16)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(radius: 8)
        }
        .buttonStyle(.plain)
    }
}

struct FloatingActionButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            FloatingActionButton(action: {}) { Image(systemName: "plus") }
                .padding()
        }
        .preferredColorScheme(.dark)
    }
}


