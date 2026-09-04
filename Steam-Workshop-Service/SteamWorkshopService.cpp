#include "SteamWorkshopService.h"

#include "SteamWorkshopSecrets.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>
#include <QtGlobal>

#include <utility>

namespace {

constexpr const char *kWallpaperEngineAppId = "431960";
constexpr int kPageSize = 40;
constexpr int kSearchCacheAgeSeconds = 120;
constexpr int kTransferTimeoutMs = 12000;

qlonglong jsonInteger(const QJsonValue &value) {
    if (value.isString())
        return value.toString().toLongLong();

    if (value.isDouble())
        return static_cast<qlonglong>(value.toDouble());

    return 0;
}

QString creatorUrlFor(const QString &creatorId) {
    if (creatorId.isEmpty())
        return QString();

    return QStringLiteral(
        "https://steamcommunity.com/profiles/%1/myworkshopfiles/?appid=431960"
    ).arg(creatorId);
}

QString tagsToJson(const QStringList &tags) {
    QJsonArray array;
    for (const QString &tag : tags)
        array.append(tag);

    return QString::fromUtf8(
        QJsonDocument(array).toJson(QJsonDocument::Compact)
    );
}

QString framedTagBlob(const QStringList &lowerTags) {
    const QChar separator(0x1f);
    QString result(separator);
    result += lowerTags.join(separator);
    result += separator;
    return result;
}

} 

SteamWorkshopService::SteamWorkshopService(QObject *parent)
    : QObject(parent) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 7, 0)
    m_network.setTransferTimeout(kTransferTimeoutMs);
#endif

    QString error;
    m_hasStoredKey = SteamWorkshopSecrets::hasApiKey(&error);

    if (!m_hasStoredKey) {
        if (!error.isEmpty())
            setErrorString(error);
        return;
    }

    if (!loadApiKeyFromKeyring()) {
        m_hasStoredKey = false;
        emit hasStoredKeyChanged();
    }
}

bool SteamWorkshopService::hasStoredKey() const {
    return m_hasStoredKey;
}

bool SteamWorkshopService::loading() const {
    return m_loading;
}

bool SteamWorkshopService::showMatureContent() const {
    return m_showMatureContent;
}

void SteamWorkshopService::setShowMatureContent(bool value) {
    if (m_showMatureContent == value)
        return;

    m_showMatureContent = value;
    emit showMatureContentChanged();
}

QString SteamWorkshopService::errorString() const {
    return m_errorString;
}

QVariantList SteamWorkshopService::results() const {
    return m_results;
}

int SteamWorkshopService::currentPage() const {
    return m_currentPage;
}

int SteamWorkshopService::totalResults() const {
    return m_totalResults;
}

bool SteamWorkshopService::hasMore() const {
    return m_hasMore;
}

void SteamWorkshopService::setErrorString(const QString &s) {
    if (m_errorString == s)
        return;

    m_errorString = s;
    emit errorStringChanged();
}

void SteamWorkshopService::setLoading(bool value) {
    if (m_loading == value)
        return;

    m_loading = value;
    emit loadingChanged();
}

void SteamWorkshopService::setHasMore(bool value) {
    if (m_hasMore == value)
        return;

    m_hasMore = value;
    emit hasMoreChanged();
}

bool SteamWorkshopService::loadApiKeyFromKeyring() {
    QString apiKey;
    QString error;

    if (!SteamWorkshopSecrets::readApiKey(&apiKey, &error)) {
        m_apiKey.fill('\0');
        m_apiKey.clear();
        setErrorString(error);
        return false;
    }

    if (apiKey.isEmpty()) {
        m_apiKey.fill('\0');
        m_apiKey.clear();
        setErrorString(QStringLiteral("Stored API key is empty"));
        return false;
    }

    m_apiKey.fill('\0');
    m_apiKey.clear();
    m_apiKey = apiKey.toUtf8();

    apiKey.fill(u'\0');
    apiKey.clear();

    setErrorString(QString());
    return !m_apiKey.isEmpty();
}

