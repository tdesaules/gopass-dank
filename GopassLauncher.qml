import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Item {
    id: root

    property var pluginService: null
    property string trigger: "pass"

    signal itemsChanged

    // Cached secret paths from gopass list --flat
    property var secrets: []
    property bool loading: false
    property bool syncing: false
    property string errorMessage: ""
    property double lastRefresh: 0
    property double lastSync: 0

    // Settings (loaded from plugin data)
    property string gopassBinary: "gopass"
    property int maxResults: 50
    property bool autoRefresh: true
    property int refreshIntervalSec: 300
    property bool syncOnActivation: true
    property int syncIntervalSec: 60

    Component.onCompleted: {
        console.info("GopassDank: Plugin loaded")

        if (!pluginService)
            return

        trigger = pluginService.loadPluginData("gopassDank", "trigger", "pass")
        gopassBinary = pluginService.loadPluginData("gopassDank", "gopassBinary", "gopass")
        maxResults = pluginService.loadPluginData("gopassDank", "maxResults", 50)
        autoRefresh = pluginService.loadPluginData("gopassDank", "autoRefresh", true)
        refreshIntervalSec = pluginService.loadPluginData("gopassDank", "refreshIntervalSec", 300)
        syncOnActivation = pluginService.loadPluginData("gopassDank", "syncOnActivation", true)
        syncIntervalSec = pluginService.loadPluginData("gopassDank", "syncIntervalSec", 60)

        // Load cached secrets and last sync from state for instant display
        var cached = pluginService.loadPluginState("gopassDank", "secrets", [])
        if (cached && cached.length > 0)
            secrets = cached
        lastSync = pluginService.loadPluginState("gopassDank", "lastSync", 0)

        // Quick local list to pick up changes since last cache (no git sync)
        refreshSecrets()
    }

    onTriggerChanged: {
        if (pluginService)
            pluginService.savePluginData("gopassDank", "trigger", trigger)
    }

    function refreshSecrets() {
        if (loading)
            return
        if (!gopassBinary || gopassBinary.length === 0) {
            errorMessage = "Gopass binary path is not configured"
            itemsChanged()
            return
        }

        loading = true
        syncing = false
        errorMessage = ""
        var proc = listProcessComponent.createObject(root)
        proc.running = true
    }

    function syncAndRefresh() {
        if (loading)
            return
        if (!gopassBinary || gopassBinary.length === 0) {
            errorMessage = "Gopass binary path is not configured"
            itemsChanged()
            return
        }

        loading = true
        syncing = true
        errorMessage = ""
        var proc = syncProcessComponent.createObject(root)
        proc.running = true
    }

    Component {
        id: syncProcessComponent

        Process {
            command: [root.gopassBinary, "sync"]
            property var syncMessages: []

            stdout: SplitParser {
                onRead: line => {
                    if (line && line.trim().length > 0)
                        syncMessages.push(line.trim())
                }
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line && line.trim().length > 0)
                        syncMessages.push(line.trim())
                }
            }

            onExited: (exitCode) => {
                root.lastSync = Date.now()
                if (root.pluginService)
                    root.pluginService.savePluginState("gopassDank", "lastSync", root.lastSync)

                if (exitCode !== 0)
                    root._showToast("Sync failed, using local cache")
                else if (syncMessages.length > 0)
                    root._showToast("Vault synced")

                root.syncing = false

                // Proceed to list secrets regardless of sync result
                var listProc = root.listProcessComponent.createObject(root)
                listProc.running = true

                destroy()
            }
        }
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
                    root.lastRefresh = Date.now()
                    if (root.pluginService)
                        root.pluginService.savePluginState("gopassDank", "secrets", root.secrets)
                } else {
                    if (root.secrets.length === 0)
                        root.errorMessage = root.errorMessage || ("gopass exited with code " + exitCode)
                }
                root.loading = false
                root.itemsChanged()
                destroy()
            }
        }
    }

    function getItems(query) {
        var now = Date.now()
        var isEmpty = !query || query.trim().length === 0

        // On activation (empty query): sync+refresh automatically if stale
        if (!loading) {
            if (isEmpty && syncOnActivation
                    && (lastSync === 0 || (now - lastSync) > syncIntervalSec * 1000)) {
                syncAndRefresh()
            } else if (secrets.length === 0
                       || (autoRefresh && lastRefresh > 0
                           && (now - lastRefresh) > refreshIntervalSec * 1000)) {
                refreshSecrets()
            }
        }

        var items = []

        // Loading state with no cached data yet
        if (loading && secrets.length === 0) {
            items.push({
                name: syncing ? "Syncing gopass vault..." : "Loading gopass vault...",
                icon: "material:hourglass_empty",
                comment: syncing ? "Syncing with git, then fetching secrets"
                                 : "Fetching secret list from gopass",
                action: "noop:",
                categories: ["Gopass"]
            })
            return items
        }

        // Error state with no cached data
        if (errorMessage !== "" && secrets.length === 0) {
            items.push({
                name: "Gopass error",
                icon: "material:error",
                comment: errorMessage,
                action: "retry:",
                categories: ["Gopass"]
            })
            items.push({
                name: "Retry",
                icon: "material:refresh",
                comment: "Attempt to sync and load secrets again",
                action: "retry:",
                categories: ["Gopass"]
            })
            return items
        }

        // No query: show all secrets up to maxResults
        if (isEmpty) {
            // Subtle status indicator while syncing/refreshing in the background
            if (loading) {
                items.push({
                    name: syncing ? "Syncing vault..." : "Refreshing vault...",
                    icon: "material:sync",
                    comment: syncing ? "Pulling latest entries from git"
                                     : "Fetching secret list from gopass",
                    action: "noop:",
                    categories: ["Gopass"]
                })
            }

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

        // Filter cached secrets by query (multi-word AND match, case-insensitive)
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
        case "retry":
            syncAndRefresh()
            break
        case "noop":
            break
        default:
            _showToast("Unknown action: " + actionType)
        }
    }

    function _copySecret(secretPath) {
        // gopass show -c decrypts and copies the password to the clipboard
        // (gopass handles the clipboard internally via wl-copy/xclip)
        Quickshell.execDetached([gopassBinary, "show", "-c", secretPath])
        _showToast("Copied password for: " + secretPath)
    }

    function _showToast(message) {
        if (typeof ToastService !== "undefined")
            ToastService.showInfo("Gopass-Dank", message)
        else
            console.log("GopassDank:", message)
    }

    function _formatAge(timestamp) {
        if (!timestamp)
            return ""
        var seconds = Math.floor((Date.now() - timestamp) / 1000)
        if (seconds < 60)
            return "just now"
        var minutes = Math.floor(seconds / 60)
        if (minutes < 60)
            return minutes + "m ago"
        var hours = Math.floor(minutes / 60)
        if (hours < 24)
            return hours + "h ago"
        var days = Math.floor(hours / 24)
        return days + "d ago"
    }
}
