import SwiftUI
import UIKit

struct ClipThumbnail: View {
    let clip: PastrClip

    var body: some View {
        if let imageData = clip.imageData,
           let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            generatedThumbnail
        }
    }

    @ViewBuilder
    private var generatedThumbnail: some View {
        switch clip.thumbnailName {
        case "map":
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.green.opacity(0.28), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Path { path in
                    path.move(to: CGPoint(x: 12, y: 38))
                    path.addLine(to: CGPoint(x: 74, y: 14))
                    path.addLine(to: CGPoint(x: 130, y: 46))
                }
                .stroke(.white.opacity(0.8), lineWidth: 5)
                Circle()
                    .fill(.orange)
                    .frame(width: 18, height: 18)
                    .overlay(Image(systemName: "cup.and.saucer.fill").font(.system(size: 8)).foregroundStyle(.white))
            }
        case "bridge":
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [.orange.opacity(0.55), .purple.opacity(0.35), .blue.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    Image(systemName: "bridge")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.78))
                )
        default:
            RoundedRectangle(cornerRadius: 10)
                .fill(PastrTheme.tint(clip.tintName).opacity(0.14))
                .overlay(
                    Image(systemName: clip.type.symbolName)
                        .foregroundStyle(PastrTheme.tint(clip.tintName))
                )
        }
    }
}
