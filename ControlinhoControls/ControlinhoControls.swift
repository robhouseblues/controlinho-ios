import AppIntents
import SwiftUI
import WidgetKit

/// Control Center controls for the paired TV. They also fit the Lock Screen's bottom
/// corners and the Action button.
@main
struct ControlinhoControls: WidgetBundle {
    var body: some Widget {
        PowerControl()
        VolumeUpControl()
        VolumeDownControl()
        MuteControl()
    }
}

struct PowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.robhouseblues.controlinho.power") {
            ControlWidgetButton(action: PowerIntent()) {
                Label("TV Power", systemImage: "power")
            }
        }
        .displayName("TV Power")
        .description("Turns your Samsung TV on or off.")
    }
}

struct VolumeUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.robhouseblues.controlinho.volume-up") {
            ControlWidgetButton(action: SendKeyIntent(key: .volumeUp)) {
                Label("TV Volume Up", systemImage: "speaker.plus.fill")
            }
        }
        .displayName("TV Volume Up")
        .description("Turns your Samsung TV's volume up.")
    }
}

struct VolumeDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.robhouseblues.controlinho.volume-down") {
            ControlWidgetButton(action: SendKeyIntent(key: .volumeDown)) {
                Label("TV Volume Down", systemImage: "speaker.minus.fill")
            }
        }
        .displayName("TV Volume Down")
        .description("Turns your Samsung TV's volume down.")
    }
}

struct MuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.robhouseblues.controlinho.mute") {
            ControlWidgetButton(action: SendKeyIntent(key: .mute)) {
                Label("TV Mute", systemImage: "speaker.slash.fill")
            }
        }
        .displayName("TV Mute")
        .description("Mutes or unmutes your Samsung TV.")
    }
}
