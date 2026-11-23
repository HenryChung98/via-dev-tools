import SwiftUI
import CoreHaptics

struct HapticsView: View {
    @State private var feedback: SensoryFeedback?
    @State private var count = 0

    var body: some View {
        List {
            Section("Impact") {
                play("Light", .impact(weight: .light))
                play("Medium", .impact(weight: .medium))
                play("Heavy", .impact(weight: .heavy))
                play("Soft", .impact(flexibility: .soft))
                play("Rigid", .impact(flexibility: .rigid))
                play("Solid", .impact(flexibility: .solid))
            }
            Section("Notification") {
                play("Success", .success)
                play("Warning", .warning)
                play("Error", .error)
            }
            Section {
                // .alignment, .levelChange, .pathComplete omitted: no haptic on iPhone
                play("Selection", .selection)
            } header: {
                Text("Other")
            } footer: {
                if !CHHapticEngine.capabilitiesForHardware().supportsHaptics {
                    Text("This device does not support haptics.")
                }
            }
        }
        .navigationTitle("Haptics")
        .sensoryFeedback(trigger: count) { _, _ in feedback }
    }

    private func play(_ title: LocalizedStringKey, _ f: SensoryFeedback) -> some View {
        Button(title) {
            feedback = f
            count += 1
        }
    }
}
