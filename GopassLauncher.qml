import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

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

    // In-memory passphrase cache (session only, never persisted). Injected as
    // GOPASS_AGE_PASSWORD into gopass show so pinentry is never invoked.
    property string _passphrase: ""
    property string _pendingSecret: ""
    property string _pendingField: ""
    property string _pendingKind: ""
    property var _passphraseDialog: null

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
                icon: "vpn_key",
                text: "Copy password",
                action: function() { root._copySecret(secretPath) }
            })
            actions.push({
                icon: "person",
                text: "Copy username",
                action: function() { root._copyField(secretPath, "username") }
            })
            actions.push({
                icon: "timer",
                text: "Copy TOTP",
                action: function() { root._copyTotp(secretPath) }
            })
        }

        actions.push({
            icon: "sync",
            text: "Sync vault",
            action: function() { root.syncAndRefresh() }
        })

        return actions
    }

    // --- Passphrase-aware decryption (bypasses pinentry via GOPASS_AGE_PASSWORD) ---

    function _copySecret(secretPath) {
        _requestSecret(secretPath, "", "password")
    }

    function _copyField(secretPath, field) {
        _requestSecret(secretPath, field, "field")
    }

    function _copyTotp(secretPath) {
        _requestSecret(secretPath, "", "totp")
    }

    function _requestSecret(secretPath, field, kind) {
        _pendingSecret = secretPath
        _pendingField = field
        _pendingKind = kind
        if (_passphrase !== "")
            _runCopy()
        else
            _openPassphraseDialog()
    }

    function _runCopy() {
        var args
        if (_pendingKind === "totp")
            args = [gopassBinary, "totp", "-c", _pendingSecret]
        else {
            args = [gopassBinary, "show", "-c", _pendingSecret]
            if (_pendingField !== "")
                args.push(_pendingField)
        }
        var proc = copyProcessComponent.createObject(root, {
            command: args,
            secretPath: _pendingSecret,
            fieldName: _pendingField,
            kind: _pendingKind
        })
        proc.running = true
    }

    function _onCopySuccess(secretPath, fieldName, kind) {
        if (_passphraseDialog && _passphraseDialog.visible)
            _passphraseDialog.hide()
        if (kind === "totp")
            _showToast("Copied TOTP code for: " + secretPath)
        else if (fieldName === "")
            _showToast("Copied password for: " + secretPath)
        else
            _showToast("Copied " + fieldName + " for: " + secretPath)
    }

    function _onCopyFailure(secretPath, fieldName, kind, exitCode, stderrText) {
        var isDecrypt = exitCode === 11 || (stderrText && stderrText.toLowerCase().indexOf("ecrypt") !== -1)
        if (isDecrypt) {
            _passphrase = ""
            if (_passphraseDialog && _passphraseDialog.visible)
                _passphraseDialog.setError("Wrong passphrase, try again")
            else
                _showToast("Copy failed: wrong passphrase")
        } else if (kind === "totp") {
            if (_passphraseDialog && _passphraseDialog.visible)
                _passphraseDialog.hide()
            _showToast("No TOTP configured in " + secretPath)
        } else if (fieldName !== "") {
            if (_passphraseDialog && _passphraseDialog.visible)
                _passphraseDialog.hide()
            _showToast("No " + fieldName + " in " + secretPath)
        } else {
            if (_passphraseDialog && _passphraseDialog.visible)
                _passphraseDialog.hide()
            _showToast("Copy failed (exit " + exitCode + ")")
        }
    }

    property Component copyProcessComponent: Component {
        Process {
            property string secretPath: ""
            property string fieldName: ""
            property string kind: ""
            property string stderrText: ""
            environment: ({
                "GOPASS_AGE_PASSWORD": root._passphrase
            })
            stderr: SplitParser {
                onRead: line => {
                    if (line)
                        stderrText += line + "\n"
                }
            }
            onExited: (exitCode) => {
                if (exitCode === 0)
                    root._onCopySuccess(secretPath, fieldName, kind)
                else
                    root._onCopyFailure(secretPath, fieldName, kind, exitCode, stderrText)
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

    // --- Passphrase dialog (native DMS-styled FloatingWindow) ---

    function _openPassphraseDialog() {
        if (!_passphraseDialog) {
            _passphraseDialog = passphraseDialogComponent.createObject(root)
            _passphraseDialog.submitted.connect(function(value) {
                root._passphrase = value
                root._runCopy()
            })
            _passphraseDialog.cancelled.connect(function() {
                root._pendingSecret = ""
                root._pendingField = ""
            })
        }
        var label
        if (_pendingKind === "totp")
            label = "Generating TOTP: " + _pendingSecret
        else
            label = "Decrypting: " + _pendingSecret
        if (_pendingField !== "")
            label += " (" + _pendingField + ")"
        _passphraseDialog.promptText = label
        _passphraseDialog.show()
    }

    property Component passphraseDialogComponent: Component {
        FloatingWindow {
            id: dlg
            visible: false
            implicitWidth: 460
            implicitHeight: 260
            title: "Gopass passphrase"
            color: Theme.surfaceContainer

            property string promptText: ""
            property string errorText: ""

            signal submitted(string value)
            signal cancelled()

            function show() {
                errorText = ""
                field.clear()
                visible = true
                Qt.callLater(function() { field.forceActiveFocus() })
            }

            function hide() { visible = false }

            function setError(msg) {
                errorText = msg
                field.clear()
                Qt.callLater(function() { field.forceActiveFocus() })
            }

            onClosed: dlg.visible = false

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                Row {
                    spacing: Theme.spacingS
                    DankIcon {
                        name: "lock"
                        size: Theme.iconSize
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        text: "Enter gopass passphrase"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                StyledText {
                    width: parent.width
                    text: dlg.promptText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    visible: dlg.promptText !== ""
                }

                DankTextField {
                    id: field
                    width: parent.width
                    echoMode: TextInput.Password
                    showPasswordToggle: true
                    placeholderText: "Passphrase"
                    leftIconName: "vpn_key"
                    onAccepted: {
                        if (field.text.length > 0) {
                            dlg.submitted(field.text)
                            field.clear()
                        }
                    }
                    Keys.onEscapePressed: {
                        dlg.cancelled()
                        dlg.hide()
                    }
                }

                StyledText {
                    width: parent.width
                    text: dlg.errorText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.WordWrap
                    visible: dlg.errorText !== ""
                }

                StyledText {
                    width: parent.width
                    text: "Enter to submit · Esc to cancel"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.outline
                }
            }
        }
    }
}
