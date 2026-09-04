#pragma once

#include <QString>

class SteamWorkshopSecrets {
public:
    static bool writeApiKey(const QString &apiKey, QString *errorOut = nullptr);
    static bool readApiKey(QString *apiKeyOut, QString *errorOut = nullptr);
    static bool deleteApiKey(QString *errorOut = nullptr);
    static bool hasApiKey(QString *errorOut = nullptr);

private:
    static QString serviceName();
    static QString keyName();
};