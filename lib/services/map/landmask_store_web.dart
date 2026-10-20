import 'landmask_store.dart';

/// The web has no disk cache for masks (the browser caches the WMS image).
LandMaskStore createLandMaskStore() => MemoryLandMaskStore();
