import SwiftUI

struct TitleHeaderView: View {
    var title: String = "Gighive"
    var body: some View {
        HStack(spacing: 8) {
            Image("beelogo")
                .resizable()
                .scaledToFit()
                .frame(height: UIFont.preferredFont(forTextStyle: .title2).pointSize + 2)
            Text(title)
                .font(.title3).bold()
                .ghForeground(GHTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TitleHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        TitleHeaderView()
            .padding()
            .ghFullScreenBackground(GHTheme.bg)
    }
}
