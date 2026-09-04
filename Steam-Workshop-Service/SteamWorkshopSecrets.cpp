#include "SteamWorkshopSecrets.h"

#include <qt6keychain/keychain.h>

#include <QEventLoop>
#include <QObject>

namespace {
struct JobState {
    bool ok = false;
    QString text;
};
}

QString SteamWorkshopSecrets::serviceName() {
    return QStringLiteral("SteamWorkshopService");
}

QString SteamWorkshopSecrets::keyName() {
    return QStringLiteral("steamApiKey");
}

bool SteamWorkshopSecrets::writeApiKey(const QString &apiKey, QString *errorOut) {
    if (apiKey.trimmed().isEmpty()) {
        if (errorOut) {
            *errorOut = QStringLiteral("API key is empty");
        }
        return false;
    }

    auto *job = new QKeychain::WritePasswordJob(serviceName());
    job->setAutoDelete(false);
    job->setKey(keyName());
    job->setTextData(apiKey);

    QEventLoop loop;
    JobState state;

    QObject::connect(job, &QKeychain::Job::finished, &loop, [&](QKeychain::Job *baseJob) {
        auto *finishedJob = qobject_cast<QKeychain::WritePasswordJob *>(baseJob);
        if (!finishedJob) {
            state.ok = false;
            state.text = QStringLiteral("Internal keychain error");
            loop.quit();
            return;
        }

        state.ok = (finishedJob->error() == QKeychain::NoError);
        if (!state.ok) {
            state.text = finishedJob->errorString();
        }
        loop.quit();
    });

    job->start();
    loop.exec();

    job->deleteLater();

    if (!state.ok && errorOut) {
        *errorOut = state.text;
    }
    return state.ok;
}

bool SteamWorkshopSecrets::readApiKey(QString *apiKeyOut, QString *errorOut) {
    if (!apiKeyOut) {
        if (errorOut) {
            *errorOut = QStringLiteral("Output pointer is null");
        }
        return false;
    }

    auto *job = new QKeychain::ReadPasswordJob(serviceName());
    job->setAutoDelete(false);
    job->setKey(keyName());

    QEventLoop loop;
    JobState state;

    QObject::connect(job, &QKeychain::Job::finished, &loop, [&](QKeychain::Job *baseJob) {
        auto *finishedJob = qobject_cast<QKeychain::ReadPasswordJob *>(baseJob);
        if (!finishedJob) {
            state.ok = false;
            state.text = QStringLiteral("Internal keychain error");
            loop.quit();
            return;
        }

        if (finishedJob->error() == QKeychain::NoError) {
            state.ok = true;
            state.text = finishedJob->textData();
        } else {
            state.ok = false;
            state.text = finishedJob->errorString();
        }

        loop.quit();
    });

    job->start();
    loop.exec();

    job->deleteLater();

    if (!state.ok) {
        if (errorOut) {
            *errorOut = state.text;
        }
        return false;
    }

    *apiKeyOut = state.text;
    return true;
}

bool SteamWorkshopSecrets::deleteApiKey(QString *errorOut) {
    auto *job = new QKeychain::DeletePasswordJob(serviceName());
    job->setAutoDelete(false);
    job->setKey(keyName());

    QEventLoop loop;
    JobState state;

    QObject::connect(job, &QKeychain::Job::finished, &loop, [&](QKeychain::Job *baseJob) {
        auto *finishedJob = qobject_cast<QKeychain::DeletePasswordJob *>(baseJob);
        if (!finishedJob) {
            state.ok = false;
            state.text = QStringLiteral("Internal keychain error");
            loop.quit();
            return;
        }

        state.ok = (finishedJob->error() == QKeychain::NoError);
        if (!state.ok) {
            state.text = finishedJob->errorString();
        }
        loop.quit();
    });

    job->start();
    loop.exec();

    job->deleteLater();

    if (!state.ok && errorOut) {
        *errorOut = state.text;
    }
    return state.ok;
}

bool SteamWorkshopSecrets::hasApiKey(QString *errorOut) {
    QString apiKey;
    QString error;
    const bool ok = readApiKey(&apiKey, &error);

    if (!ok) {
        if (errorOut) {
            *errorOut = error;
        }
        return false;
    }

    const bool has = !apiKey.isEmpty();

    apiKey.fill(u'\0');
    apiKey.clear();

    return has;
}