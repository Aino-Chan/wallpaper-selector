import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import SteamWorkshopService 1.0 as SteamBackend

Item {
    id: root

    property string weDir: ""
    property string searchText: ""
    property string sortMode: "popular"
    property string requiredTag: ""

    readonly property bool hasStoredKey: backend.hasStoredKey
    readonly property bool loading: backend.loading
    readonly property bool online: ("online" in backend) ? backend.online : true
    readonly property string errorString: backend.errorString
    readonly property int currentPage: backend.currentPage
    readonly property int totalResults: backend.totalResults
    readonly property int visibleResults: workshopFilteredModel.count

    property ListModel workshopMasterModel: ListModel {}
    property ListModel workshopFilteredModel: ListModel {}

    property int loadedPages: 0
    property bool hasMore: true
    property bool appendMode: false
    property bool prefetchQueued: false
    property bool showMatureContent: false
    property string pendingRestoreId: ""
    property string openInfoId: ""
    property string selectedWorkshopId: ""
    property int maxRestorePages: 4
    property int restorePagesFetched: 0
    property bool restoreMayPaginate: false
    property string lastSearchSignature: ""

    property var localWorkshopIds: ({})     
    property var downloadStatus: ({})        
    property var downloadProgress: ({})
    property var fetchedFileSizes: ({})
    property var fetchedCreatorNames: ({})
    property var fetchedCreatorUrls: ({})
    property var fetchedCreatorInfoIds: ({})
    property var requestedItemDetails: ({})
    property var workshopMasterIndexes: ({})
    property var workshopFilteredIndexes: ({})
    property bool installedScanValid: false
    property string installedScanDir: ""

    signal requestOpen()
    signal requestClose()
    signal wallpaperInstalled(string workshopId)
    signal selectionRequested(int index, bool center)

    onWeDirChanged: {
        if (installedScanDir !== weDir)
            installedScanValid = false
    }

    SteamBackend.SteamWorkshopService {
        id: backend
        showMatureContent: root.showMatureContent

        onResultsChanged: {
            root.consumeBackendResults()
        }

        onSearchFinished: function(ok) {
            if (!ok) {
                root.appendMode = false
                root.prefetchQueued = false
            }
        }

        onFileSizeFetched: function(publishedFileId, fileSize) {
            const wid = String(publishedFileId)
            const sizeNum = Number(fileSize)

            const nextSizes = Object.assign({}, root.fetchedFileSizes)
            nextSizes[wid] = sizeNum
            root.fetchedFileSizes = nextSizes

            root.setIndexedProperty(
                root.workshopMasterModel,
                root.workshopMasterIndexes,
                wid,
                "fileSize",
                sizeNum
            )
            root.setIndexedProperty(
                root.workshopFilteredModel,
                root.workshopFilteredIndexes,
                wid,
                "fileSize",
                sizeNum
            )
        }

        onCreatorInfoFetched: function(publishedFileId, creatorName, creatorUrl) {
            const wid = String(publishedFileId)
            const name = String(creatorName || "")
            const url = String(creatorUrl || "")

            const nextNames = Object.assign({}, root.fetchedCreatorNames)
            nextNames[wid] = name
            root.fetchedCreatorNames = nextNames

            const nextUrls = Object.assign({}, root.fetchedCreatorUrls)
            nextUrls[wid] = url
            root.fetchedCreatorUrls = nextUrls

            const completed = Object.assign({}, root.fetchedCreatorInfoIds)
            completed[wid] = true
            root.fetchedCreatorInfoIds = completed

            root.updateCreatorInModel(
                root.workshopMasterModel,
                root.workshopMasterIndexes,
                wid,
                name,
                url
            )
            root.updateCreatorInModel(
                root.workshopFilteredModel,
                root.workshopFilteredIndexes,
                wid,
                name,
                url
            )
        }

        onItemDetailsFetchFinished: function(publishedFileId, ok) {
            const wid = String(publishedFileId)
            const next = Object.assign({}, root.requestedItemDetails)
            delete next[wid]
            root.requestedItemDetails = next
        }
    }

    Timer {
        id: prefetchTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (!root.prefetchQueued)
                return

            root.prefetchQueued = false

            if (!root.hasMore || root.loading)
                return

            root.fetchNextPage()
        }
    }

    Process {
        id: scanProc

        property string requestedDir: ""

        command: requestedDir.length > 0
            ? ["find", requestedDir, "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-printf", "%f\n"]
            : ["sh", "-c", "true"]

        stdout: SplitParser {
            id: scanParser
            splitMarker: "\n"
            property var foundIds: ({})
            onRead: data => {
                const id = (data || "").trim()
                if (/^\d+$/.test(id))
                    foundIds[id] = true
            }
        }

        onExited: function(exitCode) {
            if (exitCode === 0 && root.weDir === requestedDir) {
                root.localWorkshopIds = scanParser.foundIds
                root.installedScanDir = requestedDir
                root.installedScanValid = true
            }
            scanParser.foundIds = ({})
        }
    }

    function hasOwn(object, key) {
        return Object.prototype.hasOwnProperty.call(object, key)
    }

    function validIndexedModelIndex(model, indexes, workshopId) {
        const key = "$" + workshopId
        const index = indexes[key]

        if (index === undefined || index < 0 || index >= model.count)
            return -1

        if (String(model.get(index).id || "") !== workshopId)
            return -1

        return index
    }

    function setIndexedProperty(model, indexes, workshopId, propertyName, value) {
        const index = validIndexedModelIndex(model, indexes, workshopId)
        if (index >= 0)
            model.setProperty(index, propertyName, value)
    }

    function updateCreatorInModel(model, indexes, workshopId, name, url) {
        const index = validIndexedModelIndex(model, indexes, workshopId)
        if (index < 0)
            return

        model.setProperty(index, "creatorName", name)
        model.setProperty(index, "creatorUrl", url)

        if (name !== "") {
            const oldBlob = String(model.get(index).searchBlob || "")
            const lowerName = name.toLowerCase()
            if (oldBlob.indexOf(lowerName) === -1)
                model.setProperty(index, "searchBlob", oldBlob + "\n" + lowerName)
        }
    }

    function fetchItemDetails(publishedFileId) {
        const wid = String(publishedFileId || "").trim()
        if (wid === "" || requestedItemDetails[wid])
            return

        const hasSize = hasOwn(fetchedFileSizes, wid)
        const hasCreator = !!fetchedCreatorInfoIds[wid]
        if (hasSize && hasCreator)
            return

        const next = Object.assign({}, requestedItemDetails)
        next[wid] = true
        requestedItemDetails = next
        backend.fetchItemDetails(wid)
    }

    // Compatibility functions used by the existing main QML delegate. Calls
    // made back-to-back are collapsed into one backend request.
    function fetchFileSize(publishedFileId) {
        fetchItemDetails(publishedFileId)
    }

    function fetchCreatorInfo(publishedFileId) {
        fetchItemDetails(publishedFileId)
    }

    function saveApiKey(apiKey) {
        return backend.saveApiKey(apiKey)
    }

    function deleteStoredKey() {
        const ok = backend.deleteStoredKey()
        if (ok) {
            requestedItemDetails = ({})
            fetchedFileSizes = ({})
            fetchedCreatorNames = ({})
            fetchedCreatorUrls = ({})
            fetchedCreatorInfoIds = ({})
        }
        return ok
    }

    function activateWorkshop() {
        scanInstalled()

        if (workshopMasterModel.count === 0 && !loading) {
            runSearch(searchText)
        }
    }

    function prepareNewSearch() {
        loadedPages = 0
        hasMore = true
        appendMode = false
        prefetchQueued = false
    }

    function runSearch(text) {
        const nextText = String(text || "")
        const signature = searchSignature(nextText)

        rememberCurrentWorkshopSelection()

        restoreMayPaginate =
            lastSearchSignature === "" ||
            lastSearchSignature === signature

        lastSearchSignature = signature
        searchText = nextText

        prepareNewSearch()

        let backendTag = requiredTag
        let lowerTag = String(requiredTag || "").trim().toLowerCase()

        if (["everyone", "mature", "questionable", "nsfw"].includes(lowerTag))
            backendTag = ""

        backend.search(searchText, 1, sortMode, backendTag)
    }

    function fetchNextPage() {
        if (loading || !hasMore)
            return

        const nextPage = loadedPages + 1

        appendMode = true

        let backendTag = requiredTag
        let lowerTag = String(requiredTag || "").trim().toLowerCase()

        if (lowerTag === "everyone" || lowerTag === "mature" || lowerTag === "questionable" || lowerTag === "nsfw")
            backendTag = ""

        backend.search(searchText, nextPage, sortMode, backendTag)
    }

    function maybePrefetchByView(contentX, viewWidth, contentWidth) {
        if (loading || !hasMore)
            return

        const remaining = contentWidth - (contentX + viewWidth)

        if (remaining <= viewWidth * 2) {
            prefetchQueued = true
            if (!prefetchTimer.running)
                prefetchTimer.start()
        }
    }

    function searchSignature(text) {
        return JSON.stringify([
            String(text || "").trim().toLowerCase(),
            String(sortMode || ""),
            String(requiredTag || "").trim().toLowerCase(),
            showMatureContent
        ])
    }

    function rememberCurrentWorkshopSelection() {
        pendingRestoreId = String(selectedWorkshopId || "").trim()
        restorePagesFetched = 0
    }

    function consumeBackendResults() {
        const pageResults = backend.results || []
        const wasAppend = appendMode
        const pageItems = []

        let indexes

        if (!wasAppend) {
            workshopMasterModel.clear()
            indexes = {}
        } else {
            indexes = Object.assign({}, workshopMasterIndexes)
        }

        for (let i = 0; i < pageResults.length; ++i) {
            const r = pageResults[i]
            const wid = String(r.id || "")

            if (wid === "")
                continue

            const updatedItem = {
                id: wid,
                title: String(r.title || ""),
                description: String(r.description || ""),
                previewUrl: String(r.previewUrl || ""),
                creatorName: String(
                    root.fetchedCreatorNames[wid]
                    || r.creatorName
                    || ""
                ),
                creatorUrl: String(
                    root.fetchedCreatorUrls[wid]
                    || r.creatorUrl
                    || ""
                ),
                isMature: !!r.isMature,
                fileSize: Number(
                    root.fetchedFileSizes[wid]
                    ?? r.fileSize
                    ?? 0
                ),
                subscriptions: Number(r.subscriptions || 0),
                favorited: Number(r.favorited || 0),
                tags: String(r.tags || "[]"),
                lowerTags: String(r.lowerTags || ""),
                searchBlob: String(r.searchBlob || "")
            }

            pageItems.push(updatedItem)

            const key = "$" + wid
            const existingIndex = indexes[key]

            if (existingIndex !== undefined) {
                if (!workshopItemsEqual(
                        workshopMasterModel.get(existingIndex),
                        updatedItem)) {
                    workshopMasterModel.set(existingIndex, updatedItem)
                }
            } else {
                const newIndex = workshopMasterModel.count
                workshopMasterModel.append(updatedItem)
                indexes[key] = newIndex
            }
        }

        workshopMasterIndexes = indexes

        loadedPages = Math.max(1, Number(backend.currentPage || 1))
        hasMore = !!backend.hasMore
        appendMode = false

        if (wasAppend)
            appendFilteredPageItems(pageItems)
        else
            filterWorkshopItems()

        if (pendingRestoreId !== "") {
            const restoreId = pendingRestoreId

            Qt.callLater(function() {
                for (let i = 0; i < workshopFilteredModel.count; ++i) {
                    if (String(workshopFilteredModel.get(i).id) === restoreId) {
                        pendingRestoreId = ""
                        root.selectionRequested(i, true)
                        return
                    }
                }

                if (hasMore &&
                    restoreMayPaginate &&
                    restorePagesFetched < maxRestorePages &&
                    !loading) {

                    restorePagesFetched += 1
                    fetchNextPage()
                } else {
                    pendingRestoreId = ""

                    if (workshopFilteredModel.count > 0)
                        root.selectionRequested(0, false)
                }
            })
        } else if (loadedPages === 1 &&
                workshopFilteredModel.count > 0) {
            root.selectionRequested(0, false)
        }
    }

    function workshopItemsEqual(a, b) {
        return String(a.id || "") === String(b.id || "")
            && String(a.title || "") === String(b.title || "")
            && String(a.description || "") === String(b.description || "")
            && String(a.previewUrl || "") === String(b.previewUrl || "")
            && String(a.creatorName || "") === String(b.creatorName || "")
            && String(a.creatorUrl || "") === String(b.creatorUrl || "")
            && Number(a.fileSize || 0) === Number(b.fileSize || 0)
            && Number(a.subscriptions || 0) === Number(b.subscriptions || 0)
            && Number(a.favorited || 0) === Number(b.favorited || 0)
            && String(a.tags || "") === String(b.tags || "")
            && !!a.isMature === !!b.isMature
            && String(a.lowerTags || "") === String(b.lowerTags || "")
            && String(a.searchBlob || "") === String(b.searchBlob || "")
    }

    function itemMatchesCurrentFilters(item) {
        const required = String(requiredTag || "").trim().toLowerCase()
        const needle = String(searchText || "").trim().toLowerCase()
        const lowerTags = String(item.lowerTags || "")
        const searchBlob = String(item.searchBlob || "")

        const matchesText =
            needle === "" || searchBlob.indexOf(needle) !== -1

        let matchesTag = true
        if (required === "everyone") {
            matchesTag = !item.isMature
        } else if (
            required === "mature" ||
            required === "questionable" ||
            required === "nsfw"
        ) {
            matchesTag = item.isMature
        } else if (required !== "") {
            // lowerTags is framed with U+001F by the C++ backend, so this is
            // exact and also supports multi-word tags.
            matchesTag = lowerTags.indexOf("\u001f" + required + "\u001f") !== -1
        }

        const matchesMature = root.showMatureContent || !item.isMature
        return matchesText && matchesTag && matchesMature
    }

    function makeFilteredItem(item) {
        const wid = String(item.id || "")
        return {
            id: wid,
            title: item.title,
            description: item.description,
            previewUrl: item.previewUrl,
            creatorName: String(
                root.fetchedCreatorNames[wid] || item.creatorName || ""
            ),
            creatorUrl: String(
                root.fetchedCreatorUrls[wid] || item.creatorUrl || ""
            ),
            fileSize: Number(
                root.fetchedFileSizes[wid] ?? item.fileSize ?? 0
            ),
            subscriptions: Number(item.subscriptions || 0),
            favorited: Number(item.favorited || 0),
            tags: String(item.tags || "[]"),
            lowerTags: String(item.lowerTags || ""),
            searchBlob: String(item.searchBlob || ""),
            isMature: !!item.isMature
        }
    }

    function rebuildFilteredIndexes() {
        const indexes = {}
        for (let i = 0; i < workshopFilteredModel.count; ++i) {
            const wid = String(workshopFilteredModel.get(i).id || "")
            if (wid !== "")
                indexes["$" + wid] = i
        }
        workshopFilteredIndexes = indexes
    }

    function appendFilteredPageItems(pageItems) {
        let indexes = Object.assign({}, workshopFilteredIndexes)

        for (let i = 0; i < pageItems.length; ++i) {
            const item = pageItems[i]
            const wid = String(item.id || "")
            if (wid === "")
                continue

            const key = "$" + wid
            const existingIndex = indexes[key]

            if (!itemMatchesCurrentFilters(item)) {
                // Duplicate IDs whose filter-relevant data changed are rare;
                // use the full reconciler for that exceptional case.
                if (existingIndex !== undefined) {
                    filterWorkshopItems()
                    return
                }
                continue
            }

            const filteredItem = makeFilteredItem(item)
            if (existingIndex !== undefined &&
                existingIndex >= 0 &&
                existingIndex < workshopFilteredModel.count &&
                String(workshopFilteredModel.get(existingIndex).id) === wid) {

                if (!workshopItemsEqual(
                        workshopFilteredModel.get(existingIndex),
                        filteredItem)) {
                    workshopFilteredModel.set(existingIndex, filteredItem)
                }
                continue
            }

            const newIndex = workshopFilteredModel.count
            workshopFilteredModel.append(filteredItem)
            indexes[key] = newIndex
        }

        workshopFilteredIndexes = indexes
    }

    function filterWorkshopItems() {
        const items = []
        const wantedIndexes = {}

        for (let i = 0; i < workshopMasterModel.count; ++i) {
            const item = workshopMasterModel.get(i)
            if (!itemMatchesCurrentFilters(item))
                continue

            const wid = String(item.id || "")
            const filteredItem = makeFilteredItem(item)

            wantedIndexes["$" + wid] = items.length
            items.push(filteredItem)
        }

        let previousTargetIndex = -1
        let modelWasReordered = false

        for (let i = 0; i < workshopFilteredModel.count; ++i) {
            const key = "$" + String(workshopFilteredModel.get(i).id || "")
            const targetIndex = wantedIndexes[key]

            if (targetIndex === undefined)
                continue

            if (targetIndex <= previousTargetIndex) {
                modelWasReordered = true
                break
            }

            previousTargetIndex = targetIndex
        }


        if (modelWasReordered) {
            workshopFilteredModel.clear()

            for (let i = 0; i < items.length; ++i)
                workshopFilteredModel.append(items[i])

            rebuildFilteredIndexes()
            return
        }

        let removalEnd = -1

        for (let i = workshopFilteredModel.count - 1; i >= 0; --i) {
            const id = String(workshopFilteredModel.get(i).id || "")
            const wanted = wantedIndexes["$" + id] !== undefined

            if (!wanted) {
                if (removalEnd === -1)
                    removalEnd = i
            } else if (removalEnd !== -1) {
                const removalStart = i + 1
                workshopFilteredModel.remove(
                    removalStart,
                    removalEnd - removalStart + 1
                )
                removalEnd = -1
            }
        }

        if (removalEnd !== -1)
            workshopFilteredModel.remove(0, removalEnd + 1)


        for (let i = 0; i < items.length; ++i) {
            const wantedItem = items[i]

            if (i >= workshopFilteredModel.count) {
                workshopFilteredModel.append(wantedItem)
                continue
            }

            const currentItem = workshopFilteredModel.get(i)

            if (String(currentItem.id) !== String(wantedItem.id)) {
                workshopFilteredModel.insert(i, wantedItem)
            } else if (!workshopItemsEqual(currentItem, wantedItem)) {
                workshopFilteredModel.set(i, wantedItem)
            }
        }

        if (workshopFilteredModel.count > items.length) {
            workshopFilteredModel.remove(
                items.length,
                workshopFilteredModel.count - items.length
            )
        }

        rebuildFilteredIndexes()
    }

    function scanInstalled(force) {
        if (!weDir || weDir.length === 0)
            return

        const shouldForce = !!force
        if (!shouldForce && installedScanValid && installedScanDir === weDir)
            return

        if (scanProc.running)
            return

        scanParser.foundIds = ({})
        scanProc.requestedDir = weDir
        scanProc.running = true
    }

    function isInstalled(workshopId) {
        return !!localWorkshopIds[String(workshopId)]
    }

    function getDownloadStatus(workshopId) {
        return downloadStatus[String(workshopId)] || ""
    }

    function getDownloadProgress(workshopId) {
        return downloadProgress[String(workshopId)] || 0
    }

    function setDownloadStatus(workshopId, value) {
        const next = Object.assign({}, downloadStatus)
        next[String(workshopId)] = value
        downloadStatus = next
    }

    function setDownloadProgress(workshopId, value) {
        const next = Object.assign({}, downloadProgress)
        next[String(workshopId)] = value
        downloadProgress = next
    }

    function markInstalled(workshopId) {
        const next = Object.assign({}, localWorkshopIds)
        next[String(workshopId)] = true
        localWorkshopIds = next
    }

    function queueDownload(workshopId) {
        if (isInstalled(workshopId))
            return

        setDownloadStatus(workshopId, "queued")
        setDownloadProgress(workshopId, 0)
    }
}
