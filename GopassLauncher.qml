import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "pass"

    signal itemsChanged

    // Cached secret paths from gopass list --flat
    property var secrets: []
    property bool loading: false
    property string errorMessage: ""

    // Settings (loaded from plugin data)
    property string gopassBinary: "gopass"
    property int maxResults: 50

    Component.onCompleted: {
        console.info("GopassDank: Plugin loaded")

        if (!pluginService)
            return

        trigger = pluginService.loadPluginData("gopassDank", "trigger", "pass")
        gopassBinary = pluginService.loadPluginData("gopassDank", "gopassBinary", "gopass")
        maxResults = pluginService.loadPluginData("gopassDank", "maxResults", 50)

        var cached = pluginService.loadPluginState("gopassDank", "secrets", [])
        if (cached && cached.length > 0)
            secrets = cached

        refreshSecrets()
    }

    onTriggerChanged: {
        if (pluginService)
            pluginService.savePluginData("gopassDank", "trigger", trigger)
    }

    function _requestUpdate() {
        if (!pluginService)
            return
        if (typeof pluginService.requestLauncherUpdate === "function")
            pluginService.requestLauncherUpdate("gopassDank")
        else
            console.warn("GopassDank: requestLauncherUpdate not available")
    }

    function refreshSecrets() {
        if (loading)
            return
        if (!gopassBinary || gopassBinary.length === 0) {
            errorMessage = "Gopass binary path is not configured"
            _requestUpdate()
            return
        }

        loading = true
        errorMessage = ""
        var proc = listProcessComponent.createObject(root)
        proc.running = true
    }

    Component {
        id: listProcessComponent

        Process {
            command: [root.gopassBinary, "list", "--flat"]
            property var lines: []

            stdout: SplitParser {
                onRead: line => {
                    if (line && line.trim().length > 0)
                        lines.push(line.trim())
                }
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line && line.trim().length > 0)
                        root.errorMessage = line.trim()
                }
            }

            onExited: (exitCode) => {
                if (exitCode === 0) {
                    root.secrets = lines.slice()
                    if (root.pluginService)
                        root.pluginService.savePluginState("gopassDank", "secrets", root.secrets)
                } else {
                    if (root.secrets.length === 0)
                        root.errorMessage = root.errorMessage || ("gopass exited with code " + exitCode)
                }
                root.loading = false
                root._requestUpdate()
                destroy()
            }
        }
    }

    function getItems(query) {
        var items = []
        var isEmpty = !query || query.trim().length === 0

        if (loading && secrets.length === 0) {
            items.push({
                name: "Loading gopass vault...",
                icon: "material:hourglass_empty",
                comment: "Fetching secret list from gopass",
                action: "noop:",
                categories: ["Gopass"],
                _preScored: 9999
            })
            return items
        }

        if (errorMessage !== "" && secrets.length === 0) {
            items.push({
                name: "Gopass error",
                icon: "material:error",
                comment: errorMessage,
                action: "retry:",
                categories: ["Gopass"],
                _preScored: 9999
            })
            items.push({
                name: "Retry",
                icon: "material:refresh",
                comment: "Attempt to load secrets again",
                action: "retry:",
                categories: ["Gopass"]
            })
            return items
        }

        if (isEmpty) {
            items.push(_makeRefreshItem())

            var shown = Math.min(maxResults, secrets.length)
            for (var i = 0; i < shown; i++)
                items.push(_makeSecretItem(secrets[i]))

            if (secrets.length > maxResults) {
                items.push({
                    name: (secrets.length - maxResults) + " more secrets...",
                    icon: "material:more_horiz",
                    comment: "Refine your search to see more",
                    action: "noop:",
                    categories: ["Gopass"]
                })
            }

            return items
        }

        var terms = query.trim().toLowerCase().split(/\s+/)
        for (var j = 0; j < secrets.length; j++) {
            var secret = secrets[j]
            var lower = secret.toLowerCase()
            var match = true
            for (var t = 0; t < terms.length; t++) {
                if (lower.indexOf(terms[t]) === -1) {
                    match = false
                    break
                }
            }
            if (match) {
                items.push(_makeSecretItem(secret))
                if (items.length >= maxResults)
                    break
            }
        }

        if (items.length === 0) {
            items.push({
                name: "No secrets found",
                icon: "material:search_off",
                comment: "No matches for \u2018" + query.trim() + "\u2019",
                action: "noop:",
                categories: ["Gopass"]
            })
        }

        return items
    }

    function _makeRefreshItem() {
        var name, comment, action
        if (loading) {
            name = "Refreshing vault..."
            comment = "Fetching secret list from gopass"
            action = "noop:"
        } else {
            name = "Refresh vault"
            comment = secrets.length + " secrets \u00b7 click to reload from gopass"
            action = "refresh:"
        }
        return {
            name: name,
            icon: "material:sync",
            comment: comment,
            action: action,
            categories: ["Gopass"],
            _preScored: 9999
        }
    }

    function _makeSecretItem(secret) {
        var parts = secret.split("/")
        var name = parts[parts.length - 1]
        var comment = parts.length > 1 ? parts.slice(0, -1).join(" / ") : "gopass secret"
        return {
            name: name,
            icon: "material:key",
            comment: comment,
            action: "copy:" + secret,
            categories: ["Gopass"]
        }
    }

    function executeItem(item) {
        if (!item || !item.action)
            return

        var colonIdx = item.action.indexOf(":")
        var actionType = item.action.substring(0, colonIdx)
        var actionData = item.action.substring(colonIdx + 1)

        switch (actionType) {
        case "copy":
            _copySecret(actionData)
            break
        case "refresh":
            refreshSecrets()
            break
        case "retry":
            refreshSecrets()
            break
        case "noop":
            break
        default:
            _showToast("Unknown action: " + actionType)
        }
    }

    function _copySecret(secretPath) {
        Quickshell.execDetached([gopassBinary, "show", "-c", secretPath])
        _showToast("Copied password for: " + secretPath)
    }

    function _showToast(message) {
        if (typeof ToastService !== "undefined")
            ToastService.showInfo("Gopass-Dank", message)
        else
            console.log("GopassDank:", message)
    }
}
