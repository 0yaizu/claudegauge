import SwiftUI

// メニューの項目の中のウィンドウは、キーウィンドウにならない。
// AppKit が描くコントロール (セグメント、チェックボックス) は、そのため「非アクティブ」の灰色で描かれ、
// 選択中の色も青にならない。SwiftUI で描いて、選択色を常にアクセントカラー (青) にする。

/// 押している間だけ、わずかに縮む。押したことが、すぐに伝わる。
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// セグメント型の選択。選ばれている項目が、アクセントカラーで塗られる。
struct SegmentedChoice<Value: Hashable>: View {
    struct Option {
        let label: String
        let value: Value
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(2)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(
                    isSelected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// チェックボックス。オンのときは、アクセントカラーで塗り、白いチェックを重ねる。
struct AccentCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                box(isOn: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityValue(configuration.isOn ? "on" : "off")
    }

    private func box(isOn: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return shape
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
            .overlay(shape.strokeBorder(isOn ? Color.clear : Color.primary.opacity(0.35), lineWidth: 1))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 15, height: 15)
            .animation(.easeOut(duration: 0.12), value: isOn)
    }
}
