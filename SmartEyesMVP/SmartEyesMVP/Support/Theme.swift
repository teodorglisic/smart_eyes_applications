import SwiftUI

/// Centralized color palette for Smart Eyes' dark/light appearance. Construct with the
/// current `colorScheme` and read off whichever color you need — keeps every screen's
/// palette in sync instead of each view redefining (and risking drifting from) its own copy.
///
/// Usage in a view:
/// ```
/// @Environment(\.colorScheme) var colorScheme
/// private var theme: Theme { Theme(colorScheme: colorScheme) }
/// ...
/// .foregroundColor(theme.primaryTextColor)
/// ```
struct Theme {
    let colorScheme: ColorScheme

    var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.1, green: 0.12, blue: 0.16)
    }

    var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : Color(red: 0.45, green: 0.47, blue: 0.52)
    }

    var mainBgColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.12) : Color(red: 0.96, green: 0.97, blue: 0.98)
    }

    var panelBgColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.18) : Color.white
    }

    var secondaryPanelBgColor: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.17, blue: 0.22) : Color(red: 0.91, green: 0.92, blue: 0.95)
    }

    var panelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    var textBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }
}
