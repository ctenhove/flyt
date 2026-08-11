//
//  FetchingSkeleton.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// Pulsing placeholder blocks shown while metadata is being fetched
/// (README §3.3): opacity 1 → 0.55 → 1, repeating.
struct FetchingSkeleton: View {
    @State private var isDimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.flytDivider)
                    .frame(width: 120, height: 68)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.flytDivider)
                        .frame(maxWidth: .infinity)
                        .frame(height: 13)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.flytDividerLight)
                        .frame(width: 150, height: 11)
                }
                .padding(.top, 4)
            }
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.flytDividerLight)
                .frame(height: 44)
            HStack {
                Spacer()
                Text("Reading video details…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.flytSkyTint)
                Spacer()
            }
            .frame(height: 48)
            .background(Color.flytSkyWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .opacity(isDimmed ? 0.55 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        }
    }
}
