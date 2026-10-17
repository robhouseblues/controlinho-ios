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
        PauseControl()
        OKControl()
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
            ControlWidgetButton(action: VolumeUpIntent()) {
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
            ControlWidgetButton(action: VolumeDownIntent()) {
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
            ControlWidgetButton(action: MuteIntent()) {
                Label("TV Mute", systemImage: "speaker.slash.fill")
            }
        }
        .displayName("TV Mute")
        .description("Mutes or unmutes your Samsung TV.")
    }
}

struct PauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.robhouseblues.controlinho.pause") {
            ControlWidgetButton(action: PauseIntent()) {
                Label("TV Pause", systemImage: "pause.fill")
            }
        }
        .displayName("TV Pause")
        .description("Pauses what's playing on your Samsung TV.")
    }
}

struct OKControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.robhouseblues.controlinho.ok") {
            ControlWidgetButton(action: OKIntent()) {
                Label("TV OK", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("TV OK")
        .description("Presses OK on your Samsung TV's remote.")
    }
}