bool SteamWorkshopService::saveApiKey(const QString &apiKey) {
    QString error;

    if (!SteamWorkshopSecrets::writeApiKey(apiKey, &error)) {
        setErrorString(error);
        return false;
    }

    if (!m_hasStoredKey) {
        m_hasStoredKey = true;
        emit hasStoredKeyChanged();
    }

    if (!loadApiKeyFromKeyring())
        return false;

    setErrorString(QString());
    return true;
}

void SteamWorkshopService::cancelOutstandingRequests() {
    ++m_searchSerial;

    if (m_searchReply)
        m_searchReply->abort();
    m_searchReply = nullptr;

    for (const QPointer<QNetworkReply> &reply : std::as_const(m_detailReplies)) {
        if (reply)
            reply->abort();
    }

    for (const QPointer<QNetworkReply> &reply : std::as_const(m_creatorReplies)) {
        if (reply)
            reply->abort();
    }

    m_detailReplies.clear();
    m_creatorReplies.clear();
    m_creatorWaiters.clear();
    setLoading(false);
}

bool SteamWorkshopService::deleteStoredKey() {
    QString error;

    if (!SteamWorkshopSecrets::deleteApiKey(&error)) {
        setErrorString(error);
        return false;
    }

    cancelOutstandingRequests();

    m_apiKey.fill('\0');
    m_apiKey.clear();

    if (m_hasStoredKey) {
        m_hasStoredKey = false;
        emit hasStoredKeyChanged();
    }

    m_results.clear();
    m_fileSizeCache.clear();
    m_creatorIdByWorkshop.clear();
    m_creatorNameBySteamId.clear();
    m_completeItemDetails.clear();

    if (m_currentPage != 1) {
        m_currentPage = 1;
        emit currentPageChanged();
    }

    if (m_totalResults != 0) {
        m_totalResults = 0;
        emit totalResultsChanged();
    }

    setHasMore(false);
    emit resultsChanged();
    setErrorString(QString());
    return true;
}

