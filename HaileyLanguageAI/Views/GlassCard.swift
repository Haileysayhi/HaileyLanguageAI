//
//  GlassCard.swift
//  HaileyLanguageAI
//
//  Created by 郭蕙瑄 on 2026/6/15.
//

import SwiftUI

struct GlassCard<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
    }
}


#Preview {
    GlassCard {
        Text("Preview")
            .foregroundStyle(.blue)
    }
    .padding()
}
