/// Base Service Interface
/// Defines common functionality for all services
abstract class BaseService {
  /// Initialize the service
  Future<void> initialize();

  /// Dispose resources
  Future<void> dispose();

  /// Check if service is initialized
  bool get isInitialized;

  /// Service name for debugging
  String get serviceName;
}

/// Base Network Service Interface
/// Common functionality for services that use network
abstract class BaseNetworkService extends BaseService {
  /// Check if network is available
  Future<bool> get isNetworkAvailable;

  /// Set timeout duration
  void setTimeout(Duration timeout);

  /// Get current timeout
  Duration get timeout;
}

/// Base Cache Service Interface
/// Common functionality for services that use caching
abstract class BaseCacheService extends BaseService {
  /// Clear all cache
  Future<void> clearCache();

  /// Clear specific cache by key
  Future<void> clearCacheByKey(String key);

  /// Check if cache exists for key
  Future<bool> hasCacheForKey(String key);

  /// Get cache size
  Future<int> getCacheSize();
}

/// Service Status
enum ServiceStatus { uninitialized, initializing, initialized, error, disposed }

/// Base Service Implementation
/// Provides common functionality for services
abstract class BaseServiceImpl implements BaseService {
  ServiceStatus _status = ServiceStatus.uninitialized;
  String? _errorMessage;

  @override
  bool get isInitialized => _status == ServiceStatus.initialized;

  ServiceStatus get status => _status;
  String? get errorMessage => _errorMessage;

  @override
  Future<void> initialize() async {
    if (_status == ServiceStatus.initialized) return;

    _status = ServiceStatus.initializing;
    _errorMessage = null;

    try {
      await onInitialize();
      _status = ServiceStatus.initialized;
    } catch (e) {
      _status = ServiceStatus.error;
      _errorMessage = e.toString();
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_status == ServiceStatus.disposed) return;

    try {
      await onDispose();
      _status = ServiceStatus.disposed;
    } catch (e) {
      _status = ServiceStatus.error;
      _errorMessage = e.toString();
      rethrow;
    }
  }

  /// Override this method to implement service-specific initialization
  Future<void> onInitialize();

  /// Override this method to implement service-specific disposal
  Future<void> onDispose();

  /// Check if service is ready to use
  void ensureInitialized() {
    if (!isInitialized) {
      throw StateError('Service $serviceName is not initialized');
    }
  }
}
