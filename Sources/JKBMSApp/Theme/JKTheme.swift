import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public enum JKTheme {
    public static let primaryBlue = Color(red: 3/255, green: 137/255, blue: 196/255)
    public static let secondaryBlue = Color(red: 18/255, green: 150/255, blue: 219/255)
    public static let darkBackground = Color(red: 24/255, green: 26/255, blue: 30/255)
    public static let cardBackground = Color(red: 33/255, green: 37/255, blue: 43/255)
    public static let cardBackgroundLight = Color(red: 245/255, green: 247/255, blue: 250/255)
    public static let successGreen = Color(red: 46/255, green: 204/255, blue: 113/255)
    public static let dangerRed = Color(red: 231/255, green: 76/255, blue: 60/255)
    public static let warningYellow = Color(red: 241/255, green: 196/255, blue: 15/255)
    public static let subtleText = Color(white: 0.6)

    public static func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    public static var appSystemBackground: Color {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    public static var appSecondarySystemBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    public static var appSystemGroupedBackground: Color {
        #if os(iOS)
        Color(UIColor.systemGroupedBackground)
        #else
        Color(NSColor.underPageBackgroundColor)
        #endif
    }

    public static var appSecondarySystemGroupedBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemGroupedBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }
}
