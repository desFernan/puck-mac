//
//  ImagePreviewView.swift
//  Puck
//
//  Shown instead of CodeEditorHostView for image tabs -- WorkspaceFileService
//  hands back a data: URL (see readImagePreview), decoded here into an NSImage.
//

import SwiftUI

struct ImagePreviewView: View {
    let tab: EditorTab

    var body: some View {
        VStack(spacing: ClientTheme.Metrics.spacingMedium) {
            if let previewUrl = tab.previewUrl, let image = Self.decode(previewUrl) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(ClientTheme.Metrics.spacingLarge)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
            Text((tab.path as NSString).lastPathComponent)
                .font(ClientTheme.Typography.mono)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func decode(_ dataURL: String) -> NSImage? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}
