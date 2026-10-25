//
//  PopupView.swift
//  Boop
//

import AppKit
import SwiftUI

struct PopupView: View {
    @Bindable var controller: PopupController

    var body: some View {
        VStack(spacing: 0) {
            if let error = controller.errorMessage {
                errorView(error)
            }
            list
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(controller.menuItems.enumerated()), id: \.element.id) { index, action in
                        row(action, index: index)
                            .id(index)
                    }
                }
                .padding(6)
            }
            .onChange(of: controller.highlightedIndex) { _, index in
                proxy.scrollTo(index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(controller.original.isEmpty)
    }

    private func row(_ action: RewriteAction, index: Int) -> some View {
        let isHighlighted = index == controller.highlightedIndex
        let isRunning = controller.runningAction?.id == action.id
        return Button {
            controller.run(action)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: action.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(action.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else if isHighlighted {
                    Image(systemName: "return")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.primary.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(controller.isRunning)
        .onHover { hovering in
            if hovering, !controller.isRunning { controller.highlight(index) }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