void SteamWorkshopService::search(
    const QString &query,
    int page,
    const QString &sort,
    const QString &requiredTag
) {
    if (m_apiKey.isEmpty()) {
        setErrorString(QStringLiteral("No API key available"));
        emit searchFinished(false);
        return;
    }

    const quint64 serial = ++m_searchSerial;
    if (m_searchReply)
        m_searchReply->abort();

    setLoading(true);
    setErrorString(QString());

    QUrl url(QStringLiteral(
        "https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/"
    ));
    QUrlQuery q;

    QString keyString = QString::fromUtf8(m_apiKey);
    q.addQueryItem(QStringLiteral("key"), keyString);
    keyString.fill(u'\0');
    keyString.clear();

    const int requestedPage = qMax(1, page);
    q.addQueryItem(QStringLiteral("appid"), QString::fromLatin1(kWallpaperEngineAppId));
    q.addQueryItem(QStringLiteral("filetype"), QStringLiteral("0"));
    q.addQueryItem(QStringLiteral("search_text"), query.trimmed());
    q.addQueryItem(QStringLiteral("page"), QString::number(requestedPage));
    q.addQueryItem(QStringLiteral("numperpage"), QString::number(kPageSize));
    q.addQueryItem(
        QStringLiteral("cache_max_age_seconds"),
        QString::number(kSearchCacheAgeSeconds)
    );
    q.addQueryItem(QStringLiteral("return_short_description"), QStringLiteral("1"));
    q.addQueryItem(QStringLiteral("return_previews"), QStringLiteral("1"));
    q.addQueryItem(QStringLiteral("return_tags"), QStringLiteral("1"));
    q.addQueryItem(QStringLiteral("return_vote_data"), QStringLiteral("1"));

    const QString trimmedTag = requiredTag.trimmed();
    if (!trimmedTag.isEmpty())
        q.addQueryItem(QStringLiteral("requiredtags[0]"), trimmedTag);

    const QString normalizedSort = sort.trimmed().toLower();

    int queryType = 9; 
    int trendDays = 0;
    bool recentVotesOnly = false;

    if (
        normalizedSort == QStringLiteral("popular") ||
        normalizedSort == QStringLiteral("alltime") ||
        normalizedSort == QStringLiteral("subscriptions")
    ) {
        queryType = 9;
    } else if (
        normalizedSort == QStringLiteral("day") ||
        normalizedSort == QStringLiteral("daily")
    ) {
        queryType = 3; 
        trendDays = 1;
        recentVotesOnly = true;
    } else if (
        normalizedSort == QStringLiteral("week") ||
        normalizedSort == QStringLiteral("weekly") ||
        normalizedSort == QStringLiteral("trend")
    ) {
        queryType = 3; 
        trendDays = 7;
        recentVotesOnly = true;
    } else if (
        normalizedSort == QStringLiteral("rated") ||
        normalizedSort == QStringLiteral("rating")
    ) {
        queryType = 0; 
    } else if (
        normalizedSort == QStringLiteral("votes") ||
        normalizedSort == QStringLiteral("votesup")
    ) {
        queryType = 11; 
    } else if (
        normalizedSort == QStringLiteral("recent") ||
        normalizedSort == QStringLiteral("new")
    ) {
        queryType = 1;
    } else if (
        normalizedSort == QStringLiteral("approved") ||
        normalizedSort == QStringLiteral("accepted")
    ) {
        queryType = 2; 
    } else if (normalizedSort == QStringLiteral("text")) {
        queryType = 12;
    }

    q.addQueryItem(QStringLiteral("query_type"), QString::number(queryType));

    if (trendDays > 0) {
        q.addQueryItem(QStringLiteral("days"), QString::number(trendDays));
        q.addQueryItem(
            QStringLiteral("include_recent_votes_only"),
            recentVotesOnly ? QStringLiteral("1") : QStringLiteral("0")
        );
    }

    url.setQuery(q);

    QNetworkRequest request(url);
    request.setHeader(
        QNetworkRequest::UserAgentHeader,
        QStringLiteral("SteamWorkshopService/2.0")
    );
#if QT_VERSION >= QT_VERSION_CHECK(6, 7, 0)
    request.setTransferTimeout(kTransferTimeoutMs);
#endif

    QNetworkReply *reply = m_network.get(request);
    m_searchReply = reply;
    reply->setProperty("requestedPage", requestedPage);

    connect(reply, &QNetworkReply::finished, this, [this, reply, serial]() {
        if (serial != m_searchSerial) {
            reply->deleteLater();
            return;
        }

        m_searchReply = nullptr;
        handleReply(reply);
    });
}

void SteamWorkshopService::fetchItemDetails(const QString &publishedFileId) {
    const QString workshopId = publishedFileId.trimmed();
    if (workshopId.isEmpty())
        return;

    if (m_completeItemDetails.contains(workshopId)) {
        emitCachedItemDetails(workshopId);
        return;
    }

    if (m_detailReplies.contains(workshopId) && m_detailReplies.value(workshopId))
        return;

    if (
        m_fileSizeCache.contains(workshopId) &&
        m_creatorIdByWorkshop.contains(workshopId)
    ) {
        emit fileSizeFetched(workshopId, m_fileSizeCache.value(workshopId));
        fetchCreatorSummary(workshopId, m_creatorIdByWorkshop.value(workshopId));
        return;
    }

    QUrl url(QStringLiteral(
        "https://api.steampowered.com/ISteamRemoteStorage/"
        "GetPublishedFileDetails/v1/"
    ));
    QNetworkRequest request(url);
    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/x-www-form-urlencoded")
    );
