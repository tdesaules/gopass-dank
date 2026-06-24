import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "gopassDank"

    StyledText {
        width: parent.width
        text: "Gopass-Dank"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Search and access gopass secrets from the launcher. Type the trigger followed by your search term."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "trigger"
        label: "Trigger"
        description: "Keyword to activate the plugin in the launcher"
        placeholder: "pass"
        defaultValue: "pass"
    }

    StringSetting {
        settingKey: "gopassBinary"
        label: "Gopass Binary"
        description: "Path to the gopass executable"
        placeholder: "gopass"
        defaultValue: "gopass"
    }

    SliderSetting {
        settingKey: "maxResults"
        label: "Max Results"
        description: "Maximum number of secrets to display in the launcher"
        defaultValue: 50
        minimum: 10
        maximum: 200
        unit: ""
    }

    ToggleSetting {
        settingKey: "autoRefresh"
        label: "Auto Refresh"
        description: "Periodically refresh the secret list in the background when the launcher opens"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "refreshIntervalSec"
        label: "Refresh Interval"
        description: "How often to refresh the vault cache when auto-refresh is enabled"
        defaultValue: 300
        minimum: 60
        maximum: 3600
        unit: "s"
    }
}
