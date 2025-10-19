//
//  ContentView.swift
//  Dropp
//
//  Created by Michael Yang on 10/19/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var shelf: Shelf
    @State private var isSettingsMenuPresented = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background
            backgroundColor
                .ignoresSafeArea()
                .zIndex(0)

            // Center icon (now half as big)
            Image(systemName: "tray.and.arrow.down")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconColor)
                .font(.system(size: 48, weight: .regular))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .zIndex(0)

            // Bottom-left gear menu
            Button {
                NSApp.activate(ignoringOtherApps: true)
                isSettingsMenuPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(iconColor)
                .padding(8)
            }
            .buttonStyle(.plain)
            .padding(10)
            .zIndex(2)

            if isSettingsMenuPresented {
                // Tap-catcher to dismiss by clicking outside the menu.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { isSettingsMenuPresented = false }
                    .zIndex(1)

                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        isSettingsMenuPresented = false
                        openAbout()
                    } label: {
                        Label("About Dropp", systemImage: "info.circle")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isSettingsMenuPresented = false
                        quitApp()
                    } label: {
                        Label("Quit Dropp", systemImage: "xmark.circle")
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.plain)
                .padding(14)
                .frame(width: 180, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                )
                .offset(x: 10, y: -48)
                .zIndex(2)
            }
        }
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        Color(.sRGB, red: 0.94, green: 0.92, blue: 0.90, opacity: 1.0)
    }

    private var iconColor: Color {
        Color(.sRGB, white: 0.35, opacity: 1.0)
    }

    // MARK: - Actions

    private func openAbout() {
        #if os(macOS)
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }

    private func quitApp() {
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(Shelf())
}