#if QT_VERSION >= QT_VERSION_CHECK(6, 7, 0)
    request.setTransferTimeout(kTransferTimeoutMs);
#endif

    QUrlQuery form;
    form.addQueryItem(QStringLiteral("itemcount"), QStringLiteral("1"));
    form.addQueryItem(QStringLiteral("publishedfileids[0]"), workshopId);
    const QByteArray body = form.toString(QUrl::FullyEncoded).toUtf8();

    QNetworkReply *reply = m_network.post(request, body);
    m_detailReplies.insert(workshopId, reply);

    connect(reply, &QNetworkReply::finished, this, [this, reply, workshopId]() {
        m_detailReplies.remove(workshopId);

        const QByteArray raw = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();

        if (networkError != QNetworkReply::NoError) {
            emit itemDetailsFetchFinished(workshopId, false);
            return;
        }

        const QJsonDocument document = QJsonDocument::fromJson(raw);
        if (!document.isObject()) {
            emit itemDetailsFetchFinished(workshopId, false);
            return;
        }

        const QJsonObject response = document.object()
            .value(QStringLiteral("response"))
            .toObject();
        const QJsonArray details = response
            .value(QStringLiteral("publishedfiledetails"))
            .toArray();

        if (details.isEmpty()) {
            emit itemDetailsFetchFinished(workshopId, false);
            return;
        }

        const QJsonObject object = details.first().toObject();
        const qlonglong fileSize = jsonInteger(
            object.value(QStringLiteral("file_size"))
        );
        const QString creatorId = object
            .value(QStringLiteral("creator"))
            .toString();

        m_fileSizeCache.insert(workshopId, qMax<qlonglong>(0, fileSize));
        m_creatorIdByWorkshop.insert(workshopId, creatorId);

        emit fileSizeFetched(workshopId, m_fileSizeCache.value(workshopId));
        fetchCreatorSummary(workshopId, creatorId);
    });
}

void SteamWorkshopService::fetchFileSize(const QString &publishedFileId) {
    fetchItemDetails(publishedFileId);
}

void SteamWorkshopService::fetchCreatorInfo(const QString &publishedFileId) {
    fetchItemDetails(publishedFileId);
}

