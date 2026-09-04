#include "plugin.h"
#include "SteamWorkshopService.h"

#include <qqml.h>

void SteamWorkshopPlugin::registerTypes(const char *uri) {
    qmlRegisterType<SteamWorkshopService>(uri, 1, 0, "SteamWorkshopService");
}