/// Email service configuration
///
/// After deploying the Cloudflare Worker, update WORKER_URL with your worker's URL:
/// Example: https://sweetweb-email-service.YOUR_SUBDOMAIN.workers.dev
class EmailConfig {
  /// Cloudflare Worker URL
  ///
  /// TO CONFIGURE:
  /// 1. Deploy the worker from /cloudflare-worker/
  /// 2. Copy your worker URL from Cloudflare dashboard
  /// 3. Replace the URL below
  static const String workerUrl = 'https://menuapp.alkubaisi1818.workers.dev';

  /// Default email for all notifications
  /// All order notifications will be sent to this email
  static const String defaultEmail = 'alkubaisi1818@gmail.com';

  /// Check if email service is configured
  static bool get isConfigured =>
      workerUrl != 'YOUR_WORKER_URL_HERE' && workerUrl.isNotEmpty;

  /// Order notification endpoint
  static String get orderNotificationEndpoint => workerUrl;

  /// Report generation endpoint
  static String get reportEndpoint => workerUrl;
}