void SteamWorkshopService::fetchCreatorSummary(
    const QString &publishedFileId,
    const QString &creatorId
) {
    const QString creatorUrl = creatorUrlFor(creatorId);

    if (creatorId.isEmpty()) {
        emit creatorInfoFetched(publishedFileId, QString(), QString());
        m_completeItemDetails.insert(publishedFileId);
        emit itemDetailsFetchFinished(publishedFileId, true);
        return;
    }

    if (m_creatorNameBySteamId.contains(creatorId)) {
        emit creatorInfoFetched(
            publishedFileId,
            m_creatorNameBySteamId.value(creatorId),
            creatorUrl
        );
        m_completeItemDetails.insert(publishedFileId);
        emit itemDetailsFetchFinished(publishedFileId, true);
        return;
    }

    QStringList &waiters = m_creatorWaiters[creatorId];
    if (!waiters.contains(publishedFileId))
        waiters.append(publishedFileId);

    if (m_creatorReplies.contains(creatorId) && m_creatorReplies.value(creatorId))
        return;

    if (m_apiKey.isEmpty()) {
        m_creatorNameBySteamId.insert(creatorId, creatorId);
        const QStringList pending = m_creatorWaiters.take(creatorId);
        for (const QString &workshopId : pending) {
            emit creatorInfoFetched(workshopId, creatorId, creatorUrl);
            m_completeItemDetails.insert(workshopId);
            emit itemDetailsFetchFinished(workshopId, true);
        }
        return;
    }

    QUrl url(QStringLiteral(
        "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/"
    ));
    QUrlQuery query;

    QString keyString = QString::fromUtf8(m_apiKey);
    query.addQueryItem(QStringLiteral("key"), keyString);
    keyString.fill(u'\0');
    keyString.clear();

    query.addQueryItem(QStringLiteral("steamids"), creatorId);
    url.setQuery(query);

    QNetworkRequest request(url);
#if QT_VERSION >= QT_VERSION_CHECK(6, 7, 0)
    request.setTransferTimeout(kTransferTimeoutMs);
#endif

    QNetworkReply *reply = m_network.get(request);
    m_creatorReplies.insert(creatorId, reply);

    connect(reply, &QNetworkReply::finished, this, [this, reply, creatorId]() {
        m_creatorReplies.remove(creatorId);
        const QStringList pending = m_creatorWaiters.take(creatorId);

        const QByteArray raw = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();

        if (networkError != QNetworkReply::NoError) {
            for (const QString &workshopId : pending)
                emit itemDetailsFetchFinished(workshopId, false);
            return;
        }

        QString creatorName;
        const QJsonDocument document = QJsonDocument::fromJson(raw);

        if (document.isObject()) {
            const QJsonArray players = document.object()
                .value(QStringLiteral("response"))
                .toObject()
                .value(QStringLiteral("players"))
                .toArray();

            if (!players.isEmpty()) {
                creatorName = players.first()
                    .toObject()
                    .value(QStringLiteral("personaname"))
                    .toString();
            }
        }

        if (creatorName.isEmpty())
            creatorName = creatorId;

        m_creatorNameBySteamId.insert(creatorId, creatorName);
        const QString creatorUrl = creatorUrlFor(creatorId);

        for (const QString &workshopId : pending) {
            emit creatorInfoFetched(workshopId, creatorName, creatorUrl);
            m_completeItemDetails.insert(workshopId);
            emit itemDetailsFetchFinished(workshopId, true);
        }
    });
}

void SteamWorkshopService::emitCachedItemDetails(
    const QString &publishedFileId
) {
    emit fileSizeFetched(
        publishedFileId,
        m_fileSizeCache.value(publishedFileId, 0)
    );

    const QString creatorId = m_creatorIdByWorkshop.value(publishedFileId);
    emit creatorInfoFetched(
        publishedFileId,
        m_creatorNameBySteamId.value(creatorId, creatorId),
        creatorUrlFor(creatorId)
    );
    emit itemDetailsFetchFinished(publishedFileId, true);
}

