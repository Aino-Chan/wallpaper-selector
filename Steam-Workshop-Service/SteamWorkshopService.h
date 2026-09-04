#pragma once

#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QStringList>
#include <QVariantList>

class QNetworkReply;

class SteamWorkshopService : public QObject {
    Q_OBJECT

    Q_PROPERTY(bool hasStoredKey READ hasStoredKey NOTIFY hasStoredKeyChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(bool showMatureContent READ showMatureContent WRITE setShowMatureContent NOTIFY showMatureContentChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)
    Q_PROPERTY(int currentPage READ currentPage NOTIFY currentPageChanged)
    Q_PROPERTY(int totalResults READ totalResults NOTIFY totalResultsChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY hasMoreChanged)

public:
    explicit SteamWorkshopService(QObject *parent = nullptr);

    bool hasStoredKey() const;
    bool loading() const;
    bool showMatureContent() const;
    void setShowMatureContent(bool value);
    QString errorString() const;
    QVariantList results() const;
    int currentPage() const;
    int totalResults() const;
    bool hasMore() const;

    Q_INVOKABLE bool saveApiKey(const QString &apiKey);
    Q_INVOKABLE bool deleteStoredKey();

    // Preferred API. It retrieves file size and creator information with one
    // published-file-details request, then shares/caches creator lookups.
    Q_INVOKABLE void fetchItemDetails(const QString &publishedFileId);

    // Compatibility wrappers for older QML. Both are de-duplicated internally.
    Q_INVOKABLE void fetchFileSize(const QString &publishedFileId);
    Q_INVOKABLE void fetchCreatorInfo(const QString &publishedFileId);

    Q_INVOKABLE void search(
        const QString &query,
        int page = 1,
        const QString &sort = QStringLiteral("trend"),
        const QString &requiredTag = QString()
    );

signals:
    void hasStoredKeyChanged();
    void loadingChanged();
    void showMatureContentChanged();
    void errorStringChanged();
    void resultsChanged();
    void currentPageChanged();
    void totalResultsChanged();
    void hasMoreChanged();
    void searchFinished(bool ok);

    void fileSizeFetched(const QString &publishedFileId, qlonglong fileSize);
    void creatorInfoFetched(
        const QString &publishedFileId,
        const QString &creatorName,
        const QString &creatorUrl
    );
    void itemDetailsFetchFinished(const QString &publishedFileId, bool ok);

private:
    void setErrorString(const QString &s);
    void setLoading(bool value);
    void setHasMore(bool value);
    void handleReply(QNetworkReply *reply);
    bool loadApiKeyFromKeyring();

    void fetchCreatorSummary(
        const QString &publishedFileId,
        const QString &creatorId
    );
    void emitCachedItemDetails(const QString &publishedFileId);
    void cancelOutstandingRequests();

private:
    QNetworkAccessManager m_network;
    QVariantList m_results;
    QString m_errorString;
    QByteArray m_apiKey;

    QPointer<QNetworkReply> m_searchReply;
    quint64 m_searchSerial = 0;

    QHash<QString, QPointer<QNetworkReply>> m_detailReplies;
    QHash<QString, QPointer<QNetworkReply>> m_creatorReplies;
    QHash<QString, QStringList> m_creatorWaiters;

    QHash<QString, qlonglong> m_fileSizeCache;
    QHash<QString, QString> m_creatorIdByWorkshop;
    QHash<QString, QString> m_creatorNameBySteamId;
    QSet<QString> m_completeItemDetails;

    bool m_hasStoredKey = false;
    bool m_loading = false;
    bool m_showMatureContent = false;
    bool m_hasMore = false;
    int m_currentPage = 1;
    int m_totalResults = 0;
};
