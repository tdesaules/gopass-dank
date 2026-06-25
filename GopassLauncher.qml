import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string pluginId: "gopassDank"
    property string trigger: "pass"

    signal itemsChanged

    // Cached secret paths from gopass list --flat
    property var secrets: []
    property bool loading: false
    property bool syncing: false
    property string errorMessage: ""

    // Settings (loaded from plugin data)
    property string gopassBinary: "gopass"
    property int maxResults: 50

    Component.onCompleted: {
        console.info("GopassDank: Plugin loaded")

        if (!pluginService)
            return

        trigger = pluginService.loadPluginData(pluginId, "trigger", "pass")
        gopassBinary = pluginService.loadPluginData(pluginId, "gopassBinary", "gopass")
        maxResults = pluginService.loadPluginData(pluginId, "maxResults", 50)

        var cached = pluginService.loadPluginState(pluginId, "secrets", [])
        if (cached && cached.length > 0)
            secrets = cached

        refreshSecrets()
    }

    onTriggerChanged: {
        if (pluginService)
            pluginService.savePluginData(pluginId, "trigger", trigger)
    }

    function refreshSecrets() {
        if (loading)
            return
        if (!gopassBinary || gopassBinary.length === 0) {
            errorMessage = "Gopass binary path is not configured"
            root.itemsChanged()
            return
        }

        loading = true
        syncing = false
        errorMessage = ""
        var proc = listProcessComponent.createObject(root)
        proc.running = true
    }

    // Sync git (gopass sync) then refresh the local secret list. Invoked from
    // the Tab context menu ("Sync vault") and the error retry action.
    function syncAndRefresh() {
        if (loading)
            return
        if (!gopassBinary || gopassBinary.length === 0) {
            errorMessage = "Gopass binary path is not configured"
            root.itemsChanged()
            return
        }

        loading = true
        syncing = true
        errorMessage = ""
        var proc = syncProcessComponent.createObject(root)
        proc.running = true
    }

    property Component syncProcessComponent: Component {
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
                if (exitCode !== 0)
                    root._showToast("Sync failed, using local cache")
                else if (syncMessages.length > 0)
                    root._showToast("Vault synced")

                root.syncing = false
                root._requestList()
                destroy()
            }
        }
    }

    // Launches gopass list --flat to (re)build the local cache.
    function _requestList() {
        var proc = listProcessComponent.createObject(root)
        proc.running = true
    }

    property Component listProcessComponent: Component {
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
                        root.pluginService.savePluginState(root.pluginId, "secrets", root.secrets)
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
        var items = []
        var isEmpty = !query || query.trim().length === 0

        // Trigger an initial load if the cache is empty
        if (secrets.length === 0 && !loading && errorMessage === "")
            refreshSecrets()

        if (loading && secrets.length === 0) {
            items.push({
                name: syncing ? "Syncing gopass vault..." : "Loading gopass vault...",
                icon: "material:hourglass_empty",
                comment: syncing ? "Running gopass sync, then fetching secrets"
                                 : "Fetching secret list from gopass",
                action: "noop:",
                categories: ["Gopass"]
            })
            return items
        }

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
                comment: "Attempt to load secrets again",
                action: "retry:",
                categories: ["Gopass"]
            })
            return items
        }

        if (isEmpty) {
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

    // Context menu actions (opened with Tab on a selected item).
    function getContextMenuActions(item) {
        if (!item || !item.action)
            return []

        var actions = []

        if (item.action.indexOf("copy:") === 0) {
            var colonIdx = item.action.indexOf(":")
            var secretPath = item.action.substring(colonIdx + 1)
            actions.push({
                icon: "content_copy",
                text: "Copy password",
                action: function() { root._copySecret(secretPath) }
            })
            actions.push({
                icon: "person",
                text: "Copy username",
                action: function() { root._copyField(secretPath, "username") }
            })
        }

        actions.push({
            icon: "sync",
            text: "Sync vault",
            action: function() { root.syncAndRefresh() }
        })

        return actions
    }

    function _copySecret(secretPath) {
        Quickshell.execDetached([gopassBinary, "show", "-c", secretPath])
        _showToast("Copied password for: " + secretPath)
    }

    // Copies a body field (e.g. username) from a secret. gopass show -c <secret> <key>
    // exits non-zero if the key is absent, so we can give accurate feedback.
    function _copyField(secretPath, field) {
        var proc = copyFieldProcessComponent.createObject(root, {
            command: [gopassBinary, "show", "-c", secretPath, field],
            fieldName: field,
            secretPath: secretPath
        })
        proc.running = true
    }

    property Component copyFieldProcessComponent: Component {
        Process {
            property string fieldName: ""
            property string secretPath: ""

            onExited: (exitCode) => {
                if (exitCode === 0)
                    root._showToast("Copied " + fieldName + " for: " + secretPath)
                else
                    root._showToast("No " + fieldName + " in " + secretPath)
                destroy()
            }
        }
    }

    function _showToast(message) {
        if (typeof ToastService !== "undefined")
            ToastService.showInfo("Gopass-Dank", message)
        else
            console.log("GopassDank:", message)
    }
}
