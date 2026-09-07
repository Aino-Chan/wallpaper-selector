import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Qt.labs.folderlistmodel
import Qt.labs.platform
import QtQuick.Shapes
import QtQuick.Effects
import QtQml.Models

import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import QtMultimedia

Scope {

    IpcHandler {
        target: "wallpaper"

        function close(): void {
            for (const win of wallpaperWindows.instances)
                win.doQuit()
        }
    }
    
    Variants {
        id: wallpaperWindows
        model: Quickshell.screens

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData

            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"
            implicitWidth: screen.width
            implicitHeight: screen.height + 52 * (window.screen.height / 1080)
            MouseArea {
                anchors.fill: parent

                onClicked: mouse => {
                    var p = panel.mapFromItem(this, mouse.x, mouse.y);

                    if (p.x < 0 || p.y < 0 || p.x > panel.width || p.y > panel.height) {
                        doQuit()
                    }
                }
            }

            property string defaultBaseFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/share/Steam/steamapps/workshop/content/431960/"

            property string defaultStaticWallpaperFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)

            property string defaultThumbFolder: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.cache/quickshell-wallpaper-thumbs"

            property string baseFolder: defaultBaseFolder
            property string staticWallpaperFolder: defaultStaticWallpaperFolder
            property string thumbFolder: defaultThumbFolder
            property string ffmpegPath: "/usr/bin/ffmpeg"

            property bool anyHovered: false
            property bool keyboardNavigation: true
            property int targetIndexTracker: 0
            property bool isInitialLoad: true
            property bool panelReady: false
            property string lastWallpaperPath: ""
            property var thumbQueue: []
            property var validThumbs: new Set()
            property bool showHelp: false
            property bool showMatureContent: false
            property bool isMatureContentTriggered: false
            property string toggleMatureContentKey: ""
            property bool showFavorite: false
            property bool showStatic: false
            property bool showDynamic: false
            property bool showPlaylist: false
            property var dynamicIndexes: []
            property var staticIndexes: []
            property int preCommandIndex: -1
            property string preCommandPath: ""
            property bool wasInCommandMode: false
            property bool suppressTextHandler: false
            property var favorites: []
            property string settingsPath: ""
            property string sortMode: "default"
            property bool sortDescending: false
            property var usageMap: ({})
            property bool enableGifPreview: true
            property string statusMessage: ""
            property var suggestions: []
            property int suggestionIndex: -1
            property string filterTag: ""
            property var playlist: []
            property int playlistInterval: 30
            property bool playlistActive: false
            property bool playlistShuffle: false
            property real playlistLastApplied: 0
            property var renamedTitles: ({})
            property string pendingScrollPath: ""
            property int hoveredIndex: -1
            property int previousHoveredIndex: -1
            property int previousCurrentIndex: -1
            property real cardWidth: 200
            property real cardHeight: 360
            property real cardScale: 1.2
            property real cardSpacing: 20
            property bool workshopMode: false
            property bool showWorkshopAuth: false
            property string workshopSearchText: ""
            property string workshopSelectedId: ""
            property string workshopSortMode: "popular"
            property string workshopRequiredTag: ""
            property bool isQuitting: false
            
            FileView {
                id: pathCompleteFileView
                blockLoading: true
                onLoaded: {
                    let lines = text().trim().split("\n").filter(l => l.length > 0);
                    Qt.callLater(() => {
                        window.suggestions = [];
                        window.suggestions = lines;
                        window.suggestionIndex = lines.length > 0 ? 0 : -1;
                    });
                }
            }

            Process {
                id: pathCompleteProcess
            }


            Timer {
                id: initialScanTimer
                interval: 290
                repeat: false
                onTriggered: window.scanWallpapers()
            }

            Timer {
                id: pathCompleteTimer
                interval: 150
                repeat: false
                onTriggered: {
                    pathCompleteFileView.path = "";
                    pathCompleteFileView.path = "file:///tmp/qs-path-complete.txt";
                    pathCompleteFileView.reload();
                }
            }

            Process {
                id: wallpaperProcess
            }
            Process {
                id: thumbProcess
                onExited: window.drainThumbQueue()
            }

            Process {
                id: writeProcess
            }
            Process {
                id: workshopidProcess
            }
            Process {
                id: deleteFolderProcess
            }

            Process {
                id: initSettingsProcess
            }

            Process {
                id: playlistDaemon
                Component.onCompleted: {
                    let home = stripFileScheme(StandardPaths.writableLocation(StandardPaths.HomeLocation));
                    command = ["/bin/bash", "-c", `pgrep -fx 'bash.*wallpaper-playlist.sh' > /dev/null || { nohup ${shQuote(home + "/.local/bin/wallpaper-playlist.sh")} > /dev/null 2>&1 & disown; }`];
                    startDetached();
                }
            }

            Process {
                id: hardKillProcess
            }

            ListModel {
                id: masterModel
            }

            SteamWorkshopService {
                id: steamWorkshop

                weDir: window.baseFolder
                showMatureContent: window.showMatureContent
                selectedWorkshopId: window.workshopSelectedId
                sortMode: window.workshopSortMode
                requiredTag: window.workshopRequiredTag

                onSelectionRequested: function(index, center) {
                    if (index < 0 || index >= listView.count)
                        return

                    listView.currentIndex = index

                    if (center)
                        listView.positionViewAtIndex(index, ListView.Center)
                }
            }

            FileView {
                id: sharedFileView

                property var loadCallback: null
                onLoaded: {
                    if (loadCallback) {
                        loadCallback(text().trim());
                        loadCallback = null;
                    }
                }
            }

            FileView {
                id: settingsFile
                path: settingsPath
                blockLoading: true
            }

            Timer {
                id: statusMessageTimer
                interval: 2500
                repeat: false
                onTriggered: window.statusMessage = ""
            }

            Timer {
                id: saveDebounceTimer
                interval: 400
                repeat: false
                onTriggered: saveSettings()
            }

            Timer {
                id: killTimer
                interval: 149
                repeat: false
                onTriggered: {
                    hardKillProcess.command = ["/bin/bash", "-c", "pkill -f 'quickshell -c wallpaper'"]
                    hardKillProcess.startDetached()
                }
            }

            SequentialAnimation {
                id: filterAnimation

                NumberAnimation {
                    target: listView
                    property: "opacity"
                    to: 0
                    duration: 240
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.5, 0.5, 0.75, 1.0, 1, 1]
                }

                ScriptAction {
                    script: {
                        listView.interactive = false;
                        if (window.workshopMode) {
                            steamWorkshop.filterWorkshopItems();
                        } else {
                            filterWallpapers();
                        }
                    }
                }

                NumberAnimation {
                    target: listView
                    property: "opacity"
                    to: 1
                    duration: 240
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.5, 0.5, 0.75, 1.0, 1, 1]
                }

                ScriptAction {
                    script: {
                        listView.interactive = true;
                        if (!window.workshopMode && window.pendingScrollPath !== "") {
                            let target = window.pendingScrollPath
                            window.pendingScrollPath = ""

                            for (let i = 0; i < filteredModel.count; i++) {
                                if (stripFileScheme(filteredModel.get(i).folder).replace(/\/$/, "") === target) {
                                    listView.currentIndex = i
                                    Qt.callLater(() => listView.positionViewAtIndex(i, ListView.Center))
                                    break
                                }
                            }
                        } else if (window.workshopMode) {
                            window.pendingScrollPath = ""
                        }
                    }
                }
            }

            function doQuit() {
                if (window.isQuitting) return
                window.isQuitting = true
                initialScanTimer.stop()
                filterAnimation.stop()
                saveDebounceTimer.stop()
                saveSettings()
                killTimer.start()
            }

            function openWorkshopInSteam(workshopId) {
                let id = String(workshopId || "").trim()
                if (!/^\d+$/.test(id))
                    return

                workshopidProcess.command = ["/bin/bash", "-c", `xdg-open "steam://url/CommunityFilePage/${id}"`]
                workshopidProcess.startDetached()
            }

            function shQuote(s) {
                return "'" + String(s).replace(/'/g, "'\\''") + "'";
            }

            function shJoin(parts) {
                return parts.map(shQuote).join(" ");
            }

            function setHoveredIndex(newIndex) {
                if (hoveredIndex === newIndex)
                    return

                previousHoveredIndex = hoveredIndex
                hoveredIndex = newIndex
            }

            function clearHoveredIndex(oldIndex) {
                if (hoveredIndex === oldIndex)
                    hoveredIndex = -1
            }

            function blockWorkshopOnlyCommand(message) {
                if (!window.workshopMode)
                    return false;

                showStatus(message || "This command is unavailable in workshop mode");
                window.suppressTextHandler = true;
                searchInput.text = "";
                window.suppressTextHandler = false;
                searchDebounceTimer.stop();
                listView.forceActiveFocus();
                return true;
            }

            function formatWorkshopBytes(bytes) {
                let n = Number(bytes)

                if (!Number.isFinite(n) || n <= 0)
                    return "Unknown"

                let units = ["B", "KB", "MB", "GB", "TB"]
                let i = 0

                while (n >= 1024 && i < units.length - 1) {
                    n /= 1024
                    i++
                }

                if (i === 0)
                    return Math.round(n) + " B"
                if (n >= 100)
                    return Math.round(n) + " " + units[i]
                if (n >= 10)
                    return n.toFixed(1) + " " + units[i]
                return n.toFixed(2) + " " + units[i]
            }

            function formatInt(n) {
                let value = Number(n)

                if (!Number.isFinite(value) || value <= 0)
                    return "0"

                value = Math.floor(value)
                return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
            }

            function resetNavigationState() {
                window.anyHovered = false
                window.keyboardNavigation = true
                window.hoveredIndex = -1
                window.previousHoveredIndex = -1
                window.previousCurrentIndex = -1
                window.targetIndexTracker = 0
                listView.currentIndex = -1
            }

            function resetCommandModeState() {
                window.wasInCommandMode = false
                window.suggestions = []
                window.suggestionIndex = -1
                searchDebounceTimer.stop()
            }

            function rememberLocalSelectionForFilter() {
                if (window.workshopMode)
                    return

                let item = getCurrentFilteredItem()
                if (!item || !item.folder)
                    return

                let path = stripFileScheme(item.folder).replace(/\/$/, "")
                window.pendingScrollPath = path
                window.preCommandPath = path
                window.preCommandIndex = listView.currentIndex
            }

            function updateSuggestions(input) {
                let raw = input.trim();
                let lower = raw.toLowerCase();
                suggestions = [];
                suggestionIndex = -1;

                if (raw === "")
                    return;

                let matureSuggestion = ":" + toggleMatureContentKey;

                if (window.workshopMode) {
                    if (lower === ":sort" || lower.startsWith(":sort ")) {
                        let sortCommands = [
                            ":sort popular",
                            ":sort day",
                            ":sort week",
                            ":sort rated",
                            ":sort votes",
                            ":sort recent",
                            ":sort approved",
                            ":sort text"
                        ];

                        suggestions = sortCommands.filter(function(command) {
                            return command.startsWith(lower) && command !== lower;
                        });

                        suggestionIndex = suggestions.length > 0 ? 0 : -1;
                        hoverItem = "";
                        return;
                    }

                    if (lower === ":tag" || lower.startsWith(":tag ")) {
                        let partial = lower.slice(4).trim();
                        let workshopTags = getUniqueWorkshopTags();

                        suggestions = workshopTags
                            .filter(function(tag) {
                                return tag.startsWith(partial) && tag !== partial;
                            })
                            .map(function(tag) {
                                return ":tag " + tag;
                            });

                        suggestionIndex = suggestions.length > 0 ? 0 : -1;
                        hoverItem = "";
                        return;
                    }

                    if (raw.startsWith(":") && !raw.includes(" ")) {
                        let commands = [
                            matureSuggestion,
                            ":workshop",
                            ":sort",
                            ":tag",
                            ":width",
                            ":height",
                            ":scale",
                            ":spacing",
                            ":help"
                        ];

                        suggestions = commands.filter(function(command) {
                            return command.startsWith(lower) && command !== lower;
                        });

                        suggestionIndex = suggestions.length > 0 ? 0 : -1;
                    }

                    return;
                }

                if (lower.startsWith(":tag")) {
                    let partial = lower.replace(":tag", "").trim();
                    let allTags = getUniqueTags();
                    suggestions = allTags.filter(t => t.startsWith(partial) && t !== partial).map(t => ":tag " + t);
                    suggestionIndex = suggestions.length > 0 ? 0 : -1;
                    hoverItem = "";
                    return;
                }

                if (raw.startsWith(":") && !raw.includes(" ")) {
                    let commands = [
                        ":static", ":dynamic", ":favorite", matureSuggestion, ":workshop", ":gif",
                        ":rename", ":playlist", ":playlistshuffle", ":playlist clear",
                        ":width", ":height", ":spacing", ":scale",
                        ":random", ":randomstatic", ":randomfav",
                        ":export", ":setfolder", ":setstatic", ":setthumb", ":setffmpeg",
                        ":clearcache", ":reload", ":tag", ":id", ":open",
                        ":sort default", ":sort name", ":sort recent", ":sort favorite", ":sort random",
                        ":help"
                    ];
                    suggestions = commands.filter(c => c.startsWith(lower) && c !== lower);
                    suggestionIndex = suggestions.length > 0 ? 0 : -1;
                    return;
                }

                let pathCommands = [":setfolder ", ":sf ", ":setstatic ", ":ss ", ":setthumb ", ":st ", ":setffmpeg "];
                let isPathCmd = pathCommands.some(p => lower.startsWith(p));
                if (isPathCmd) {
                    let spaceIdx = raw.indexOf(" ");
                    let partial = raw.substring(spaceIdx + 1);
                    if (partial.length > 0) {
                        let cmd;
                        if (partial.endsWith("/")) {
                            cmd = "find " + shQuote(partial) + " -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's|$|/|' | head -20 > /tmp/qs-path-complete.txt";
                        } else {
                            let lastSlash = partial.lastIndexOf("/");
                            let dir = lastSlash >= 0 ? partial.substring(0, lastSlash + 1) : "/";
                            let base = lastSlash >= 0 ? partial.substring(lastSlash + 1) : partial;
                            cmd = "find " + shQuote(dir) + " -maxdepth 1 -mindepth 1 -type d -iname " + shQuote("*" + base + "*") + " 2>/dev/null | sed 's|$|/|' | head -20 > /tmp/qs-path-complete.txt";
                        }
                        pathCompleteProcess.command = ["/bin/bash", "-c", cmd];
                        pathCompleteProcess.startDetached();
                        pathCompleteTimer.restart();
                    } else {
                        window.suggestions = [];
                    }
                    return;
                }
            }

            function acceptSuggestion(accepted) {
                let raw = searchInput.text.trim();
                let pathCommands = [":setfolder ", ":sf ", ":setstatic ", ":ss ", ":setthumb ", ":st ", ":setffmpeg "];
                let matchedCmd = pathCommands.find(p => raw.toLowerCase().startsWith(p));
                window.suppressTextHandler = true;
                if (matchedCmd) {
                    let cmdPart = raw.substring(0, raw.indexOf(" ") + 1);
                    searchInput.text = cmdPart + accepted;
                    window.suppressTextHandler = false;
                    searchInput.cursorPosition = searchInput.text.length;
                    window.suggestions = [];
                    window.suggestionIndex = -1;
                    if (accepted.endsWith("/")) {
                        Qt.callLater(() => updateSuggestions(searchInput.text));
                    }
                } else {
                    searchInput.text = accepted;
                    window.suppressTextHandler = false;
                    searchInput.cursorPosition = searchInput.text.length;
                    window.suggestions = [];
                    window.suggestionIndex = -1;
                    filterWallpapersAnimation();
                }
            }

            function getUniqueTags() {
                let tags = new Set();
                for (let i = 0; i < masterModel.count; i++) {
                    let raw = masterModel.get(i).tags;
                    try {
                        let arr = JSON.parse(raw || "[]");
                        arr.forEach(t => tags.add(t));
                    } catch (e) {}
                }
                return Array.from(tags).sort();
            }

            function getUniqueWorkshopTags() {
                let tags = new Set();
                let model = steamWorkshop.workshopMasterModel;

                for (let i = 0; i < model.count; ++i) {
                    let rawTags = model.get(i).tags;

                    try {
                        let parsedTags = JSON.parse(rawTags || "[]");

                        parsedTags.forEach(function(tag) {
                            let normalized = String(tag || "").trim().toLowerCase();

                            if (normalized !== "")
                                tags.add(normalized);
                        });
                    } catch (error) {
                        console.warn("Invalid Workshop tags:", error);
                    }
                }

                return Array.from(tags).sort();
            }

            function showStatus(msg) {
                window.statusMessage = msg;
                statusMessageTimer.restart();
            }

            function stripFileScheme(path) {
                return String(path).replace(/^file:\/\//, "");
            }

            function getWallpaperInfo(folderPath, callback) {
                let jsonPath = folderPath + "/project.json";
                var xhr = new XMLHttpRequest();
                xhr.open("GET", jsonPath);
                xhr.onreadystatechange = function () {
                    if (xhr.readyState === XMLHttpRequest.DONE) {
                        try {
                            let json = JSON.parse(xhr.responseText);
                            callback({
                                title: String(json.title || "Untitled"),
                                preview: json.preview || json.file || "",
                                contentrating: json.contentrating || "Everyone",
                                tags: Array.isArray(json.tags) ? json.tags.map(t => String(t).toLowerCase()) : []
                            });
                        } catch (e) {
                            let cleanPath = stripFileScheme(folderPath);
                            callback({
                                title: cleanPath.split("/").pop(),
                                preview: ""
                            });
                        }
                    }
                };
                xhr.send();
            }

            function getCurrentFilteredItem() {
                if (listView.currentIndex < 0 || listView.currentIndex >= filteredModel.count)
                    return null;

                return filteredModel.get(listView.currentIndex);
            }

            function applyWallpaper(item) {
                if (!item || !item.folder)
                    return;
                var folder = stripFileScheme(item.folder).replace(/\/$/, "");
                let now = Date.now();
                window.usageMap[folder] = now;
                var home = stripFileScheme(StandardPaths.writableLocation(StandardPaths.HomeLocation));
                var scriptPath = item.isStatic ? home + "/.local/bin/wallpaper-apply-static.sh" : home + "/.local/bin/wallpaper-apply.sh";

                console.log("Applying wallpaper:", folder);

                let args = ["/bin/bash", scriptPath,];

                if (!item.isStatic) {
                    let cleanFolder = stripFileScheme(item.folder).replace(/\/$/, "");
                    let fullPath = item.preview && item.preview !== "" ? cleanFolder + "/" + item.preview : cleanFolder;

                    let hash = Qt.md5(fullPath);

                    args.push("--hash", hash);
                    args.push("--thumb-folder", window.thumbFolder);
                }
                args.push(folder);

                wallpaperProcess.command = args;
                wallpaperProcess.startDetached();

                window.lastWallpaperPath = folder;
                saveSettings();
            }

            function queueThumbnail(filePath) {
                let clean = stripFileScheme(filePath).replace(/\/$/, "");
                let ext = clean.split(".").pop().toLowerCase();

                let hash = Qt.md5(clean);
                window.validThumbs.add(hash);
                let thumbPath = window.thumbFolder + "/" + hash + ".jpg";

                let qThumbFolder = shQuote(window.thumbFolder);
                let qThumbPath = shQuote(thumbPath);
                let qClean = shQuote(clean);
                let qFfmpeg = shQuote(window.ffmpegPath);

                let cmd = `
                    mkdir -p -- ${qThumbFolder} &&
                    if [ ! -f ${qThumbPath} ]; then
                        case ${shQuote(ext)} in
                            'mp4'|'webm'|'mov'|'mkv'|'gif')
                                ${qFfmpeg} -y -ss 0.5 -i ${qClean} -frames:v 1 -vf 'scale=500:-1' ${qThumbPath}
                                ;;
                            'jpg'|'jpeg'|'png')
                                ${qFfmpeg} -y -i ${qClean} -vf 'scale=500:-1' ${qThumbPath}
                                ;;
                            *)
                                cp -- ${qClean} ${qThumbPath}
                                ;;
                        esac
                    fi
                `;

                thumbQueue.push(cmd);
                drainThumbQueue();
                return thumbPath;
            }

            function drainThumbQueue() {
                if (thumbQueue.length === 0 || thumbProcess.running)
                    return;
                thumbProcess.command = ["/bin/bash", "-c", thumbQueue.shift()];
                thumbProcess.startDetached();
            }

            function cleanupThumbnails(validSet) {
                if (validSet.size === 0)
                    return;

                let hashes = Array.from(validSet).join("|");
                let qThumbFolder = shQuote(window.thumbFolder);

                let cmd = `
                    shopt -s nullglob
                    for file in ${qThumbFolder}/*.jpg; do
                        name=$(basename "$file" .jpg)
                        if [[ ! "$name" =~ ^(${hashes})$ ]]; then
                            rm -- "$file"
                        fi
                    done
                `;

                thumbQueue.push(cmd);
                drainThumbQueue();
            }

            function loadSettings(callback) {
                let settingsPath = Qt.resolvedUrl("settings.json");

                sharedFileView.loadCallback = function (data) {
                    try {
                        let json = JSON.parse(data.trim());
                        window.showMatureContent = !!json.showMatureContent;
                        window.toggleMatureContentKey = json.toggleMatureContentKey || "sus";
                        if (!window.toggleMatureContentKey || window.toggleMatureContentKey.trim() === "")
                            window.toggleMatureContentKey = "sus";
                        window.cardWidth = json.width || 200;
                        window.cardHeight = json.height || 360;
                        window.cardSpacing = json.spacing || 20;
                        window.cardScale = json.scale || 1.2;
                        window.playlist = json.playlist || [];
                        window.playlistInterval = json.playlistInterval || 30;
                        window.playlistActive = !!json.playlistActive;
                        window.playlistShuffle = !!json.playlistShuffle;
                        window.showPlaylist = !!json.showPlaylist;
                        window.playlistLastApplied = json.playlistLastApplied || 0;
                        window.enableGifPreview = json.enableGifPreview !== false;
                        window.sortMode = json.sortMode || "default";
                        window.sortDescending = !!json.sortDescending;
                        window.showStatic = !!json.showStatic;
                        window.showDynamic = !!json.showDynamic;
                        window.showFavorite = !!json.showFavorite;
                        window.lastWallpaperPath = json.lastWallpaper || "";
                        window.baseFolder = json.baseFolder || window.defaultBaseFolder;
                        window.staticWallpaperFolder = json.staticWallpaperFolder || window.defaultStaticWallpaperFolder;
                        window.thumbFolder = json.thumbFolder || window.defaultThumbFolder;
                        window.ffmpegPath = json.ffmpegPath || "/usr/bin/ffmpeg";
                        window.filterTag = json.filterTag || "";
                        window.renamedTitles = json.renamedTitles || {};
                        window.favorites = json.favorites || [];
                        window.usageMap = json.usageMap || {};
                        window.workshopSearchText = json.workshopSearchText || "";
                        window.workshopSelectedId = json.workshopSelectedId || "";
                        window.workshopSortMode = json.workshopSortMode || "popular";
                        window.workshopRequiredTag = json.workshopRequiredTag || "";
                    } catch (e) {
                        console.warn("Failed to parse settings:", e);
                        window.showMatureContent = false;
                        window.cardWidth = 200;
                        window.cardHeight = 360;
                        window.cardSpacing = 20;
                        window.cardScale = 1.2;
                        window.favorites = [];
                        window.playlist = [];
                        window.playlistActive = false;
                        window.playlistShuffle = false;
                        window.showPlaylist = false;
                        window.playlistInterval = 30;
                        window.playlistLastApplied = 0;
                        window.renamedTitles = ({});
                        window.usageMap = ({});
                        window.toggleMatureContentKey = "sus";
                        window.enableGifPreview = true;
                        window.sortMode = "default";
                        window.sortDescending = false;
                        window.filterTag = "";
                        window.baseFolder = window.defaultBaseFolder;
                        window.staticWallpaperFolder = window.defaultStaticWallpaperFolder;
                        window.thumbFolder = window.defaultThumbFolder;
                        window.ffmpegPath = "/usr/bin/ffmpeg";
                        window.workshopSearchText = "";
                        window.workshopSelectedId = "";
                        window.workshopSortMode = "popular";
                        window.workshopRequiredTag = "";
                    }
                    if (callback)
                        callback();
                };

                sharedFileView.path = settingsPath;
            }

            function saveSettings() {
                let settingsPath = stripFileScheme(Qt.resolvedUrl("settings.json"));

                let jsonStr = JSON.stringify({
                    showMatureContent: window.showMatureContent,
                    toggleMatureContentKey: window.toggleMatureContentKey,
                    width: window.cardWidth,
                    height: window.cardHeight,
                    spacing: window.cardSpacing,
                    scale: window.cardScale,
                    playlist: window.playlist,
                    playlistInterval: window.playlistInterval,
                    playlistActive: window.playlist.length > 0 && window.playlistActive,
                    playlistShuffle: window.playlistShuffle,
                    playlistLastApplied: window.playlistLastApplied,
                    showPlaylist: window.showPlaylist,
                    enableGifPreview: window.enableGifPreview,
                    sortMode: window.sortMode,
                    sortDescending: window.sortDescending,
                    showStatic: window.showStatic,
                    showDynamic: window.showDynamic,
                    showFavorite: window.showFavorite,
                    lastWallpaper: window.lastWallpaperPath,
                    baseFolder: stripFileScheme(window.baseFolder),
                    staticWallpaperFolder: stripFileScheme(window.staticWallpaperFolder),
                    thumbFolder: window.thumbFolder,
                    ffmpegPath: window.ffmpegPath,
                    filterTag: window.filterTag,
                    renamedTitles: window.renamedTitles,
                    favorites: window.favorites,
                    usageMap: window.usageMap,
                    workshopSearchText: window.workshopSearchText,
                    workshopSelectedId: window.workshopSelectedId,
                    workshopSortMode: window.workshopSortMode,
                    workshopRequiredTag: window.workshopRequiredTag
                });

                writeProcess.command = [
                    "/bin/bash",
                    "-c",
                    "printf %s " + shQuote(jsonStr) + " > " + shQuote(settingsPath)
                ];
                writeProcess.startDetached();
            }

            function reloadWallpapers() {
                window.anyHovered = false
                window.hoveredIndex = -1
                window.previousHoveredIndex = -1
                window.previousCurrentIndex = -1
                masterModel.clear();
                filteredModel.clear();
                window.validThumbs.clear();
                window.thumbQueue = [];
                scanWallpapers();
            }

            function getFilteredCandidates() {

                if (window.workshopMode) {
                    return steamWorkshop.workshopFilteredModel;
                }

                let candidates = [];
                for (let i = 0; i < masterModel.count; i++) {
                    let item = masterModel.get(i);
                    let allowedContent = window.showMatureContent || (item.contentrating !== "Mature" && item.contentrating !== "Questionable");
                    let matchesFavorite = !window.showFavorite || item.isFavorite;
                    let matchesStatic = !window.showStatic || item.isStatic;
                    let matchesDynamic = !window.showDynamic || !item.isStatic;
                    let itemTags = [];
                    try {
                        itemTags = JSON.parse(item.tags || "[]");
                    } catch (e) {}
                    let matchesTag = window.filterTag === "" || itemTags.some(t => t === window.filterTag.toLowerCase());
                    let matchesPlaylist = !window.showPlaylist || window.playlist.indexOf(stripFileScheme(item.folder).replace(/\/$/, "")) !== -1;
                    if (allowedContent && matchesFavorite && matchesStatic && matchesDynamic && matchesTag && matchesPlaylist)
                        candidates.push(item);
                }
                return candidates;
            }

            Shortcut {
                sequences: ["Return", "Enter"]
                onActivated: {
                    window.suggestions = []
                    window.suggestionIndex = -1
                    if (window.showHelp) {
                        window.showHelp = false
                        return
                    }

                    let rawCmd = searchInput.text.trim()
                    let cmd = rawCmd.toLowerCase()

                    if (window.workshopMode && listView.currentIndex >= 0 && !cmd.startsWith(":")) {
                        let item = steamWorkshop.workshopFilteredModel.get(listView.currentIndex)
                        if (item && item.id)
                            window.openWorkshopInSteam(item.id)
                        return
                    }

                    let expectedPrefix = ":"
                    let matureCmd = expectedPrefix + window.toggleMatureContentKey.toLowerCase()

                    if (cmd === ":help" || cmd === ":h") {
                        window.showHelp = true
                        filterWallpapersAnimation()
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        searchDebounceTimer.stop()
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd.startsWith(":setffmpeg ")) {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        let newPath = rawCmd.replace(/^:setffmpeg\s+/i, "").trim()
                        let fileName = newPath.split("/").pop()
                        let badChars = /[\n\r\t"'`]/.test(newPath)

                        if (newPath === "" || !newPath.startsWith("/") || fileName !== "ffmpeg" || badChars) {
                            showStatus("Error! ffmpeg path must be a clean absolute path ending in /ffmpeg")
                            window.suppressTextHandler = true
                            searchInput.text = ""
                            window.suppressTextHandler = false
                            searchDebounceTimer.stop()
                            listView.forceActiveFocus()
                            return
                        }

                        window.ffmpegPath = newPath
                        saveSettings()
                        filterWallpapersAnimation()
                        showStatus("Set ffmpeg path as: " + newPath)

                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        searchDebounceTimer.stop()
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd.startsWith(":rename") || cmd.startsWith(":rn")) {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        let item = window.preCommandPath !== "" ? window.preCommandPath : (getCurrentFilteredItem() ? stripFileScheme(getCurrentFilteredItem().folder).replace(/\/$/, "") : "")
                        if (item !== "") {
                            let newName = rawCmd.replace(/^:(rename|rn)\s*/i, "").trim()
                            if (newName === "") {
                                delete window.renamedTitles[item]
                                window.renamedTitles = Object.assign({}, window.renamedTitles)
                            } else {
                                window.renamedTitles[item] = newName
                                window.renamedTitles = Object.assign({}, window.renamedTitles)
                            }
                            for (let i = 0; i < masterModel.count; i++) {
                                let mItem = masterModel.get(i)
                                if (stripFileScheme(mItem.folder).replace(/\/$/, "") === item) {
                                    if (newName === "") {
                                        masterModel.setProperty(i, "title", mItem.originalTitle || item.split("/").pop())
                                    } else {
                                        masterModel.setProperty(i, "title", newName)
                                    }
                                    break
                                }
                            }
                            saveSettings()
                            filterWallpapersAnimation()
                            showStatus(newName === "" ? "Name cleared" : "Renamed to: " + newName)
                        }
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd === ":playlistshuffle" || cmd === ":pls") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        window.playlistShuffle = !window.playlistShuffle
                        saveSettings()
                        filterWallpapersAnimation()
                        showStatus(window.playlistShuffle ? "Playlist shuffle on" : "Playlist shuffle off")
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }
                    if (cmd === ":playlist" || cmd === ":pl") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        window.showPlaylist = !window.showPlaylist
                        saveSettings()
                        filterWallpapersAnimation()
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd === ":playlist clear" || cmd === ":playlist c" || cmd === ":pl clear" || cmd === ":pl c") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        window.playlist = []
                        window.playlistActive = false
                        window.showPlaylist = false
                        saveSettings()
                        showStatus("Playlist cleared")
                        filterWallpapersAnimation()
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd.startsWith(":playlist ")) {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        let mins = parseInt(rawCmd.replace(/^:playlist\s+/i, "").trim())
                        if (!isNaN(mins) && mins > 0) {
                            window.playlistInterval = mins
                            saveSettings()
                            filterWallpapersAnimation()
                            showStatus("Playlist interval set to " + mins + " minutes")
                        }
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd.startsWith(":width ")) {
                        let width = parseInt(rawCmd.replace(/^:width\s+/i, "").trim())
                        if (!isNaN(width) && width > 0) {
                            width = Math.max(100, Math.min(1000, width))
                            window.cardWidth = width;
                            saveSettings()
                            filterWallpapersAnimation()
                            showStatus("Wallpaper cards width set to " + width + " px")
                        }
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd.startsWith(":height ")) {
                        let height = parseInt(rawCmd.replace(/^:height\s+/i, "").trim())
                        if (!isNaN(height) && height > 0) {
                            height = Math.max(100, Math.min(600, height))
                            window.cardHeight = height;
                            saveSettings()
                            filterWallpapersAnimation()
                            showStatus("Wallpaper cards height set to " + height + " px")
                        }
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd.startsWith(":scale ")) {
                        let scale = parseFloat(rawCmd.replace(/^:scale\s+/i, "").trim())
                        if (!isNaN(scale) && scale > 0) {
                            window.cardScale = scale
                            saveSettings()
                            filterWallpapersAnimation()
                            showStatus("Wallpaper cards scale set to " + scale + "x")
                        }
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd.startsWith(":spacing ")) {
                        let spacing = parseInt(rawCmd.replace(/^:spacing\s+/i, "").trim());
                        if (!isNaN(spacing) && spacing > 0) {
                            window.cardSpacing = spacing;
                            saveSettings()
                            filterWallpapersAnimation()
                            showStatus("Wallpaper cards spacing set to " + spacing + "px")
                        }
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd === matureCmd) {
                        window.showMatureContent = !window.showMatureContent
                        saveSettings()

                        if (window.workshopMode)
                            steamWorkshop.filterWorkshopItems()
                        else
                            filterWallpapersAnimation()

                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        searchDebounceTimer.stop()
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd === ":static" || cmd === ":s") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        window.showStatic = !window.showStatic
                        if (window.showStatic)
                            window.showDynamic = false
                        saveSettings()
                        filterWallpapersAnimation()
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        searchDebounceTimer.stop()
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd === ":dynamic" || cmd === ":d") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        window.showDynamic = !window.showDynamic
                        if (window.showDynamic)
                            window.showStatic = false
                        saveSettings()
                        filterWallpapersAnimation()
                        window.suppressTextHandler = true;
                        searchInput.text = ""
                        window.suppressTextHandler = false;
                        searchDebounceTimer.stop()
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd === ":favorite" || cmd === ":f") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        window.showFavorite = !window.showFavorite
                        saveSettings()
                        filterWallpapersAnimation()
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        searchDebounceTimer.stop()
                        listView.forceActiveFocus()
                        return;
                    }
                    if (cmd === ":clearcache" || cmd === ":cc") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        deleteFolder(window.thumbFolder)
                        window.validThumbs.clear()
                        window.thumbQueue = []
                        reloadWallpapers()
                        showStatus("Cleared cache")
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd === ":reload" || cmd === ":rl") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return
                        reloadWallpapers()
                        showStatus("Reloaded wallpapers")
                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false
                        listView.forceActiveFocus()
                        return;
                    }

                    if (cmd === ":workshop" || cmd === ":ws") {
                        resetNavigationState()
                        resetCommandModeState()

                        window.suggestions = []
                        window.suggestionIndex = -1
                        searchDebounceTimer.stop()

                        window.suppressTextHandler = true
                        searchInput.text = ""
                        window.suppressTextHandler = false

                        if (!window.workshopMode) {
                            if (!steamWorkshop.hasStoredKey) {
                                window.showWorkshopAuth = true
                            } else {
                                window.showWorkshopAuth = false
                                window.workshopMode = true
                                if (window.workshopSearchText !== "") {
                                    window.suppressTextHandler = true
                                    searchInput.text = window.workshopSearchText
                                    window.suppressTextHandler = false
                                }
                                steamWorkshop.scanInstalled()
                                steamWorkshop.runSearch(window.workshopSearchText)
                                showStatus("Workshop mode")
                            }
                        } else {
                            window.workshopMode = false
                            window.showWorkshopAuth = false
                            window.closeWorkshopInfoPanel()
                            listView.currentIndex = filteredModel.count > 0 ? 0 : -1
                            Qt.callLater(function() {
                                if (listView.currentIndex >= 0)
                                    listView.positionViewAtIndex(listView.currentIndex, ListView.Center)
                            })
                            filterWallpapers()
                            showStatus("Local mode")
                        }

                        listView.forceActiveFocus()
                        return
                    }

                    if (cmd === ":random" || cmd === ":r") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let candidates = getFilteredCandidates().filter(item => !item.isStatic);
                        if (candidates.length > 0) {
                            let pick = candidates[Math.floor(Math.random() * candidates.length)];
                            applyWallpaper(pick);
                            window.pendingScrollPath = stripFileScheme(pick.folder).replace(/\/$/, "");
                            window.preCommandPath = window.pendingScrollPath;
                            window.wasInCommandMode = false;
                            window.suppressTextHandler = true;
                            searchInput.text = "";
                            window.suppressTextHandler = false;
                            filterWallpapersAnimation();
                            listView.forceActiveFocus();
                            showStatus("Applied random wallpaper");
                        }
                        return;
                    }

                    if (cmd === ":randomstatic" || cmd === ":rs") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let candidates = getFilteredCandidates().filter(item => item.isStatic);
                        if (candidates.length > 0) {
                            let pick = candidates[Math.floor(Math.random() * candidates.length)];
                            applyWallpaper(pick);
                            window.pendingScrollPath = stripFileScheme(pick.folder).replace(/\/$/, "");
                            window.preCommandPath = window.pendingScrollPath;
                            window.wasInCommandMode = false;
                            window.suppressTextHandler = true;
                            searchInput.text = "";
                            window.suppressTextHandler = false;
                            filterWallpapersAnimation();
                            listView.forceActiveFocus();
                            showStatus("Applied random static wallpaper");
                        }
                        return;
                    }

                    if (cmd === ":randomfav" || cmd === ":rf") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let candidates = getFilteredCandidates().filter(item => item.isFavorite);
                        if (candidates.length > 0) {
                            let pick = candidates[Math.floor(Math.random() * candidates.length)];
                            applyWallpaper(pick);
                            window.pendingScrollPath = stripFileScheme(pick.folder).replace(/\/$/, "");
                            window.preCommandPath = window.pendingScrollPath;
                            window.wasInCommandMode = false;
                            window.suppressTextHandler = true;
                            searchInput.text = "";
                            window.suppressTextHandler = false;
                            filterWallpapersAnimation();
                            listView.forceActiveFocus();
                            showStatus("Applied random favorite wallpaper");
                        }
                        return;
                    }

                    if (cmd.startsWith(":export") || cmd.startsWith(":ex")) {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let arg = rawCmd.replace(/^:(export|ex)\s*/i, "").trim().toLowerCase();

                        let exportItems = getFilteredCandidates().filter(item => {
                            if (item.isStatic)
                                return false;
                            if (arg === "")
                                return true;
                            let title = (item.title || "").toLowerCase();
                            let folderName = item.folder.split("/").pop().toLowerCase();
                            return title.indexOf(arg) !== -1 || folderName.indexOf(arg) !== -1;
                        });

                        let exportPath = stripFileScheme(Qt.resolvedUrl("exported-wallpapers.txt"));
                        let exportDir = exportPath.replace(/\/[^\/]+$/, "");
                        let previewDir = exportDir + "/exported-previews";

                        let lines = exportItems.map((item, i) => {
                            let cleanFolder = stripFileScheme(item.folder).replace(/\/$/, "");
                            let id = cleanFolder.split("/").pop().replace(/-1$/, "");
                            let title = (item.title || "").toLowerCase();
                            let num = String(i + 1);
                            return num + ".  " + title + "    https://steamcommunity.com/sharedfiles/filedetails/?id=" + id;
                        }).join("\n");

                        let copyLines = [];
                        exportItems.forEach((item, i) => {
                            let cleanFolder = stripFileScheme(item.folder).replace(/\/$/, "");
                            let fullPath = item.preview && item.preview !== ""
                                ? cleanFolder + "/" + item.preview
                                : cleanFolder;
                            let hash = Qt.md5(fullPath);
                            let src = window.thumbFolder + "/" + hash + ".jpg";
                            let num = String(i + 1).padStart(3, "0");
                            let dest = previewDir + "/" + num + ".jpg";
                            copyLines.push("[ -f " + shQuote(src) + " ] && cp -- " + shQuote(src) + " " + shQuote(dest));
                        });

                        let script = [
                            "mkdir -p -- " + shQuote(previewDir),
                            "printf %s " + shQuote(lines) + " > " + shQuote(exportPath),
                            ...copyLines
                        ].join("\n");

                        writeProcess.command = ["/bin/bash", "-c", script];
                        writeProcess.startDetached();
                        showStatus("Exported " + exportItems.length + " wallpapers + previews");
                        window.suppressTextHandler = true;
                        searchInput.text = "";
                        window.suppressTextHandler = false;
                        filterWallpapersAnimation();
                        listView.forceActiveFocus();
                        return;
                    }

                    if (cmd.startsWith(":setfolder ") || cmd.startsWith(":sf ")) {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let newPath = rawCmd.replace(/^:(setfolder|sf)\s+/i, "").trim();

                        if (newPath !== "") {
                            window.baseFolder = newPath;
                            saveSettings();
                            reloadWallpapers();
                            showStatus("Dynamic folder set as: " + newPath);
                        }

                        searchInput.text = "";
                        searchDebounceTimer.stop();
                        listView.forceActiveFocus();
                        return;
                    }

                    if (cmd.startsWith(":setstatic ") || cmd.startsWith(":ss ")) {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let newPath = rawCmd.replace(/^:(setstatic|ss)\s+/i, "").trim();

                        if (newPath !== "") {
                            window.staticWallpaperFolder = newPath;
                            saveSettings();
                            reloadWallpapers();
                            showStatus("Static folder set as: " + newPath);
                        }

                        searchInput.text = "";
                        searchDebounceTimer.stop();
                        listView.forceActiveFocus();
                        return;
                    }

                    if (cmd.startsWith(":setthumb ") || cmd.startsWith(":st ")) {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let newPath = rawCmd.replace(/^:(setthumb|st)\s+/i, "").trim();

                        if (newPath !== "" && newPath !== window.thumbFolder) {
                            let oldPath = window.thumbFolder;
                            window.thumbQueue = [];
                            window.thumbFolder = newPath;
                            saveSettings();
                            reloadWallpapers();
                            deleteFolder(oldPath);
                            showStatus("Thumbnail folder set as: " + newPath);
                        }

                        searchInput.text = "";
                        searchDebounceTimer.stop();
                        listView.forceActiveFocus();
                        return;
                    }

                    if (cmd === ":sort" || cmd.startsWith(":sort ")) {
                        let mode = cmd.slice(5).trim();

                        if (window.workshopMode) {
                            let aliases = {
                                "p": "popular",
                                "all": "popular",
                                "alltime": "popular",
                                "subscriptions": "popular",
                                "1d": "day",
                                "daily": "day",
                                "7d": "week",
                                "weekly": "week",
                                "trend": "week",
                                "rating": "rated",
                                "new": "recent",
                                "accepted": "approved"
                            };

                            mode = aliases[mode] || mode;

                            let validModes = [
                                "popular",
                                "day",
                                "week",
                                "rated",
                                "votes",
                                "recent",
                                "updated",
                                "approved",
                                "playtime-trend",
                                "playtime",
                                "average-playtime-trend",
                                "average-playtime",
                                "sessions-trend",
                                "sessions",
                                "text"
                            ];

                            if (mode === "") {
                                showStatus(
                                    "Workshop sort: " + window.workshopSortMode
                                    + " — popular, day, week, rated, votes, recent, updated, approved"
                                );
                            } else if (mode === "month") {
                                showStatus("Steam only exposes 1–7 day trend windows; month is unavailable");
                            } else if (!validModes.includes(mode)) {
                                showStatus("Unknown Steam Workshop sort: " + mode);
                            } else {
                                window.workshopSortMode = mode;
                                saveSettings();
                                steamWorkshop.runSearch(window.workshopSearchText);
                                showStatus("Workshop sort: " + mode);
                            }
                        } else {
                            if (mode === "d")
                                mode = "default";
                            else if (mode === "n")
                                mode = "name";
                            else if (mode === "r")
                                mode = "recent";
                            else if (mode === "f")
                                mode = "favorite";

                            if (["default", "name", "recent", "favorite", "random"].includes(mode)) {
                                if (window.sortMode === mode) {
                                    window.sortDescending = !window.sortDescending;
                                } else {
                                    window.sortMode = mode;
                                    window.sortDescending = false;
                                }

                                saveSettings();
                                filterWallpapersAnimation();
                            }
                        }

                        window.suppressTextHandler = true;
                        searchInput.text = "";
                        window.suppressTextHandler = false;
                        searchDebounceTimer.stop();
                        listView.forceActiveFocus();
                        return;
                    }

                    if (cmd === ":open" || cmd === ":o") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let path = window.preCommandPath !== "" ? window.preCommandPath.replace(/\/$/, "").split("/").pop() : window.lastWallpaperPath.replace(/\/$/, "").split("/").pop();
                        let id = path.replace(/\/$/, "").split("/").pop().replace(/-1$/, "");
                        if (id && /^\d+$/.test(id)) {
                            workshopidProcess.command = ["/bin/bash", "-c", `xdg-open "steam://url/CommunityFilePage/${id}"`];
                            workshopidProcess.startDetached();
                        }
                        filterWallpapersAnimation();
                        window.suppressTextHandler = true;
                        searchInput.text = "";
                        window.suppressTextHandler = false;
                        listView.forceActiveFocus();
                        return;
                    }

                    if (cmd === ":id") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        let path = window.preCommandPath !== "" ? window.preCommandPath : window.lastWallpaperPath;
                        if (path !== "") {
                            let id = path.replace(/\/$/, "").split("/").pop();
                            workshopidProcess.command = ["/bin/bash", "-c", `printf '%s' "${id}" | wl-copy`];
                            workshopidProcess.startDetached();
                        }
                        filterWallpapersAnimation();
                        window.suppressTextHandler = true;
                        searchInput.text = "";
                        window.suppressTextHandler = false;
                        listView.forceActiveFocus();
                        return;
                    }

                    if (cmd === ":gif") {
                        if (blockWorkshopOnlyCommand("Unavailable in workshop mode"))
                            return;
                        window.enableGifPreview = !window.enableGifPreview;
                        saveSettings();
                        filterWallpapersAnimation();
                        window.suppressTextHandler = true;
                        searchInput.text = "";
                        window.suppressTextHandler = false;
                        listView.forceActiveFocus();
                        return;
                    }

                    if (cmd === ":tag" || cmd.startsWith(":tag ")) {
                        let tag = rawCmd.replace(/^:tag\s*/i, "").trim();

                        if (window.workshopMode) {
                            window.workshopRequiredTag = tag;
                            saveSettings();
                            steamWorkshop.runSearch(window.workshopSearchText);

                            showStatus(
                                tag === ""
                                    ? "Workshop tag cleared"
                                    : "Workshop tag: " + tag
                            );
                        } else {
                            let localTag = tag.toLowerCase();
                            window.filterTag = localTag;
                            saveSettings();
                            filterWallpapersAnimation();

                            showStatus(
                                localTag === ""
                                    ? "Tag cleared"
                                    : "Tag: " + localTag
                            );
                        }

                        window.suppressTextHandler = true;
                        searchInput.text = "";
                        window.suppressTextHandler = false;
                        searchDebounceTimer.stop();
                        listView.forceActiveFocus();
                        return;
                    }
                    applyWallpaper(getCurrentFilteredItem());
                }
            }

           function deleteFolder(path) {
                let cleanPath = stripFileScheme(path).replace(/\/$/, "");
                let allowed = stripFileScheme(window.thumbFolder).replace(/\/$/, "");

                if (cleanPath !== allowed) {
                    console.log("Refusing to delete non-thumb folder:", cleanPath);
                    return;
                }

                deleteFolderProcess.command = ["/bin/bash", "-c", "rm -rf -- " + shQuote(cleanPath)];
                deleteFolderProcess.startDetached();
            }

            function scanWallpapers() {
                console.log("Scanning:", baseFolder);

                var folders = Qt.createQmlObject('import Qt.labs.folderlistmodel 1.0; FolderListModel {}', window);
                folders.folder = "file://" + baseFolder;
                folders.showDirs = true;
                folders.showFiles = false;

                folders.onStatusChanged.connect(function () {
                    if (folders.status !== FolderListModel.Ready)
                        return;
                    masterModel.clear();

                    for (let i = 0; i < folders.count; i++) {
                        let folderPath = folders.get(i, "filePath");
                        let cleanPath = stripFileScheme(folderPath);

                        masterModel.append({
                            folder: folderPath,
                            title: "Error! Fix project file.",
                            originalTitle: "",
                            preview: "",
                            isStatic: false,
                            isFavorite: window.favorites.includes(cleanPath),
                            tags: "[]",
                            hash: Qt.md5(cleanPath)
                        });

                        let index = masterModel.count - 1;

                        getWallpaperInfo(folderPath, function (data) {
                            let cleanPath = stripFileScheme(folderPath);
                            let displayTitle = window.renamedTitles[cleanPath] || data.title;
                            masterModel.setProperty(index, "title", displayTitle);
                            masterModel.setProperty(index, "originalTitle", data.title);
                            masterModel.setProperty(index, "preview", data.preview);
                            masterModel.setProperty(index, "contentrating", data.contentrating || "Everyone");
                            masterModel.setProperty(index, "tags", JSON.stringify(data.tags || []));

                            if (data.preview && data.preview !== "") {
                                let fullPath = stripFileScheme(folderPath) + "/" + data.preview;
                                queueThumbnail(fullPath);
                            }
                        });
                    }

                    var staticFiles = Qt.createQmlObject('import Qt.labs.folderlistmodel 1.0; FolderListModel {}', window);
                    staticFiles.folder = "file://" + staticWallpaperFolder;
                    staticFiles.showDirs = false;
                    staticFiles.showFiles = true;
                    staticFiles.nameFilters = ["*.jpg", "*.png", "*.jpeg", "*.gif"];

                    staticFiles.onStatusChanged.connect(function () {
                        if (staticFiles.status !== FolderListModel.Ready)
                            return;
                        for (let i = 0; i < staticFiles.count; i++) {
                            let filePath = stripFileScheme(staticFiles.get(i, "filePath")).replace(/\/$/, "");

                            queueThumbnail(filePath);
                            let displayTitle = window.renamedTitles[filePath] || filePath.split("/").pop();
                            masterModel.append({
                                folder: filePath,
                                title: displayTitle,
                                originalTitle: filePath.split("/").pop(),
                                isStatic: true,
                                isFavorite: window.favorites.includes(filePath),
                                tags: "[]"
                            });
                        }
                        Qt.callLater(() => {
                            cleanupThumbnails(window.validThumbs);
                        });
                        filterWallpapers();

                        Qt.callLater(() => {
                            initialFadeIn.start();
                            window.isInitialLoad = false;
                        });
                    });
                });
            }
            Component.onCompleted: {
                let path = Qt.resolvedUrl("settings.json").toString().replace(/^file:\/\//, "");
                let dir = path.replace(/\/[^\/]*$/, "");
                window.settingsPath = path;
                const command =
                    "mkdir -p -- " + shQuote(dir) +
                    " && if [ ! -f " + shQuote(path) + " ]; then " +
                    "printf '%s\\n' '{}' > " + shQuote(path) +
                    "; fi"

                initSettingsProcess.command = ["/bin/bash", "-c", command];
                initSettingsProcess.startDetached();
                Qt.callLater(() => {
                    loadSettings(function () {
                        window.panelReady = true
                        initialScanTimer.start()
                    });
                });
            }

            function filterWallpapersAnimation() {
                if (window.isInitialLoad) {
                    filterWallpapers();
                    return;
                }

                if (filterAnimation.running) {
                    filterAnimation.stop();
                }

                filterAnimation.start();
            }

            function filterWallpapers() {
                
                window.anyHovered = false
                window.hoveredIndex = -1
                window.previousHoveredIndex = -1
                window.previousCurrentIndex = -1
                listView.lastCurrentIndex = -1
                if (window.keyboardNavigation)
                window.keyboardNavigation = true

                var rawFilter = searchInput.text.trim();
                let wasInCommandMode = window.wasInCommandMode;
                let enteringCommand = rawFilter.startsWith(":");
                let leavingCommand = !enteringCommand && wasInCommandMode;

                if (enteringCommand && !window.wasInCommandMode) {
                    let item = getCurrentFilteredItem();
                    if (item) {
                        window.preCommandIndex = listView.currentIndex;
                        window.preCommandPath = stripFileScheme(item.folder).replace(/\/$/, "");
                    }
                }
                if (enteringCommand) {
                    filteredModel.clear();

                    window.dynamicIndexes = [];
                    window.staticIndexes = [];

                    Qt.callLater(() => listView.currentIndex = -1);

                    window.wasInCommandMode = true;
                    return;
                }
                var filter = rawFilter.toLowerCase();
                var previousItem = getCurrentFilteredItem();
                var previousFolder = previousItem ? stripFileScheme(previousItem.folder).replace(/\/$/, "") : "";

                var newIndex = -1;
                let items = [];

                for (var i = 0; i < masterModel.count; i++) {
                    var item = masterModel.get(i);
                    var title = (item.title || "").toLowerCase();
                    var folderName = item.folder.split("/").pop().toLowerCase();

                    var matchesText = filter === "" || title.indexOf(filter) !== -1 || folderName.indexOf(filter) !== -1;

                    var allowedContent = window.showMatureContent || (item.contentrating !== "Mature" && item.contentrating !== "Questionable");
                    var matchesFavorite = !window.showFavorite || item.isFavorite;
                    var matchesStatic = !window.showStatic || item.isStatic;
                    var matchesDynamic = !window.showDynamic || !item.isStatic;
                    var itemTags = [];
                    try {
                        itemTags = JSON.parse(item.tags || "[]");
                    } catch (e) {}
                    var matchesTag = window.filterTag === "" || (item.tags && item.tags.indexOf(window.filterTag.toLowerCase()) !== -1);
                    var matchesPlaylist = !window.showPlaylist || window.playlist.indexOf(stripFileScheme(item.folder).replace(/\/$/, "")) !== -1;
                    if (matchesText && allowedContent && matchesFavorite && matchesStatic && matchesDynamic && matchesTag && matchesPlaylist) {
                        items.push({
                            folder: item.folder,
                            title: item.title,
                            preview: item.preview,
                            isStatic: item.isStatic,
                            isFavorite: item.isFavorite,
                            contentrating: item.contentrating,
                            tags: item.tags || "[]"
                        });
                    }
                }

                if (window.showPlaylist) {
                    items.sort((a, b) => {
                        let aIdx = window.playlist.indexOf(stripFileScheme(a.folder).replace(/\/$/, ""));
                        let bIdx = window.playlist.indexOf(stripFileScheme(b.folder).replace(/\/$/, ""));
                        return aIdx - bIdx;
                    });
                } else if (window.sortMode === "default") {
                    let dynamicItems = [];
                    let staticItems = [];

                    for (let item of items) {
                        if (item.isStatic)
                            staticItems.push(item);
                        else
                            dynamicItems.push(item);
                    }

                    dynamicItems.sort((a, b) => {
                        let aName = a.folder.split("/").pop();
                        let bName = b.folder.split("/").pop();

                        let aId = parseInt(aName);
                        let bId = parseInt(bName);

                        if (isNaN(aId) || isNaN(bId))
                            return aName.localeCompare(bName);

                        return aId - bId;
                    });

                    staticItems.sort((a, b) => {
                        let aName = a.folder.split("/").pop();
                        let bName = b.folder.split("/").pop();
                        return aName.localeCompare(bName);
                    });

                    items = dynamicItems.concat(staticItems);
                    if (window.sortDescending)
                        items.reverse();
                } else if (window.sortMode === "name") {
                    items.sort((a, b) => (a.title || "").localeCompare(b.title || ""));
                    if (window.sortDescending)
                        items.reverse();
                } else if (window.sortMode === "recent") {
                    items.sort((a, b) => {
                        let ta = window.usageMap[stripFileScheme(a.folder).replace(/\/$/, "")] || 0;
                        let tb = window.usageMap[stripFileScheme(b.folder).replace(/\/$/, "")] || 0;
                        return tb - ta;
                    });
                    if (window.sortDescending)
                        items.reverse();
                } else if (window.sortMode === "favorite") {
                    items.sort((a, b) => {
                        if (a.isFavorite === b.isFavorite)
                            return 0;
                        return b.isFavorite ? 1 : -1;
                    });
                    if (window.sortDescending)
                        items.reverse();
                } else if (window.sortMode === "random") {
                    for (let i = items.length - 1; i > 0; i--) {
                        let j = Math.floor(Math.random() * (i + 1));
                        let tmp = items[i];
                        items[i] = items[j];
                        items[j] = tmp;
                    }
                    if (window.sortDescending)
                        items.reverse();
                }

                listView.highlightMoveDuration = 0;
                listView.currentIndex = -1;
                filteredModel.clear();
                for (let i = 0; i < items.length; i++) {
                    filteredModel.append(items[i]);
                }

                if (previousFolder !== "") {
                    for (let i = 0; i < filteredModel.count; i++) {
                        let modelPath = stripFileScheme(filteredModel.get(i).folder).replace(/\/$/, "");
                        if (modelPath === previousFolder) {
                            newIndex = i;
                            break;
                        }
                    }
                }

                if (leavingCommand && !window.isMatureContentTriggered && window.preCommandPath !== "") {
                    let target = window.preCommandPath;

                    for (let i = 0; i < filteredModel.count; i++) {
                        let modelPath = stripFileScheme(filteredModel.get(i).folder).replace(/\/$/, "");

                        if (modelPath === target) {
                            newIndex = i;
                            break;
                        }
                    }
                }

                if (window.pendingScrollPath !== "") {
                    let target = window.pendingScrollPath;
                    for (let i = 0; i < filteredModel.count; i++) {
                        let modelPath = stripFileScheme(filteredModel.get(i).folder).replace(/\/$/, "");
                        if (modelPath === target) {
                            newIndex = i;
                            break;
                        }
                    }
                }

                window.dynamicIndexes = [];
                window.staticIndexes = [];
                for (let i = 0; i < filteredModel.count; i++) {
                    let item = filteredModel.get(i);
                    if (item.isStatic)
                        window.staticIndexes.push(i);
                    else
                        window.dynamicIndexes.push(i);
                }

                if ((window.isInitialLoad || window.isMatureContentTriggered) && window.lastWallpaperPath) {
                    for (let i = 0; i < filteredModel.count; i++) {
                        let modelPath = stripFileScheme(filteredModel.get(i).folder);
                        if (modelPath === window.lastWallpaperPath) {
                            newIndex = i;
                            break;
                        }
                    }
                    window.isMatureContentTriggered = false;
                }

                if (newIndex === -1 && filteredModel.count > 0)
                    newIndex = 0;

                window.pendingScrollPath = "";
                if (newIndex !== -1) {
                    window.targetIndexTracker = newIndex;
                    Qt.callLater(() => {
                        if (listView.count === 0)
                            return;
                        listView.currentIndex = newIndex;
                        listView.positionViewAtIndex(newIndex, ListView.Center);
                        Qt.callLater(() => listView.highlightMoveDuration = 300);
                    });
                }
                window.wasInCommandMode = enteringCommand;
            }

            ListModel {
                id: filteredModel
            }

            Rectangle {
                id: panel

                property real widthScale: screen.width / 1920
                property real heightScale: screen.height / 1200

                property real panelWidthMultiplier: 8.25 * widthScale
                property real panelHeightMultiplier: 1.3889 * heightScale
                property real panelMinWidth: 825 * widthScale
                property real panelMinHeight: 200 * heightScale
                property real panelMaxWidth: 1650 * widthScale
                property real panelMaxHeight: 800 * heightScale

                width: Math.max(
                    panelMinWidth,
                    Math.min(panelMaxWidth, cardWidth * panelWidthMultiplier)
                )

                height: Math.max(
                    panelMinHeight,
                    Math.min(panelMaxHeight, cardHeight * panelHeightMultiplier)
                )

                Behavior on width {
                        enabled: !isInitialLoad
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                        }
                    }
                Behavior on height {
                        enabled: !isInitialLoad
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                        }
                    }

                radius: 20
                color: Theme.background
                border.color: Theme.border
                anchors.centerIn: parent
                clip: true

                opacity: 0
                scale: 0.87
                transformOrigin: Item.Center

                states: [
                State {
                    name: "opened"
                    when: window.panelReady && !window.isQuitting

                    PropertyChanges {
                        target: panel
                        opacity: 1
                        scale: 1
                    }
                },
                State {
                    name: "closed"
                    when: !window.panelReady || window.isQuitting

                    PropertyChanges {
                        target: panel
                        opacity: 0
                        scale: 0.87
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "closed"
                    to: "opened"

                    NumberAnimation {
                        properties: "opacity,scale"
                        duration: 410
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                    }
                },
                Transition {
                    from: "opened"
                    to: "closed"

                    ParallelAnimation {
                        NumberAnimation {
                            property: "scale"
                            duration: 149
                            easing.type: Easing.Linear
                        }

                        NumberAnimation {
                            property: "opacity"
                            duration: 146
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.5, 0.5, 0.75, 1, 1, 1]
                        }
                    }
                }
            ]

                FocusScope {
                    id: keyScope
                    anchors.fill: parent
                    focus: true
                    Component.onCompleted: listView.forceActiveFocus()

                    Keys.onPressed: event => {
                        if (event.matches(StandardKey.Paste)) {
                            searchInput.visible = true;
                            Qt.callLater(() => {
                                searchInput.forceActiveFocus();
                                searchInput.paste();
                            });

                            event.accepted = true;
                            return;
                        }

                        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                            let item = getCurrentFilteredItem();
                            if (!item)
                                return;
                            let path = stripFileScheme(item.folder);

                            for (let i = 0; i < masterModel.count; i++) {
                                let mItem = masterModel.get(i);
                                if (stripFileScheme(mItem.folder) === path) {
                                    mItem.isFavorite = !mItem.isFavorite;

                                    if (mItem.isFavorite) {
                                        if (!window.favorites.includes(path))
                                            window.favorites.push(path);
                                    } else {
                                        let idx = window.favorites.indexOf(path);
                                        if (idx !== -1)
                                            window.favorites.splice(idx, 1);
                                    }

                                    saveSettings();
                                    break;
                                }
                            }

                            item.isFavorite = !item.isFavorite;
                            event.accepted = true;
                            return;
                        }

                        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) {
                            if (!(event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier))) {
                                return;
                            }
                        }
                        if (!searchInput.activeFocus && !window.showHelp && event.key !== Qt.Key_Escape && event.key !== Qt.Key_Tab && event.text.length > 0) {
                            if (event.key === Qt.Key_Backspace) {
                                if (searchInput.text.length > 0) {
                                    searchInput.forceActiveFocus();
                                }
                                event.accepted = true;
                                return;
                            }
                            searchInput.visible = true;
                            searchInput.forceActiveFocus();
                            searchInput.insert(searchInput.text.length, event.text);
                            searchInput.cursorPosition = searchInput.text.length;
                            event.accepted = true;
                        }
                    }

                    TextField {
                        id: searchInput
                        width: 300
                        height: 35
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        leftPadding: 30
                        rightPadding: 12

                        visible: true
                        opacity: (text.length > 0 || activeFocus) ? 1 : 0

                        focus: false
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.background
                        z: 1

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter

                            text: ""
                            font.pixelSize: 16
                            color: Theme.border
                            opacity: 0.7
                        }

                        Timer {
                            id: searchDebounceTimer
                            interval: 250
                            repeat: false
                            onTriggered: {
                                if (window.workshopMode) {
                                    window.workshopSearchText = searchInput.text
                                    saveDebounceTimer.restart() 
                                    steamWorkshop.runSearch(searchInput.text)
                                    if (searchInput.text.length === 0)
                                        listView.forceActiveFocus()
                                    return
                                }

                                rememberLocalSelectionForFilter();
                                filterWallpapersAnimation();

                                if (searchInput.text.length === 0) {
                                    listView.forceActiveFocus();
                                }
                            }
                        }

                        background: Rectangle {
                            radius: 15
                            color: Theme.background
                            border.width: 1
                            border.color: Theme.border
                        }

                        Keys.forwardTo: [listView]

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.5, 0.5, 0.75, 1.0, 1, 1]
                            }
                        }

                        onTextChanged: {
                            if (window.suppressTextHandler)
                                return;

                            let isCommand = text.trim().startsWith(":");
                            let wasCommand = window.wasInCommandMode;
                            updateSuggestions(text);

                            if (isCommand && !wasCommand) {
                                searchDebounceTimer.stop();
                                rememberLocalSelectionForFilter();
                                filterWallpapersAnimation();
                            } else if (!isCommand) {
                                if (!window.workshopMode)
                                    rememberLocalSelectionForFilter();
                                searchDebounceTimer.restart();
                            }

                            window.wasInCommandMode = isCommand;
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: false
                        enabled: window.suggestions.length > 0
                        z: 19
                        propagateComposedEvents: true
                        onClicked: {
                            window.suggestions = [];
                            window.suggestionIndex = -1;
                        }
                    }

                    Rectangle {
                        id: autocompleteDropdown
                        visible: window.suggestions.length > 0 && searchInput.activeFocus
                        anchors.top: searchInput.bottom
                        anchors.topMargin: 6
                        anchors.horizontalCenter: searchInput.horizontalCenter
                        width: 300
                        height: Math.min(window.suggestions.length, 6) * 32
                        radius: 15
                        color: Theme.background
                        border.color: Theme.border
                        border.width: 1
                        z: 20
                        clip: true

                        ListView {
                            id: suggestionList
                            anchors.fill: parent
                            model: window.suggestions
                            boundsBehavior: Flickable.StopAtBounds
                            currentIndex: window.suggestionIndex
                            property string hoverItem: ""
                            property bool hoverLocked: false
                            clip: true

                            onCurrentIndexChanged: {
                                if (currentIndex >= 0) {
                                    positionViewAtIndex(currentIndex, ListView.Contain);
                                }
                            }

                            onModelChanged: {
                                suggestionList.hoverItem = "";
                                suggestionList.hoverLocked = false;
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                propagateComposedEvents: true
                                onWheel: wheel => {
                                    suggestionList.hoverItem = "";
                                    suggestionList.hoverLocked = true;

                                    let newIndex = window.suggestionIndex;

                                    if (newIndex < 0)
                                        newIndex = 0;

                                    if (wheel.angleDelta.y > 0)
                                        newIndex--;
                                    else
                                        newIndex++;

                                    newIndex = Math.max(0, Math.min(window.suggestions.length - 1, newIndex));

                                    window.suggestionIndex = newIndex;
                                }
                            }

                            delegate: Rectangle {
                                id: suggestionDelegate
                                width: autocompleteDropdown.width
                                height: 32
                                radius: 15
                                color: (suggestionList.hoverItem !== "") ? (modelData === suggestionList.hoverItem ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent") : (index === suggestionList.currentIndex ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent")

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 200
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    text: {
                                        let s = modelData.endsWith("/") ? modelData.slice(0, -1) : modelData;
                                        return s.split("/").pop() + (modelData.endsWith("/") ? "/" : "");
                                    }
                                    color: Theme.text
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    width: parent.width - 24
                                    opacity: (suggestionList.hoverItem !== "") ? (modelData === suggestionList.hoverItem ? 1 : 0.7) : (index === window.suggestionIndex ? 1 : 0.7)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onPositionChanged: {
                                        suggestionList.hoverLocked = false;
                                    }

                                    onEntered: {
                                        if (!suggestionList.hoverLocked) {
                                            suggestionList.hoverItem = modelData;
                                            window.suggestionIndex = index;
                                        }
                                    }

                                    onExited: {
                                        if (suggestionList.hoverItem === modelData) {
                                            suggestionList.hoverItem = "";
                                        }
                                    }

                                    onClicked: acceptSuggestion(modelData)
                                }
                            }
                        }
                    }

                    Text {
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 1000
                        height: 35
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 13
                        color: Theme.text
                        opacity: (searchInput.text.length > 0 || searchInput.activeFocus) ? 0 : 0.5
                        elide: Text.ElideRight
                        z: 1

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                            }
                        }

                        text: {
                            if (window.statusMessage !== "")
                                return window.statusMessage;
                            let parts = [];
                            if (window.showFavorite)
                                parts.push(" Favorites");
                            if (window.showStatic)
                                parts.push(" Static");
                            if (window.showDynamic)
                                parts.push(" Dynamic");
                            if (window.showMatureContent && !showStatic)
                                parts.push(" NSFW");
                            if (window.playlistActive) {
                                parts.push("󰐑 Playlist " + (window.showPlaylist ? "only " : "") + window.playlist.length + (window.playlistShuffle ? " " : ""));
                            } else if (window.playlist.length > 0) {
                                parts.push(" Playlist " + (window.showPlaylist ? "only " : "") + window.playlist.length + (window.playlistShuffle ? " " : ""));
                            } else if (window.showPlaylist) {
                                parts.push(" Playlist only");
                            }
                            if (window.sortMode !== "default" && window.sortMode !== "random")
                                parts.push("Sort: " + window.sortMode + (window.sortDescending ? " ↓" : " ↑"));
                            if (window.sortMode == "random")
                                parts.push("Sort: " + window.sortMode);
                            if (window.filterTag !== "")
                                parts.push("⌗ " + window.filterTag);
                            if (!window.enableGifPreview)
                                parts.push(" No gif");
                            return parts.length > 0 ? parts.join("  |  ") : " ";
                        }
                    }

                    Rectangle {
                        id: clipContainer
                        anchors.fill: parent
                        anchors.margins: 45
                        anchors.topMargin: 0
                        anchors.bottomMargin: 0
                        color: "transparent"
                        clip: true
                        z: 0

                        ListView {
                            id: listView
                            opacity: 0
                            anchors.fill: parent
                            anchors.topMargin: 90
                            anchors.bottomMargin: 90
                            orientation: ListView.Horizontal
                            spacing: cardSpacing
                            model: window.workshopMode ? steamWorkshop.workshopFilteredModel : filteredModel
                            cacheBuffer: 300
                            highlightMoveDuration: 300
                            boundsBehavior: Flickable.StopAtBounds
                            highlightFollowsCurrentItem: true
                            highlight: Item {}
                            preferredHighlightBegin: (width / 2) - (window.cardWidth / 2)
                            preferredHighlightEnd: (width / 2) - (window.cardWidth / 2)
                            highlightRangeMode: ListView.StrictlyEnforceRange
                            property real parallaxPx: 15 * (window.cardWidth / 200)

                            NumberAnimation {
                                id: initialFadeIn
                                target: listView
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: 240
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.5, 0.5, 0.75, 1.0, 1, 1]
                            }

                            property int lastCurrentIndex: -1

                            onCurrentIndexChanged: {
                                if (window.keyboardNavigation) {
                                    window.previousCurrentIndex = lastCurrentIndex
                                    lastCurrentIndex = currentIndex
                                }

                                if (window.workshopMode) {
                                    Qt.callLater(function() {
                                        if (window.isQuitting)
                                            return
                                        if (currentIndex >= 0 && currentIndex < steamWorkshop.workshopFilteredModel.count) {
                                            let item = steamWorkshop.workshopFilteredModel.get(currentIndex)
                                            if (item && item.id) {
                                                window.workshopSelectedId = String(item.id)
                                                saveDebounceTimer.restart()
                                            }
                                        }
                                    })
                                    if (!window.isQuitting)
                                        steamWorkshop.maybePrefetchByView(contentX, width, contentWidth)
                                }
                            }

                            onContentXChanged: {
                                if (window.workshopMode && !window.isQuitting) {
                                    steamWorkshop.maybePrefetchByView(contentX, width, contentWidth)
                                }
                            }

                            onMovementEnded: {
                                if (window.workshopMode && !window.isQuitting) {
                                    steamWorkshop.maybePrefetchByView(contentX, width, contentWidth)
                                }
                            }

                            delegate: Item {
                                id: delegateRoot
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                anchors.verticalCenterOffset: 20
                                property real baseWidth: window.cardWidth
                                property real baseHeight: window.cardHeight
                                property real activeScale: window.cardScale
                                property real sideOffset: (baseWidth * activeScale - baseWidth) / 2
                                property int activeIndex: window.keyboardNavigation ? listView.currentIndex : window.hoveredIndex
                                property bool hoverMode: !window.keyboardNavigation && window.hoveredIndex !== -1
                                property bool hoverActive: hoverMode && index === window.hoveredIndex
                                property bool active: window.keyboardNavigation ? index === activeIndex : hoverActive

                                readonly property real parallaxRank: {
                                    let slot = Math.max(1, baseWidth + listView.spacing)
                                    let cardCenter =
                                        delegateRoot.x
                                        - listView.contentX
                                        + baseWidth / 2

                                    return (cardCenter - listView.width / 2) / slot
                                }

                                readonly property int parallaxHalfVisible: Math.max(
                                    1,
                                    Math.ceil(
                                        listView.width
                                        / (2 * Math.max(1, baseWidth + listView.spacing))
                                    )
                                )

                                readonly property real parallaxOverscan:
                                    (parallaxHalfVisible + 1) * listView.parallaxPx + 20

                                property bool isWorkshopItem: window.workshopMode
                                property var workshopItem: isWorkshopItem ? model : null
                                property string workshopId: isWorkshopItem ? String(model.id || "") : ""
                                property bool workshopInstalled: isWorkshopItem ? steamWorkshop.isInstalled(workshopId) : false
                                property string workshopDlState: isWorkshopItem ? steamWorkshop.getDownloadStatus(workshopId) : ""
                                property real workshopDlPct: isWorkshopItem ? steamWorkshop.getDownloadProgress(workshopId) : 0
                                property bool workshopDownloading: isWorkshopItem && (workshopDlState === "queued" || workshopDlState === "downloading")
                                property bool workshopInfoOpen: isWorkshopItem && steamWorkshop.openInfoId === workshopId
                                property real workshopFileSize: Number(
                                    steamWorkshop.fetchedFileSizes[workshopId] ?? model.fileSize ?? 0
                                )
                                property string workshopCreatorName: isWorkshopItem ? String(model.creatorName || "") : ""
                                property string workshopCreatorUrl: isWorkshopItem ? String(model.creatorUrl || "") : ""

                                width: baseWidth
                                height: baseHeight

                                property real itemOffset: {
                                    if (activeIndex === -1)
                                        return 0

                                    if (index < activeIndex)
                                        return -sideOffset
                                    if (index > activeIndex)
                                        return sideOffset
                                    return 0
                                }

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 600
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                    }
                                }

                                property bool isVisibleOnScreen: delegateRoot.ListView.view ? (x + width > ListView.view.contentX && x < ListView.view.contentX + ListView.view.width) : false

                                property int playlistPosition: {
                                    if (delegateRoot.isWorkshopItem) return -1
                                    let path = folder ? stripFileScheme(folder).replace(/\/$/, "") : "";
                                    return window.playlist.indexOf(path);
                                }
                                property bool inPlaylist: playlistPosition !== -1
                                property int lastValidPosition: 0

                                onPlaylistPositionChanged: {
                                    if (playlistPosition !== -1)
                                        lastValidPosition = playlistPosition;
                                }

                        
                                Item {
                                    id: scaleContainer
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: baseWidth
                                    height: baseHeight
                                    scale: active ? activeScale : 1
                                    transformOrigin: Item.Center
                                    x: itemOffset

                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 600
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                        }
                                    }

                                    Behavior on x {
                                        NumberAnimation {
                                            duration: 600
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                        }
                                    }
                                

                                    Rectangle {
                                        anchors.fill: parent
                                        color: Theme.background
                                        radius: 15
                                        antialiasing: true

                                        Item {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            clip: true
                                            layer.enabled: isVisibleOnScreen
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: ShaderEffectSource {
                                                    sourceItem: Rectangle {
                                                        width: scaleContainer.width
                                                        height: scaleContainer.height
                                                        radius: 15
                                                        color: "black"
                                                        antialiasing: true
                                                    }
                                                }
                                            }

                                            Loader {
                                                id: previewLoader
                                                anchors.fill: parent

                                                property string normalizedPath: {
                                                    if (delegateRoot.isWorkshopItem) return ""
                                                    return folder ? folder.replace(/\/$/, "") : ""
                                                }

                                                property bool isGif: window.enableGifPreview && !delegateRoot.isWorkshopItem && preview && preview.toLowerCase().endsWith(".gif")

                                                sourceComponent: delegateRoot.isWorkshopItem
                                                    ? workshopPreview
                                                    : (isGif ? animatedPreview : staticPreview)

                                                Component {
                                                    id: workshopPreview

                                                    Item {
                                                        anchors.fill: parent

                                                        AnimatedImage {
                                                            id: workshopAnim
                                                            width: parent.width + delegateRoot.parallaxOverscan * 2
                                                            height: parent.height
                                                            anchors.verticalCenter: parent.verticalCenter

                                                            x: (parent.width - width) / 2
                                                            - delegateRoot.parallaxRank * listView.parallaxPx
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                            smooth: true
                                                            cache: true
                                                            playing: isVisibleOnScreen
                                                            source: model.previewUrl || ""
                                                            visible: status === AnimatedImage.Ready
                                                        }

                                                        Image {
                                                            id: workshopStatic
                                                            width: parent.width + delegateRoot.parallaxOverscan * 2
                                                            height: parent.height
                                                            anchors.verticalCenter: parent.verticalCenter

                                                            x: (parent.width - width) / 2
                                                            - delegateRoot.parallaxRank * listView.parallaxPx
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                            smooth: true
                                                            cache: true
                                                            sourceSize.width: scaleContainer.width
                                                            sourceSize.height: scaleContainer.height
                                                            source: model.previewUrl || ""
                                                            visible: workshopAnim.status !== AnimatedImage.Ready
                                                        }
                                                    }
                                                }

                                                Component {
                                                    id: staticPreview
                                                    Item {
                                                        anchors.fill: parent
                                                        Image {
                                                            id: staticImg
                                                            width: parent.width + delegateRoot.parallaxOverscan * 2
                                                            height: parent.height
                                                            anchors.verticalCenter: parent.verticalCenter

                                                            x: (parent.width - width) / 2
                                                            - delegateRoot.parallaxRank * listView.parallaxPx
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                            smooth: true
                                                            cache: true
                                                            sourceSize.width: scaleContainer.width
                                                            sourceSize.height: scaleContainer.height
                                                            source: {
                                                                if (!previewLoader.normalizedPath)
                                                                    return ""
                                                                let fullPath
                                                                if (preview && preview !== "")
                                                                    fullPath = previewLoader.normalizedPath + "/" + preview
                                                                else if (isStatic)
                                                                    fullPath = previewLoader.normalizedPath
                                                                else
                                                                    return ""
                                                                let hash = Qt.md5(fullPath)
                                                                return "file://" + window.thumbFolder + "/" + hash + ".jpg"
                                                            }
                                                        }
                                                    }
                                                }

                                                Component {
                                                    id: animatedPreview
                                                        Item {
                                                        anchors.fill: parent
                                                        AnimatedImage {
                                                            id: animImg
                                                            width: parent.width + delegateRoot.parallaxOverscan * 2
                                                            height: parent.height
                                                            anchors.verticalCenter: parent.verticalCenter

                                                            x: (parent.width - width) / 2
                                                            - delegateRoot.parallaxRank * listView.parallaxPx
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                            smooth: true
                                                            cache: true
                                                            playing: isVisibleOnScreen
                                                            source: previewLoader.normalizedPath !== "" ? "file://" + previewLoader.normalizedPath + "/" + preview : ""
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: active ? 33 : 0
                                            color: Theme.background
                                            radius: 15
                                            opacity: active ? 1 : 0
                                            visible: true

                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: 300
                                                    easing.type: Easing.BezierSpline
                                                    easing.bezierCurve: [0.5, 0.5, 0.75, 1.0, 1, 1]
                                                }
                                            }

                                            Behavior on height {
                                                NumberAnimation {
                                                    duration: 300
                                                    easing.type: Easing.BezierSpline
                                                    easing.bezierCurve: [0.5, 0.5, 0.75, 1.0, 1, 1]
                                                }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: title
                                                color: Theme.text
                                                width: parent.width - 20
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                                font.pixelSize: 13
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "transparent"
                                            border.width: 1
                                            border.color: Theme.background
                                            radius: 15
                                            antialiasing: true
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "transparent"
                                            border.width: 2
                                            border.color: Theme.border
                                            radius: 15
                                            antialiasing: true
                                            opacity: active ? 1 : 0
                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: 300
                                                    easing.type: Easing.BezierSpline
                                                    easing.bezierCurve: [0.5, 0.5, 0.75, 1.0, 1, 1]
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        opacity: delegateRoot.inPlaylist ? 1 : 0
                                        anchors.centerIn: parent
                                        anchors.topMargin: 10
                                        anchors.leftMargin: 10
                                        width: baseWidth
                                        height: baseHeight
                                        radius: 15
                                        color: Theme.background
                                        border.width: active ? 2 : 1
                                        border.color: active ? Theme.border : Theme.background
                                        Behavior on border.color {
                                            ColorAnimation {
                                                duration: 300
                                            }
                                        }
                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: 300
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: [0.5, 0.5, 0.75, 1.0, 1, 1]
                                            }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: String(delegateRoot.lastValidPosition + 1)
                                            color: Theme.border
                                            font.pixelSize: 100
                                            font.weight: Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        id: workshopInfoCard
                                        visible: delegateRoot.isWorkshopItem && delegateRoot.workshopInfoOpen
                                        opacity: visible ? 1 : 0

                                        width: baseWidth
                                        height: baseHeight
                                        anchors.centerIn: parent
                                        anchors.topMargin: 10
                                        anchors.leftMargin: 10
                                        z: 30

                                        radius: 15
                                        color: Theme.background90
                                        border.width: active ? 2 : 1
                                        border.color: active ? Theme.border : Theme.background
                                        Behavior on border.color {
                                            ColorAnimation {
                                                duration: 300
                                            }
                                        }
                                        
                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: 300
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                            }
                                        }

                                        Column {
                                            id: infoColumn
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 10
                                            spacing: 6

                                            Text {
                                                horizontalAlignment: Text.AlignHCenter
                                                width: parent.width
                                                text: String(model.title || "")
                                                color: Theme.text
                                                font.pixelSize: 16
                                                font.weight: Font.Medium
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 1
                                                color: Theme.border
                                                opacity: 0.5
                                            }

                                            Text {
                                                horizontalAlignment: Text.AlignHCenter
                                                width: parent.width
                                                text: delegateRoot.workshopFileSize > 0
                                                ? "Size: " + window.formatWorkshopBytes(delegateRoot.workshopFileSize)
                                                : "Size: Unknown"
                                                color: Theme.text
                                                font.pixelSize: 13
                                                wrapMode: Text.WordWrap
                                            }

                                            Text {
                                                horizontalAlignment: Text.AlignHCenter
                                                width: parent.width
                                                text: "Subscribers: " + window.formatInt(model.subscriptions)
                                                color: Theme.text
                                                font.pixelSize: 13
                                                wrapMode: Text.WordWrap
                                            }

                                            Text {
                                                horizontalAlignment: Text.AlignHCenter
                                                width: parent.width
                                                text: "Favorites: " + window.formatInt(model.favorited)
                                                color: Theme.text
                                                font.pixelSize: 13
                                                wrapMode: Text.WordWrap
                                            }

                                            Text {
                                                horizontalAlignment: Text.AlignHCenter
                                                width: parent.width
                                                text: "Creator"
                                                color: Theme.border
                                                font.pixelSize: 14
                                            }

                                            Text {
                                                horizontalAlignment: Text.AlignHCenter
                                                width: parent.width
                                                text: delegateRoot.workshopCreatorName !== ""
                                                    ? delegateRoot.workshopCreatorName
                                                    : "Loading..."
                                                color: creatorMouse.containsMouse ? Theme.accent : Theme.text
                                                font.pixelSize: 13
                                                font.underline: creatorMouse.containsMouse
                                                wrapMode: Text.WordWrap

                                                MouseArea {
                                                    id: creatorMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.LeftButton
                                                    preventStealing: true
                                                    propagateComposedEvents: false
                                                    enabled: delegateRoot.workshopCreatorUrl !== ""
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                                                    onPressed: mouse => {
                                                        mouse.accepted = true
                                                    }

                                                    onClicked: mouse => {
                                                        mouse.accepted = true

                                                        let u = String(delegateRoot.workshopCreatorUrl || "").trim()
                                                        if (u === "")
                                                            return

                                                        workshopidProcess.command = [
                                                            "/bin/sh",
                                                            "-c",
                                                            shJoin(["xdg-open", "steam://openurl/" + u])
                                                        ]
                                                        workshopidProcess.startDetached()
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 10
                                            text: delegateRoot.workshopInstalled
                                                ? "Installed"
                                                : delegateRoot.workshopDlState
                                            color: Theme.border
                                            font.pixelSize: 12
                                            width: parent.width
                                            wrapMode: Text.WordWrap
                                        }

                                        Rectangle {
                                            width: parent.width - 20
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 10
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            height: 34
                                            radius: 16
                                            color: openSteamMouse.containsMouse
                                                ? Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.85)
                                                : Theme.border
                                            border.color: Theme.border
                                            border.width: 1

                                            Behavior on color {
                                                ColorAnimation { duration: 120 }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Open in Steam"
                                                color: Theme.background
                                                font.pixelSize: 13
                                                font.weight: Font.Medium
                                            }

                                            MouseArea {
                                                id: openSteamMouse
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton
                                                hoverEnabled: true
                                                preventStealing: true
                                                propagateComposedEvents: false

                                                onPressed: mouse => {
                                                    mouse.accepted = true
                                                }

                                                onClicked: mouse => {
                                                    mouse.accepted = true
                                                    window.openWorkshopInSteam(delegateRoot.workshopId)
                                                    steamWorkshop.openInfoId = ""
                                                    window.showStatus("Opened workshop item in Steam: " + String(model.title || ""))
                                                }
                                            }
                                        }
                                    }
                                }
                            
                                    Item {
                                        id: favContainer
                                        width: 30
                                        height: 30
                                        scale: active ? cardScale : 1.0
                                        property bool isWorkshop: delegateRoot.isWorkshopItem
                                        property string workshopId: model.id ? String(model.id) : ""
                                        property bool installed: isWorkshop && steamWorkshop.isInstalled(workshopId)

                                        visible: isWorkshop ? installed : true
                                        property int offsetX: active ? cardScale * 15 : 15
                                        property int offsetY: active ? cardScale * 10 : 10
                                        x: scaleContainer.x + baseWidth * (1 + scaleContainer.scale) / 2 - width - offsetX
                                        y: baseHeight * (1 - scaleContainer.scale) / 2 + offsetY
                                        property bool mouseOverFav: false
                                        z: 20

                                        Behavior on scale {
                                            NumberAnimation {
                                            duration: 300
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                            }
                                        }

                                        Behavior on offsetX {
                                            NumberAnimation {
                                            duration: 300
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                            }
                                        }

                                        Behavior on offsetY {
                                            NumberAnimation {
                                            duration: 300
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: !favContainer.isWorkshop
                                            enabled: !favContainer.isWorkshop
                                            cursorShape: !favContainer.isWorkshop ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onEntered: favContainer.mouseOverFav = true
                                            onExited: favContainer.mouseOverFav = false
                                            onClicked: {
                                                let path = window.stripFileScheme(model.folder);

                                                for (let i = 0; i < masterModel.count; i++) {
                                                    let mItem = masterModel.get(i);
                                                    if (window.stripFileScheme(mItem.folder) === path) {
                                                        mItem.isFavorite = !mItem.isFavorite;

                                                        if (mItem.isFavorite) {
                                                            if (!window.favorites.includes(path))
                                                                window.favorites.push(path);
                                                        } else {
                                                            let idx = window.favorites.indexOf(path);
                                                            if (idx !== -1)
                                                                window.favorites.splice(idx, 1);
                                                        }

                                                        window.saveSettings();
                                                        break;
                                                    }
                                                }
                                                model.isFavorite = !model.isFavorite;
                                            }
                                        }

                                        Text {
                                            text: favContainer.isWorkshop ? "" : ""
                                            color: Theme.border
                                            font.pixelSize: 28
                                            anchors.fill: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            opacity: favContainer.isWorkshop ? 1 : (model.isFavorite ? 1 : 0)
                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: 300
                                                    easing.type: Easing.BezierSpline
                                                    easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                                }
                                            }
                                        }

                                        Text {
                                            text: "♥"
                                            color: Theme.border
                                            font.pixelSize: 28
                                            anchors.fill: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            opacity: (!favContainer.isWorkshop && !model.isFavorite && favContainer.mouseOverFav) ? 1 : 0
                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: 500
                                                    easing.type: Easing.BezierSpline
                                                    easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                                }
                                            }
                                        }
                                    }

                                MouseArea {
                                    id: scaleMouseArea
                                    anchors.centerIn: delegateRoot
                                    width: active ? cardScale * baseWidth : baseWidth
                                    height: active ? cardScale * baseHeight : baseHeight
                                    hoverEnabled: true
                                    propagateComposedEvents: true
                                    acceptedButtons: delegateRoot.workshopInfoOpen
                                    ? Qt.RightButton
                                    : (Qt.LeftButton | Qt.RightButton)
                                    z: 1
                                    onEntered: {
                                        window.anyHovered = true
                                        window.setHoveredIndex(index)
                                    }

                                    onExited: {
                                        window.anyHovered = false
                                        if (!favContainer.mouseOverFav)
                                            Qt.callLater(() => window.clearHoveredIndex(index))
                                    }
                                    onDoubleClicked: {
                                        if (mouse.modifiers & Qt.ShiftModifier)
                                            return

                                        if (delegateRoot.isWorkshopItem) {
                                            window.openWorkshopInSteam(delegateRoot.workshopId)
                                            return
                                        }

                                        applyWallpaper(model)
                                    }
                                    onClicked: mouse => {
                                        if (delegateRoot.isWorkshopItem) {
                                            if (mouse.button === Qt.RightButton) {
                                                listView.currentIndex = index

                                                const willOpen = steamWorkshop.openInfoId !== delegateRoot.workshopId
                                                steamWorkshop.openInfoId = willOpen ? delegateRoot.workshopId : ""

                                                if (willOpen) {
                                                    if (delegateRoot.workshopFileSize <= 0)
                                                        steamWorkshop.fetchFileSize(delegateRoot.workshopId)

                                                    if (delegateRoot.workshopCreatorName === "")
                                                        steamWorkshop.fetchCreatorInfo(delegateRoot.workshopId)
                                                }
                                                return
                                            }

                                            if (mouse.button === Qt.LeftButton) {
                                                listView.currentIndex = index
                                                return
                                            }

                                            return
                                        }

                                        if (mouse.modifiers & Qt.ShiftModifier) {
                                            let path = stripFileScheme(model.folder).replace(/\/$/, "")
                                            let idx = window.playlist.indexOf(path)

                                            if (idx === -1) {
                                                window.playlist = [...window.playlist, path]
                                                if (showPlaylist) {
                                                    filterWallpapersAnimation()
                                                }
                                            } else {
                                                window.playlist = window.playlist.filter((_, i) => i !== idx)
                                                if (showPlaylist) {
                                                    filterWallpapersAnimation()
                                                }
                                            }

                                            if (window.playlist.length === 0) {
                                                window.playlistActive = false
                                            }

                                            saveSettings()
                                        }
                                    }

                                    onWheel: function (wheel) {
                                        if (filterAnimation.running) return;
                                        window.keyboardNavigation = false;
                                        if (wheel.angleDelta.y > 0)
                                            listView.currentIndex = Math.max(0, listView.currentIndex - 1);
                                        else
                                            listView.currentIndex = Math.min(listView.count - 1, listView.currentIndex + 1);
                                    }
                                }
                            }

                            Keys.onTabPressed: event => {
                                if (window.suggestions.length > 0) {
                                    let selectedItem = "";

                                    if (suggestionList.hoverItem !== "") {
                                        selectedItem = suggestionList.hoverItem;
                                    } else if (window.suggestionIndex >= 0) {
                                        selectedItem = window.suggestions[window.suggestionIndex];
                                    }

                                    if (selectedItem !== "") {
                                        acceptSuggestion(selectedItem);
                                    }

                                    event.accepted = true;
                                }
                            }
                            Keys.onEscapePressed: event => {
                                if (window.showHelp) {
                                    window.showHelp = false;
                                    window.suggestions = [];
                                    window.suggestionIndex = -1;
                                    listView.forceActiveFocus();
                                    event.accepted = true;
                                    return;
                                }
                                if (window.suggestions.length > 0) {
                                    window.suggestions = [];
                                    window.suggestionIndex = -1;
                                    event.accepted = true;
                                    return;
                                }
                                doQuit()
                            }

                            Keys.onUpPressed: event => {
                                if (window.suggestions.length > 0) {
                                    suggestionList.hoverItem = "";
                                    suggestionList.hoverLocked = true;

                                    let newIndex = window.suggestionIndex;
                                    if (newIndex < 0)
                                        newIndex = 0;

                                    window.suggestionIndex = Math.max(0, newIndex - 1);
                                    event.accepted = true;
                                }
                            }

                            Keys.onDownPressed: event => {
                                if (window.suggestions.length > 0) {
                                    suggestionList.hoverItem = "";
                                    suggestionList.hoverLocked = true;

                                    let newIndex = window.suggestionIndex;
                                    if (newIndex < 0)
                                        newIndex = 0;

                                    window.suggestionIndex = Math.min(window.suggestions.length - 1, newIndex + 1);
                                    event.accepted = true;
                                }
                            }

                            Keys.onLeftPressed: event => {
                                if (filterAnimation.running) { event.accepted = true; return; }
                                window.keyboardNavigation = true;
                                listView.currentIndex = Math.max(0, listView.currentIndex - 1);
                            }

                            Keys.onRightPressed: event => {
                                if (filterAnimation.running) { event.accepted = true; return; }
                                window.keyboardNavigation = true;
                                listView.currentIndex = Math.min(listView.count - 1, listView.currentIndex + 1);
                            }

                            Keys.onReturnPressed: event => {
                                if (window.showHelp) {
                                    window.showHelp = false;
                                    return;
                                }
                                if (window.playlist.length > 0) {
                                    window.playlistActive = !window.playlistActive;
                                    if (window.playlistActive) {
                                        window.playlistLastApplied = 0;
                                    }
                                    saveSettings();
                                    showStatus(window.playlistActive ? "Playlist started · " + window.playlist.length + " wallpapers · every " + window.playlistInterval + "m" : "Playlist stopped");
                                    return;
                                }
                                applyWallpaper(getCurrentFilteredItem());
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: window.showHelp
                    z: 9
                    onClicked: window.showHelp = false
                }

                Rectangle {
                    id: helpPopup
                    visible: opacity > 0
                    opacity: window.showHelp ? 1 : 0
                    anchors.centerIn: parent
                    width: 605
                    height: 472
                    radius: 14
                    color: Theme.background90
                    border.color: Theme.border
                    border.width: 1
                    z: 10

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onWheel: event => event.accepted = true
                    }

                    Text {
                        id: helpTitle
                        anchors.top: parent.top
                        anchors.topMargin: 24
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Commands"
                        color: Theme.text
                        font.pixelSize: 25
                        font.weight: Font.Medium
                    }

                    Text {
                        id: helpFooter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 16
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Esc / Enter to close"
                        color: Theme.text
                        font.pixelSize: 12
                        opacity: 0.4
                    }

                    ListView {
                        anchors.top: helpTitle.bottom
                        anchors.bottom: helpFooter.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 24
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        boundsBehavior: Flickable.StopAtBounds

                        MouseArea {
                            hoverEnabled: true
                        }

                        clip: true
                        spacing: 0

                        model: [
                            {
                                cmd: ":static          |  :s",
                                desc: "Toggle static wallpapers"
                            },
                            {
                                cmd: ":dynamic         |  :d",
                                desc: "Toggle dynamic wallpapers"
                            },
                            {
                                cmd: ":favorite        |  :f",
                                desc: "Toggle favorites filter"
                            },
                            {
                                cmd: "Customizeable    |  :sus",
                                desc: "Toggle Mature content filter"
                            },
                            {
                                cmd: ":rename <name>   |  :rn ",
                                desc: "Renames highlighted wallpaper"
                            },
                            {
                                cmd: ":rename          |  :rn ",
                                desc: "Removes the current rename."
                            },
                            {
                                cmd: ":gif             |    ",
                                desc: "Toggle animated gif preview"
                            },
                            {
                                cmd: ":playlist<mins>  |  :pl",
                                desc: "Set playlist interval in minutes"
                            },
                            {
                                cmd: ":playlist        |  :pl",
                                desc: "Toggle playlist filter"
                            },
                            {
                                cmd: ":playlistshuffle |  :pls",
                                desc: "Makes playlist random"
                            },
                            {
                                cmd: "Shift+Click      |    ",
                                desc: "Add/remove wallpaper from playlist"
                            },
                            {
                                cmd: "Shift+Enter      |    ",
                                desc: "Start/stop playlist when items added"
                            },
                            {
                                cmd: ":width           |    ",
                                desc: "Set wallpaper cards width"
                            },
                            {
                                cmd: ":height          |    ",
                                desc: "Set wallpaper cards height"
                            },
                            {
                                cmd: ":spacing         |    ",
                                desc: "Set wallpaper cards spacing"
                            },
                            {
                                cmd: ":scale           |    ",
                                desc: "Set selected wallpapers scale"
                            },
                            {
                                cmd: ":random          |  :r",
                                desc: "Apply a random dynamic wallpaper"
                            },
                            {
                                cmd: ":randomstatic    |  :rs",
                                desc: "Apply a random static wallpaper"
                            },
                            {
                                cmd: ":randomfav       |  :rf",
                                desc: "Apply a random favorited wallpaper"
                            },
                            {
                                cmd: ":export <filter> |  :ex",
                                desc: "Export filtered wallpaper as steam URLs"
                            },
                            {
                                cmd: ":setfolder       |  :sf",
                                desc: "Set dynamic wallpapers folder"
                            },
                            {
                                cmd: ":setstatic       |  :ss",
                                desc: "Set static wallpapers folder"
                            },
                            {
                                cmd: ":setthumb        |  :st",
                                desc: "Set thumbnail cache folder"
                            },
                            {
                                cmd: ":setffmpeg       |     ",
                                desc: "Set ffmpeg path"
                            },
                            {
                                cmd: ":clearcache      |  :cc",
                                desc: "Clear thumbnail cache and regenerate"
                            },
                            {
                                cmd: ":reload          |  :rl",
                                desc: "Reload wallpaper folders"
                            },
                            {
                                cmd: ":open            |  :o ",
                                desc: "Open workshop for highlighted wallpaper"
                            },
                            {
                                cmd: ":id              |     ",
                                desc: "Copy highlighted wallpapers id"
                            },
                            {
                                cmd: ":tag <name>      |     ",
                                desc: "Filter by tag"
                            },
                            {
                                cmd: ":tag             |     ",
                                desc: "Clear tag filter"
                            },
                            {
                                cmd: ":sort            |     ",
                                desc: "Sorts wallpapers"
                            },
                            {
                                cmd: "Sort Arguments   |",
                                desc: "default, name, recent, favorite, random"
                            },
                            {
                                cmd: "Sort Shortcuts   |",
                                desc: "d,       n,    r,      f,"
                            },
                            {
                                cmd: ":help            |   :h",
                                desc: "Show this help"
                            }
                        ]

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 36
                            radius: 6

                            color: index % 2 === 0 ? "transparent" : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)

                            Row {
                                anchors.fill: parent
                                anchors.margins: 8

                                Text {
                                    width: 220
                                    text: modelData.cmd
                                    color: Theme.text
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    text: modelData.desc
                                    color: Theme.text
                                    font.pixelSize: 13
                                    opacity: 0.6
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: workshopAuthPopup
                    visible: opacity > 0
                    opacity: window.showWorkshopAuth ? 1 : 0
                    anchors.centerIn: parent
                    width: 420
                    height: steamWorkshop.hasStoredKey ? cardHeight * 0.611 : cardHeight * 0.833
                    radius: 15
                    color: Theme.background90
                    border.color: Theme.border
                    border.width: 1
                    z: 11

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                        }
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onWheel: event => event.accepted = true
                        onClicked: {}
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 14
                        width: parent.width - 60

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "Steam API Key Setup"
                            color: Theme.text
                            font.pixelSize: 18
                            font.weight: Font.Medium
                        }

                        Rectangle {
                            width: parent.width
                            height: 38
                            radius: 15
                            color: Theme.background
                            border.color: Theme.border
                            border.width: 1

                            TextField {
                                id: apiKeyField
                                anchors.fill: parent
                                anchors.margins: 1
                                background: Item {}
                                color: Theme.text
                                placeholderText: "Steam API key"
                                placeholderTextColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.35)
                                font.pixelSize: 13
                                leftPadding: 12
                                echoMode: TextInput.Password

                                Keys.onReturnPressed: authConfirmButton.clicked()
                                Keys.onEscapePressed: {
                                    window.showWorkshopAuth = false
                                    apiKeyField.text = ""
                                    authErrorText.text = ""
                                    listView.forceActiveFocus()
                                }
                            }
                        }

                        Text {
                            id: authErrorText
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: steamWorkshop.errorString
                            color: "#e06c75"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            visible: text.length > 0
                        }

                        Rectangle {
                            id: authConfirmButton
                            width: parent.width
                            height: 38
                            radius: 12
                            color: confirmMouse.containsMouse
                                ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)
                                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                            Behavior on color {
                                ColorAnimation {
                                    duration: 300
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                                }
                            }

                            signal clicked()

                            onClicked: {
                                let key = apiKeyField.text.trim()

                                if (key === "") {
                                    authErrorText.text = "API key cannot be empty"
                                    return
                                }

                                if (steamWorkshop.saveApiKey(key)) {
                                    window.showWorkshopAuth = false
                                    apiKeyField.text = ""
                                    authErrorText.text = ""

                                    window.workshopMode = true
                                    steamWorkshop.activateWorkshop()
                                    showStatus("Workshop mode")
                                    listView.forceActiveFocus()
                                } else {
                                    console.log("steam workshop error:", steamWorkshop.errorString)
                                    authErrorText.text = steamWorkshop.errorString !== ""
                                        ? steamWorkshop.errorString
                                        : "Failed to save API key"
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "Save API Key"
                                color: Theme.text
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: confirmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: authConfirmButton.clicked()
                            }
                        }
                    }

                    onVisibleChanged: {
                        if (visible) {
                            Qt.callLater(function() {
                                if (apiKeyField)
                                    apiKeyField.forceActiveFocus()
                            })
                        }
                    }
                }

                Text {
                    id: emptyStateText
                    anchors.centerIn: parent

                    property string targetText: window.workshopMode
                        ? ""
                        : window.wasInCommandMode
                            ? "  Command Mode"
                            : "  No wallpapers found"

                    text: ""
                    visible: listView.count === 0 && !isInitialLoad
                    color: Theme.text
                    font.pixelSize: 24

                    Component.onCompleted: text = targetText

                    onTargetTextChanged: textChangeAnimation.restart()

                    SequentialAnimation {
                        id: textChangeAnimation

                        NumberAnimation {
                            target: emptyStateText
                            property: "opacity"
                            to: 0
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                        }

                        ScriptAction {
                            script: emptyStateText.text = emptyStateText.targetText
                        }

                        NumberAnimation {
                            target: emptyStateText
                            property: "opacity"
                            to: 1
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                        }
                    }
                }
            }
        }
    }
}