void SteamWorkshopService::handleReply(QNetworkReply *reply) {
    setLoading(false);

    if (reply->error() != QNetworkReply::NoError) {
        setErrorString(reply->errorString());
        reply->deleteLater();
        emit searchFinished(false);
        return;
    }

    const QByteArray body = reply->readAll();
    const int requestedPage = reply->property("requestedPage").toInt();
    reply->deleteLater();

    const QJsonDocument document = QJsonDocument::fromJson(body);
    if (!document.isObject()) {
        setErrorString(QStringLiteral("Steam API returned invalid JSON"));
        emit searchFinished(false);
        return;
    }

    const QJsonObject response = document.object()
        .value(QStringLiteral("response"))
        .toObject();

    const int responsePage = response.value(QStringLiteral("page")).toInt();
    const int effectivePage = responsePage > 0 ? responsePage : requestedPage;

    if (m_currentPage != effectivePage) {
        m_currentPage = effectivePage;
        emit currentPageChanged();
    }

    const int total = response.value(QStringLiteral("total")).toInt();
    if (m_totalResults != total) {
        m_totalResults = total;
        emit totalResultsChanged();
    }

    const QJsonArray files = response
        .value(QStringLiteral("publishedfiledetails"))
        .toArray();

    setHasMore(
        !files.isEmpty() &&
        effectivePage * kPageSize < total
    );

    QVariantList parsed;
    parsed.reserve(files.size());

    for (const QJsonValue &value : files) {
        const QJsonObject object = value.toObject();
        const QString workshopId = object
            .value(QStringLiteral("publishedfileid"))
            .toString();

        if (workshopId.isEmpty())
            continue;

        const QString title = object
            .value(QStringLiteral("title"))
            .toString();
        const QString description = object
            .value(QStringLiteral("short_description"))
            .toString();

        QString previewUrl = object
            .value(QStringLiteral("preview_url"))
            .toString();
        const QJsonArray previews = object
            .value(QStringLiteral("previews"))
            .toArray();

        if (!previews.isEmpty()) {
            const QString firstPreview = previews.first()
                .toObject()
                .value(QStringLiteral("url"))
                .toString();
            if (!firstPreview.isEmpty())
                previewUrl = firstPreview;
        }

        QStringList tags;
        const QJsonArray tagArray = object
            .value(QStringLiteral("tags"))
            .toArray();

        tags.reserve(tagArray.size());
        for (const QJsonValue &tagValue : tagArray) {
            QString tag;
            if (tagValue.isObject()) {
                tag = tagValue.toObject()
                    .value(QStringLiteral("tag"))
                    .toString();
            } else {
                tag = tagValue.toString();
            }

            if (!tag.isEmpty())
                tags.append(tag);
        }

        QStringList lowerTags;
        lowerTags.reserve(tags.size());
        for (const QString &tag : tags)
            lowerTags.append(tag.toLower());

        const bool isMature =
            lowerTags.contains(QStringLiteral("mature")) ||
            lowerTags.contains(QStringLiteral("questionable")) ||
            lowerTags.contains(QStringLiteral("nsfw")) ||
            lowerTags.contains(QStringLiteral("partial nudity")) ||
            lowerTags.contains(QStringLiteral("nudity")) ||
            lowerTags.contains(QStringLiteral("gore"));

        const qlonglong fileSize = jsonInteger(
            object.value(QStringLiteral("file_size"))
        );
        if (fileSize > 0)
            m_fileSizeCache.insert(workshopId, fileSize);

        const QString creatorId = object
            .value(QStringLiteral("creator"))
            .toString();
        if (!creatorId.isEmpty())
            m_creatorIdByWorkshop.insert(workshopId, creatorId);

        const QString creatorName = m_creatorNameBySteamId.value(creatorId);
        const QString lowerTagBlob = framedTagBlob(lowerTags);
        const QString searchBlob = (
            title + QLatin1Char('\n') +
            description + QLatin1Char('\n') +
            creatorName + QLatin1Char('\n') +
            creatorId + QLatin1Char('\n') +
            tags.join(QLatin1Char(' '))
        ).toLower();

        QVariantMap item;
        item.insert(QStringLiteral("id"), workshopId);
        item.insert(QStringLiteral("title"), title);
        item.insert(QStringLiteral("description"), description);
        item.insert(QStringLiteral("previewUrl"), previewUrl);
        item.insert(QStringLiteral("creatorId"), creatorId);
        item.insert(QStringLiteral("creatorName"), creatorName);
        item.insert(QStringLiteral("creatorUrl"), creatorUrlFor(creatorId));
        item.insert(QStringLiteral("fileSize"), qMax<qlonglong>(0, fileSize));
        item.insert(
            QStringLiteral("subscriptions"),
            jsonInteger(object.value(QStringLiteral("subscriptions")))
        );
        item.insert(
            QStringLiteral("favorited"),
            jsonInteger(object.value(QStringLiteral("favorited")))
        );
        item.insert(QStringLiteral("tags"), tagsToJson(tags));
        item.insert(QStringLiteral("lowerTags"), lowerTagBlob);
        item.insert(QStringLiteral("searchBlob"), searchBlob);
        item.insert(QStringLiteral("isMature"), isMature);
        parsed.append(item);
    }

    m_results = parsed;
    emit resultsChanged();
    setErrorString(QString());
    emit searchFinished(true);
}
